// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

struct ACPAgentCapabilities: Equatable, Sendable {
    let agentName: String
    let agentVersion: String
    let supportsHostOwnedIdleSteering: Bool
    let supportsAIRAsyncTasks: Bool

    static func decode(
        initializeResult: ACPJSONValue,
        preset: AgentHarnessPreset,
        clientAdvertisesAIRAsyncTasks: Bool = true
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
        let advertisesAIRAsyncTasks = try airAsyncTasksSupport(from: result["_meta"])
        let isPinnedClaude = preset == .claude
            && agentName == "@agentclientprotocol/claude-agent-acp"
            && agentVersion == "0.73.0"
        return Self(
            agentName: agentName,
            agentVersion: agentVersion,
            supportsHostOwnedIdleSteering:
                isPinnedClaude && advertisesSteering,
            supportsAIRAsyncTasks:
                isPinnedClaude
                && clientAdvertisesAIRAsyncTasks
                && advertisesAIRAsyncTasks)
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

    private static func airAsyncTasksSupport(from metadataValue: ACPJSONValue?) throws -> Bool {
        guard let metadataValue, metadataValue != .null else { return false }
        let metadata = try requiredObject(metadataValue, named: "initialize _meta")
        guard let jetBrainsValue = metadata["jetbrains"], jetBrainsValue != .null else {
            return false
        }
        let jetBrains = try requiredObject(
            jetBrainsValue,
            named: "initialize _meta.jetbrains")
        guard let airValue = jetBrains["air"], airValue != .null else { return false }
        let air = try requiredObject(airValue, named: "initialize _meta.jetbrains.air")
        guard let versionValue = air["version"], versionValue != .null,
              let capabilitiesValue = air["capabilities"], capabilitiesValue != .null
        else {
            return false
        }
        let version = try requiredInteger(versionValue, named: "AIR version")
        guard version == 1 else { return false }
        let capabilities = try requiredArray(capabilitiesValue, named: "AIR capabilities")
        guard capabilities.count <= 32 else {
            throw ACPClientError.malformedResponse("Invalid AIR capabilities.")
        }
        let names = try capabilities.map { value in
            let name = try requiredString(value, named: "AIR capability")
            guard name.utf8.count <= 128 else {
                throw ACPClientError.malformedResponse("Invalid AIR capability.")
            }
            return name
        }
        return names.contains("asyncTasks")
    }
}
