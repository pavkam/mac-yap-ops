// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import YapOpsCore

struct AgentHarnessDraft: Equatable {
    var preset: AgentHarnessPreset
    var displayName: String { preset.displayName }
    var executablePath: String
    var argumentDrafts: ArgumentDraftCollection
    var workingDirectory: String
    var permissionPolicy: AgentPermissionPolicy
    var systemPrompt: String

    var arguments: [String] {
        get { argumentDrafts.values }
        set { argumentDrafts.replace(with: newValue) }
    }

    init(
        preset: AgentHarnessPreset,
        executablePath: String,
        arguments: [String],
        workingDirectory: String,
        permissionPolicy: AgentPermissionPolicy,
        systemPrompt: String = "")
    {
        self.preset = preset
        self.executablePath = executablePath
        argumentDrafts = ArgumentDraftCollection(values: arguments)
        self.workingDirectory = workingDirectory
        self.permissionPolicy = permissionPolicy
        self.systemPrompt = systemPrompt
    }

    init(configuration: AgentHarnessConfiguration) {
        preset = configuration.preset
        executablePath = configuration.executablePath
        argumentDrafts = ArgumentDraftCollection(values: configuration.arguments)
        workingDirectory = configuration.workingDirectory
        permissionPolicy = configuration.permissionPolicy
        systemPrompt = configuration.systemPrompt
    }

    static func empty(workingDirectory: String) -> AgentHarnessDraft {
        AgentHarnessDraft(
            preset: .custom,
            executablePath: "",
            arguments: [],
            workingDirectory: workingDirectory,
            permissionPolicy: .ask,
            systemPrompt: "")
    }

    mutating func selectPreset(
        _ selectedPreset: AgentHarnessPreset,
        locator: AgentExecutableLocator = AgentExecutableLocator())
    {
        guard selectedPreset != preset else { return }
        preset = selectedPreset

        switch selectedPreset {
        case .cursor:
            executablePath = ""
            arguments = ["acp"]
        case .codex:
            executablePath = ""
            arguments = ["-y", "@agentclientprotocol/codex-acp@1.8.0"]
        case .claude:
            executablePath = ""
            arguments = ["-y", "@agentclientprotocol/claude-agent-acp@0.73.0"]
        case .custom:
            break
        }

        _ = detectExecutable(locator: locator)
    }

    @discardableResult
    mutating func detectExecutable(
        locator: AgentExecutableLocator = AgentExecutableLocator()) -> AgentExecutableLocation?
    {
        let executable: String
        switch preset {
        case .cursor:
            executable = "cursor-agent"
        case .codex, .claude:
            executable = "npx"
        case .custom:
            executable = executablePath
        }

        guard let location = locator.resolve(executable: executable) else { return nil }
        executablePath = location.path
        return location
    }

    mutating func selectDefaultPresetIfAvailable(
        locator: AgentExecutableLocator = AgentExecutableLocator())
    {
        guard preset == .custom,
              executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              arguments.isEmpty
        else {
            return
        }

        for candidate in [AgentHarnessPreset.cursor, .codex, .claude] {
            let executable = candidate == .cursor ? "cursor-agent" : "npx"
            guard locator.locate(executable: executable) != nil else { continue }
            selectPreset(candidate, locator: locator)
            return
        }
    }

    func validatedConfiguration() throws -> AgentHarnessConfiguration {
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

extension AgentHarnessPreset {
    var displayName: String {
        switch self {
        case .cursor: "Cursor"
        case .codex: "Codex"
        case .claude: "Claude"
        case .custom: "Custom"
        }
    }
}
