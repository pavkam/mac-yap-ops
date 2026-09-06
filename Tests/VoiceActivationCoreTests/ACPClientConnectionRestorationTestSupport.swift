// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
@testable import VoiceActivationCore

extension ACPClientConnectionTests {
    func restorationConnection(
        transport: FakeACPTransport,
        need: AgentSessionRestorationNeed,
        recorder: AgentEventRecorder = AgentEventRecorder(),
        diagnostics: any VoiceActivationDiagnosticRecording = VoiceActivationDiagnostics.shared
    ) -> Task<ACPConnectionResult, any Error> {
        Task {
            try await ACPClientConnection.connect(
                transport: transport,
                configuration: try makeConfiguration(),
                restoration: try .init(sessionID: "saved", need: need),
                onRestoredEvent: { _, event in await recorder.record(event) },
                diagnostics: diagnostics)
        }
    }

    func initializeRequest(
        capabilities: ACPJSONValue = .object([
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
        ])
    ) -> ACPMessage {
        .request(
            id: .integer(1),
            method: "initialize",
            params: .object([
                "protocolVersion": .integer(1),
                "clientCapabilities": capabilities,
                "clientInfo": .object([
                    "name": .string("voice-activation"),
                    "title": .string("Voice Activation"),
                    "version": .string("0.1.0"),
                ]),
            ]))
    }

    func restorationInitializeResponse(load: Bool, resume: Bool) -> ACPMessage {
        var capabilities: [String: ACPJSONValue] = ["loadSession": .bool(load)]
        if resume {
            capabilities["sessionCapabilities"] = .object(["resume": .object([:])])
        }
        return .response(
            id: .integer(1),
            result: .object([
                "protocolVersion": .integer(1),
                "agentCapabilities": .object(capabilities),
                "agentInfo": .object([
                    "name": .string("test-agent"),
                    "title": .string("Test Agent"),
                    "version": .string("1.0.0"),
                ]),
            ]))
    }

    func restorationRequest(id: Int64, method: String) -> ACPMessage {
        .request(
            id: .integer(id),
            method: method,
            params: .object([
                "sessionId": .string("saved"),
                "cwd": .string("/tmp/project"),
                "mcpServers": .array([]),
            ]))
    }

    func restoredAgentMessage(
        text: String,
        messageID: String? = nil,
        sessionID: String = "saved"
    ) -> ACPMessage {
        var update: [String: ACPJSONValue] = [
            "sessionUpdate": .string("agent_message_chunk"),
            "content": .object([
                "type": .string("text"),
                "text": .string(text),
            ]),
        ]
        if let messageID {
            update["messageId"] = .string(messageID)
        }
        return sessionUpdate(.object(update), sessionID: sessionID)
    }

    func restoredUserMessage(text: String, role: ACPJSONValue?) -> ACPMessage {
        var content: [String: ACPJSONValue] = [
            "type": .string("text"),
            "text": .string(text),
        ]
        if let role {
            content["_meta"] = .object([
                "ciobanu.org.voiceActivation": .object([
                    "promptBlockRole": role,
                ]),
            ])
        }
        return sessionUpdate(.object([
            "sessionUpdate": .string("user_message_chunk"),
            "content": .object(content),
        ]), sessionID: "saved")
    }

    func resumeSetupUpdates() -> [ACPJSONValue] {
        [
            .object([
                "sessionUpdate": .string("available_commands_update"),
                "availableCommands": .array([]),
            ]),
            .object([
                "sessionUpdate": .string("current_mode_update"),
                "currentModeId": .string("code"),
            ]),
            .object([
                "sessionUpdate": .string("config_option_update"),
                "configOptions": .array([]),
            ]),
            .object([
                "sessionUpdate": .string("session_info_update"),
                "title": .null,
                "updatedAt": .null,
            ]),
            .object([
                "sessionUpdate": .string("usage_update"),
                "used": .integer(1),
                "size": .integer(2),
            ]),
        ]
    }

    func requestMethods(_ transport: FakeACPTransport) async -> [String] {
        await transport.allSentMessages().compactMap { message in
            guard case let .request(_, method, _) = message else { return nil }
            return method
        }
    }
}
