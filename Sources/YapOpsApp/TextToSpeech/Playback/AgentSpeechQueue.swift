// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import YapOpsCore

enum AgentSpeechQueueState: Equatable {
    case idle
    case preparing
    case starting
    case playing
}

struct AgentSpeechConfiguration: Equatable, Sendable {
    let selection: TextToSpeechVoiceSelection
    let credential: String?

    init(selection: TextToSpeechVoiceSelection, credential: String?) {
        self.selection = selection
        let trimmedCredential = credential?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.credential = trimmedCredential?.isEmpty == false ? trimmedCredential : nil
    }

    init(
        provider: AgentSpeechProvider,
        elevenLabsAPIKey: String,
        elevenLabsVoiceID: String
    ) {
        let backendID: TextToSpeechBackendID = provider == .system ? .system : .elevenLabs
        self.init(
            selection: TextToSpeechVoiceSelection(
                backendID: backendID,
                voiceID: provider == .system ? nil : elevenLabsVoiceID),
            credential: provider == .system ? nil : elevenLabsAPIKey)
    }

    static let systemDefault = AgentSpeechConfiguration(
        selection: TextToSpeechVoiceSelection(backendID: .system, voiceID: nil),
        credential: nil)
}

enum AgentSpeechInputFormat: Equatable, Sendable {
    case legacyMarkdown
    case agentAuthoredPlainText
}

enum AgentSpeechAdmissionPolicy: Equatable, Sendable {
    case legacyNormalized
    case agentAuthoredVerbatim
}

struct AgentSpeechRequest: Equatable, Sendable {
    let text: String
    let localeID: String
    let configuration: AgentSpeechConfiguration
    let inputFormat: AgentSpeechInputFormat
    let admissionPolicy: AgentSpeechAdmissionPolicy

    init(
        text: String,
        localeID: String,
        configuration: AgentSpeechConfiguration,
        inputFormat: AgentSpeechInputFormat = .legacyMarkdown,
        admissionPolicy: AgentSpeechAdmissionPolicy = .legacyNormalized
    ) {
        self.text = text
        self.localeID = localeID
        self.configuration = configuration
        self.inputFormat = inputFormat
        self.admissionPolicy = admissionPolicy
    }
}

@MainActor
protocol AgentSpeechQueueing: AnyObject {
    var onStateChange: ((AgentSpeechQueueState) -> Void)? { get set }

    @discardableResult
    func enqueue(_ request: AgentSpeechRequest) -> Bool
    @discardableResult
    func enqueueVerbatimBatch(_ requests: [AgentSpeechRequest]) -> Bool
    func stop()
}

@MainActor
final class AgentSpeechQueue: AgentSpeechQueueing {
    private static let maximumPendingRequests = 64
    private static let maximumConcurrentSynthesisRequests = 2
    private static let maximumCoalescedCharacters = 20_000

    var onStateChange: ((AgentSpeechQueueState) -> Void)?

    private enum Preparation {
        case audio(Data)
        case system(voiceID: String?)
    }

    private struct TimedPreparation: Sendable {
        let value: PreparedTextToSpeech
        let readyAtUptime: UInt64
    }

    private struct PendingRequest {
        let id: UInt64
        var request: AgentSpeechRequest
        let enqueuedAtUptime: UInt64
        var synthesis: Task<TimedPreparation, any Error>?
        var preparation: Preparation?
    }

    private let backendRegistry: TextToSpeechBackendRegistry
    private let audioPlayer: any AgentAudioDataPlaying
    private let systemSpeechPlayer: any AgentSystemSpeechPlaying
    private let diagnostics: any YapOpsDiagnosticRecording
    private var pending: [PendingRequest] = []
    private var activePlaybackID: UInt64?
    private var state = AgentSpeechQueueState.idle
    private var generation: UInt64 = 0
    private var nextID: UInt64 = 0

    init(
        backendRegistry: TextToSpeechBackendRegistry? = nil,
        synthesizer: any ElevenLabsSpeechSynthesizing = ElevenLabsSpeechClient(),
        audioPlayer: any AgentAudioDataPlaying = SystemAgentAudioDataPlayer(),
        systemSpeechPlayer: any AgentSystemSpeechPlaying = SystemAgentSpeechPlayer(),
        diagnostics: any YapOpsDiagnosticRecording = YapOpsDiagnostics.shared
    ) {
        self.backendRegistry = backendRegistry ?? .live(
            elevenLabsSynthesizer: synthesizer)
        self.audioPlayer = audioPlayer
        self.systemSpeechPlayer = systemSpeechPlayer
        self.diagnostics = diagnostics
    }

    @discardableResult
    func enqueue(_ request: AgentSpeechRequest) -> Bool {
        let admittedRequest: AgentSpeechRequest
        let appended: (id: UInt64, coalesced: Bool)
        switch request.admissionPolicy {
        case .legacyNormalized:
            let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                reject(reason: "empty", policy: request.admissionPolicy)
                return false
            }
            admittedRequest = AgentSpeechRequest(
                text: String(text.prefix(Self.maximumCoalescedCharacters)),
                localeID: request.localeID,
                configuration: request.configuration,
                inputFormat: request.inputFormat,
                admissionPolicy: request.admissionPolicy)
            appended = appendLegacy(admittedRequest)
        case .agentAuthoredVerbatim:
            guard !request.text.isEmpty else {
                reject(reason: "empty", policy: request.admissionPolicy)
                return false
            }
            guard request.text.count <= Self.maximumCoalescedCharacters else {
                reject(reason: "oversized", policy: request.admissionPolicy)
                return false
            }
            guard pending.count < Self.maximumPendingRequests else {
                reject(reason: "queue_full", policy: request.admissionPolicy)
                return false
            }
            admittedRequest = request
            let pendingRequest = makePendingRequest(request)
            pending.append(pendingRequest)
            appended = (pendingRequest.id, false)
        }
        diagnostics.record(
            category: .audio,
            event: "speech.queue_enqueued",
            fields: [
                "request_id": String(appended.id),
                "backend": admittedRequest.configuration.selection.backendID.rawValue,
                "character_count": String(admittedRequest.text.count),
                "pending_count": String(pending.count),
                "coalesced": String(appended.coalesced),
                "input_format": admittedRequest.inputFormat.diagnosticName,
                "admission_policy": admittedRequest.admissionPolicy.diagnosticName,
                "generation": String(generation),
            ])
        startPrefetching()
        advance()
        return true
    }

    @discardableResult
    func enqueueVerbatimBatch(_ requests: [AgentSpeechRequest]) -> Bool {
        guard !requests.isEmpty,
            requests.allSatisfy({
                !$0.text.isEmpty
                    && $0.inputFormat == .agentAuthoredPlainText
                    && $0.admissionPolicy == .agentAuthoredVerbatim
            })
        else {
            reject(reason: "empty", policy: .agentAuthoredVerbatim)
            return false
        }
        let characterCount = requests.reduce(0) { count, request in
            let (value, overflow) = count.addingReportingOverflow(request.text.count)
            return overflow ? Int.max : value
        }
        guard characterCount <= Self.maximumCoalescedCharacters else {
            reject(reason: "oversized", policy: .agentAuthoredVerbatim)
            return false
        }
        guard requests.count <= Self.maximumPendingRequests - pending.count else {
            reject(reason: "queue_full", policy: .agentAuthoredVerbatim)
            return false
        }

        for request in requests {
            let pendingRequest = makePendingRequest(request)
            pending.append(pendingRequest)
            diagnostics.record(
                category: .audio,
                event: "speech.queue_enqueued",
                fields: [
                    "request_id": String(pendingRequest.id),
                    "backend": request.configuration.selection.backendID.rawValue,
                    "character_count": String(request.text.count),
                    "pending_count": String(pending.count),
                    "coalesced": "false",
                    "input_format": request.inputFormat.diagnosticName,
                    "admission_policy": request.admissionPolicy.diagnosticName,
                    "generation": String(generation),
                ])
        }
        startPrefetching()
        advance()
        return true
    }

    func stop() {
        let stoppedGeneration = generation
        let cancelledCount = pending.count
        let stoppedPlayback = activePlaybackID != nil
        generation &+= 1
        for request in pending {
            request.synthesis?.cancel()
        }
        pending.removeAll(keepingCapacity: true)
        activePlaybackID = nil
        audioPlayer.stop()
        systemSpeechPlayer.stop()
        setState(.idle)
        diagnostics.record(
            category: .audio,
            event: "speech.queue_stopped",
            fields: [
                "previous_generation": String(stoppedGeneration),
                "generation": String(generation),
                "cancelled_request_count": String(cancelledCount),
                "stopped_playback": String(stoppedPlayback),
            ])
    }

    private func appendLegacy(_ request: AgentSpeechRequest) -> (id: UInt64, coalesced: Bool) {
        guard pending.count >= Self.maximumPendingRequests,
            var previous = pending.popLast()
        else {
            let pendingRequest = makePendingRequest(request)
            pending.append(pendingRequest)
            return (pendingRequest.id, false)
        }

        previous.synthesis?.cancel()
        let combinedText = String(
            "\(previous.request.text) \(request.text)"
                .suffix(Self.maximumCoalescedCharacters))
        previous = makePendingRequest(
            AgentSpeechRequest(
                text: combinedText,
                localeID: request.localeID,
                configuration: request.configuration,
                inputFormat: request.inputFormat,
                admissionPolicy: request.admissionPolicy))
        pending.append(previous)
        return (previous.id, true)
    }

    private func reject(reason: String, policy: AgentSpeechAdmissionPolicy) {
        diagnostics.record(
            category: .audio,
            event: "speech.queue_rejected",
            level: .warning,
            fields: [
                "reason": reason,
                "admission_policy": policy.diagnosticName,
            ])
    }

    private func makePendingRequest(_ request: AgentSpeechRequest) -> PendingRequest {
        nextID &+= 1
        return PendingRequest(
            id: nextID,
            request: request,
            enqueuedAtUptime: DispatchTime.now().uptimeNanoseconds,
            synthesis: nil,
            preparation: nil)
    }

    private func startPrefetching() {
        var availableSlots = Self.maximumConcurrentSynthesisRequests
            - pending.reduce(into: 0) { count, request in
                if request.synthesis != nil { count += 1 }
            }
        guard availableSlots > 0 else { return }

        for index in pending.indices
        where pending[index].preparation == nil && pending[index].synthesis == nil {
            let pendingRequest = pending[index]
            let request = pendingRequest.request
            let configuration = request.configuration
            let registry = backendRegistry
            let diagnostics = diagnostics
            let requestID = pendingRequest.id
            let enqueuedAtUptime = pendingRequest.enqueuedAtUptime
            let synthesis = Task.detached(priority: .userInitiated) {
                let startedAtUptime = DispatchTime.now().uptimeNanoseconds
                diagnostics.record(
                    category: .audio,
                    event: "speech.synthesis_started",
                    fields: [
                        "request_id": String(requestID),
                        "backend": configuration.selection.backendID.rawValue,
                        "character_count": String(request.text.count),
                        "queue_wait_ms": String(
                            Self.milliseconds(from: enqueuedAtUptime, to: startedAtUptime)),
                        "task_priority": String(Task.currentPriority.rawValue),
                    ])
                do {
                    let value = try await registry.prepare(
                        TextToSpeechPreparationRequest(
                            text: request.text,
                            localeID: request.localeID,
                            voiceID: configuration.selection.voiceID),
                        backendID: configuration.selection.backendID,
                        credential: configuration.credential)
                    try Task.checkCancellation()
                    let readyAtUptime = DispatchTime.now().uptimeNanoseconds
                    let byteCount = switch value {
                    case .audio(let data): data.count
                    case .systemVoice: 0
                    }
                    diagnostics.record(
                        category: .audio,
                        event: "speech.synthesis_finished",
                        fields: [
                            "request_id": String(requestID),
                            "outcome": "success",
                            "duration_ms": String(
                                Self.milliseconds(from: startedAtUptime, to: readyAtUptime)),
                            "audio_byte_count": String(byteCount),
                            "task_priority": String(Task.currentPriority.rawValue),
                        ])
                    return TimedPreparation(value: value, readyAtUptime: readyAtUptime)
                } catch {
                    let failedAtUptime = DispatchTime.now().uptimeNanoseconds
                    diagnostics.record(
                        category: .audio,
                        event: "speech.synthesis_finished",
                        level: error is CancellationError ? .info : .error,
                        fields: [
                            "request_id": String(requestID),
                            "outcome": error is CancellationError ? "cancelled" : "failure",
                            "duration_ms": String(
                                Self.milliseconds(from: startedAtUptime, to: failedAtUptime)),
                            "error_type": String(describing: type(of: error)),
                            "task_priority": String(Task.currentPriority.rawValue),
                        ])
                    throw error
                }
            }
            pending[index].synthesis = synthesis
            let activeGeneration = generation
            Task.detached(priority: .userInitiated) { [weak self] in
                let result = await synthesis.result
                await MainRunLoopScheduler.shared.perform { [weak self] in
                    self?.completeSynthesis(
                        requestID: requestID,
                        generation: activeGeneration,
                        result: result)
                }
            }
            availableSlots -= 1
            if availableSlots == 0 { break }
        }
    }

    private func completeSynthesis(
        requestID: UInt64,
        generation activeGeneration: UInt64,
        result: Result<TimedPreparation, any Error>
    ) {
        guard generation == activeGeneration,
            let index = pending.firstIndex(where: { $0.id == requestID })
        else {
            diagnostics.record(
                category: .audio,
                event: "speech.synthesis_result_discarded",
                fields: [
                    "request_id": String(requestID),
                    "result_generation": String(activeGeneration),
                    "generation": String(generation),
                ])
            return
        }
        pending[index].synthesis = nil
        switch result {
        case .success(let prepared):
            let receivedAtUptime = DispatchTime.now().uptimeNanoseconds
            let byteCount: Int
            switch prepared.value {
            case .audio(let data) where !data.isEmpty:
                pending[index].preparation = .audio(data)
                byteCount = data.count
            case .systemVoice(let voiceID):
                pending[index].preparation = .system(voiceID: voiceID)
                byteCount = 0
            case .audio:
                pending[index].preparation = .system(voiceID: nil)
                byteCount = 0
            }
            diagnostics.record(
                category: .audio,
                event: "speech.synthesis_result_received",
                fields: [
                    "request_id": String(requestID),
                    "main_delivery_ms": String(
                        Self.milliseconds(
                            from: prepared.readyAtUptime,
                            to: receivedAtUptime)),
                    "audio_byte_count": String(byteCount),
                    "task_priority": String(Task.currentPriority.rawValue),
                    "run_loop_mode": RunLoop.current.currentMode?.rawValue ?? "none",
                ])
        case .failure:
            pending[index].preparation = .system(voiceID: nil)
            diagnostics.record(
                category: .audio,
                event: "speech.synthesis_fallback_selected",
                level: .warning,
                fields: ["request_id": String(requestID)])
        }
        startPrefetching()
        advance()
    }

    private func advance(continuingSpeech: Bool = false) {
        guard activePlaybackID == nil else { return }
        guard let first = pending.first else {
            setState(.idle)
            return
        }
        guard let preparation = first.preparation else {
            setState(.preparing)
            return
        }

        pending.removeFirst()
        startPrefetching()
        switch preparation {
        case .audio(let data):
            startCloudPlayback(
                data,
                request: first.request,
                requestID: first.id,
                continuingSpeech: continuingSpeech)
        case .system(let voiceID):
            startSystemPlayback(
                request: first.request,
                requestID: first.id,
                voiceID: voiceID,
                continuingSpeech: continuingSpeech)
        }
    }

    private func startCloudPlayback(
        _ data: Data,
        request: AgentSpeechRequest,
        requestID: UInt64,
        continuingSpeech: Bool
    ) {
        diagnostics.record(
            category: .audio,
            event: "speech.playback_starting",
            fields: [
                "request_id": String(requestID),
                "kind": "cloud",
                "audio_byte_count": String(data.count),
            ])
        if !continuingSpeech {
            setState(.starting)
        }
        activePlaybackID = requestID
        let activeGeneration = generation
        let started = audioPlayer.play(data) { [weak self] completed in
            self?.completePlayback(
                requestID: requestID,
                generation: activeGeneration,
                completed: completed)
        }
        guard started else {
            diagnostics.record(
                category: .audio,
                event: "speech.playback_rejected",
                level: .warning,
                fields: [
                    "request_id": String(requestID),
                    "kind": "cloud",
                ])
            activePlaybackID = nil
            startSystemPlayback(
                request: request,
                requestID: requestID,
                voiceID: nil,
                continuingSpeech: continuingSpeech)
            return
        }
        guard activePlaybackID == requestID, generation == activeGeneration else { return }
        diagnostics.record(
            category: .audio,
            event: "speech.playback_started",
            fields: [
                "request_id": String(requestID),
                "kind": "cloud",
            ])
        setState(.playing)
    }

    private func startSystemPlayback(
        request: AgentSpeechRequest,
        requestID: UInt64,
        voiceID: String?,
        continuingSpeech: Bool
    ) {
        diagnostics.record(
            category: .audio,
            event: "speech.playback_starting",
            fields: [
                "request_id": String(requestID),
                "kind": "system",
                "character_count": String(request.text.count),
            ])
        if !continuingSpeech {
            setState(.starting)
        }
        activePlaybackID = requestID
        let activeGeneration = generation
        let started = systemSpeechPlayer.play(
            text: request.text,
            localeID: request.localeID,
            voiceID: voiceID
        ) { [weak self] in
            self?.completePlayback(
                requestID: requestID,
                generation: activeGeneration,
                completed: true)
        }
        guard started else {
            diagnostics.record(
                category: .audio,
                event: "speech.playback_rejected",
                level: .error,
                fields: [
                    "request_id": String(requestID),
                    "kind": "system",
                ])
            activePlaybackID = nil
            advance(continuingSpeech: continuingSpeech)
            return
        }
        guard activePlaybackID == requestID, generation == activeGeneration else { return }
        diagnostics.record(
            category: .audio,
            event: "speech.playback_started",
            fields: [
                "request_id": String(requestID),
                "kind": "system",
            ])
        setState(.playing)
    }

    private func completePlayback(
        requestID: UInt64,
        generation activeGeneration: UInt64,
        completed: Bool
    ) {
        guard generation == activeGeneration, activePlaybackID == requestID else { return }
        activePlaybackID = nil
        diagnostics.record(
            category: .audio,
            event: "speech.playback_finished",
            fields: [
                "request_id": String(requestID),
                "completed": String(completed),
                "pending_count": String(pending.count),
            ])
        advance(continuingSpeech: true)
    }

    private func setState(_ state: AgentSpeechQueueState) {
        guard self.state != state else { return }
        self.state = state
        diagnostics.record(
            category: .audio,
            event: "speech.state_changed",
            fields: ["state": String(describing: state)])
        onStateChange?(state)
    }

    nonisolated private static func milliseconds(from start: UInt64, to end: UInt64) -> UInt64 {
        guard end >= start else { return 0 }
        return (end - start) / 1_000_000
    }
}

private extension AgentSpeechInputFormat {
    var diagnosticName: String {
        switch self {
        case .legacyMarkdown: "legacy_markdown"
        case .agentAuthoredPlainText: "agent_authored_plain_text"
        }
    }
}

private extension AgentSpeechAdmissionPolicy {
    var diagnosticName: String {
        switch self {
        case .legacyNormalized: "legacy_normalized"
        case .agentAuthoredVerbatim: "agent_authored_verbatim"
        }
    }
}
