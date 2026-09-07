// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import YapOpsApp
@testable import YapOpsCore

@Suite(.serialized, .timeLimit(.minutes(1)))
struct AgentPermissionTransportResultFlowTests {
    @MainActor @Test
    func selectedPermission_UsesExactWireIdentityAndSpeaksOnlyFollowingAgentMessage()
        async throws
    {
        let fixture = try makeFixture()
        defer { Task { await fixture.runner.shutdown() } }
        #expect(await fixture.app.model.start())
        let profileID = try #require(fixture.app.preferences.wakeProfiles.first?.id)
        fixture.app.model.coordinator.pushToTalkPressed(profileID: profileID)
        fixture.app.speech.emit("clean downloads")
        fixture.app.model.coordinator.pushToTalkReleased()
        guard await waitUntil(condition: {
            await fixture.transport.hasPromptRequest()
        }) else {
            let frames = await fixture.transport.sentFrameKinds()
            let phase = String(describing: fixture.app.model.agentRunSnapshot?.phase)
            Issue.record("Prompt did not start; frames=\(frames), phase=\(phase)")
            return
        }
        await fixture.transport.emitPermissionRequest()
        #expect(await waitUntil { fixture.app.model.agentRunSnapshot?.permissions.count == 1 })
        let snapshot = try #require(fixture.app.model.agentRunSnapshot)
        let permission = try #require(snapshot.permissions.first)
        #expect(fixture.audio.spoken.map(\.text) == [
            "Move 43 old downloads to Trash?", "Allow once", "Deny",
        ])

        fixture.app.model.resolveAgentPermission(
            runID: snapshot.runID,
            key: permission.key,
            optionID: "allow-once")
        #expect(await waitUntil {
            await fixture.transport.selectedPermissionResponseCount() == 1
        })
        #expect(await fixture.transport.sentMessages().contains(
            exactSelectionResponse(optionID: "allow-once")))

        let speechBeforeToolCompletion = fixture.audio.spoken.map(\.text)
        await fixture.transport.emitToolCompletion()
        #expect(await waitUntil {
            fixture.app.model.agentRunSnapshot?.tools.first?.status == .completed
        })
        #expect(fixture.audio.spoken.map(\.text) == speechBeforeToolCompletion)

        let result = "Done — 43 items are in Trash."
        await fixture.transport.emitAgentMessage(result)
        #expect(await waitUntil { fixture.audio.spoken.map(\.text).contains(result) })
        await fixture.transport.completePrompt(stopReason: "end_turn")
        #expect(await waitUntil { fixture.app.model.agentRunSnapshot?.phase == .listening })

        #expect(fixture.audio.spoken.map(\.text).filter { $0 == result }.count == 1)
        await fixture.app.model.shutdown()
    }

    @MainActor @Test
    func cancelledPermission_SettlesOnceAndSpeaksNoAppAuthoredResult() async throws {
        let fixture = try makeFixture()
        defer { Task { await fixture.runner.shutdown() } }
        #expect(await fixture.app.model.start())
        let profileID = try #require(fixture.app.preferences.wakeProfiles.first?.id)
        fixture.app.model.coordinator.pushToTalkPressed(profileID: profileID)
        fixture.app.speech.emit("clean downloads")
        fixture.app.model.coordinator.pushToTalkReleased()
        guard await waitUntil(condition: {
            await fixture.transport.hasPromptRequest()
        }) else {
            let frames = await fixture.transport.sentFrameKinds()
            let phase = String(describing: fixture.app.model.agentRunSnapshot?.phase)
            Issue.record("Prompt did not start; frames=\(frames), phase=\(phase)")
            return
        }
        await fixture.transport.emitPermissionRequest()
        #expect(await waitUntil { fixture.app.model.agentRunSnapshot?.permissions.count == 1 })
        let snapshot = try #require(fixture.app.model.agentRunSnapshot)
        let confirmationSpeech = fixture.audio.spoken.map(\.text)

        fixture.app.model.cancelAgentRun(runID: snapshot.runID)
        #expect(await waitUntil {
            await fixture.transport.cancelledPermissionResponseCount() == 1
        })
        #expect(await waitUntil { fixture.app.model.agentRunSnapshot?.phase == .listening })

        #expect(await fixture.transport.cancelledPermissionResponseCount() == 1)
        #expect(fixture.audio.spoken.map(\.text) == confirmationSpeech)
        #expect(!fixture.audio.spoken.map(\.text).contains("Stopped."))
        await fixture.app.model.shutdown()
    }

    @MainActor
    private func makeFixture() throws -> FlowFixture {
        let helpers = AppModelTests()
        let profile = try helpers.makeAgentProfile(
            displayName: "Codex",
            pushToTalkHotKey: .defaultValue)
        let transport = PermissionFlowACPTransport()
        let runner = ACPAgentRunner(
            transportFactory: PermissionFlowACPTransportFactory(transport: transport),
            settleClock: PermissionFlowImmediateClock())
        let audio = AppModelAgentConversationAudioSpy()
        let app = try AppModelTests.Fixture(
            profiles: [profile],
            agentRunner: runner,
            agentConversationAudioPlayer: audio,
            isExecutableFile: { _ in true },
            isDirectory: { _ in true })
        return FlowFixture(app: app, runner: runner, transport: transport, audio: audio)
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(5),
        condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return await condition()
    }

    private func exactSelectionResponse(optionID: String) -> ACPMessage {
        .response(
            id: PermissionFlowACPTransport.permissionRequestID,
            result: .object([
                "outcome": .object([
                    "outcome": .string("selected"),
                    "optionId": .string(optionID),
                ]),
            ]))
    }
}

@MainActor
private struct FlowFixture {
    let app: AppModelTests.Fixture
    let runner: ACPAgentRunner
    let transport: PermissionFlowACPTransport
    let audio: AppModelAgentConversationAudioSpy
}

private enum PermissionFlowTransportError: Error {
    case invalidFrame
}

private actor PermissionFlowACPTransport: ACPTransport {
    static let permissionRequestID = ACPRequestID.string("permission-flow")

    private let outputStream: AsyncThrowingStream<Data, any Error>
    private let outputContinuation: AsyncThrowingStream<Data, any Error>.Continuation
    private let diagnosticStream: AsyncStream<Data>
    private let diagnosticContinuation: AsyncStream<Data>.Continuation
    private var messages: [ACPMessage] = []
    private var promptRequestID: ACPRequestID?
    private var exitStatus: Int32?
    private var exitContinuation: CheckedContinuation<Int32, Never>?

    init() {
        let output = AsyncThrowingStream<Data, any Error>.makeStream()
        outputStream = output.stream
        outputContinuation = output.continuation
        let diagnostics = AsyncStream<Data>.makeStream()
        diagnosticStream = diagnostics.stream
        diagnosticContinuation = diagnostics.continuation
    }

    func output() async -> AsyncThrowingStream<Data, any Error> { outputStream }
    func diagnostics() async -> AsyncStream<Data> { diagnosticStream }

    func send(_ data: Data) async throws {
        guard data.last == 0x0A,
            let message = try? JSONDecoder().decode(
                ACPMessage.self,
                from: Data(data.dropLast()))
        else {
            throw PermissionFlowTransportError.invalidFrame
        }
        messages.append(message)
        switch message {
        case .request(let id, "initialize", _):
            feed(.response(
                id: id,
                result: .object([
                    "protocolVersion": .integer(1),
                    "agentCapabilities": .object([:]),
                    "agentInfo": .object([
                        "name": .string("test-agent"),
                        "title": .string("Test Agent"),
                        "version": .string("1.0.0"),
                    ]),
                    "authMethods": .array([]),
                ])))
        case .request(let id, "session/new", _):
            feed(.response(
                id: id,
                result: .object(["sessionId": .string("flow-session")])))
        case .request(let id, "session/prompt", _):
            promptRequestID = id
        case .notification("session/cancel", _):
            if let promptRequestID {
                feed(.response(
                    id: promptRequestID,
                    result: .object(["stopReason": .string("cancelled")])))
            }
        default:
            break
        }
    }

    func emitToolCompletion() {
        feed(sessionUpdate(.object([
            "sessionUpdate": .string("tool_call"),
            "toolCallId": .string("trash"),
            "title": .string("Move downloads"),
            "kind": .string("delete"),
            "status": .string("in_progress"),
        ])))
        feed(sessionUpdate(.object([
            "sessionUpdate": .string("tool_call_update"),
            "toolCallId": .string("trash"),
            "status": .string("completed"),
        ])))
    }

    func hasPromptRequest() -> Bool { promptRequestID != nil }

    func emitPermissionRequest() {
        feed(permissionRequest())
    }

    func emitAgentMessage(_ text: String) {
        feed(sessionUpdate(.object([
            "sessionUpdate": .string("agent_message_chunk"),
            "messageId": .string("result"),
            "content": .object([
                "type": .string("text"),
                "text": .string(text),
            ]),
        ])))
    }

    func completePrompt(stopReason: String) {
        guard let promptRequestID else { return }
        feed(.response(
            id: promptRequestID,
            result: .object(["stopReason": .string(stopReason)])))
    }

    func sentMessages() -> [ACPMessage] { messages }

    func sentFrameKinds() -> [String] {
        messages.map { message in
            switch message {
            case .request(_, let method, _): "request:\(method)"
            case .notification(let method, _): "notification:\(method)"
            case .response: "response"
            case .errorResponse: "error_response"
            }
        }
    }

    func selectedPermissionResponseCount() -> Int {
        messages.count { message in
            guard case .response(Self.permissionRequestID, let result) = message else {
                return false
            }
            guard case .object(let response) = result,
                case .object(let outcome)? = response["outcome"],
                outcome["outcome"] == .string("selected")
            else {
                return false
            }
            return true
        }
    }

    func cancelledPermissionResponseCount() -> Int {
        messages.count { message in
            message == .response(
                id: Self.permissionRequestID,
                result: .object([
                    "outcome": .object(["outcome": .string("cancelled")]),
                ]))
        }
    }

    func waitForExit() async -> Int32 {
        if let exitStatus { return exitStatus }
        return await withCheckedContinuation { exitContinuation = $0 }
    }

    func waitForDrain() async {}
    func closeReadStreams() async { finish(status: -15) }
    func terminate() async { finish(status: -15) }

    private func permissionRequest() -> ACPMessage {
        .request(
            id: Self.permissionRequestID,
            method: "session/request_permission",
            params: .object([
                "sessionId": .string("flow-session"),
                "toolCall": .object([
                    "toolCallId": .string("trash"),
                    "title": .string("Move downloads"),
                    "kind": .string("delete"),
                    "status": .string("pending"),
                ]),
                "options": .array([
                    .object([
                        "optionId": .string("allow-once"),
                        "name": .string("Allow once"),
                        "kind": .string("allow_once"),
                    ]),
                    .object([
                        "optionId": .string("deny"),
                        "name": .string("Deny"),
                        "kind": .string("reject_once"),
                    ]),
                ]),
                "_meta": .object([
                    "permission": .object([
                        "version": .integer(1),
                        "title": .string("Move 43 old downloads to Trash?"),
                    ]),
                ]),
            ]))
    }

    private func sessionUpdate(_ update: ACPJSONValue) -> ACPMessage {
        .notification(
            method: "session/update",
            params: .object([
                "sessionId": .string("flow-session"),
                "update": update,
            ]))
    }

    private func feed(_ message: ACPMessage) {
        guard var data = try? JSONEncoder().encode(message) else { return }
        data.append(0x0A)
        outputContinuation.yield(data)
    }

    private func finish(status: Int32) {
        guard exitStatus == nil else { return }
        exitStatus = status
        outputContinuation.finish()
        diagnosticContinuation.finish()
        exitContinuation?.resume(returning: status)
        exitContinuation = nil
    }
}

private struct PermissionFlowACPTransportFactory: ACPTransportCreating {
    let transport: PermissionFlowACPTransport

    func makeTransport(configuration: AgentHarnessConfiguration) async throws
        -> any ACPTransport
    {
        transport
    }
}

private struct PermissionFlowImmediateClock: ACPAgentRunnerClock {
    func sleep(for duration: Duration) async {}
}
