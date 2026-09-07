// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import YapOpsCore

actor GuardedRunnerRestorationRecorder {
    private let restoredGate: RunnerEventGate
    private var currentToken: AgentRestorationToken?
    private var accepted: [AgentRunStreamEvent] = []

    init(restoredGate: RunnerEventGate) {
        self.restoredGate = restoredGate
    }

    func handle(_ event: AgentRunStreamEvent) async {
        switch event {
        case .restorationStarted(let token, _):
            currentToken = token
            accepted.append(event)
        case .restored(let token, _):
            await restoredGate.wait()
            guard currentToken == token else { return }
            accepted.append(event)
        case .restorationAborted(let token):
            guard currentToken == token else { return }
            currentToken = nil
            accepted.append(event)
        case .restorationCompleted(let token, _):
            guard currentToken == token else { return }
            currentToken = nil
            accepted.append(event)
        case .live:
            accepted.append(event)
        }
    }

    func events() -> [AgentRunStreamEvent] {
        accepted
    }
}

@Suite(.serialized)
struct ACPAgentRunnerContinuityLifecycleTests {
    @Test func run_WhenPromptWriteFails_ClearsOnlyNewPrepublicationMarker() async throws {
        let markGate = RunnerEventGate()
        let store = RecordingAgentContinuityStore(markGate: markGate)
        let transport = FakeACPTransport()
        let runner = makeRunner(transport: transport, store: store)
        let run = startRun(runner)

        try await establishNewSession(transport, sessionID: "prepublish")
        await markGate.waitUntilEntered()
        await transport.failNextSend()
        await markGate.open()
        await #expect(throws: ACPClientError.connectionClosed) {
            try await run.value
        }

        let calls = await store.recordedCalls()
        let marked = calls.compactMap { call -> AgentInterruptedWorkKey? in
            guard case .mark(let key) = call else { return nil }
            return key
        }
        let cleared = calls.compactMap { call -> AgentInterruptedWorkKey? in
            guard case .clear(let key) = call else { return nil }
            return key
        }
        #expect(marked.count == 1)
        #expect(cleared == marked)
    }

    @Test func run_WhenConnectionFailsAfterPromptPublication_DoesNotRetryPrompt()
        async throws
    {
        let store = RecordingAgentContinuityStore()
        let transport = FakeACPTransport()
        let factory = RunnerTransportFactory(transports: [transport])
        let runner = ACPAgentRunner(
            transportFactory: factory,
            continuityStore: store,
            settleClock: ImmediateACPAgentRunnerClock())
        let run = startRun(runner)

        try await establishNewSession(transport, sessionID: "published")
        #expect(await requestMethod(transport.nextSentMessage()) == "session/prompt")
        await transport.failOutput()
        await #expect(throws: (any Error).self) { try await run.value }

        #expect(await factory.createdConfigurations().count == 1)
        #expect((await store.snapshot()).interruptedWork.count == 1)
        #expect(!(await store.recordedCalls()).contains { call in
            if case .clear = call { return true }
            return false
        })
    }

    @Test func run_WhenOuterDeliveryIsBlocked_ClearsMarkerOnlyAfterDrain() async throws {
        let deliveryGate = RunnerEventGate()
        let responseGate = RunnerEventGate()
        let store = RecordingAgentContinuityStore()
        let transport = FakeACPTransport()
        let runner = ACPAgentRunner(
            transportFactory: RunnerTransportFactory(transports: [transport]),
            continuityStore: store,
            settleClock: ImmediateACPAgentRunnerClock(),
            testingHooks: ACPAgentRunnerTestingHooks(
                afterPromptResponseBeforeDeliveryDrain: { await responseGate.wait() }))
        let run = Task {
            try await runner.run(
                profileID: UUID(),
                configuration: try configuration(),
                prompt: AgentPrompt(request: "request", context: nil),
                onEvent: { event in
                    if case .live = event { await deliveryGate.wait() }
                })
        }

        try await establishNewSession(transport, sessionID: "drain")
        await deliveryGate.waitUntilEntered()
        _ = await transport.nextSentMessage()
        try await transport.feed(promptResponse(id: 3))
        await responseGate.waitUntilEntered()
        #expect(!(await store.recordedCalls()).contains { call in
            if case .clear = call { return true }
            return false
        })
        await responseGate.open()
        await deliveryGate.open()
        _ = try await run.value
        #expect((await store.recordedCalls()).contains { call in
            if case .clear = call { return true }
            return false
        })
    }

    @Test func shutdown_RetainsBookmarksButMarksActiveWorkInterrupted() async throws {
        let store = RecordingAgentContinuityStore()
        let transport = FakeACPTransport()
        let runner = makeRunner(transport: transport, store: store)
        let run = startRun(runner)

        try await establishNewSession(transport, sessionID: "shutdown-session")
        _ = await transport.nextSentMessage()
        await runner.shutdown()
        _ = try? await run.value

        let beforeReconciliation = await store.snapshot()
        #expect(beforeReconciliation.bookmarks.map(\.sessionID) == ["shutdown-session"])
        #expect(beforeReconciliation.interruptedWork.map(\.state) == [.active])
        let interrupted = try await store.reconcileInterruptedWork()
        #expect(interrupted.map(\.state) == [.interruptedByProcessExit])
    }

    @Test func run_WhenCancelledDuringRestore_DoesNotPublishLateRestoredOrLiveEvents()
        async throws
    {
        let profileID = UUID()
        let configuration = try configuration()
        let store = RecordingAgentContinuityStore(bookmarks: [AgentSessionBookmark(
            profileID: profileID,
            sessionID: "saved-session",
            providerFingerprint: AgentProviderFingerprint.make(configuration: configuration),
            lastAccessOrdinal: 1)])
        let transport = FakeACPTransport()
        let cancellationClock = ManualACPAgentRunnerClock()
        let restoredGate = RunnerEventGate()
        let recorder = GuardedRunnerRestorationRecorder(restoredGate: restoredGate)
        let runner = ACPAgentRunner(
            transportFactory: RunnerTransportFactory(transports: [transport]),
            continuityStore: store,
            clock: cancellationClock,
            settleClock: ImmediateACPAgentRunnerClock())
        let run = Task {
            try await runner.run(
                profileID: profileID,
                configuration: configuration,
                prompt: AgentPrompt(request: "request", context: nil),
                onEvent: { await recorder.handle($0) })
        }

        _ = await transport.nextSentMessage()
        try await transport.feed(initializeResponse(loadSession: true))
        #expect(await requestMethod(transport.nextSentMessage()) == "session/load")
        try await transport.feed(.notification(
            method: "session/update",
            params: .object([
                "sessionId": .string("saved-session"),
                "update": .object([
                    "sessionUpdate": .string("agent_message_chunk"),
                    "content": .object([
                        "type": .string("text"),
                        "text": .string("history"),
                    ]),
                ]),
            ])))
        try await transport.feed(.response(id: .integer(2), result: .object([:])))
        await restoredGate.waitUntilEntered()

        let cancellation = Task { await runner.cancel() }
        await cancellationClock.waitUntilSleeping()
        await cancellationClock.advance()
        await cancellation.value
        await restoredGate.open()
        _ = try? await run.value

        let events = await recorder.events()
        #expect(events.count == 2)
        guard case let .restorationStarted(token, _) = events[0] else {
            Issue.record("Expected restoration start")
            return
        }
        #expect(events[1] == .restorationAborted(token: token))
    }

    private func makeRunner(
        transport: FakeACPTransport,
        store: any AgentContinuityStoring
    ) -> ACPAgentRunner {
        ACPAgentRunner(
            transportFactory: RunnerTransportFactory(transports: [transport]),
            continuityStore: store,
            settleClock: ImmediateACPAgentRunnerClock())
    }

    private func startRun(_ runner: ACPAgentRunner) -> Task<AgentRunResult, any Error> {
        Task {
            try await runner.run(
                profileID: UUID(),
                configuration: try configuration(),
                prompt: AgentPrompt(request: "request", context: nil),
                onEvent: { _ in })
        }
    }

    private func configuration() throws -> AgentHarnessConfiguration {
        try AgentHarnessConfiguration(
            preset: .codex,
            displayName: "Configured Agent",
            executablePath: "/usr/bin/agent",
            arguments: ["acp"],
            workingDirectory: "/tmp/project",
            permissionPolicy: .ask)
    }

    private func establishNewSession(
        _ transport: FakeACPTransport,
        sessionID: String
    ) async throws {
        #expect(await requestMethod(transport.nextSentMessage()) == "initialize")
        try await transport.feed(initializeResponse(loadSession: false))
        #expect(await requestMethod(transport.nextSentMessage()) == "session/new")
        try await transport.feed(.response(
            id: .integer(2),
            result: .object(["sessionId": .string(sessionID)])))
    }

    private func initializeResponse(loadSession: Bool) -> ACPMessage {
        .response(
            id: .integer(1),
            result: .object([
                "protocolVersion": .integer(1),
                "agentCapabilities": .object(["loadSession": .bool(loadSession)]),
                "agentInfo": .object([
                    "name": .string("test-agent"),
                    "version": .string("1.0.0"),
                ]),
                "authMethods": .array([]),
            ]))
    }

    private func promptResponse(id: Int64) -> ACPMessage {
        .response(
            id: .integer(id),
            result: .object(["stopReason": .string("end_turn")]))
    }

    private func requestMethod(_ message: ACPMessage) -> String? {
        guard case let .request(_, method, _) = message else { return nil }
        return method
    }
}
