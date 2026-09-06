// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationCore

extension ACPClientConnectionTests {
    @Test func updateAfterPromptResponse_IsDeliveredOnceToSessionObserver() async throws {
        let transport = FakeACPTransport()
        let connection = try await establishAIRConnection(transport: transport)
        let promptEvents = AgentEventRecorder()
        let sessionEvents = AgentEventRecorder()
        await connection.setSessionEventHandler { await sessionEvents.record($0) }
        let promptTask = prompt(connection, text: "Watch", recorder: promptEvents)
        _ = await promptEvents.nextEvent()
        _ = await transport.nextSentMessage()

        try await transport.feed(promptResponse(id: 3, stopReason: "end_turn"))
        _ = try await promptTask.value
        try await transport.feed(asyncTaskSpawned())

        #expect(await sessionEvents.nextEvent() == spawnedEvent)
        #expect(await promptEvents.recordedEvents().isEmpty)
        #expect(await sessionEvents.recordedEvents().isEmpty)
        await connection.close()
    }

    @Test func backgroundUpdateBeforePromptResponse_StaysOnPromptObserver() async throws {
        let transport = FakeACPTransport()
        let connection = try await establishAIRConnection(transport: transport)
        let promptEvents = AgentEventRecorder()
        let sessionEvents = AgentEventRecorder()
        await connection.setSessionEventHandler { await sessionEvents.record($0) }
        let promptTask = prompt(connection, text: "Watch", recorder: promptEvents)
        _ = await promptEvents.nextEvent()
        _ = await transport.nextSentMessage()

        try await transport.feed(asyncTaskSpawned())
        #expect(await promptEvents.nextEvent() == spawnedEvent)
        try await transport.feed(promptResponse(id: 3, stopReason: "end_turn"))
        _ = try await promptTask.value

        #expect(await sessionEvents.recordedEvents().isEmpty)
        await connection.close()
    }

    @Test func updateRacingPromptResponse_IsDeliveredToExactlyOneObserver() async throws {
        for responseFirst in [false, true] {
            let transport = FakeACPTransport()
            let connection = try await establishAIRConnection(transport: transport)
            let promptEvents = AgentEventRecorder()
            let sessionEvents = AgentEventRecorder()
            await connection.setSessionEventHandler { await sessionEvents.record($0) }
            let promptTask = prompt(connection, text: "Watch", recorder: promptEvents)
            _ = await promptEvents.nextEvent()
            _ = await transport.nextSentMessage()

            if responseFirst {
                try await transport.feed(promptResponse(id: 3, stopReason: "end_turn"))
                _ = try await promptTask.value
                try await transport.feed(asyncTaskSpawned())
                #expect(await sessionEvents.nextEvent() == spawnedEvent)
            } else {
                try await transport.feed(asyncTaskSpawned())
                #expect(await promptEvents.nextEvent() == spawnedEvent)
                try await transport.feed(promptResponse(id: 3, stopReason: "end_turn"))
                _ = try await promptTask.value
            }
            let promptCount = await promptEvents.recordedEvents().filter { $0 == spawnedEvent }.count
            let sessionCount = await sessionEvents.recordedEvents().filter { $0 == spawnedEvent }.count
            #expect(promptCount + sessionCount == 0)
            await connection.close()
        }
    }

    @Test func unnegotiatedAsyncUpdate_DoesNotReachSessionObserver() async throws {
        let transport = FakeACPTransport()
        let connection = try await establishConnection(transport: transport)
        let events = AgentEventRecorder()
        await connection.setSessionEventHandler { await events.record($0) }

        try await transport.feed(asyncTaskSpawned())
        try await transport.feed(typedDisplayMessage(text: "Visible"))

        #expect(await events.nextEvent() == .agentDisplayMessageDelta(
            messageID: "background-message", text: "Visible"))
        #expect(await events.recordedEvents().isEmpty)
        await connection.close()
    }

    @Test func permissionRequestBetweenTurns_IsCancelledWithoutObserverDelivery() async throws {
        let transport = FakeACPTransport()
        let connection = try await establishAIRConnection(transport: transport)
        let events = AgentEventRecorder()
        await connection.setSessionEventHandler { await events.record($0) }
        let requestID = ACPRequestID.string("late-permission")

        try await transport.feed(permissionRequest(
            id: requestID,
            options: [.object([
                "optionId": .string("allow"),
                "name": .string("Allow"),
                "kind": .string("allow_once"),
            ])]))

        #expect(await transport.nextSentMessage() == .response(
            id: requestID,
            result: .object([
                "outcome": .object(["outcome": .string("cancelled")]),
            ])))
        #expect(await events.recordedEvents().isEmpty)
        await connection.close()
    }

    @Test func stopTask_WhenNegotiated_WritesExactAIRMethodAndParams() async throws {
        let transport = FakeACPTransport()
        let connection = try await establishAIRConnection(transport: transport)
        let task = Task {
            try await connection.stopBackgroundTask(
                taskID: AgentBackgroundTaskID(rawValue: "task-7"))
        }

        #expect(await transport.nextSentMessage() == .request(
            id: .integer(3),
            method: "_session/async_task/stop",
            params: .object([
                "sessionId": .string("session-1"),
                "asyncTaskId": .string("task-7"),
            ])))
        try await transport.feed(.response(
            id: .integer(3),
            result: .object(["stopped": .bool(true)])))
        #expect(try await task.value)
        await connection.close()
    }

    @Test func stopTask_WhenUnnegotiated_PerformsNoWrite() async throws {
        let transport = FakeACPTransport()
        let connection = try await establishConnection(transport: transport)
        let before = await transport.allSentMessages()

        #expect(try await connection.stopBackgroundTask(
            taskID: AgentBackgroundTaskID(rawValue: "task-7")) == false)
        #expect(await transport.allSentMessages() == before)
        await connection.close()
    }

    @Test func stopTaskResponseTrue_DoesNotFabricateTerminalEvent() async throws {
        let transport = FakeACPTransport()
        let connection = try await establishAIRConnection(transport: transport)
        let events = AgentEventRecorder()
        await connection.setSessionEventHandler { await events.record($0) }
        let task = Task {
            try await connection.stopBackgroundTask(
                taskID: AgentBackgroundTaskID(rawValue: "task-7"))
        }
        _ = await transport.nextSentMessage()
        try await transport.feed(.response(
            id: .integer(3),
            result: .object(["stopped": .bool(true)])))

        #expect(try await task.value)
        #expect(await events.recordedEvents().isEmpty)
        await connection.close()
    }

    @Test func stopTaskResponseMalformed_ThrowsWithoutRetry() async throws {
        let transport = FakeACPTransport()
        let connection = try await establishAIRConnection(transport: transport)
        let task = Task {
            try await connection.stopBackgroundTask(
                taskID: AgentBackgroundTaskID(rawValue: "task-7"))
        }
        _ = await transport.nextSentMessage()
        try await transport.feed(.response(
            id: .integer(3),
            result: .object(["stopped": .string("yes")])))

        await #expect(throws: ACPClientError.self) { try await task.value }
        #expect(await transport.allSentMessages().filter {
            guard case .request(_, "_session/async_task/stop", _) = $0 else { return false }
            return true
        }.count == 1)
        await connection.close()
    }

    @Test func stopTask_WhileSameTaskIsInFlight_PerformsOneWrite() async throws {
        let transport = FakeACPTransport()
        let connection = try await establishAIRConnection(transport: transport)
        let taskID = AgentBackgroundTaskID(rawValue: "task-7")
        let first = Task { try await connection.stopBackgroundTask(taskID: taskID) }
        _ = await transport.nextSentMessage()

        #expect(try await connection.stopBackgroundTask(taskID: taskID) == false)
        #expect(await transport.allSentMessages().filter {
            guard case .request(_, "_session/async_task/stop", _) = $0 else { return false }
            return true
        }.count == 1)
        try await transport.feed(.response(
            id: .integer(3),
            result: .object(["stopped": .bool(false)])))
        #expect(try await first.value == false)
        await connection.close()
    }

    @Test func stopTask_WhenIdentityIsInvalid_PerformsNoWrite() async throws {
        let transport = FakeACPTransport()
        let connection = try await establishAIRConnection(transport: transport)
        let before = await transport.allSentMessages()

        #expect(try await connection.stopBackgroundTask(
            taskID: AgentBackgroundTaskID(rawValue: "")) == false)
        #expect(try await connection.stopBackgroundTask(taskID: AgentBackgroundTaskID(
            rawValue: String(repeating: "x", count: 257))) == false)
        #expect(await transport.allSentMessages() == before)
        await connection.close()
    }

    @Test func shutdown_InvalidatesSessionObserverBeforeTransportTermination() async throws {
        let transport = FakeACPTransport()
        let connection = try await establishAIRConnection(transport: transport)
        var probe: BackgroundTaskLifecycleProbe? = BackgroundTaskLifecycleProbe()
        weak var weakProbe = probe
        await connection.setSessionEventHandler { [probe] _ in probe?.observe() }
        probe = nil
        #expect(weakProbe != nil)

        await connection.close()
        for _ in 0..<10 where weakProbe != nil { await Task.yield() }

        #expect(weakProbe == nil)
        #expect(await transport.observedTerminationCount() == 1)
    }

    @Test func sessionObserver_WhenBackpressured_PreservesBoundAndOrder() async throws {
        let transport = FakeACPTransport()
        let connection = try await establishAIRConnection(transport: transport)
        let gate = AgentEventGate()
        let events = AgentEventRecorder()
        await connection.setSessionEventHandler { event in
            await gate.pause()
            await events.record(event)
        }

        for index in 0..<64 {
            try await transport.feed(sessionUpdate(.object([
                "sessionUpdate": .string("async_task_progress"),
                "asyncTaskId": .string("task-\(index)"),
                "summary": .string("progress-\(index)"),
            ])))
        }
        let requestID = ACPRequestID.string("barrier")
        try await transport.feed(permissionRequest(
            id: requestID,
            options: [.object([
                "optionId": .string("allow"),
                "name": .string("Allow"),
                "kind": .string("allow_once"),
            ])]))
        _ = await transport.nextSentMessage()
        let snapshot = try #require(await connection.sessionEventDeliverySnapshotForTesting())
        #expect(snapshot.pendingEntryCount <= AgentRunEventDelivery.maximumPendingEntries)
        #expect(snapshot.pendingControlBytes <= AgentRunEventDelivery.maximumPendingControlBytes)

        await gate.open()
        for index in 0..<64 {
            guard case let .backgroundTask(.progress(id, _, summary, _, _, _, _)) =
                await events.nextEvent()
            else {
                Issue.record("Expected ordered task progress")
                break
            }
            #expect(id.rawValue == "task-\(index)")
            #expect(summary == "progress-\(index)")
        }
        await connection.close()
    }

    private var spawnedEvent: AgentRunEvent {
        .backgroundTask(.spawned(
            id: AgentBackgroundTaskID(rawValue: "task-7"),
            name: "Watch build",
            taskType: "shell",
            description: "Waiting for CI",
            showInTranscript: true,
            canStop: true,
            outputFilePath: nil,
            toolCallID: "tool-9"))
    }

    private func asyncTaskSpawned() -> ACPMessage {
        sessionUpdate(.object([
            "sessionUpdate": .string("async_task_spawned"),
            "asyncTaskId": .string("task-7"),
            "name": .string("Watch build"),
            "taskType": .string("shell"),
            "description": .string("Waiting for CI"),
            "showInTranscript": .bool(true),
            "canStop": .bool(true),
            "toolCallId": .string("tool-9"),
        ]))
    }

    private func typedDisplayMessage(text: String) -> ACPMessage {
        sessionUpdate(.object([
            "sessionUpdate": .string("agent_message_chunk"),
            "messageId": .string("background-message"),
            "content": .object([
                "type": .string("text"),
                "text": .string(text),
                "_meta": .object([
                    "ciobanu.org.voiceActivation": .object([
                        "responseChannel": .object([
                            "version": .integer(1),
                            "channel": .string("display"),
                        ]),
                    ]),
                ]),
            ]),
        ]))
    }

    private func establishAIRConnection(
        transport: FakeACPTransport
    ) async throws -> ACPClientConnection {
        let task = Task {
            try await ACPClientConnection.connect(
                transport: transport,
                configuration: try makeConfiguration(preset: .claude)).connection
        }
        _ = await transport.nextSentMessage()
        try await transport.feed(.response(id: .integer(1), result: .object([
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
        ])))
        _ = await transport.nextSentMessage()
        try await transport.feed(.response(
            id: .integer(2),
            result: .object(["sessionId": .string("session-1")])))
        return try await task.value
    }
}

private final class BackgroundTaskLifecycleProbe: @unchecked Sendable {
    func observe() {}
}
