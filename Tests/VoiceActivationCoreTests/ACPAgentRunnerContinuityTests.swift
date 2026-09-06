// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationCore

actor RunnerStreamEventRecorder {
    private var events: [AgentRunStreamEvent] = []

    func record(_ event: AgentRunStreamEvent) {
        events.append(event)
    }

    func recordedEvents() -> [AgentRunStreamEvent] {
        events
    }
}

struct ImmediateACPAgentRunnerClock: ACPAgentRunnerClock {
    func sleep(for duration: Duration) async {}
}

@Suite(.serialized)
struct ACPAgentRunnerContinuityTests {
    @Test func run_AfterRunnerReplacement_LoadsSavedCompatibleSessionBeforePrompt()
        async throws
    {
        try await assertRunnerReplacementLoadsSavedSession()
    }

    @Test func run_WhenLoadCompletes_ComposesContinuityBeforeEncodingPrompt() async throws {
        try await assertRunnerReplacementLoadsSavedSession()
    }

    private func assertRunnerReplacementLoadsSavedSession() async throws {
        let store = InMemoryAgentContinuityStore()
        let profileID = UUID()
        let configuration = try makeConfiguration()
        let firstTransport = FakeACPTransport()
        let firstRunner = ACPAgentRunner(
            transportFactory: RunnerTransportFactory(transports: [firstTransport]),
            continuityStore: store,
            settleClock: ImmediateACPAgentRunnerClock())
        let firstRun = Task {
            try await firstRunner.run(
                profileID: profileID,
                configuration: configuration,
                prompt: AgentPrompt(request: "first", context: nil),
                restorationNeed: .visibleHistory,
                onEvent: { _ in })
        }

        try await establishNewSession(
            firstTransport,
            workingDirectory: configuration.workingDirectory,
            sessionID: "persisted")
        _ = await firstTransport.nextSentMessage()
        try await firstTransport.feed(promptResponse(id: 3))
        _ = try await firstRun.value
        await firstRunner.shutdown()

        let secondTransport = FakeACPTransport()
        let secondRunner = ACPAgentRunner(
            transportFactory: RunnerTransportFactory(transports: [secondTransport]),
            continuityStore: store,
            settleClock: ImmediateACPAgentRunnerClock())
        let recorder = RunnerStreamEventRecorder()
        let secondRun = Task {
            try await secondRunner.run(
                profileID: profileID,
                configuration: configuration,
                prompt: AgentPrompt(request: "follow-up", context: nil),
                restorationNeed: .visibleHistory,
                onEvent: { await recorder.record($0) })
        }

        #expect(await requestMethod(secondTransport.nextSentMessage()) == "initialize")
        try await secondTransport.feed(initializeResponse(loadSession: true))
        let load = await secondTransport.nextSentMessage()
        #expect(requestMethod(load) == "session/load")
        #expect(encodedSessionID(load) == "persisted")
        try await secondTransport.feed(.response(id: .integer(2), result: .object([:])))
        let prompt = await secondTransport.nextSentMessage()
        #expect(requestMethod(prompt) == "session/prompt")
        let blocks = promptTextBlocks(prompt)
        #expect(blocks.contains { value in
            value.contains("\"sessionState\":\"loaded\"")
        })
        #expect(blocks.last == "follow-up")
        try await secondTransport.feed(promptResponse(id: 3))
        _ = try await secondRun.value

        let events = await recorder.recordedEvents()
        guard case let .restorationStarted(token, sessionID) = events.first else {
            Issue.record("Expected restoration start")
            return
        }
        #expect(sessionID == "persisted")
        #expect(events.contains(.restorationCompleted(
            token: token,
            activation: .loaded(sessionID: "persisted"))))
    }

    @Test func run_WhenFingerprintDiffers_NeverSendsSavedSessionID() async throws {
        let profileID = UUID()
        let oldConfiguration = try makeConfiguration()
        let configuration = try AgentHarnessConfiguration(
            preset: .codex,
            displayName: "Configured Agent",
            executablePath: "/usr/bin/agent-v2",
            arguments: ["acp"],
            workingDirectory: "/tmp/project",
            permissionPolicy: .ask)
        let store = RecordingAgentContinuityStore(bookmarks: [matchingBookmark(
            profileID: profileID,
            configuration: oldConfiguration,
            sessionID: "saved-secret-id")])
        let transport = FakeACPTransport()
        let runner = makeRunner(transport: transport, store: store)
        let run = startRun(runner, profileID: profileID, configuration: configuration)

        #expect(await requestMethod(transport.nextSentMessage()) == "initialize")
        try await transport.feed(initializeResponse(loadSession: true))
        #expect(await requestMethod(transport.nextSentMessage()) == "session/new")
        try await transport.feed(.response(
            id: .integer(2),
            result: .object(["sessionId": .string("fresh-session")])))
        #expect(await requestMethod(transport.nextSentMessage()) == "session/prompt")
        try await transport.feed(promptResponse(id: 3))
        _ = try await run.value

        let bytes = await transport.allRawFrames().reduce(into: Data()) { $0.append($1) }
        #expect(!String(decoding: bytes, as: UTF8.self).contains("saved-secret-id"))
        #expect((await store.snapshot()).bookmarks.map(\.sessionID) == ["fresh-session"])
    }

    @Test func run_WhenOnlyDisplayAndPermissionChange_ReopensSavedSession() async throws {
        let profileID = UUID()
        let original = try makeConfiguration()
        let updated = try AgentHarnessConfiguration(
            preset: original.preset,
            displayName: "Renamed agent",
            executablePath: original.executablePath,
            arguments: original.arguments,
            workingDirectory: original.workingDirectory,
            permissionPolicy: .rejectAlways,
            systemPrompt: original.systemPrompt)
        let firstTransport = FakeACPTransport()
        let secondTransport = FakeACPTransport()
        let factory = RunnerTransportFactory(transports: [firstTransport, secondTransport])
        let store = RecordingAgentContinuityStore()
        let runner = ACPAgentRunner(transportFactory: factory, continuityStore: store)
        let firstRun = startRun(runner, profileID: profileID, configuration: original)

        try await establishNewSession(
            firstTransport,
            workingDirectory: original.workingDirectory,
            sessionID: "saved-session")
        _ = await firstTransport.nextSentMessage()
        try await firstTransport.feed(promptResponse(id: 3))
        _ = try await firstRun.value

        let secondRun = startRun(runner, profileID: profileID, configuration: updated)
        #expect(await requestMethod(secondTransport.nextSentMessage()) == "initialize")
        #expect(await firstTransport.observedTerminationCount() == 1)
        try await secondTransport.feed(initializeResponse(loadSession: true))
        let restoration = await secondTransport.nextSentMessage()
        #expect(requestMethod(restoration) == "session/load")
        guard case .request(_, _, .object(let parameters)) = restoration else {
            Issue.record("Expected session/load request")
            return
        }
        #expect(parameters["sessionId"] == .string("saved-session"))
        try await secondTransport.feed(.response(id: .integer(2), result: .object([:])))
        _ = await secondTransport.nextSentMessage()
        try await secondTransport.feed(promptResponse(id: 3))
        _ = try await secondRun.value
    }

    @Test func run_WhenRestoreUnsupported_ClearsBookmarkAndStartsNewSession() async throws {
        try await assertUnsupportedRestorationStartsFreshWithContinuity()
    }

    @Test func run_WhenRestoreUnsupported_SendsTypedContinuityStatusBeforeUntouchedRequest()
        async throws
    {
        try await assertUnsupportedRestorationStartsFreshWithContinuity()
    }

    private func assertUnsupportedRestorationStartsFreshWithContinuity() async throws {
        let profileID = UUID()
        let configuration = try makeConfiguration()
        let store = RecordingAgentContinuityStore(bookmarks: [matchingBookmark(
            profileID: profileID,
            configuration: configuration)])
        let transport = FakeACPTransport()
        let factory = RunnerTransportFactory(transports: [transport])
        let recorder = RunnerStreamEventRecorder()
        let runner = ACPAgentRunner(
            transportFactory: factory,
            continuityStore: store,
            settleClock: ImmediateACPAgentRunnerClock())
        let run = startRun(
            runner,
            profileID: profileID,
            configuration: configuration,
            recorder: recorder)

        _ = await transport.nextSentMessage()
        try await transport.feed(initializeResponse(loadSession: false))
        #expect(await requestMethod(transport.nextSentMessage()) == "session/new")
        try await transport.feed(.response(
            id: .integer(2),
            result: .object(["sessionId": .string("unsupported-fresh")])))
        let prompt = await transport.nextSentMessage()
        let blocks = promptTextBlocks(prompt)
        #expect(blocks.contains {
            $0.contains("fresh_because_restoration_unsupported")
        })
        #expect(blocks.last == "request")
        try await transport.feed(promptResponse(id: 3))
        _ = try await run.value

        #expect(await factory.createdConfigurations().count == 1)
        #expect(await transport.allSentMessages().filter {
            requestMethod($0) == "session/prompt"
        }.count == 1)
        let calls = await store.recordedCalls()
        #expect(calls.contains(.remove([profileID])))
        #expect((await store.snapshot()).bookmarks.map(\.sessionID) == ["unsupported-fresh"])
        guard case let .restorationStarted(token, _) = await recorder.recordedEvents().first else {
            Issue.record("Expected restoration start")
            return
        }
        #expect(await recorder.recordedEvents().contains(.restorationCompleted(
            token: token,
            activation: .freshBecauseRestorationUnsupported(
                sessionID: "unsupported-fresh"))))
    }

    @Test func run_WhenLoadSaysMissingBeforePrompt_ClosesThenRetriesNewExactlyOnce()
        async throws
    {
        try await assertMissingLoadStartsOneFreshPrompt()
    }

    @Test func run_WhenFreshFallbackCompletes_ComposesFreshContinuityBeforeEncodingPrompt()
        async throws
    {
        try await assertMissingLoadStartsOneFreshPrompt()
    }

    private func assertMissingLoadStartsOneFreshPrompt() async throws {
        let profileID = UUID()
        let configuration = try makeConfiguration()
        let store = RecordingAgentContinuityStore(bookmarks: [matchingBookmark(
            profileID: profileID,
            configuration: configuration)])
        let restoring = FakeACPTransport()
        let fresh = FakeACPTransport()
        let factory = RunnerTransportFactory(transports: [restoring, fresh])
        let runner = ACPAgentRunner(
            transportFactory: factory,
            continuityStore: store,
            settleClock: ImmediateACPAgentRunnerClock())
        let run = startRun(runner, profileID: profileID, configuration: configuration)

        _ = await restoring.nextSentMessage()
        try await restoring.feed(initializeResponse(loadSession: true))
        let load = await restoring.nextSentMessage()
        #expect(requestMethod(load) == "session/load")
        try await restoring.feed(sessionUnavailableResponse(id: 2))

        _ = await fresh.nextSentMessage()
        try await fresh.feed(initializeResponse(loadSession: false))
        #expect(await requestMethod(fresh.nextSentMessage()) == "session/new")
        try await fresh.feed(.response(
            id: .integer(2),
            result: .object(["sessionId": .string("fallback-session")])))
        let prompt = await fresh.nextSentMessage()
        #expect(requestMethod(prompt) == "session/prompt")
        let blocks = promptTextBlocks(prompt)
        #expect(blocks.contains {
            $0.contains("fresh_after_unavailable_bookmark")
        })
        #expect(blocks.last == "request")
        try await fresh.feed(promptResponse(id: 3))
        _ = try await run.value

        #expect(await factory.createdConfigurations().count == 2)
        #expect(await restoring.allSentMessages().filter {
            requestMethod($0) == "session/prompt"
        }.isEmpty)
        #expect(await fresh.allSentMessages().filter {
            requestMethod($0) == "session/prompt"
        }.count == 1)
    }

    @Test func run_WhenBookmarkSaveFails_CompletesLiveTurnAndRecordsSafeDiagnostic()
        async throws
    {
        let store = RecordingAgentContinuityStore(failures: [.save])
        let diagnostics = RunnerDiagnosticRecorder()
        let transport = FakeACPTransport()
        let runner = ACPAgentRunner(
            transportFactory: RunnerTransportFactory(transports: [transport]),
            continuityStore: store,
            settleClock: ImmediateACPAgentRunnerClock(),
            diagnostics: diagnostics)
        let run = startRun(
            runner,
            profileID: UUID(),
            configuration: try makeConfiguration())

        try await establishNewSession(
            transport,
            workingDirectory: "/tmp/project",
            sessionID: "live-session")
        _ = await transport.nextSentMessage()
        try await transport.feed(promptResponse(id: 3))
        #expect(try await run.value == AgentRunResult(stopReason: .endTurn))
        let failures = diagnostics.snapshot().filter {
            $0.event == "continuity_store.save_failed"
        }
        #expect(failures.map(\.fields) == [["failure_category": "save"]])
    }

    @Test func run_WhenPromptBegins_WritesActiveMarkerBeforePromptFrame() async throws {
        let markGate = RunnerEventGate()
        let store = RecordingAgentContinuityStore(markGate: markGate)
        let transport = FakeACPTransport()
        let runner = makeRunner(transport: transport, store: store)
        let run = startRun(
            runner,
            profileID: UUID(),
            configuration: try makeConfiguration())

        try await establishNewSession(
            transport,
            workingDirectory: "/tmp/project",
            sessionID: "marked-session")
        await markGate.waitUntilEntered()
        #expect(await transport.allSentMessages().map(requestMethod) == [
            "initialize", "session/new",
        ])
        await markGate.open()
        #expect(await requestMethod(transport.nextSentMessage()) == "session/prompt")
        try await transport.feed(promptResponse(id: 3))
        _ = try await run.value
    }

    @Test func run_WhenMarkFails_DoesNotPublishPromptFrame() async throws {
        let store = RecordingAgentContinuityStore(failures: [.mark])
        let transport = FakeACPTransport()
        let runner = makeRunner(transport: transport, store: store)
        let run = startRun(
            runner,
            profileID: UUID(),
            configuration: try makeConfiguration())

        try await establishNewSession(
            transport,
            workingDirectory: "/tmp/project",
            sessionID: "safe-session")
        await #expect(throws: ACPClientError.promptPublicationPreparationFailed) {
            try await run.value
        }
        #expect(await transport.allSentMessages().map(requestMethod) == [
            "initialize", "session/new",
        ])
    }

    @Test func run_WhenPromptSettles_ClearsOnlyMatchingOccurrenceKey() async throws {
        let store = RecordingAgentContinuityStore()
        let transport = FakeACPTransport()
        let runner = makeRunner(transport: transport, store: store)
        let run = startRun(
            runner,
            profileID: UUID(),
            configuration: try makeConfiguration())

        try await establishNewSession(
            transport,
            workingDirectory: "/tmp/project",
            sessionID: "settled-session")
        _ = await transport.nextSentMessage()
        try await transport.feed(promptResponse(id: 3))
        _ = try await run.value

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

    @Test func run_WhenProviderTaskIDIsReused_PreservesEachLocalOccurrence() {
        let profileID = UUID()
        let first = AgentInterruptedWorkMarker(
            key: .init(profileID: profileID, sessionID: "session", occurrenceID: UUID()),
            providerTaskID: "reused-task",
            state: .interruptedByProcessExit)
        let second = AgentInterruptedWorkMarker(
            key: .init(profileID: profileID, sessionID: "session", occurrenceID: UUID()),
            providerTaskID: "reused-task",
            state: .interruptedByProcessExit)

        let request = AgentRunContinuityRequest(
            previousTurnInterrupted: true,
            interruptedWork: [first, second])

        #expect(request.ordinaryInterruptedWorkKeys.isEmpty)
        #expect(first.key != second.key)
    }

    @Test func run_WhenResumeCompletes_ComposesResumeContinuityBeforeEncodingPrompt()
        async throws
    {
        let profileID = UUID()
        let configuration = try makeConfiguration()
        let store = RecordingAgentContinuityStore(bookmarks: [matchingBookmark(
            profileID: profileID,
            configuration: configuration)])
        let transport = FakeACPTransport()
        let runner = makeRunner(transport: transport, store: store)
        let run = Task {
            try await runner.run(
                profileID: profileID,
                configuration: configuration,
                prompt: AgentPrompt(request: "resume", context: nil),
                restorationNeed: .contextOnly,
                onEvent: { _ in })
        }

        _ = await transport.nextSentMessage()
        try await transport.feed(initializeResponse(loadSession: false, resumeSession: true))
        #expect(await requestMethod(transport.nextSentMessage()) == "session/resume")
        try await transport.feed(.response(id: .integer(2), result: .object([:])))
        let prompt = await transport.nextSentMessage()
        #expect(promptTextBlocks(prompt).contains { $0.contains("resumed_without_history") })
        try await transport.feed(promptResponse(id: 3))
        _ = try await run.value
    }

    @Test func run_WhenInterruptedOrdinaryWorkExists_AcknowledgesOnlyAfterPublication()
        async throws
    {
        let profileID = UUID()
        let oldKey = AgentInterruptedWorkKey(
            profileID: profileID,
            sessionID: "old-session",
            occurrenceID: UUID())
        let marker = AgentInterruptedWorkMarker(
            key: oldKey,
            state: .interruptedByProcessExit)
        let unrelatedMarker = AgentInterruptedWorkMarker(
            key: .init(
                profileID: UUID(),
                sessionID: "unrelated-session",
                occurrenceID: UUID()),
            state: .interruptedByProcessExit)
        let providerMarker = AgentInterruptedWorkMarker(
            key: .init(
                profileID: profileID,
                sessionID: "provider-session",
                occurrenceID: UUID()),
            providerTaskID: "provider-task",
            state: .interruptedByProcessExit)
        let acknowledgementGate = RunnerEventGate()
        let acknowledgementRecorder = RunnerContinuityAcknowledgementRecorder()
        let store = RecordingAgentContinuityStore(
            markers: [marker, unrelatedMarker, providerMarker],
            acknowledgeGate: acknowledgementGate)
        let transport = FakeACPTransport()
        let runner = makeRunner(transport: transport, store: store)
        let run = Task {
            try await runner.run(
                profileID: profileID,
                configuration: try makeConfiguration(),
                prompt: AgentPrompt(request: "continue", context: nil),
                restorationNeed: .visibleHistory,
                runContinuity: AgentRunContinuityRequest(
                    previousTurnInterrupted: true,
                    interruptedWork: [marker, unrelatedMarker, providerMarker],
                    onPublishedAcknowledgement: {
                        await acknowledgementRecorder.record($0)
                    }),
                onEvent: { _ in })
        }

        try await establishNewSession(
            transport,
            workingDirectory: "/tmp/project",
            sessionID: "new-session")
        #expect(!(await store.recordedCalls()).contains(.acknowledge([oldKey])))
        let prompt = await transport.nextSentMessage()
        await acknowledgementGate.waitUntilEntered()
        #expect(promptTextBlocks(prompt).contains {
            $0.contains("\"sessionState\":null")
                && $0.contains("\"previousTurnInterrupted\":true")
        })
        #expect(await store.recordedCalls().contains(.acknowledge([oldKey])))
        #expect(await acknowledgementRecorder.snapshot().isEmpty)
        await acknowledgementGate.open()
        try await transport.feed(promptResponse(id: 3))
        _ = try await run.value
        #expect(Set((await store.snapshot()).interruptedWork.map(\.key)) == [
            unrelatedMarker.key,
            providerMarker.key,
        ])
        #expect(await acknowledgementRecorder.snapshot() == [[oldKey]])
    }

    @Test func reset_RemovesOnlySpecifiedBookmarksAndMarkers() async throws {
        let firstProfile = UUID()
        let secondProfile = UUID()
        let configuration = try makeConfiguration()
        let first = matchingBookmark(profileID: firstProfile, configuration: configuration)
        let second = matchingBookmark(profileID: secondProfile, configuration: configuration)
        let firstMarker = AgentInterruptedWorkMarker(
            key: .init(
                profileID: firstProfile,
                sessionID: first.sessionID,
                occurrenceID: UUID()),
            state: .active)
        let secondMarker = AgentInterruptedWorkMarker(
            key: .init(
                profileID: secondProfile,
                sessionID: second.sessionID,
                occurrenceID: UUID()),
            state: .active)
        let store = RecordingAgentContinuityStore(
            bookmarks: [first, second],
            markers: [firstMarker, secondMarker])
        let runner = ACPAgentRunner(continuityStore: store)

        await runner.reset(profileIDs: [firstProfile])

        let snapshot = await store.snapshot()
        #expect(snapshot.bookmarks.map(\.profileID) == [secondProfile])
        #expect(snapshot.interruptedWork.map(\.key) == [secondMarker.key])
    }

    @Test func run_WhenAdmissionLosesRace_PerformsNoStoreOrTransportSideEffect() async throws {
        let store = RecordingAgentContinuityStore()
        let factory = RunnerTransportFactory(transports: [])
        let runner = ACPAgentRunner(transportFactory: factory, continuityStore: store)
        let admission = AgentRunAdmission()
        admission.invalidate()

        await #expect(throws: CancellationError.self) {
            try await runner.run(
                admission: admission,
                profileID: UUID(),
                configuration: try makeConfiguration(),
                prompt: AgentPrompt(request: "never", context: nil),
                restorationNeed: .visibleHistory,
                runContinuity: AgentRunContinuityRequest(),
                onEvent: { _ in })
        }
        #expect(await store.recordedCalls().isEmpty)
        #expect(await factory.createdConfigurations().isEmpty)
    }

    private func makeConfiguration() throws -> AgentHarnessConfiguration {
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
        workingDirectory: String,
        sessionID: String
    ) async throws {
        #expect(await requestMethod(transport.nextSentMessage()) == "initialize")
        try await transport.feed(initializeResponse(loadSession: false))
        #expect(await requestMethod(transport.nextSentMessage()) == "session/new")
        try await transport.feed(.response(
            id: .integer(2),
            result: .object(["sessionId": .string(sessionID)])))
    }

    private func initializeResponse(
        loadSession: Bool,
        resumeSession: Bool = false
    ) -> ACPMessage {
        var agentCapabilities: [String: ACPJSONValue] = [
            "loadSession": .bool(loadSession),
        ]
        if resumeSession {
            agentCapabilities["sessionCapabilities"] = .object([
                "resume": .object([:]),
            ])
        }
        return .response(
            id: .integer(1),
            result: .object([
                "protocolVersion": .integer(1),
                "agentCapabilities": .object(agentCapabilities),
                "agentInfo": .object([
                    "name": .string("test-agent"),
                    "version": .string("1.0.0"),
                ]),
                "authMethods": .array([]),
            ]))
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

    private func promptResponse(id: Int64) -> ACPMessage {
        .response(
            id: .integer(id),
            result: .object(["stopReason": .string("end_turn")]))
    }

    private func requestMethod(_ message: ACPMessage) -> String? {
        guard case let .request(_, method, _) = message else { return nil }
        return method
    }

    private func encodedSessionID(_ message: ACPMessage) -> String? {
        guard case let .request(_, _, .object(parameters)) = message,
              case let .string(sessionID) = parameters["sessionId"]
        else { return nil }
        return sessionID
    }

    private func promptTextBlocks(_ message: ACPMessage) -> [String] {
        guard case let .request(_, "session/prompt", .object(parameters)) = message,
              case let .array(blocks) = parameters["prompt"]
        else { return [] }
        return blocks.compactMap { block in
            guard case let .object(object) = block,
                  case let .string(text) = object["text"]
            else { return nil }
            return text
        }
    }
}
