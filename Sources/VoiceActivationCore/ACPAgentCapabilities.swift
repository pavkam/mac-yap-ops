// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

struct ACPAgentCapabilities: Equatable, Sendable {
    let agentName: String
    let agentVersion: String
    let supportsHostOwnedIdleSteering: Bool

    static func decode(
        initializeResult: ACPJSONValue,
        preset: AgentHarnessPreset
    ) throws -> Self {
        let result = try requiredObject(initializeResult, named: "initialize result")
        let agentInfo = try requiredObject(result["agentInfo"], named: "agentInfo")
        let agentName = try requiredString(agentInfo["name"], named: "agentInfo.name")
        let agentVersion = try requiredString(
            agentInfo["version"],
            named: "agentInfo.version")
        guard !agentName.isEmpty,
              !agentVersion.isEmpty,
              agentName.utf8.count <= ACPEventDecoder.maximumOpaqueIdentifierBytes,
              agentVersion.utf8.count <= ACPEventDecoder.maximumOpaqueIdentifierBytes
        else {
            throw ACPClientError.malformedResponse("Invalid agent capability identity.")
        }

        let advertisesSteering = try steeringSupport(from: result["_meta"])
        return Self(
            agentName: agentName,
            agentVersion: agentVersion,
            supportsHostOwnedIdleSteering:
                preset == .claude
                && agentName == "@agentclientprotocol/claude-agent-acp"
                && agentVersion == "0.73.0"
                && advertisesSteering)
    }

    private static func steeringSupport(from metadataValue: ACPJSONValue?) throws -> Bool {
        guard let metadataValue, metadataValue != .null else {
            return false
        }
        let metadata = try requiredObject(metadataValue, named: "initialize _meta")
        guard let steeringValue = metadata["steering"], steeringValue != .null else {
            return false
        }
        let steering = try requiredObject(steeringValue, named: "initialize _meta.steering")
        switch steering["supported"] {
        case nil, .null:
            return false
        case .bool(let supported):
            return supported
        default:
            throw ACPClientError.malformedResponse(
                "Invalid initialize _meta.steering.supported.")
        }
    }
}
