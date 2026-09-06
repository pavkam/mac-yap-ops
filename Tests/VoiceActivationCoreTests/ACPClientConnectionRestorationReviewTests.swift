// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationCore

private actor TokenGuardedRestorationRecipient {
    private let gate: AgentEventGate
    private let attempted = AgentEventSignal()
    private var currentToken: AgentRestorationToken?
    private var events: [AgentRunEvent] = []

    init(gate: AgentEventGate) {
        self.gate = gate
    }

    func receive(token: AgentRestorationToken, event: AgentRunEvent) async {
        currentToken = token
        await gate.pause()
        if currentToken == token {
            events.append(event)
        }
        await attempted.signal()
    }

    func retire() {
        currentToken = nil
    }

    func waitUntilAttempted() async {
        await attempted.wait()
    }

    func recordedEvents() -> [AgentRunEvent] {
        events
    }
}

private final class SignallingConnectionDiagnosticRecorder: VoiceActivationDiagnosticRecording,
    @unchecked Sendable
{
    private let stream: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation

    init() {
        let events = AsyncStream<String>.makeStream()
        stream = events.stream
        continuation = events.continuation
    }

    deinit {
        continuation.finish()
    }

    func record(
        category: VoiceActivationDiagnosticCategory,
        event: String,
        level: VoiceActivationDiagnosticLevel,
        fields: [String: String]
    ) {
        continuation.yield(event)
    }

    func flush() {}

    func wait(for expectedEvent: String) async {
        for await event in stream where event == expectedEvent {
            return
        }
    }
}

extension ACPClientConnectionTests {
    @Test func connect_WhenRestorationRemoteErrorArrives_RedactsEveryErrorSurface()
        async throws
    {
        let fixtures: [(
            need: AgentSessionRestorationNeed,
            load: Bool,
            resume: Bool,
            code: Int64,
            message: String,
            dataSecret: String,
            isUnavailable: Bool
        )] = [
            (
                .visibleHistory,
                true,
                false,
                -32_001,
                "private-load-message opaque-session-741",
                "private-load-data",
                false),
            (
                .contextOnly,
                false,
                true,
                -32_004,
                "private-resume-message opaque-session-852",
                "private-resume-data",
                false),
            (
                .visibleHistory,
                true,
                false,
                -32_603,
                "session opaque-session-963 is not found; private-missing-message",
                "private-missing-data",
                true),
        ]

        for fixture in fixtures {
            let transport = FakeACPTransport()
            let diagnostics = ConnectionDiagnosticRecorder()
            let task = restorationConnection(
                transport: transport,
                need: fixture.need,
                diagnostics: diagnostics)
            _ = await transport.nextSentMessage()
            try await transport.feed(restorationInitializeResponse(
                load: fixture.load,
                resume: fixture.resume))
            _ = await transport.nextSentMessage()
            try await transport.feed(.errorResponse(
                id: .integer(2),
                error: ACPJSONRPCError(
                    code: fixture.code,
                    message: fixture.message,
                    data: .object([
                        "sessionId": .string("opaque-session-963"),
                        "detail": .string(fixture.dataSecret),
                    ]))))

            let error: ACPClientError
            do {
                _ = try await task.value
                Issue.record("Expected restoration error")
                continue
            } catch let caught as ACPClientError {
                error = caught
            }

            if fixture.isUnavailable {
                #expect(error == .sessionUnavailable(
                    code: fixture.code,
                    message: "Saved agent session is unavailable."))
            } else {
                #expect(error == .remoteError(
                    code: fixture.code,
                    message: "Agent session restoration failed."))
            }
            for secret in [fixture.message, fixture.dataSecret, "opaque-session-963"] {
                #expect(!(error.errorDescription ?? "").contains(secret))
                #expect(!error.localizedDescription.contains(secret))
                #expect(!String(describing: error).contains(secret))
                #expect(!String(reflecting: error).contains(secret))
                for entry in diagnostics.snapshot() {
                    #expect(!entry.event.contains(secret))
                    #expect(!entry.fields.keys.contains(where: { $0.contains(secret) }))
                    #expect(!entry.fields.values.contains(where: { $0.contains(secret) }))
                }
            }
            #expect(await transport.observedTerminationCount() == 1)
        }
    }

    @Test func connect_WhenEnteredRestorationCallbackOutlivesCancellation_TokenRejectsMutation()
        async throws
    {
        let transport = FakeACPTransport()
        let gate = AgentEventGate()
        let recipient = TokenGuardedRestorationRecipient(gate: gate)
        let task = Task {
            do {
                return try await ACPClientConnection.connect(
                    transport: transport,
                    configuration: try makeConfiguration(),
                    restoration: try .init(sessionID: "saved", need: .visibleHistory),
                    onRestoredEvent: { token, event in
                        await recipient.receive(token: token, event: event)
                    })
            } catch {
                await recipient.retire()
                throw error
            }
        }
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: true, resume: false))
        _ = await transport.nextSentMessage()
        try await transport.feed(restoredAgentMessage(text: "late mutation"))
        try await transport.feed(.response(id: .integer(2), result: .object([:])))
        await gate.waitUntilEntered()

        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        await gate.open()
        await recipient.waitUntilAttempted()

        #expect(await recipient.recordedEvents().isEmpty)
        #expect(await transport.observedTerminationCount() == 1)
    }

    @Test func connect_WhenLoadDeliveryIsBlockedAndOutputEnds_RejectsReadyClosedConnection()
        async throws
    {
        let transport = FakeACPTransport()
        let diagnostics = SignallingConnectionDiagnosticRecorder()
        let gate = AgentEventGate()
        let recipient = TokenGuardedRestorationRecipient(gate: gate)
        let task = Task {
            do {
                return try await ACPClientConnection.connect(
                    transport: transport,
                    configuration: try makeConfiguration(),
                    restoration: try .init(sessionID: "saved", need: .visibleHistory),
                    onRestoredEvent: { token, event in
                        await recipient.receive(token: token, event: event)
                    },
                    diagnostics: diagnostics)
            } catch {
                await recipient.retire()
                throw error
            }
        }
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: true, resume: false))
        _ = await transport.nextSentMessage()
        try await transport.feed(restoredAgentMessage(text: "must stay retired"))
        try await transport.feed(.response(id: .integer(2), result: .object([:])))
        await gate.waitUntilEntered()

        await transport.finishStreams()
        await diagnostics.wait(for: "acp_client.receive_finished")
        await #expect(throws: ACPClientError.connectionClosed) { try await task.value }
        await gate.open()
        await recipient.waitUntilAttempted()

        #expect(await recipient.recordedEvents().isEmpty)
        #expect(await transport.observedTerminationCount() == 1)
    }

    @Test func connect_WhenResumeResponseIsValidatedThenOutputEnds_DoesNotReturnClosedConnection()
        async throws
    {
        let transport = FakeACPTransport()
        let diagnostics = SignallingConnectionDiagnosticRecorder()
        let responseGate = AgentEventGate()
        let task = Task {
            try await ACPClientConnection.connect(
                transport: transport,
                configuration: try makeConfiguration(),
                restoration: try .init(sessionID: "saved", need: .contextOnly),
                onRestoredEvent: { _, _ in },
                clientCapabilityFragments: [],
                afterRestorationResponseValidation: {
                    await responseGate.pause()
                },
                diagnostics: diagnostics)
        }
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: false, resume: true))
        _ = await transport.nextSentMessage()
        try await transport.feed(.response(id: .integer(2), result: .object([:])))
        await responseGate.waitUntilEntered()

        await transport.finishStreams()
        await diagnostics.wait(for: "acp_client.receive_finished")
        await responseGate.open()

        await #expect(throws: ACPClientError.connectionClosed) { try await task.value }
        #expect(await transport.observedTerminationCount() == 1)
    }
}
