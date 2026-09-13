// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import YapOpsCore


extension ACPClientConnectionTests {
    func establishConnection(
        transport: FakeACPTransport,
        policy: AgentPermissionPolicy = .ask,
        preset: AgentHarnessPreset = .codex,
        systemPrompt: String = "",
        diagnostics: any YapOpsDiagnosticRecording = YapOpsDiagnostics.shared
    ) async throws -> ACPClientConnection
    {
        let connectionTask = Task {
            try await ACPClientConnection.connect(
                transport: transport,
                configuration: try makeConfiguration(
                    policy: policy,
                    preset: preset,
                    systemPrompt: systemPrompt),
                diagnostics: diagnostics).connection
        }
        _ = await transport.nextSentMessage()
        try await transport.feed(initializeResponse())
        _ = await transport.nextSentMessage()
        try await transport.feed(.response(
            id: .integer(2),
            result: .object(["sessionId": .string("session-1")])))
        return try await connectionTask.value
    }

    final class ConnectionDiagnosticRecorder: YapOpsDiagnosticRecording,
        @unchecked Sendable
    {
        struct Entry: Sendable {
            let event: String
            let fields: [String: String]
        }

        private let lock = NSLock()
        private var entries: [Entry] = []

        func record(
            category: YapOpsDiagnosticCategory,
            event: String,
            level: YapOpsDiagnosticLevel,
            fields: [String: String]
        ) {
            lock.withLock {
                entries.append(Entry(event: event, fields: fields))
            }
        }

        func flush() {}

        func snapshot() -> [Entry] {
            lock.withLock { entries }
        }
    }

    func prompt(
        _ connection: ACPClientConnection,
        text: String,
        recorder: AgentEventRecorder) -> Task<AgentRunResult, any Error>
    {
        Task {
            try await connection.prompt(
                AgentPrompt(request: text, context: nil),
                onEvent: { event in await recorder.record(event) })
        }
    }

    /// Waits until the receive loop has handled every frame fed so far.
    ///
    /// One receive loop drains one ordered stream, so observing the reply to a later
    /// probe frame proves every earlier frame was fully handled. An unsupported method
    /// always draws a reply, which makes this usable between turns, where no event
    /// delivery is active to observe instead.
    func drainFedFrames(
        transport: FakeACPTransport,
        probeID: ACPRequestID = .string("drain-probe")) async throws
    {
        try await transport.feed(.request(
            id: probeID,
            method: "yapops/drain-probe",
            params: .object([:])))
        #expect(await transport.nextSentMessage() == .errorResponse(
            id: probeID,
            error: ACPJSONRPCError(code: -32_601, message: "Method not found")))
    }

    func promptRequest(id: Int64, text: String, sessionID: String = "session-1") -> ACPMessage {
        .request(
            id: .integer(id),
            method: "session/prompt",
            params: .object([
                "sessionId": .string(sessionID),
                "prompt": .array([
                    ACPClientConnection.encodedPromptBlock(for: .text(
                        role: .instruction,
                        value: ACPClientConnection.markdownPresentationInstruction)),
                    ACPClientConnection.encodedPromptBlock(for: .text(
                        role: .request,
                        value: text)),
                ]),
            ]))
    }

    func assertCursorBlockingRequestIsCancelled(method: String) async throws {
        let transport = FakeACPTransport()
        let connection = try await establishConnection(transport: transport)
        let recorder = AgentEventRecorder()
        let promptTask = prompt(connection, text: "Wait", recorder: recorder)
        _ = await recorder.nextEvent()
        _ = await transport.nextSentMessage()
        let requestID = ACPRequestID.string("cursor-extension")
        try await transport.feed(.request(
            id: requestID,
            method: method,
            params: .object(["private": .string(String(repeating: "x", count: 2_000))])))

        #expect(await transport.nextSentMessage() == .response(
            id: requestID,
            result: .object([
                "outcome": .object(["outcome": .string("cancelled")]),
            ])))
        guard case let .diagnostic(summary) = await recorder.nextEvent() else {
            Issue.record("Expected a diagnostic")
            return
        }
        #expect(summary.utf8.count <= ACPClientConnection.maximumDiagnosticBytes)
        #expect(summary.contains(method))
        try await transport.feed(promptResponse(id: 3, stopReason: "end_turn"))
        _ = try await promptTask.value
        await connection.close()
    }

    func makeConfiguration(
        policy: AgentPermissionPolicy = .ask,
        preset: AgentHarnessPreset = .codex,
        systemPrompt: String = "") throws -> AgentHarnessConfiguration
    {
        try AgentHarnessConfiguration(
            preset: preset,
            displayName: "Configured Agent",
            executablePath: "/usr/bin/agent",
            arguments: ["acp"],
            workingDirectory: "/tmp/project",
            permissionPolicy: policy,
            systemPrompt: systemPrompt)
    }

    func initializeResponse(
        protocolVersion: Int64 = 1,
        authMethods: [ACPJSONValue] = []) -> ACPMessage
    {
        .response(
            id: .integer(1),
            result: .object([
                "protocolVersion": .integer(protocolVersion),
                "agentCapabilities": .object([:]),
                "agentInfo": .object([
                    "name": .string("test-agent"),
                    "title": .string("Test Agent"),
                    "version": .string("2.0.0"),
                ]),
                "authMethods": .array(authMethods),
            ]))
    }

    func authMethod(id: String, name: String) -> ACPJSONValue {
        .object([
            "id": .string(id),
            "name": .string(name),
            "description": .string("Authenticate outside the client"),
        ])
    }

    func sessionUpdate(
        _ update: ACPJSONValue,
        sessionID: String = "session-1") -> ACPMessage
    {
        .notification(
            method: "session/update",
            params: .object([
                "sessionId": .string(sessionID),
                "update": update,
            ]))
    }

    func promptResponse(id: Int64, stopReason: String) -> ACPMessage {
        .response(
            id: .integer(id),
            result: .object(["stopReason": .string(stopReason)]))
    }

    func permissionRequest(
        id: ACPRequestID,
        toolID: String = "tool-1",
        options: [ACPJSONValue],
        sessionID: String = "session-1") -> ACPMessage
    {
        .request(
            id: id,
            method: "session/request_permission",
            params: .object([
                "sessionId": .string(sessionID),
                "toolCall": .object([
                    "toolCallId": .string(toolID),
                    "title": .string("Edit a file"),
                    "kind": .string("edit"),
                    "status": .string("pending"),
                ]),
                "options": .array(options),
            ]))
    }

    func permissionOption(id: String, name: String, kind: String) -> ACPJSONValue {
        .object([
            "optionId": .string(id),
            "name": .string(name),
            "kind": .string(kind),
        ])
    }

    func permissionSelection(id: ACPRequestID, optionID: String) -> ACPMessage {
        .response(
            id: id,
            result: .object([
                "outcome": .object([
                    "outcome": .string("selected"),
                    "optionId": .string(optionID),
                ]),
            ]))
    }

    func permissionCancellation(id: ACPRequestID) -> ACPMessage {
        .response(
            id: id,
            result: .object([
                "outcome": .object(["outcome": .string("cancelled")]),
            ]))
    }
}
