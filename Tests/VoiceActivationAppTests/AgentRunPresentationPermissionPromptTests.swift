// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationApp
@testable import VoiceActivationCore

struct AgentRunPresentationPermissionPromptTests {
    @MainActor @Test
    func extendedPrompt_ShowsExactTitleDescriptionAndOrderedOptions() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        presentation.start(runID: runID, profile: try profile(), prompt: "Clean up")

        presentation.receive(
            runID: runID,
            event: .permissionRequested(request(
                turnToken: AgentTurnToken(),
                requestID: .integer(7),
                title: "  Move 43 old downloads to Trash?  ",
                description: "This keeps them recoverable.",
                toolTitle: "Move downloads")))

        let permission = try #require(presentation.snapshot?.permissions.first)
        #expect(permission.promptTitle == "  Move 43 old downloads to Trash?  ")
        #expect(permission.promptDescription == "This keeps them recoverable.")
        #expect(permission.options.map(\.label) == ["Allow once", "Deny"])
        #expect(permission.options.map(\.id) == ["once", "deny"])
    }

    @MainActor @Test
    func standardFallback_PreservesMissingTitleForVisualOnlyFallback() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        presentation.start(runID: runID, profile: try profile(), prompt: "Work")

        presentation.receive(
            runID: runID,
            event: .permissionRequested(request(
                turnToken: AgentTurnToken(),
                requestID: .string("permission"),
                title: nil,
                description: nil,
                toolTitle: nil)))

        let permission = try #require(presentation.snapshot?.permissions.first)
        #expect(permission.promptTitle == nil)
        #expect(permission.promptDescription == nil)
    }

    @MainActor @Test
    func duplicateAndStaleIdentities_DoNotDuplicateOrRestoreCards() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        let turn = AgentTurnToken()
        let first = request(
            turnToken: turn,
            requestID: .string("reused"),
            title: "First title",
            description: nil,
            toolTitle: "Fallback")
        presentation.start(runID: runID, profile: try profile(), prompt: "Work")

        presentation.receive(runID: runID, event: .permissionRequested(first))
        presentation.receive(runID: runID, event: .permissionRequested(first))
        presentation.receive(
            runID: runID,
            event: .permissionRequested(request(
                turnToken: AgentTurnToken(),
                requestID: .string("reused"),
                title: "Second turn",
                description: nil,
                toolTitle: "Fallback")))
        presentation.receive(runID: UUID(), event: .permissionRequested(first))

        #expect(presentation.snapshot?.permissions.map(\.promptTitle) == [
            "First title", "Second turn",
        ])
    }

    private func request(
        turnToken: AgentTurnToken,
        requestID: ACPRequestID,
        title: String?,
        description: String?,
        toolTitle: String?
    ) -> AgentPermissionRequest {
        AgentPermissionRequest(
            turnToken: turnToken,
            requestID: requestID,
            toolCall: AgentToolCallUpdate(id: "tool", title: toolTitle),
            options: [
                AgentPermissionOption(id: "once", label: "Allow once", kind: .allowOnce),
                AgentPermissionOption(id: "deny", label: "Deny", kind: .rejectOnce),
            ],
            presentationText: title.map {
                AgentPermissionPresentationText(title: $0, description: description)
            })
    }

    private func profile() throws -> WakeProfile {
        try WakeProfile(
            wakePhrase: "agent",
            action: .agent(AgentHarnessConfiguration(
                preset: .codex,
                displayName: "Codex",
                executablePath: "/usr/bin/true",
                arguments: [],
                workingDirectory: "/tmp",
                permissionPolicy: .ask)),
            accent: .purple)
    }
}
