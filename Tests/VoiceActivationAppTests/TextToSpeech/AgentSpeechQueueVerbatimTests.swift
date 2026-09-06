// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationApp
@testable import VoiceActivationCore

@MainActor
private final class VerbatimSystemSpeechPlayer: AgentSystemSpeechPlaying {
    private(set) var texts: [String] = []

    func play(
        text: String,
        localeID: String,
        voiceID: String?,
        completion: @escaping @MainActor () -> Void
    ) -> Bool {
        texts.append(text)
        return true
    }

    func stop() {}
}

private final class VerbatimDiagnosticRecorder: VoiceActivationDiagnosticRecording,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var values: [(String, [String: String])] = []

    func record(
        category: VoiceActivationDiagnosticCategory,
        event: String,
        level: VoiceActivationDiagnosticLevel,
        fields: [String: String]
    ) {
        lock.lock()
        values.append((event, fields))
        lock.unlock()
    }

    func flush() {}

    func contains(event: String, reason: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return values.contains { $0.0 == event && $0.1["reason"] == reason }
    }
}

@Suite(.timeLimit(.minutes(1)))
struct AgentSpeechQueueVerbatimTests {
    @MainActor @Test
    func verbatim_PreservesWhitespace() async throws {
        let player = VerbatimSystemSpeechPlayer()
        let queue = AgentSpeechQueue(systemSpeechPlayer: player)
        let text = "  Keep this\nexactly.  "

        queue.enqueue(request(text, policy: .agentAuthoredVerbatim))
        try await waitUntil { player.texts == [text] }

        #expect(player.texts == [text])
        queue.stop()
    }

    @MainActor @Test
    func verbatim_WhenFull_RejectsWithoutCoalescing() {
        let diagnostics = VerbatimDiagnosticRecorder()
        let queue = AgentSpeechQueue(diagnostics: diagnostics)
        for index in 0..<64 {
            queue.enqueue(request("Legacy \(index)."))
        }

        queue.enqueue(request("  exact  ", policy: .agentAuthoredVerbatim))

        #expect(diagnostics.contains(event: "speech.queue_rejected", reason: "queue_full"))
        queue.stop()
    }

    @MainActor @Test
    func verbatimBatch_WhenCombinedTextIsOversized_RejectsEveryUtterance() async throws {
        let player = VerbatimSystemSpeechPlayer()
        let diagnostics = VerbatimDiagnosticRecorder()
        let queue = AgentSpeechQueue(
            systemSpeechPlayer: player,
            diagnostics: diagnostics)

        let admitted = queue.enqueueVerbatimBatch([
            request(String(repeating: "a", count: 10_001), policy: .agentAuthoredVerbatim),
            request(String(repeating: "b", count: 10_000), policy: .agentAuthoredVerbatim),
        ])
        try await Task.sleep(for: .milliseconds(25))

        #expect(!admitted)
        #expect(player.texts.isEmpty)
        #expect(diagnostics.contains(event: "speech.queue_rejected", reason: "oversized"))
        queue.stop()
    }

    @MainActor @Test
    func verbatimBatch_WhenQueueIsFull_RejectsTheWholeBatch() {
        let diagnostics = VerbatimDiagnosticRecorder()
        let queue = AgentSpeechQueue(diagnostics: diagnostics)
        for index in 0..<64 {
            queue.enqueue(request("Legacy \(index)."))
        }

        let admitted = queue.enqueueVerbatimBatch([
            request("First exact option", policy: .agentAuthoredVerbatim),
            request("Second exact option", policy: .agentAuthoredVerbatim),
        ])

        #expect(!admitted)
        #expect(diagnostics.contains(event: "speech.queue_rejected", reason: "queue_full"))
        queue.stop()
    }

    @MainActor @Test
    func verbatim_WhenOversized_RejectsWithoutPrefixing() async throws {
        let player = VerbatimSystemSpeechPlayer()
        let diagnostics = VerbatimDiagnosticRecorder()
        let queue = AgentSpeechQueue(
            systemSpeechPlayer: player,
            diagnostics: diagnostics)

        queue.enqueue(request(
            String(repeating: "x", count: 20_001),
            policy: .agentAuthoredVerbatim))
        try await Task.sleep(for: .milliseconds(25))

        #expect(player.texts.isEmpty)
        #expect(diagnostics.contains(event: "speech.queue_rejected", reason: "oversized"))
        queue.stop()
    }

    @MainActor @Test
    func legacy_NormalizationRemainsUnchanged() async throws {
        let player = VerbatimSystemSpeechPlayer()
        let queue = AgentSpeechQueue(systemSpeechPlayer: player)

        queue.enqueue(request("  Legacy text.  "))
        try await waitUntil { player.texts == ["Legacy text."] }

        #expect(player.texts == ["Legacy text."])
        queue.stop()
    }

    @MainActor
    private func request(
        _ text: String,
        policy: AgentSpeechAdmissionPolicy = .legacyNormalized
    ) -> AgentSpeechRequest {
        AgentSpeechRequest(
            text: text,
            localeID: "en-US",
            configuration: .systemDefault,
            inputFormat: policy == .agentAuthoredVerbatim
                ? .agentAuthoredPlainText
                : .legacyMarkdown,
            admissionPolicy: policy)
    }

    @MainActor
    private func waitUntil(
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for speech playback")
    }
}
