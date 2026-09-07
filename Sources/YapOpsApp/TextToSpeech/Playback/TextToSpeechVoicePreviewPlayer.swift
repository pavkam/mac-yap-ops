// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import YapOpsCore

struct TextToSpeechVoicePreviewRequest: Equatable, Sendable {
    let selection: TextToSpeechVoiceSelection
    let credential: String?
    let localeID: String
}

@MainActor
protocol TextToSpeechVoicePreviewing: AnyObject {
    func play(_ request: TextToSpeechVoicePreviewRequest) async throws
    func stop()
}

enum TextToSpeechVoicePreviewError: Error, Equatable, LocalizedError {
    case playbackFailed

    var errorDescription: String? {
        "The voice preview could not be played."
    }
}

@MainActor
final class TextToSpeechVoicePreviewPlayer: TextToSpeechVoicePreviewing {
    private static let sample = "Hello from YapOps. This is how I will sound."

    private let backendRegistry: TextToSpeechBackendRegistry
    private let audioPlayer: any AgentAudioDataPlaying
    private let systemSpeechPlayer: any AgentSystemSpeechPlaying
    private let diagnostics: any YapOpsDiagnosticRecording
    private var generation: UInt64 = 0
    private var playbackContinuation: CheckedContinuation<Void, any Error>?

    init(
        backendRegistry: TextToSpeechBackendRegistry,
        audioPlayer: any AgentAudioDataPlaying = SystemAgentAudioDataPlayer(),
        systemSpeechPlayer: any AgentSystemSpeechPlaying = SystemAgentSpeechPlayer(),
        diagnostics: any YapOpsDiagnosticRecording = YapOpsDiagnostics.shared
    ) {
        self.backendRegistry = backendRegistry
        self.audioPlayer = audioPlayer
        self.systemSpeechPlayer = systemSpeechPlayer
        self.diagnostics = diagnostics
    }

    func play(_ request: TextToSpeechVoicePreviewRequest) async throws {
        retireActivePreview()
        let activeGeneration = generation
        diagnostics.record(
            category: .audio,
            event: "voice_preview.started",
            fields: [
                "backend": request.selection.backendID.rawValue,
                "generation": String(activeGeneration),
            ])

        let prepared = try await backendRegistry.prepare(
            TextToSpeechPreparationRequest(
                text: Self.sample,
                localeID: request.localeID,
                voiceID: request.selection.voiceID),
            backendID: request.selection.backendID,
            credential: request.credential)
        try Task.checkCancellation()
        guard generation == activeGeneration else {
            throw CancellationError()
        }

        try await play(
            prepared,
            localeID: request.localeID,
            generation: activeGeneration)
        diagnostics.record(
            category: .audio,
            event: "voice_preview.finished",
            fields: [
                "backend": request.selection.backendID.rawValue,
                "generation": String(activeGeneration),
            ])
    }

    func stop() {
        let stoppedGeneration = generation
        retireActivePreview()
        diagnostics.record(
            category: .audio,
            event: "voice_preview.stopped",
            fields: [
                "previous_generation": String(stoppedGeneration),
                "generation": String(generation),
            ])
    }

    private func play(
        _ prepared: PreparedTextToSpeech,
        localeID: String,
        generation activeGeneration: UInt64
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            playbackContinuation = continuation
            let started: Bool
            switch prepared {
            case .audio(let data) where !data.isEmpty:
                started = audioPlayer.play(data) { [weak self] completed in
                    self?.finishPlayback(
                        generation: activeGeneration,
                        error: completed ? nil : TextToSpeechVoicePreviewError.playbackFailed)
                }
            case .systemVoice(let voiceID):
                started = systemSpeechPlayer.play(
                    text: Self.sample,
                    localeID: localeID,
                    voiceID: voiceID
                ) { [weak self] in
                    self?.finishPlayback(generation: activeGeneration, error: nil)
                }
            case .audio:
                started = false
            }
            guard !started else { return }
            finishPlayback(
                generation: activeGeneration,
                error: TextToSpeechVoicePreviewError.playbackFailed)
        }
    }

    private func retireActivePreview() {
        generation &+= 1
        let continuation = playbackContinuation
        playbackContinuation = nil
        audioPlayer.stop()
        systemSpeechPlayer.stop()
        continuation?.resume(throwing: CancellationError())
    }

    private func finishPlayback(
        generation activeGeneration: UInt64,
        error: (any Error)?
    ) {
        guard generation == activeGeneration, let continuation = playbackContinuation else {
            return
        }
        playbackContinuation = nil
        if let error {
            diagnostics.record(
                category: .audio,
                event: "voice_preview.playback_failed",
                level: .error,
                fields: ["generation": String(activeGeneration)])
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
