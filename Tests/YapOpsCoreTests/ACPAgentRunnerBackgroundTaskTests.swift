// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import YapOpsCore

extension ACPAgentRunnerTests {
    @Test func sessionEnvelope_PreservesExactProfileSessionAndLiveSource() {
        let profileID = UUID()
        let event = backgroundTaskProgress(taskID: "task-7")

        let envelope = AgentSessionEventEnvelope(
            profileID: profileID,
            sessionID: "opaque-session",
            streamEvent: .live(event))

        #expect(envelope.profileID == profileID)
        #expect(envelope.sessionID == "opaque-session")
        #expect(envelope.streamEvent == .live(event))
    }

    @Test func backgroundUpdate_EmitsProfileAndSessionEnvelope() async throws {
        let transport = FakeACPTransport()
        let runner = ACPAgentRunner(
            transportFactory: RunnerTransportFactory(transports: [transport]))
        let envelopes = RunnerSessionEnvelopeRecorder()
        let profileID = UUID()
        let sessionID = "background-session"
        await runner.setSessionEventHandler { await envelopes.record($0) }

        try await completeAIRTurn(
            runner: runner,
            transport: transport,
            profileID: profileID,
            sessionID: sessionID,
            workingDirectory: "/tmp/background-envelope")
        try await transport.feed(backgroundTaskSpawnedMessage(
            taskID: "task-envelope",
            sessionID: sessionID))

        let envelope = await envelopes.nextEnvelope()
        #expect(envelope.profileID == profileID)
        #expect(envelope.sessionID == sessionID)
        #expect(envelope.streamEvent == .live(backgroundTaskSpawned(taskID: "task-envelope")))
        await runner.shutdown()
    }

    @Test func backgroundUpdate_IsQualifiedAsLiveNotRestored() async throws {
        let transport = FakeACPTransport()
        let runner = ACPAgentRunner(
            transportFactory: RunnerTransportFactory(transports: [transport]))
        let envelopes = RunnerSessionEnvelopeRecorder()
        let profileID = UUID()
        let sessionID = "source-session"
        await runner.setSessionEventHandler { await envelopes.record($0) }

        try await completeAIRTurn(
            runner: runner,
            transport: transport,
            profileID: profileID,
            sessionID: sessionID,
            workingDirectory: "/tmp/background-source")
        let recordID = try #require(await runner.recordIDForBackgroundTaskTesting(
            profileID: profileID))
        await runner.receiveSessionEvent(
            .restored(
                token: AgentRestorationToken(),
                event: backgroundTaskSpawned(taskID: "restored-task")),
            profileID: profileID,
            sessionID: sessionID,
            recordID: recordID)

        #expect(await envelopes.recordedEnvelopes().isEmpty)
        await runner.shutdown()
    }

    @Test func fifthSession_WhenAllFourArePinned_FailsBeforeProcessLaunch() async throws {
        let sessionLimit = ACPAgentRunner.maximumCachedSessions
        let transports = (0..<sessionLimit).map { _ in FakeACPTransport() }
        let factory = RunnerTransportFactory(transports: transports)
        let runner = ACPAgentRunner(transportFactory: factory)

        for index in 0..<sessionLimit {
            try await completeAIRTurn(
                runner: runner,
                transport: transports[index],
                profileID: UUID(),
                sessionID: "full-session-\(index)",
                workingDirectory: "/tmp/background-full-\(index)",
                spawnedTaskID: "full-task-\(index)")
        }

        let fifth = run(
            runner,
            profileID: UUID(),
            configuration: try makeConfiguration(
                workingDirectory: "/tmp/background-refused",
                preset: .claude))
        await #expect(throws: ACPAgentRunnerError.sessionCapacityReached) {
            try await fifth.value
        }
        #expect(await factory.createdConfigurations().count == sessionLimit)
        await runner.shutdown()
    }

    @Test func terminalTask_UnpinsSessionForOrdinaryLRUEviction() async throws {
        let sessionLimit = ACPAgentRunner.maximumCachedSessions
        let transports = (0...sessionLimit).map { _ in FakeACPTransport() }
        let runner = ACPAgentRunner(
            transportFactory: RunnerTransportFactory(transports: transports))
        let envelopes = RunnerSessionEnvelopeRecorder()
        let profileIDs = (0...sessionLimit).map { _ in UUID() }
        await runner.setSessionEventHandler { await envelopes.record($0) }

        for index in 0..<sessionLimit {
            try await completeAIRTurn(
                runner: runner,
                transport: transports[index],
                profileID: profileIDs[index],
                sessionID: "unpin-session-\(index)",
                workingDirectory: "/tmp/background-unpin-\(index)",
                spawnedTaskID: "unpin-task-\(index)")
        }
        try await transports[0].feed(backgroundTaskTerminalMessage(
            taskID: "unpin-task-0",
            sessionID: "unpin-session-0"))
        _ = await envelopes.nextEnvelope()

        try await completeAIRTurn(
            runner: runner,
            transport: transports[sessionLimit],
            profileID: profileIDs[sessionLimit],
            sessionID: "unpin-session-\(sessionLimit)",
            workingDirectory: "/tmp/background-unpin-\(sessionLimit)")

        #expect(await transports[0].observedTerminationCount() == 1)
        #expect(await transports[1].observedTerminationCount() == 0)
        await runner.shutdown()
    }

    @Test func stopBackgroundTask_ValidatesExactSessionAndDelegatesOnce() async throws {
        let transport = FakeACPTransport()
        let runner = ACPAgentRunner(
            transportFactory: RunnerTransportFactory(transports: [transport]))
        let envelopes = RunnerSessionEnvelopeRecorder()
        let profileID = UUID()
        let sessionID = "stop-session"
        let taskID = AgentBackgroundTaskID(rawValue: "stop-task")
        await runner.setSessionEventHandler { await envelopes.record($0) }

        try await completeAIRTurn(
            runner: runner,
            transport: transport,
            profileID: profileID,
            sessionID: sessionID,
            workingDirectory: "/tmp/background-stop")
        try await transport.feed(backgroundTaskSpawnedMessage(
            taskID: taskID.rawValue,
            sessionID: sessionID))
        _ = await envelopes.nextEnvelope()
        let before = await transport.allSentMessages()
        await #expect(throws: ACPAgentRunnerError.backgroundTaskUnavailable) {
            try await runner.stopBackgroundTask(
                profileID: profileID,
                sessionID: "stale-session",
                taskID: taskID)
        }
        #expect(await transport.allSentMessages() == before)

        let stop = Task {
            try await runner.stopBackgroundTask(
                profileID: profileID,
                sessionID: sessionID,
                taskID: taskID)
        }
        #expect(await transport.nextSentMessage() == .request(
            id: .integer(4),
            method: "_session/async_task/stop",
            params: .object([
                "sessionId": .string(sessionID),
                "asyncTaskId": .string(taskID.rawValue),
            ])))
        await #expect(throws: ACPAgentRunnerError.backgroundTaskUnavailable) {
            try await runner.stopBackgroundTask(
                profileID: profileID,
                sessionID: sessionID,
                taskID: taskID)
        }
        try await transport.feed(.response(
            id: .integer(4),
            result: .object(["stopped": .bool(true)])))
        #expect(try await stop.value)
        #expect(await transport.allSentMessages().filter {
            guard case .request(_, "_session/async_task/stop", _) = $0 else { return false }
            return true
        }.count == 1)
        await runner.shutdown()
    }

    @Test func taskSpawnMarker_IsOrderedPrivateAndDistinctAcrossIDReuse() async throws {
        let transport = FakeACPTransport()
        let store = RecordingAgentContinuityStore()
        let runner = ACPAgentRunner(
            transportFactory: RunnerTransportFactory(transports: [transport]),
            continuityStore: store)
        let envelopes = RunnerSessionEnvelopeRecorder()
        let profileID = UUID()
        let sessionID = "marker-session"
        let taskID = "opaque-task-7"
        let (activeRun, promptEvents) = beginAIRTurn(
            runner: runner,
            profileID: profileID,
            configuration: try makeConfiguration(
                workingDirectory: "/tmp/background-marker",
                preset: .claude),
            prompt: "distinctive private prompt")
        await runner.setSessionEventHandler { await envelopes.record($0) }
        let promptRequestID = try await establishAIRRunnerConnection(
            transport,
            workingDirectory: "/tmp/background-marker",
            sessionID: sessionID)

        try await transport.feed(backgroundTaskSpawnedMessage(
            taskID: taskID,
            sessionID: sessionID))
        _ = await nextBackgroundTaskEvent(promptEvents)
        let firstMarker = try #require(await store.snapshot().interruptedWork.first {
            $0.providerTaskID == taskID
        })
        #expect(firstMarker.state == .active)
        let encoded = String(
            decoding: try JSONEncoder().encode(await store.snapshot()),
            as: UTF8.self)
        #expect(encoded.contains(taskID))
        #expect(encoded.contains("active"))
        for forbidden in [
            "distinctive private prompt", "Watch build", "Waiting for CI",
            "Build summary", "Bash", "/tmp/private-build.log", "totalTokens",
        ] {
            #expect(!encoded.contains(forbidden))
        }

        try await transport.feed(promptResponse(
            id: promptRequestID,
            stopReason: "end_turn"))
        _ = try await activeRun.value
        try await transport.feed(backgroundTaskTerminalMessage(
            taskID: taskID,
            sessionID: sessionID))
        _ = await envelopes.nextEnvelope()
        #expect(await store.snapshot().interruptedWork.allSatisfy {
            $0.providerTaskID != taskID
        })

        try await transport.feed(backgroundTaskSpawnedMessage(
            taskID: taskID,
            sessionID: sessionID))
        _ = await envelopes.nextEnvelope()
        let secondMarker = try #require(await store.snapshot().interruptedWork.first {
            $0.providerTaskID == taskID
        })
        #expect(secondMarker.key.occurrenceID != firstMarker.key.occurrenceID)
        await runner.shutdown()
    }
}

private actor RunnerSessionEnvelopeRecorder {
    private var envelopes: [AgentSessionEventEnvelope] = []
    private var waiters: [CheckedContinuation<AgentSessionEventEnvelope, Never>] = []

    func record(_ envelope: AgentSessionEventEnvelope) {
        guard waiters.isEmpty else {
            waiters.removeFirst().resume(returning: envelope)
            return
        }
        envelopes.append(envelope)
    }

    func nextEnvelope() async -> AgentSessionEventEnvelope {
        guard envelopes.isEmpty else { return envelopes.removeFirst() }
        return await withCheckedContinuation { waiters.append($0) }
    }

    func recordedEnvelopes() -> [AgentSessionEventEnvelope] {
        envelopes
    }
}

private enum BackgroundTaskRunnerTestError: Error {
    case unexpectedRequest
}

private extension ACPAgentRunnerTests {
    func beginAIRTurn(
        runner: ACPAgentRunner,
        profileID: UUID,
        configuration: AgentHarnessConfiguration,
        prompt: String = "Watch the build"
    ) -> (Task<AgentRunResult, any Error>, RunnerEventRecorder) {
        let events = RunnerEventRecorder()
        let task = Task {
            try await runner.run(
                profileID: profileID,
                configuration: configuration,
                prompt: AgentPrompt(request: prompt, context: nil),
                onEvent: { await events.record($0) })
        }
        return (task, events)
    }

    func completeAIRTurn(
        runner: ACPAgentRunner,
        transport: FakeACPTransport,
        profileID: UUID,
        sessionID: String,
        workingDirectory: String,
        spawnedTaskID: String? = nil
    ) async throws {
        let (activeRun, promptEvents) = beginAIRTurn(
            runner: runner,
            profileID: profileID,
            configuration: try makeConfiguration(
                workingDirectory: workingDirectory,
                preset: .claude))
        let promptRequestID = try await establishAIRRunnerConnection(
            transport,
            workingDirectory: workingDirectory,
            sessionID: sessionID)
        if let spawnedTaskID {
            try await transport.feed(backgroundTaskSpawnedMessage(
                taskID: spawnedTaskID,
                sessionID: sessionID))
            _ = await nextBackgroundTaskEvent(promptEvents)
        }
        try await transport.feed(promptResponse(
            id: promptRequestID,
            stopReason: "end_turn"))
        _ = try await activeRun.value
    }

    func establishAIRRunnerConnection(
        _ transport: FakeACPTransport,
        workingDirectory: String,
        sessionID: String
    ) async throws -> Int64 {
        let initializeID = try await nextIntegerRequestID(
            transport,
            method: "initialize")
        try await transport.feed(.response(
            id: .integer(initializeID),
            result: .object([
                "protocolVersion": .integer(1),
                "agentCapabilities": .object([:]),
                "agentInfo": .object([
                    "name": .string("@agentclientprotocol/claude-agent-acp"),
                    "title": .string("Claude"),
                    "version": .string("0.73.0"),
                ]),
                "_meta": .object([
                    "jetbrains": .object([
                        "air": .object([
                            "version": .integer(1),
                            "capabilities": .array([.string("asyncTasks")]),
                        ]),
                    ]),
                ]),
                "authMethods": .array([]),
            ])))
        let newSessionID = try await nextIntegerRequestID(
            transport,
            method: "session/new")
        try await transport.feed(.response(
            id: .integer(newSessionID),
            result: .object(["sessionId": .string(sessionID)])))
        return try await nextIntegerRequestID(transport, method: "session/prompt")
    }

    func nextIntegerRequestID(
        _ transport: FakeACPTransport,
        method: String
    ) async throws -> Int64 {
        guard case .request(.integer(let id), let observedMethod, _) =
                await transport.nextSentMessage(),
              observedMethod == method
        else { throw BackgroundTaskRunnerTestError.unexpectedRequest }
        return id
    }

    func nextBackgroundTaskEvent(_ recorder: RunnerEventRecorder) async -> AgentRunEvent {
        while true {
            let event = await recorder.nextEvent()
            if case .backgroundTask = event { return event }
        }
    }

    func backgroundTaskSpawned(taskID: String) -> AgentRunEvent {
        .backgroundTask(.spawned(
            id: AgentBackgroundTaskID(rawValue: taskID),
            name: "Watch build",
            taskType: "shell",
            description: "Waiting for CI",
            showInTranscript: true,
            canStop: true,
            outputFilePath: "/tmp/private-build.log",
            toolCallID: "tool-9"))
    }

    func backgroundTaskProgress(taskID: String) -> AgentRunEvent {
        .backgroundTask(.progress(
            id: AgentBackgroundTaskID(rawValue: taskID),
            description: "Still running",
            summary: "Build summary",
            lastToolName: "Bash",
            usage: AgentBackgroundTaskUsage(
                totalTokens: 12,
                toolUses: 3,
                durationMilliseconds: 900),
            outputFilePath: "/tmp/private-build.log",
            toolCallID: "tool-9"))
    }

    func backgroundTaskSpawnedMessage(
        taskID: String,
        sessionID: String
    ) -> ACPMessage {
        backgroundTaskMessage(
            sessionID: sessionID,
            update: .object([
                "sessionUpdate": .string("async_task_spawned"),
                "asyncTaskId": .string(taskID),
                "name": .string("Watch build"),
                "taskType": .string("shell"),
                "description": .string("Waiting for CI"),
                "showInTranscript": .bool(true),
                "canStop": .bool(true),
                "outputFilePath": .string("/tmp/private-build.log"),
                "toolCallId": .string("tool-9"),
            ]))
    }

    func backgroundTaskTerminalMessage(
        taskID: String,
        sessionID: String
    ) -> ACPMessage {
        backgroundTaskMessage(
            sessionID: sessionID,
            update: .object([
                "sessionUpdate": .string("async_task_state_update"),
                "asyncTaskId": .string(taskID),
                "state": .string("completed"),
                "summary": .string("Build summary"),
                "outputFilePath": .string("/tmp/private-build.log"),
                "toolCallId": .string("tool-9"),
            ]))
    }

    func backgroundTaskMessage(
        sessionID: String,
        update: ACPJSONValue
    ) -> ACPMessage {
        .notification(
            method: "session/update",
            params: .object([
                "sessionId": .string(sessionID),
                "update": update,
            ]))
    }
}

private extension ACPAgentRunner {
    func recordIDForBackgroundTaskTesting(profileID: UUID) -> UUID? {
        records[profileID]?.id
    }
}
