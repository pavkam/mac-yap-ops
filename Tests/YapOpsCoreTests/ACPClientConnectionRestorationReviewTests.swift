// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import YapOpsCore

private actor TokenGuardedRestorationRecipient {
    private let attempted = AgentEventSignal()
    private var currentToken: AgentRestorationToken?
    private var attemptedTokens: [AgentRestorationToken] = []
    private var events: [AgentRunEvent] = []

    init(currentToken: AgentRestorationToken) {
        self.currentToken = currentToken
    }

    func receive(token: AgentRestorationToken, event: AgentRunEvent) async {
        attemptedTokens.append(token)
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

    func observedTokens() -> [AgentRestorationToken] {
        attemptedTokens
    }

    func owns(_ token: AgentRestorationToken) -> Bool {
        currentToken == token
    }
}

private final class SignallingConnectionDiagnosticRecorder: YapOpsDiagnosticRecording,
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
        category: YapOpsDiagnosticCategory,
        event: String,
        level: YapOpsDiagnosticLevel,
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
    @Test func connect_WhenLoadSucceeds_CallbackUsesPreEstablishedRequestToken() async throws {
        let transport = FakeACPTransport()
        let token = AgentRestorationToken(
            rawValue: try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111")))
        let request = try AgentSessionRestorationRequest(
            sessionID: "saved",
            need: .visibleHistory,
            token: token)
        let recipient = TokenGuardedRestorationRecipient(currentToken: token)
        let task = Task {
            try await ACPClientConnection.connect(
                transport: transport,
                configuration: try makeConfiguration(),
                restoration: request,
                onRestoredEvent: { callbackToken, event in
                    await recipient.receive(token: callbackToken, event: event)
                })
        }
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: true, resume: false))
        _ = await transport.nextSentMessage()
        try await transport.feed(restoredAgentMessage(text: "history"))
        try await transport.feed(.response(id: .integer(2), result: .object([:])))

        let result = try await task.value
        #expect(request.token == token)
        #expect(await recipient.observedTokens() == [token])
        #expect(await recipient.recordedEvents() == [
            .agentMessageDelta(messageID: nil, text: "history"),
        ])
        await result.connection.close()
    }

    @Test func connect_WhenLoadHasNoReplay_CallerStillOwnsRequestToken() async throws {
        let transport = FakeACPTransport()
        let token = AgentRestorationToken(
            rawValue: try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")))
        let request = try AgentSessionRestorationRequest(
            sessionID: "saved",
            need: .visibleHistory,
            token: token)
        let recipient = TokenGuardedRestorationRecipient(currentToken: token)
        let task = Task {
            try await ACPClientConnection.connect(
                transport: transport,
                configuration: try makeConfiguration(),
                restoration: request,
                onRestoredEvent: { callbackToken, event in
                    await recipient.receive(token: callbackToken, event: event)
                })
        }
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: true, resume: false))
        _ = await transport.nextSentMessage()
        try await transport.feed(.response(id: .integer(2), result: .object([:])))

        let result = try await task.value
        #expect(request.token == token)
        #expect(await recipient.owns(token))
        #expect(await recipient.observedTokens().isEmpty)
        #expect(await recipient.recordedEvents().isEmpty)
        await result.connection.close()
    }

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
        let token = AgentRestorationToken(
            rawValue: try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")))
        let request = try AgentSessionRestorationRequest(
            sessionID: "saved",
            need: .visibleHistory,
            token: token)
        let preRecipientGate = AgentEventGate()
        let recipient = TokenGuardedRestorationRecipient(currentToken: token)
        let task = Task {
            do {
                return try await ACPClientConnection.connect(
                    transport: transport,
                    configuration: try makeConfiguration(),
                    restoration: request,
                    onRestoredEvent: { callbackToken, event in
                        await preRecipientGate.pause()
                        await recipient.receive(token: callbackToken, event: event)
                    })
            } catch {
                await recipient.retire()
                throw error
            }
        }
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: true, resume: false))
        _ = await transport.nextSentMessage()
        try await transport.feed(restoredAgentMessage(
            text: "late first mutation",
            messageID: "first"))
        try await transport.feed(restoredAgentMessage(
            text: "queued second mutation",
            messageID: "second"))
        try await transport.feed(.response(id: .integer(2), result: .object([:])))
        await preRecipientGate.waitUntilEntered()

        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!(await recipient.owns(token)))
        await preRecipientGate.open()
        await recipient.waitUntilAttempted()

        #expect(await recipient.observedTokens() == [token])
        #expect(await recipient.recordedEvents().isEmpty)
        #expect(await transport.observedTerminationCount() == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func connect_WhenLoadDeliveryIsBlockedAndOutputEnds_RejectsReadyClosedConnection()
        async throws
    {
        let transport = FakeACPTransport()
        let token = AgentRestorationToken(
            rawValue: try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444")))
        let request = try AgentSessionRestorationRequest(
            sessionID: "saved",
            need: .visibleHistory,
            token: token)
        let preRecipientGate = AgentEventGate()
        let recipient = TokenGuardedRestorationRecipient(currentToken: token)
        let task = Task {
            do {
                return try await ACPClientConnection.connect(
                    transport: transport,
                    configuration: try makeConfiguration(),
                    restoration: request,
                    onRestoredEvent: { callbackToken, event in
                        await preRecipientGate.pause()
                        await recipient.receive(token: callbackToken, event: event)
                    })
            } catch {
                await recipient.retire()
                throw error
            }
        }
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: true, resume: false))
        _ = await transport.nextSentMessage()
        try await transport.feed(restoredAgentMessage(
            text: "late first mutation",
            messageID: "first"))
        try await transport.feed(restoredAgentMessage(
            text: "queued second mutation",
            messageID: "second"))
        try await transport.feed(.response(id: .integer(2), result: .object([:])))
        await preRecipientGate.waitUntilEntered()

        await transport.finishStreams()
        await #expect(throws: ACPClientError.connectionClosed) { try await task.value }
        #expect(!(await recipient.owns(token)))
        await preRecipientGate.open()
        await recipient.waitUntilAttempted()

        #expect(await recipient.observedTokens() == [token])
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
