// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationCore

extension ACPClientConnectionTests {
    @Test func initialize_AdvertisesResponseChannelV1UnderClientCapabilitiesMeta() async throws {
        let transport = FakeACPTransport()
        let task = Task {
            try await ACPClientConnection.connect(
                transport: transport,
                configuration: try makeConfiguration()).connection
        }

        guard case let .request(_, "initialize", .object(parameters)) =
            await transport.nextSentMessage()
        else {
            Issue.record("Expected initialize request")
            return
        }
        #expect(parameters["clientCapabilities"] == .object([
            "_meta": .object([
                "ciobanu.org.voiceActivation": .object([
                    "responseChannels": .object([
                        "version": .integer(1),
                        "channels": .array([.string("spoken"), .string("display")]),
                    ]),
                ]),
                "jetbrains": .object([
                    "air": .object([
                        "version": .integer(1),
                        "capabilities": .array([.string("asyncTasks")]),
                    ]),
                ]),
            ]),
        ]))

        try await transport.feed(initializeResponse())
        _ = await transport.nextSentMessage()
        try await transport.feed(.response(
            id: .integer(2),
            result: .object(["sessionId": .string("session-1")])))
        let connection = try await task.value
        await connection.close()
    }

    @Test func initialize_WhenAIRContributionAlsoExists_PreservesBothCapabilityNamespaces()
        async throws
    {
        let transport = FakeACPTransport()
        let task = Task {
            try await ACPClientConnection.connect(
                transport: transport,
                configuration: try makeConfiguration(),
                restoration: nil,
                onRestoredEvent: { _, _ in },
                clientCapabilityFragments: [
                    .object(["vendor": .object(["tasks": .object(["version": .integer(1)])])]),
                ],
                diagnostics: VoiceActivationDiagnostics.shared).connection
        }

        guard case let .request(_, "initialize", .object(parameters)) =
            await transport.nextSentMessage(),
            case let .object(capabilities) = parameters["clientCapabilities"],
            case let .object(metadata) = capabilities["_meta"]
        else {
            Issue.record("Expected composed initialize capabilities")
            return
        }
        #expect(metadata["ciobanu.org.voiceActivation"] != nil)
        #expect(metadata["jetbrains"] == .object([
            "air": .object([
                "version": .integer(1),
                "capabilities": .array([.string("asyncTasks")]),
            ]),
        ]))
        #expect(capabilities["vendor"] == .object([
            "tasks": .object(["version": .integer(1)]),
        ]))

        try await transport.feed(initializeResponse())
        _ = await transport.nextSentMessage()
        try await transport.feed(.response(
            id: .integer(2),
            result: .object(["sessionId": .string("session-1")])))
        let connection = try await task.value
        await connection.close()
    }

    @Test func prompt_IncludesExactMarkerContractBeforeContinuityContextResourcesAndUntouchedRequest()
        async throws
    {
        let transport = FakeACPTransport()
        let connection = try await establishConnection(transport: transport)
        let recorder = AgentEventRecorder()
        let context = MacContextSnapshot.normalized(
            state: .complete,
            target: .init(
                processIdentifier: 42,
                applicationName: "Editor",
                bundleIdentifier: "com.example.Editor"),
            windowTitle: "Notes",
            documentURL: nil,
            selectedText: "Selection",
            resources: [.init(uri: "file:///tmp/notes.md", name: "notes.md")])
        let request = "Use this exactly"
        let task = Task {
            try await connection.prompt(AgentPrompt(
                request: request,
                context: context,
                continuity: AgentContinuityPromptContext(
                    sessionState: .loaded,
                    previousTurnInterrupted: false))) {
                        await recorder.record($0)
                    }
        }
        _ = await recorder.nextEvent()

        guard case let .request(_, "session/prompt", .object(parameters)) =
            await transport.nextSentMessage(),
            case let .array(blocks) = parameters["prompt"]
        else {
            Issue.record("Expected typed prompt blocks")
            return
        }
        #expect(blocks.count == 5)
        #expect(blocks[0] == ACPClientConnection.encodedPromptBlock(for: .text(
            role: .instruction,
            value: ACPClientConnection.markdownPresentationInstruction)))
        #expect(text(in: blocks[0])?.contains(AgentResponseChannelRouter.spokenMarker) == true)
        #expect(text(in: blocks[0])?.contains(AgentResponseChannelRouter.displayMarker) == true)
        #expect(text(in: blocks[1])?.contains("voice-activation.agent-continuity.v1") == true)
        #expect(text(in: blocks[2])?.contains("voice-activation.mac-context.v1") == true)
        #expect(object(blocks[3])?["uri"] == .string("file:///tmp/notes.md"))
        #expect(blocks[4] == ACPClientConnection.encodedPromptBlock(for: .text(
            role: .request,
            value: request)))

        try await transport.feed(promptResponse(id: 3, stopReason: "end_turn"))
        _ = try await task.value
        await connection.close()
    }

    @Test func promptCompletion_FlushesPartialMarkerBeforeTurnEnd() async throws {
        let transport = FakeACPTransport()
        let connection = try await establishConnection(transport: transport)
        let recorder = AgentEventRecorder()
        let task = prompt(connection, text: "Answer", recorder: recorder)
        _ = await recorder.nextEvent()
        _ = await transport.nextSentMessage()
        let partial = String(AgentResponseChannelRouter.spokenMarker.prefix(12))

        try await transport.feed(agentMessageUpdate(text: partial))
        try await transport.feed(promptResponse(id: 3, stopReason: "end_turn"))
        _ = try await task.value

        #expect(await recorder.recordedEvents() == [
            .agentMessageDelta(messageID: "answer", text: partial),
        ])
        await connection.close()
    }

    @Test func backgroundMessageBetweenTurns_UsesRetainedSessionRouter() async throws {
        let transport = FakeACPTransport()
        let connection = try await establishConnection(transport: transport)
        let firstRecorder = AgentEventRecorder()
        let first = prompt(connection, text: "First", recorder: firstRecorder)
        _ = await firstRecorder.nextEvent()
        _ = await transport.nextSentMessage()
        try await transport.feed(promptResponse(id: 3, stopReason: "end_turn"))
        _ = try await first.value

        try await transport.feed(agentMessageUpdate(
            text: AgentResponseChannelRouter.spokenMarker + "Background"))

        let secondRecorder = AgentEventRecorder()
        let second = prompt(connection, text: "Second", recorder: secondRecorder)
        _ = await secondRecorder.nextEvent()
        _ = await transport.nextSentMessage()
        try await transport.feed(sessionUpdate(.object([
            "sessionUpdate": .string("usage_update"),
            "used": .integer(1),
            "size": .integer(10),
        ])))
        try await transport.feed(promptResponse(id: 4, stopReason: "end_turn"))
        _ = try await second.value

        #expect(await secondRecorder.recordedEvents().contains(
            .agentSpokenNarrationSuppressed(
                messageID: "answer",
                reason: .incompleteDelivery)))
        await connection.close()
    }

    @Test func cancel_DoesNotDeliverBufferedMarkerAfterTurnRetirement() async throws {
        let transport = FakeACPTransport()
        let connection = try await establishConnection(transport: transport)
        let recorder = AgentEventRecorder()
        let task = prompt(connection, text: "Answer", recorder: recorder)
        _ = await recorder.nextEvent()
        _ = await transport.nextSentMessage()
        let partial = String(AgentResponseChannelRouter.spokenMarker.prefix(12))
        try await transport.feed(agentMessageUpdate(text: partial))

        await connection.cancel()
        _ = await transport.nextSentMessage()
        try await transport.feed(agentMessageUpdate(
            text: String(AgentResponseChannelRouter.spokenMarker.dropFirst(12)) + "Late"))
        try await transport.feed(sessionUpdate(.object([
            "sessionUpdate": .string("usage_update"),
            "used": .integer(1),
            "size": .integer(10),
        ])))
        try await transport.feed(promptResponse(id: 3, stopReason: "cancelled"))
        _ = try await task.value

        #expect(await recorder.recordedEvents().isEmpty)
        await connection.close()
    }

    @Test func loadRestoration_FlushesItsOwnPartialMarkerBeforeCompletion() async throws {
        let transport = FakeACPTransport()
        let recorder = AgentEventRecorder()
        let task = restorationConnection(
            transport: transport,
            need: .visibleHistory,
            recorder: recorder)
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: true, resume: false))
        _ = await transport.nextSentMessage()
        let partial = String(AgentResponseChannelRouter.spokenMarker.prefix(12))
        try await transport.feed(restoredAgentMessage(
            text: partial,
            messageID: "restored"))
        try await transport.feed(.response(id: .integer(2), result: .object([:])))

        let result = try await task.value
        #expect(await recorder.recordedEvents() == [
            .agentMessageDelta(messageID: "restored", text: partial),
        ])
        await result.connection.close()
    }

    @Test func emptyTypedSpokenDelta_DoesNotSuppressNextValidMessage() async throws {
        let transport = FakeACPTransport()
        let connection = try await establishConnection(transport: transport)
        let recorder = AgentEventRecorder()
        let task = prompt(connection, text: "Answer", recorder: recorder)
        _ = await recorder.nextEvent()
        _ = await transport.nextSentMessage()

        try await transport.feed(typedSpokenUpdate(messageID: "empty", text: ""))
        try await transport.feed(typedSpokenUpdate(messageID: "valid", text: "Speak exactly"))
        try await transport.feed(promptResponse(id: 3, stopReason: "end_turn"))
        _ = try await task.value

        #expect(await recorder.recordedEvents() == [
            .agentSpokenMessageDelta(messageID: "valid", text: "Speak exactly"),
            .agentSpokenNarrationReady(messageID: "valid", text: "Speak exactly"),
        ])
        await connection.close()
    }

    private func agentMessageUpdate(text: String) -> ACPMessage {
        sessionUpdate(.object([
            "sessionUpdate": .string("agent_message_chunk"),
            "messageId": .string("answer"),
            "content": .object([
                "type": .string("text"),
                "text": .string(text),
            ]),
        ]))
    }

    private func typedSpokenUpdate(messageID: String, text: String) -> ACPMessage {
        sessionUpdate(.object([
            "sessionUpdate": .string("agent_message_chunk"),
            "messageId": .string(messageID),
            "content": .object([
                "type": .string("text"),
                "text": .string(text),
                "_meta": .object([
                    "ciobanu.org.voiceActivation": .object([
                        "responseChannel": .object([
                            "version": .integer(1),
                            "channel": .string("spoken"),
                        ]),
                    ]),
                ]),
            ]),
        ]))
    }

    private func text(in value: ACPJSONValue) -> String? {
        guard case let .string(text) = object(value)?["text"] else { return nil }
        return text
    }

    private func object(_ value: ACPJSONValue) -> [String: ACPJSONValue]? {
        guard case let .object(object) = value else { return nil }
        return object
    }
}
