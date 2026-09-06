// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Testing
@testable import VoiceActivationCore

@Suite struct AgentProviderFingerprintTests {
    @Test func make_WhenConfigurationIsCanonical_ReturnsDeterministicDigest() throws {
        let configuration = try fixtureConfiguration(
            arguments: ["--mode", "", "fast"],
            workingDirectory: "/Users/alex/Project",
            systemPrompt: "Be concise.")

        #expect(
            AgentProviderFingerprint.make(configuration: configuration)
                == "4aaaa543242ae3567084d9b150fadcc2376d72a96f9c19373d87fe14f4a45dc2")
    }

    @Test func make_WhenEachSessionDefiningFieldChanges_ChangesFingerprint() throws {
        let baseline = AgentProviderFingerprint.make(configuration: try fixtureConfiguration())

        #expect(AgentProviderFingerprint.make(configuration: try fixtureConfiguration(
            preset: .claude)) != baseline)
        #expect(AgentProviderFingerprint.make(configuration: try fixtureConfiguration(
            executablePath: "/opt/local/bin/codex-acp")) != baseline)
        #expect(AgentProviderFingerprint.make(configuration: try fixtureConfiguration(
            arguments: ["--mode", "other"])) != baseline)
        #expect(AgentProviderFingerprint.make(configuration: try fixtureConfiguration(
            workingDirectory: "/tmp/other")) != baseline)
        #expect(AgentProviderFingerprint.make(configuration: try fixtureConfiguration(
            systemPrompt: "Answer carefully.")) != baseline)
    }

    @Test func make_WhenOnlyDisplayOrPermissionChanges_PreservesFingerprint() throws {
        let baseline = AgentProviderFingerprint.make(configuration: try fixtureConfiguration())

        #expect(AgentProviderFingerprint.make(configuration: try fixtureConfiguration(
            displayName: "Renamed")) == baseline)
        #expect(AgentProviderFingerprint.make(configuration: try fixtureConfiguration(
            permissionPolicy: .rejectAlways)) == baseline)
    }

    @Test func make_WhenArgumentsCouldConcatenateToSameBytes_RemainsUnambiguous() throws {
        let first = AgentProviderFingerprint.make(configuration: try fixtureConfiguration(
            arguments: ["ab", "c"]))
        let second = AgentProviderFingerprint.make(configuration: try fixtureConfiguration(
            arguments: ["a", "bc"]))

        #expect(first != second)
    }

    @Test func make_WhenArgumentOrderOrEmptyValuesDiffer_ChangesFingerprint() throws {
        let ordered = AgentProviderFingerprint.make(configuration: try fixtureConfiguration(
            arguments: ["one", "", "two"]))

        #expect(AgentProviderFingerprint.make(configuration: try fixtureConfiguration(
            arguments: ["two", "", "one"])) != ordered)
        #expect(AgentProviderFingerprint.make(configuration: try fixtureConfiguration(
            arguments: ["one", "two"])) != ordered)
        #expect(AgentProviderFingerprint.make(configuration: try fixtureConfiguration(
            arguments: ["one", "two", ""])) != ordered)
        #expect(AgentProviderFingerprint.make(configuration: try fixtureConfiguration(
            arguments: [])) != AgentProviderFingerprint.make(
                configuration: try fixtureConfiguration(arguments: [""])))
    }

    private func fixtureConfiguration(
        preset: AgentHarnessPreset = .codex,
        displayName: String = "Codex ACP",
        executablePath: String = "/usr/local/bin/codex-acp",
        arguments: [String] = ["--mode", "fast"],
        workingDirectory: String = "/Users/alex/Development",
        permissionPolicy: AgentPermissionPolicy = .ask,
        systemPrompt: String = "Be useful."
    ) throws -> AgentHarnessConfiguration {
        try AgentHarnessConfiguration(
            preset: preset,
            displayName: displayName,
            executablePath: executablePath,
            arguments: arguments,
            workingDirectory: workingDirectory,
            permissionPolicy: permissionPolicy,
            systemPrompt: systemPrompt)
    }
}
