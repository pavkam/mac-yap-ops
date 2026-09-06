// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Testing
@testable import VoiceActivationCore

@Suite struct ACPAgentCapabilitiesTests {
    @Test func decode_WhenPinnedClaudeAdvertisesSteering_EnablesHostOwnedIdleSteering()
        throws
    {
        let result = try ACPAgentCapabilities.decode(
            initializeResult: initializeResult(
                name: "@agentclientprotocol/claude-agent-acp",
                version: "0.73.0",
                steering: .object(["supported": .bool(true)])),
            preset: .claude)

        #expect(result.agentName == "@agentclientprotocol/claude-agent-acp")
        #expect(result.agentVersion == "0.73.0")
        #expect(result.supportsHostOwnedIdleSteering)
    }

    @Test(arguments: [AgentHarnessPreset.cursor, .codex, .custom])
    func decode_WhenPresetIsNotValidatedClaude_RejectsSteering(
        preset: AgentHarnessPreset
    ) throws {
        let result = try ACPAgentCapabilities.decode(
            initializeResult: initializeResult(
                name: "@agentclientprotocol/claude-agent-acp",
                version: "0.73.0",
                steering: .object(["supported": .bool(true)])),
            preset: preset)

        #expect(!result.supportsHostOwnedIdleSteering)
    }

    @Test(arguments: [
        ("@agentclientprotocol/claude-agent-acp", "0.74.0"),
        ("another-agent", "0.73.0"),
    ])
    func decode_WhenIdentityIsNotExact_RejectsSteering(
        name: String,
        version: String
    ) throws {
        let result = try ACPAgentCapabilities.decode(
            initializeResult: initializeResult(
                name: name,
                version: version,
                steering: .object(["supported": .bool(true)])),
            preset: .claude)

        #expect(!result.supportsHostOwnedIdleSteering)
    }

    @Test(arguments: [true, false])
    func decode_WhenIdentityIsEmpty_FailsClosed(emptyName: Bool) {
        #expect(throws: ACPClientError.self) {
            try ACPAgentCapabilities.decode(
                initializeResult: initializeResult(
                    name: emptyName ? "" : "valid-agent",
                    version: emptyName ? "1.0.0" : ""),
                preset: .claude)
        }
    }

    @Test func decode_WhenSteeringMetadataIsMissing_RejectsSteering() throws {
        let result = try ACPAgentCapabilities.decode(
            initializeResult: initializeResult(
                name: "@agentclientprotocol/claude-agent-acp",
                version: "0.73.0"),
            preset: .claude)

        #expect(!result.supportsHostOwnedIdleSteering)
    }

    @Test(arguments: [
        (ACPJSONValue.string("private steering payload"), "private steering payload"),
        (
            ACPJSONValue.object(["supported": .string("private capability value")]),
            "private capability value"
        ),
    ])
    func decode_WhenClaimedSteeringIsMalformed_FailsContentFree(
        steering: ACPJSONValue,
        privateValue: String
    ) {
        do {
            _ = try ACPAgentCapabilities.decode(
                initializeResult: initializeResult(
                    name: "@agentclientprotocol/claude-agent-acp",
                    version: "0.73.0",
                    steering: steering),
                preset: .claude)
            Issue.record("Expected malformed steering metadata")
        } catch {
            #expect(!String(reflecting: error).contains(privateValue))
            #expect(!error.localizedDescription.contains(privateValue))
        }
    }

    @Test func decode_WhenTopLevelMetadataIsMalformed_FailsContentFree() {
        let privateValue = "private top-level metadata"
        let result: ACPJSONValue = .object([
            "agentInfo": .object([
                "name": .string("@agentclientprotocol/claude-agent-acp"),
                "version": .string("0.73.0"),
            ]),
            "_meta": .string(privateValue),
        ])

        do {
            _ = try ACPAgentCapabilities.decode(initializeResult: result, preset: .claude)
            Issue.record("Expected malformed top-level metadata")
        } catch {
            #expect(!String(reflecting: error).contains(privateValue))
            #expect(!error.localizedDescription.contains(privateValue))
        }
    }

    @Test(arguments: [true, false])
    func decode_WhenIdentityIsOversized_FailsContentFree(oversizeName: Bool) {
        let privateValue = String(
            repeating: "private-provider-identity-",
            count: ACPEventDecoder.maximumOpaqueIdentifierBytes)

        do {
            _ = try ACPAgentCapabilities.decode(
                initializeResult: initializeResult(
                    name: oversizeName ? privateValue : "valid-agent",
                    version: oversizeName ? "1.0.0" : privateValue,
                    steering: .object(["supported": .bool(true)])),
                preset: .claude)
            Issue.record("Expected oversized agent identity")
        } catch {
            #expect(!String(reflecting: error).contains(privateValue))
            #expect(!error.localizedDescription.contains(privateValue))
        }
    }

    @Test func applyInitializeResult_PreservesDisplayAndRestorationNegotiation()
        async throws
    {
        let configuration = try AgentHarnessConfiguration(
            preset: .claude,
            displayName: "Configured Agent",
            executablePath: "/usr/bin/agent",
            arguments: ["acp"],
            workingDirectory: "/tmp/project",
            permissionPolicy: .ask)
        let connection = ACPClientConnection(
            transport: FakeACPTransport(),
            configuration: configuration,
            diagnostics: VoiceActivationDiagnostics.shared)

        try await connection.applyInitializeResult(.object([
            "protocolVersion": .integer(1),
            "agentCapabilities": .object([
                "loadSession": .bool(true),
                "sessionCapabilities": .object(["resume": .object([:])]),
            ]),
            "agentInfo": .object([
                "name": .string("@agentclientprotocol/claude-agent-acp"),
                "title": .string("Claude Display Title"),
                "version": .string("0.73.0"),
            ]),
            "_meta": .object([
                "steering": .object(["supported": .bool(true)]),
            ]),
        ]))

        #expect(await connection.agentName == "Claude Display Title")
        #expect(await connection.sessionRestorationCapabilities == .init(
            loadSession: true,
            resumeSession: true))
        #expect(await connection.capabilities?.supportsHostOwnedIdleSteering == true)
    }

    private func initializeResult(
        name: String,
        version: String,
        steering: ACPJSONValue? = nil
    ) -> ACPJSONValue {
        var result: [String: ACPJSONValue] = [
            "protocolVersion": .integer(1),
            "agentInfo": .object([
                "name": .string(name),
                "version": .string(version),
            ]),
        ]
        if let steering {
            result["_meta"] = .object(["steering": steering])
        }
        return .object(result)
    }
}
