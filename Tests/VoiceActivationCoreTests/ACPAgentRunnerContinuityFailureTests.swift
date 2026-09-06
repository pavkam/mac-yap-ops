// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationCore

@Suite(.serialized)
struct ACPAgentRunnerContinuityFailureTests {
    @Test func run_WhenBookmarkReadFails_StartsFreshAndRecordsSafeDiagnostic() async throws {
        let store = RecordingAgentContinuityStore(failures: [.read])
        let diagnostics = RunnerDiagnosticRecorder()
        let transport = FakeACPTransport()
        let runner = makeRunner(
            transports: [transport],
            store: store,
            diagnostics: diagnostics)
        let run = startRun(runner, profileID: UUID(), configuration: try configuration())

        try await establishNewSession(transport, sessionID: "fresh-after-read-failure")
        _ = await transport.nextSentMessage()
        try await transport.feed(promptResponse(id: 3))
        #expect(try await run.value == AgentRunResult(stopReason: .endTurn))

        let failures = diagnostics.snapshot().filter {
            $0.event == "continuity_store.read_failed"
        }
        #expect(failures.map(\.fields) == [["failure_category": "read"]])
    }

    @Test func reset_WhenStoreRemoveFails_PreservesRecordsAndReportsSafeDiagnostic()
        async throws
    {
        let profileID = UUID()
        let bookmark = matchingBookmark(
            profileID: profileID,
            configuration: try configuration())
        let marker = AgentInterruptedWorkMarker(
            key: .init(
                profileID: profileID,
                sessionID: bookmark.sessionID,
                occurrenceID: UUID()),
            state: .active)
        let store = RecordingAgentContinuityStore(
            bookmarks: [bookmark],
            markers: [marker],
            failures: [.remove])
        let diagnostics = RunnerDiagnosticRecorder()
        let runner = makeRunner(
            transports: [],
            store: store,
            diagnostics: diagnostics)

        await runner.reset(profileIDs: [profileID])

        #expect((await store.snapshot()).bookmarks == [bookmark])
        #expect((await store.snapshot()).interruptedWork == [marker])
        let failures = diagnostics.snapshot().filter {
            $0.event == "continuity_store.save_failed"
        }
        #expect(failures.map(\.fields) == [["failure_category": "remove"]])
    }

    @Test func run_WhenSettledMarkerClearFails_ReturnsSuccessAndRetainsMarker() async throws {
        let store = RecordingAgentContinuityStore(failures: [.clear])
        let diagnostics = RunnerDiagnosticRecorder()
        let transport = FakeACPTransport()
        let runner = makeRunner(
            transports: [transport],
            store: store,
            diagnostics: diagnostics)
        let run = startRun(runner, profileID: UUID(), configuration: try configuration())

        try await establishNewSession(transport, sessionID: "clear-failure")
        _ = await transport.nextSentMessage()
        try await transport.feed(promptResponse(id: 3))
        #expect(try await run.value == AgentRunResult(stopReason: .endTurn))

        #expect((await store.snapshot()).interruptedWork.count == 1)
        let failures = diagnostics.snapshot().filter {
            $0.event == "continuity_store.save_failed"
        }
        #expect(failures.map(\.fields) == [["failure_category": "clear"]])
    }

    @Test func run_WhenLoadReplaysHistory_EmitsOneTokenInStrictLifecycleOrder()
        async throws
    {
        let profileID = UUID()
        let configuration = try configuration()
        let store = RecordingAgentContinuityStore(bookmarks: [matchingBookmark(
            profileID: profileID,
            configuration: configuration)])
        let transport = FakeACPTransport()
        let recorder = RunnerStreamEventRecorder()
        let runner = makeRunner(transports: [transport], store: store)
        let run = startRun(
            runner,
            profileID: profileID,
            configuration: configuration,
            recorder: recorder)

        _ = await transport.nextSentMessage()
        try await transport.feed(initializeResponse(loadSession: true))
        #expect(await requestMethod(transport.nextSentMessage()) == "session/load")
        let restoredEvent = AgentRunEvent.agentMessageDelta(
            messageID: nil,
            text: "history")
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
        _ = await transport.nextSentMessage()
        try await transport.feed(promptResponse(id: 3))
        _ = try await run.value

        let events = await recorder.recordedEvents()
        guard events.count >= 3,
              case let .restorationStarted(token, sessionID) = events[0]
        else {
            Issue.record("Expected restoration lifecycle")
            return
        }
        #expect(sessionID == "saved-session")
        #expect(events[1] == .restored(token: token, event: restoredEvent))
        #expect(events[2] == .restorationCompleted(
            token: token,
            activation: .loaded(sessionID: "saved-session")))
        #expect(events.dropFirst(3).allSatisfy { event in
            if case .live = event { return true }
            return false
        })
    }

    @Test func run_TwiceOnLiveSession_UsesDistinctPromptOccurrenceKeys() async throws {
        let profileID = UUID()
        let configuration = try configuration()
        let store = RecordingAgentContinuityStore()
        let transport = FakeACPTransport()
        let runner = makeRunner(transports: [transport], store: store)

        let first = startRun(runner, profileID: profileID, configuration: configuration)
        try await establishNewSession(transport, sessionID: "reused-live-session")
        _ = await transport.nextSentMessage()
        try await transport.feed(promptResponse(id: 3))
        _ = try await first.value

        let second = startRun(runner, profileID: profileID, configuration: configuration)
        #expect(await requestMethod(transport.nextSentMessage()) == "session/prompt")
        try await transport.feed(promptResponse(id: 4))
        _ = try await second.value

        let calls = await store.recordedCalls()
        let markedKeys: [AgentInterruptedWorkKey] = calls.compactMap { call in
            guard case .mark(let key) = call else { return nil }
            return key
        }
        #expect(markedKeys.count == 2)
        #expect(markedKeys[0].profileID == profileID)
        #expect(markedKeys[0].sessionID == "reused-live-session")
        #expect(markedKeys[0].occurrenceID != markedKeys[1].occurrenceID)
    }

    @Test func run_WhenLiveCacheEvictsFifthProfile_RetainsAllDurableBookmarks()
        async throws
    {
        let count = ACPAgentRunner.maximumCachedSessions + 1
        let profiles = (0..<count).map { _ in UUID() }
        let configurations = try (0..<count).map { index in
            try configuration(workingDirectory: "/tmp/project-\(index)")
        }
        let transports = (0..<count).map { _ in FakeACPTransport() }
        let store = RecordingAgentContinuityStore()
        let runner = makeRunner(transports: transports, store: store)

        for index in 0..<count {
            let run = startRun(
                runner,
                profileID: profiles[index],
                configuration: configurations[index])
            try await establishNewSession(
                transports[index],
                sessionID: "session-\(index)")
            _ = await transports[index].nextSentMessage()
            try await transports[index].feed(promptResponse(id: 3))
            _ = try await run.value
        }

        let snapshot = await store.snapshot()
        #expect(Set(snapshot.bookmarks.map(\.profileID)) == Set(profiles))
        #expect(!(await store.recordedCalls()).contains { call in
            if case .remove = call { return true }
            return false
        })
        #expect(await transports[0].observedTerminationCount() == 1)
    }

    @Test func run_WhenFreshRestorationFallbackIsAlsoMissing_DoesNotStartThirdTransport()
        async throws
    {
        let profileID = UUID()
        let configuration = try configuration()
        let store = RecordingAgentContinuityStore(bookmarks: [matchingBookmark(
            profileID: profileID,
            configuration: configuration)])
        let restoring = FakeACPTransport()
        let fresh = FakeACPTransport()
        let unused = FakeACPTransport()
        let factory = RunnerTransportFactory(transports: [restoring, fresh, unused])
        let runner = ACPAgentRunner(
            transportFactory: factory,
            continuityStore: store,
            settleClock: ImmediateACPAgentRunnerClock())
        let run = startRun(
            runner,
            profileID: profileID,
            configuration: configuration)

        _ = await restoring.nextSentMessage()
        try await restoring.feed(initializeResponse(loadSession: true))
        _ = await restoring.nextSentMessage()
        try await restoring.feed(sessionUnavailableResponse(id: 2))

        try await establishNewSession(fresh, sessionID: "replacement")
        _ = await fresh.nextSentMessage()
        try await fresh.feed(sessionUnavailableResponse(id: 3))
        await #expect(throws: ACPClientError.sessionUnavailable(
            code: -32_002,
            message: "missing")) {
            try await run.value
        }

        #expect(await factory.createdConfigurations().count == 2)
        #expect(await unused.allSentMessages().isEmpty)
    }

    private func configuration(
        workingDirectory: String = "/tmp/project"
    ) throws -> AgentHarnessConfiguration {
        try AgentHarnessConfiguration(
            preset: .codex,
            displayName: "Configured Agent",
            executablePath: "/usr/bin/agent",
            arguments: ["acp"],
            workingDirectory: workingDirectory,
            permissionPolicy: .ask)
    }

    private func matchingBookmark(
        profileID: UUID,
        configuration: AgentHarnessConfiguration
    ) -> AgentSessionBookmark {
        AgentSessionBookmark(
            profileID: profileID,
            sessionID: "saved-session",
            providerFingerprint: AgentProviderFingerprint.make(configuration: configuration),
            lastAccessOrdinal: 1)
    }

    private func makeRunner(
        transports: [FakeACPTransport],
        store: any AgentContinuityStoring,
        diagnostics: any VoiceActivationDiagnosticRecording = VoiceActivationDiagnostics.shared
    ) -> ACPAgentRunner {
        ACPAgentRunner(
            transportFactory: RunnerTransportFactory(transports: transports),
            continuityStore: store,
            settleClock: ImmediateACPAgentRunnerClock(),
            diagnostics: diagnostics)
    }

    private func startRun(
        _ runner: ACPAgentRunner,
        profileID: UUID,
        configuration: AgentHarnessConfiguration,
        recorder: RunnerStreamEventRecorder? = nil
    ) -> Task<AgentRunResult, any Error> {
        Task {
            try await runner.run(
                profileID: profileID,
                configuration: configuration,
                prompt: AgentPrompt(request: "request", context: nil),
                restorationNeed: .visibleHistory,
                onEvent: { event in await recorder?.record(event) })
        }
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
                "agentInfo": .object(["name": .string("test-agent")]),
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

    private func sessionUnavailableResponse(id: Int64) -> ACPMessage {
        .errorResponse(
            id: .integer(id),
            error: ACPJSONRPCError(
                code: -32_002,
                message: "missing",
                data: .object([
                    "resourceType": .string("session"),
                    "resourceId": .string("saved-session"),
                ])))
    }
}
