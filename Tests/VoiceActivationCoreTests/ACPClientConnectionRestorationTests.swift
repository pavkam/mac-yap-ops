// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationCore

extension ACPClientConnectionTests {
    @Test func connect_WhenLoadIsSelected_InstallsIdentityBeforeHistoryReplay() async throws {
        let transport = FakeACPTransport()
        let recorder = AgentEventRecorder()
        let task = restorationConnection(
            transport: transport,
            need: .visibleHistory,
            recorder: recorder)

        #expect(await transport.nextSentMessage() == initializeRequest())
        try await transport.feed(restorationInitializeResponse(load: true, resume: true))
        #expect(await transport.nextSentMessage() == restorationRequest(
            id: 2,
            method: "session/load"))
        try await transport.feed(restoredUserMessage(text: "old question", role: .string("request")))
        try await transport.feed(restoredAgentMessage(text: "old answer"))
        try await transport.feed(.response(id: .integer(2), result: .object([:])))

        let result = try await task.value
        #expect(result.activation == .loaded(sessionID: "saved"))
        #expect(result.capabilities == .init(loadSession: true, resumeSession: true))
        #expect(await recorder.recordedEvents() == [
            .userMessageDelta(messageID: nil, text: "old question"),
            .agentMessageDelta(messageID: nil, text: "old answer"),
        ])
        #expect(await requestMethods(transport) == ["initialize", "session/load"])
        await result.connection.close()
    }

    @Test func connect_WhenLoadCapabilityIsAbsent_DoesNotSendSessionLoad() async throws {
        let transport = FakeACPTransport()
        let task = restorationConnection(transport: transport, need: .visibleHistory)
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: false, resume: false))

        #expect(await transport.nextSentMessage() == .request(
            id: .integer(2),
            method: "session/new",
            params: .object([
                "cwd": .string("/tmp/project"),
                "mcpServers": .array([]),
            ])))
        try await transport.feed(.response(
            id: .integer(2),
            result: .object(["sessionId": .string("fresh")])))

        let result = try await task.value
        #expect(result.activation == .freshBecauseRestorationUnsupported(sessionID: "fresh"))
        #expect(result.capabilities == .init(loadSession: false, resumeSession: false))
        #expect(await requestMethods(transport) == ["initialize", "session/new"])
        await result.connection.close()
    }

    @Test func connect_WhenResumeIsSelected_SendsResumeAndAcceptsNoReplay() async throws {
        let transport = FakeACPTransport()
        let recorder = AgentEventRecorder()
        let task = restorationConnection(
            transport: transport,
            need: .contextOnly,
            recorder: recorder)
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: true, resume: true))

        #expect(await transport.nextSentMessage() == restorationRequest(
            id: 2,
            method: "session/resume"))
        try await transport.feed(.response(id: .integer(2), result: .object([:])))

        let result = try await task.value
        #expect(result.activation == .resumed(sessionID: "saved"))
        #expect(await recorder.recordedEvents().isEmpty)
        await result.connection.close()
    }

    @Test func connect_WhenResumeEmitsHistoricalMessage_ClosesAsMalformed() async throws {
        let transport = FakeACPTransport()
        let task = restorationConnection(transport: transport, need: .contextOnly)
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: true, resume: true))
        _ = await transport.nextSentMessage()

        try await transport.feed(restoredAgentMessage(text: "must not replay"))

        await #expect(throws: ACPClientError.malformedResponse(
            "Historical session update arrived during session/resume.")) {
            try await task.value
        }
        #expect(await transport.observedTerminationCount() == 1)
    }

    @Test func connect_WhenResumePublishesAllowlistedSetupState_KeepsItSilentAndSucceeds()
        async throws
    {
        let transport = FakeACPTransport()
        let recorder = AgentEventRecorder()
        let task = restorationConnection(
            transport: transport,
            need: .contextOnly,
            recorder: recorder)
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: false, resume: true))
        _ = await transport.nextSentMessage()

        for update in resumeSetupUpdates() {
            try await transport.feed(sessionUpdate(update, sessionID: "saved"))
        }
        try await transport.feed(.response(id: .integer(2), result: .object([:])))

        let result = try await task.value
        #expect(result.activation == .resumed(sessionID: "saved"))
        #expect(await recorder.recordedEvents().isEmpty)
        await result.connection.close()
    }

    @Test func connect_WhenResumePublishesUnknownSetupState_ClosesAsMalformed() async throws {
        let transport = FakeACPTransport()
        let task = restorationConnection(transport: transport, need: .contextOnly)
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: false, resume: true))
        _ = await transport.nextSentMessage()

        try await transport.feed(sessionUpdate(.object([
            "sessionUpdate": .string("vendor_setup_update"),
        ]), sessionID: "saved"))

        await #expect(throws: ACPClientError.malformedResponse(
            "Historical session update arrived during session/resume.")) {
            try await task.value
        }
    }

    @Test func connect_WhenLoadUpdateUsesAnotherSession_IgnoresIt() async throws {
        let transport = FakeACPTransport()
        let recorder = AgentEventRecorder()
        let task = restorationConnection(
            transport: transport,
            need: .visibleHistory,
            recorder: recorder)
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: true, resume: false))
        _ = await transport.nextSentMessage()

        try await transport.feed(sessionUpdate(.object([
            "sessionUpdate": .string("agent_message_chunk"),
            "content": .string("malformed but irrelevant"),
        ]), sessionID: "other"))
        try await transport.feed(restoredAgentMessage(text: "ours"))
        try await transport.feed(.response(id: .integer(2), result: .object([:])))

        let result = try await task.value
        #expect(await recorder.recordedEvents() == [
            .agentMessageDelta(messageID: nil, text: "ours"),
        ])
        await result.connection.close()
    }

    @Test func connect_WhenReplayContainsPermission_RejectsAndCloses() async throws {
        let transport = FakeACPTransport()
        let recorder = AgentEventRecorder()
        let task = restorationConnection(
            transport: transport,
            need: .visibleHistory,
            recorder: recorder)
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: true, resume: false))
        _ = await transport.nextSentMessage()
        try await transport.feed(restoredAgentMessage(text: "staged"))

        try await transport.feed(permissionRequest(
            id: .string("historical-permission"),
            options: [permissionOption(id: "once", name: "Once", kind: "allow_once")],
            sessionID: "saved"))

        await #expect(throws: ACPClientError.malformedResponse(
            "Permission request arrived during session restoration.")) {
            try await task.value
        }
        #expect(await recorder.recordedEvents().isEmpty)
        #expect(await transport.allSentMessages().count == 2)
        #expect(await transport.observedTerminationCount() == 1)
    }

    @Test func connect_WhenReplayOverflowsBound_ClosesBeforePrompt() async throws {
        let transport = FakeACPTransport()
        let recorder = AgentEventRecorder()
        let task = restorationConnection(
            transport: transport,
            need: .visibleHistory,
            recorder: recorder)
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: true, resume: false))
        _ = await transport.nextSentMessage()

        for index in 0...(AgentRunEventDelivery.maximumPendingEntries + 1) {
            try await transport.feed(sessionUpdate(.object([
                "sessionUpdate": .string("current_mode_update"),
                "currentModeId": .string("mode-\(index)"),
            ]), sessionID: "saved"))
        }

        await #expect(throws: ACPClientError.eventDeliveryOverflow) {
            try await task.value
        }
        #expect(await recorder.recordedEvents().isEmpty)
        #expect(await requestMethods(transport) == ["initialize", "session/load"])
        #expect(await transport.observedTerminationCount() == 1)
    }

    @Test func connect_WhenCancelledDuringLoad_IgnoresLateHistoryAndTerminatesOnce()
        async throws
    {
        let transport = FakeACPTransport()
        let recorder = AgentEventRecorder()
        let task = restorationConnection(
            transport: transport,
            need: .visibleHistory,
            recorder: recorder)
        _ = await transport.nextSentMessage()
        await transport.suspendNextSend()
        try await transport.feed(restorationInitializeResponse(load: true, resume: false))
        await transport.waitUntilSendIsSuspended()

        task.cancel()
        await transport.resumeSuspendedSend()
        try? await transport.feed(restoredAgentMessage(text: "late"))

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await recorder.recordedEvents().isEmpty)
        #expect(await transport.observedTerminationCount() == 1)
    }

    @Test func connect_WhenFirstRestoreAborts_DiscardsStagedReplayAndRejectsLateFirstToken()
        async throws
    {
        let recorder = AgentEventRecorder()
        let first = FakeACPTransport()
        let firstTask = restorationConnection(
            transport: first,
            need: .visibleHistory,
            recorder: recorder)
        _ = await first.nextSentMessage()
        try await first.feed(restorationInitializeResponse(load: true, resume: false))
        _ = await first.nextSentMessage()
        try await first.feed(restoredAgentMessage(text: "discard me"))
        try await first.feed(permissionRequest(
            id: .string("old"),
            options: [],
            sessionID: "saved"))
        await #expect(throws: ACPClientError.self) { try await firstTask.value }
        try? await first.feed(restoredAgentMessage(text: "late first"))

        let second = FakeACPTransport()
        let secondTask = restorationConnection(
            transport: second,
            need: .visibleHistory,
            recorder: recorder)
        _ = await second.nextSentMessage()
        try await second.feed(restorationInitializeResponse(load: true, resume: false))
        _ = await second.nextSentMessage()
        try await second.feed(restoredAgentMessage(text: "second attempt"))
        try await second.feed(.response(id: .integer(2), result: .object([:])))

        let result = try await secondTask.value
        #expect(await recorder.recordedEvents() == [
            .agentMessageDelta(messageID: nil, text: "second attempt"),
        ])
        await result.connection.close()
    }

    @Test func connect_WhenRestoredUserChunkHasNonRequestRole_DoesNotExposeIt() async throws {
        try await assertUserReplaySuppressed(role: .string("instruction"))
    }

    @Test func connect_WhenRestoredUserChunkLacksRoleMetadata_SuppressesIt() async throws {
        try await assertUserReplaySuppressed(role: nil)
    }

    @Test func connect_WhenRestoredUserChunkHasMalformedOptionalMetadata_SuppressesIt()
        async throws
    {
        for role in [ACPJSONValue.null, .bool(true), .array([]), .object([:])] {
            try await assertUserReplaySuppressed(role: role)
        }
    }

    @Test func connect_WhenRestorationIsAdded_PreservesAllComposedClientCapabilities()
        async throws
    {
        let transport = FakeACPTransport()
        let task = Task {
            try await ACPClientConnection.connect(
                transport: transport,
                configuration: try makeConfiguration(),
                restoration: try .init(sessionID: "saved", need: .visibleHistory),
                onRestoredEvent: { _ in },
                clientCapabilityFragments: [
                    .object(["response": .object(["version": .integer(1)])]),
                    .object(["background": .object(["enabled": .bool(true)])]),
                ],
                diagnostics: VoiceActivationDiagnostics.shared)
        }

        #expect(await transport.nextSentMessage() == initializeRequest(capabilities: .object([
            "response": .object(["version": .integer(1)]),
            "background": .object(["enabled": .bool(true)]),
        ])))
        try await transport.feed(restorationInitializeResponse(load: false, resume: false))
        _ = await transport.nextSentMessage()
        try await transport.feed(.response(
            id: .integer(2),
            result: .object(["sessionId": .string("fresh")])))
        let result = try await task.value
        await result.connection.close()
    }

    @Test func connect_WhenCapabilityFragmentsCollide_ClosesBeforeASessionRequest()
        async throws
    {
        let transport = FakeACPTransport()
        let adversarial = "authorization\nprivate-token"

        do {
            _ = try await ACPClientConnection.connect(
                transport: transport,
                configuration: try makeConfiguration(),
                restoration: try .init(sessionID: "saved", need: .visibleHistory),
                onRestoredEvent: { _ in },
                clientCapabilityFragments: [
                    .object([adversarial: .bool(true)]),
                    .object([adversarial: .bool(false)]),
                ],
                diagnostics: VoiceActivationDiagnostics.shared)
            Issue.record("Expected capability collision")
        } catch let error as ACPClientCapabilitiesError {
            #expect(error == .conflictingValues)
            #expect(!error.localizedDescription.contains("authorization"))
            #expect(!String(reflecting: error).contains("private-token"))
        }
        #expect(await requestMethods(transport).isEmpty)
        #expect(await transport.observedTerminationCount() == 1)
    }

    @Test func connect_WhenLoadFailsWithMissingSession_ReportsUnavailableBeforePrompt()
        async throws
    {
        let transport = FakeACPTransport()
        let task = restorationConnection(transport: transport, need: .visibleHistory)
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: true, resume: false))
        _ = await transport.nextSentMessage()
        try await transport.feed(.errorResponse(
            id: .integer(2),
            error: ACPJSONRPCError(
                code: -32_603,
                message: "session saved is not found; private-token",
                data: .object(["sessionId": .string("saved")]))))

        do {
            _ = try await task.value
            Issue.record("Expected unavailable session")
        } catch let error as ACPClientError {
            guard case let .sessionUnavailable(code, message) = error else {
                Issue.record("Expected sessionUnavailable, got \(error)")
                return
            }
            #expect(code == -32_603)
            #expect(message == "Saved agent session is unavailable.")
            #expect(!error.localizedDescription.contains("saved"))
            #expect(!error.localizedDescription.contains("private-token"))
        }
        #expect(await requestMethods(transport) == ["initialize", "session/load"])
    }

    @Test func connect_WhenCapabilityValueIsMalformed_ClosesBeforeSessionRequest() async throws {
        let transport = FakeACPTransport()
        let task = restorationConnection(transport: transport, need: .contextOnly)
        _ = await transport.nextSentMessage()
        try await transport.feed(.response(
            id: .integer(1),
            result: .object([
                "protocolVersion": .integer(1),
                "agentCapabilities": .object([
                    "sessionCapabilities": .object(["resume": .bool(true)]),
                ]),
            ])))

        await #expect(throws: ACPClientError.malformedResponse(
            "Invalid agentCapabilities.sessionCapabilities.resume.")) {
            try await task.value
        }
        #expect(await requestMethods(transport) == ["initialize"])
        #expect(await transport.observedTerminationCount() == 1)
    }

    @Test func connect_WhenMatchingReplayContentIsMalformed_UsesContentFreeFailure()
        async throws
    {
        let transport = FakeACPTransport()
        let task = restorationConnection(transport: transport, need: .visibleHistory)
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: true, resume: false))
        _ = await transport.nextSentMessage()
        try await transport.feed(sessionUpdate(.object([
            "sessionUpdate": .string("agent_message_chunk"),
            "content": .object(["private-token": .string("do not expose")]),
        ]), sessionID: "saved"))

        do {
            _ = try await task.value
            Issue.record("Expected malformed replay failure")
        } catch let error as ACPClientError {
            #expect(error == .malformedResponse("Invalid session restoration update."))
            #expect(!error.localizedDescription.contains("private-token"))
            #expect(!String(reflecting: error).contains("do not expose"))
        }
        #expect(await transport.observedTerminationCount() == 1)
    }

    @Test func connect_WhenRestorationUpdateSessionIdentifierIsInvalid_ClosesContentFree()
        async throws
    {
        for sessionID in ["", String(repeating: "private-id", count: 500)] {
            let transport = FakeACPTransport()
            let task = restorationConnection(transport: transport, need: .visibleHistory)
            _ = await transport.nextSentMessage()
            try await transport.feed(restorationInitializeResponse(load: true, resume: false))
            _ = await transport.nextSentMessage()
            try await transport.feed(restoredAgentMessage(
                text: "private replay",
                sessionID: sessionID))

            do {
                _ = try await task.value
                Issue.record("Expected invalid update session ID")
            } catch let error as ACPClientError {
                #expect(error == .malformedResponse("Invalid session/update sessionId."))
                #expect(!error.localizedDescription.contains("private-id"))
                #expect(!String(reflecting: error).contains("private replay"))
            }
            #expect(await transport.observedTerminationCount() == 1)
        }
    }

    @Test func connect_WhenLoadDiscardingReplayIsSelected_ValidatesAndDiscardsHistory()
        async throws
    {
        let transport = FakeACPTransport()
        let recorder = AgentEventRecorder()
        let task = restorationConnection(
            transport: transport,
            need: .contextOnly,
            recorder: recorder)
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: true, resume: false))
        #expect(await transport.nextSentMessage() == restorationRequest(
            id: 2,
            method: "session/load"))
        try await transport.feed(restoredAgentMessage(text: "valid but discarded"))
        try await transport.feed(.response(id: .integer(2), result: .object([:])))

        let result = try await task.value
        #expect(result.activation == .loaded(sessionID: "saved"))
        #expect(await recorder.recordedEvents().isEmpty)
        await result.connection.close()
    }

    @Test func connect_WhenRestoredDeliveryIsDelayed_DrainsBeforeReturning() async throws {
        let transport = FakeACPTransport()
        let gate = AgentEventGate()
        let completion = AgentEventSignal()
        let task = Task {
            let result = try await ACPClientConnection.connect(
                transport: transport,
                configuration: try makeConfiguration(),
                restoration: try .init(sessionID: "saved", need: .visibleHistory),
                onRestoredEvent: { event in
                    if case .agentMessageDelta = event {
                        await gate.pause()
                    }
                })
            await completion.signal()
            return result
        }
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: true, resume: false))
        _ = await transport.nextSentMessage()
        try await transport.feed(restoredAgentMessage(text: "wait"))
        try await transport.feed(.response(id: .integer(2), result: .object([:])))

        await gate.waitUntilEntered()
        #expect(await completion.observedSignal() == false)
        await gate.open()
        let result = try await task.value
        #expect(await completion.observedSignal())
        await result.connection.close()
    }

    @Test func connect_WhenTaskWasAlreadyCancelled_SendsNothingAndTerminatesOnce() async throws {
        let transport = FakeACPTransport()
        let start = AgentEventSignal()
        let task = Task {
            await start.wait()
            return try await ACPClientConnection.connect(
                transport: transport,
                configuration: try makeConfiguration())
        }
        task.cancel()
        await start.signal()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.allSentMessages().isEmpty)
        #expect(await transport.observedTerminationCount() == 1)
    }

    @Test func connect_WhenInitializeWriteIsCancelled_ClosesWithoutSetupOrPrompt() async throws {
        let transport = FakeACPTransport()
        await transport.suspendNextSend()
        let task = Task {
            try await ACPClientConnection.connect(
                transport: transport,
                configuration: try makeConfiguration())
        }
        await transport.waitUntilSendIsSuspended()

        task.cancel()
        await transport.resumeSuspendedSend()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await requestMethods(transport).allSatisfy { $0 == "initialize" })
        #expect(await transport.observedTerminationCount() == 1)
    }

    @Test func connect_WhenCancelledAfterLoadResponse_ClosesBeforeReadiness() async throws {
        let transport = FakeACPTransport()
        let gate = AgentEventGate()
        let task = Task {
            try await ACPClientConnection.connect(
                transport: transport,
                configuration: try makeConfiguration(),
                restoration: try .init(sessionID: "saved", need: .visibleHistory),
                onRestoredEvent: { event in
                    if case .agentMessageDelta = event {
                        await gate.pause()
                    }
                })
        }
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: true, resume: false))
        _ = await transport.nextSentMessage()
        try await transport.feed(restoredAgentMessage(text: "staged"))
        try await transport.feed(.response(id: .integer(2), result: .object([:])))
        await gate.waitUntilEntered()

        task.cancel()
        await gate.open()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await requestMethods(transport) == ["initialize", "session/load"])
        #expect(await transport.observedTerminationCount() == 1)
    }

    @Test func restorationRequest_WhenSessionIdentifierIsInvalid_ThrowsContentFreeError() {
        let invalid = [
            "",
            String(repeating: "x", count: ACPEventDecoder.maximumOpaqueIdentifierBytes + 1),
            String(repeating: "é", count: ACPEventDecoder.maximumOpaqueIdentifierBytes / 2 + 1),
        ]
        for sessionID in invalid {
            do {
                _ = try AgentSessionRestorationRequest(
                    sessionID: sessionID,
                    need: .visibleHistory)
                Issue.record("Expected invalid restoration ID")
            } catch let error as AgentSessionRestorationRequest.ValidationError {
                #expect(error == .invalidSessionID)
                #expect(!error.localizedDescription.contains(sessionID))
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test func connect_WhenNewSessionIdentifierIsInvalid_ClosesContentFree() async throws {
        for sessionID in [
            "",
            String(repeating: "secret-id", count: 600),
        ] {
            let transport = FakeACPTransport()
            let task = Task {
                try await ACPClientConnection.connect(
                    transport: transport,
                    configuration: try makeConfiguration())
            }
            _ = await transport.nextSentMessage()
            try await transport.feed(restorationInitializeResponse(load: false, resume: false))
            _ = await transport.nextSentMessage()
            try await transport.feed(.response(
                id: .integer(2),
                result: .object(["sessionId": .string(sessionID)])))

            do {
                _ = try await task.value
                Issue.record("Expected invalid new session ID")
            } catch let error as ACPClientError {
                #expect(!error.localizedDescription.contains("secret-id"))
            }
            #expect(await transport.observedTerminationCount() == 1)
        }
    }

    private func assertUserReplaySuppressed(role: ACPJSONValue?) async throws {
        let transport = FakeACPTransport()
        let recorder = AgentEventRecorder()
        let task = restorationConnection(
            transport: transport,
            need: .visibleHistory,
            recorder: recorder)
        _ = await transport.nextSentMessage()
        try await transport.feed(restorationInitializeResponse(load: true, resume: false))
        _ = await transport.nextSentMessage()
        try await transport.feed(restoredUserMessage(text: "private context", role: role))
        try await transport.feed(.response(id: .integer(2), result: .object([:])))

        let result = try await task.value
        #expect(await recorder.recordedEvents().isEmpty)
        await result.connection.close()
    }
}
