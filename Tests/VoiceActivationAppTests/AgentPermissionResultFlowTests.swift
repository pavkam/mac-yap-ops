// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationApp
@testable import VoiceActivationCore

struct AgentPermissionResultFlowTests {
    @MainActor @Test
    func selectedPermission_ResultComesOnlyFromFollowingAgentMessage() throws {
        let player = AgentConversationAudioSpy()
        let presenter = AgentConversationAudioPresenter(
            player: player,
            readsReplies: { true },
            playsWorkingSound: { true },
            localeID: { "en-US" })
        let runID = UUID()
        let request = permissionRequest()
        presenter.handle(.started(runID: runID, profile: try profile(), prompt: "Clean"))
        presenter.handle(.event(runID: runID, event: .permissionRequested(request)))
        presenter.permissionResolutionBegan(
            runID: runID,
            turnToken: request.turnToken,
            requestID: request.requestID)
        let speechBeforeToolCompletion = player.spoken.map(\.text)

        presenter.handle(.event(
            runID: runID,
            event: .toolCallUpdate(AgentToolCallUpdate(
                id: "trash",
                status: .completed))))
        #expect(player.spoken.map(\.text) == speechBeforeToolCompletion)

        presenter.handle(.event(
            runID: runID,
            event: .agentSpokenNarrationReady(
                messageID: "result",
                text: "Done — 43 items are in Trash.")))

        #expect(player.spoken.map(\.text).last == "Done — 43 items are in Trash.")
        #expect(player.spokenPolicies.last == .agentAuthoredVerbatim)
    }

    @MainActor @Test
    func cancelledPermission_EmitsNoAppAuthoredResultProse() throws {
        let player = AgentConversationAudioSpy()
        let presenter = AgentConversationAudioPresenter(
            player: player,
            readsReplies: { true },
            playsWorkingSound: { true },
            localeID: { "en-US" })
        let runID = UUID()
        presenter.handle(.started(runID: runID, profile: try profile(), prompt: "Clean"))
        presenter.handle(.event(
            runID: runID,
            event: .permissionRequested(permissionRequest())))
        let confirmationSpeech = player.spoken.map(\.text)

        presenter.handle(.turnCancellationStarted(runID: runID))
        presenter.handle(.completed(
            runID: runID,
            result: AgentRunResult(stopReason: .cancelled)))

        #expect(player.spoken.map(\.text) == confirmationSpeech)
        #expect(!player.spoken.map(\.text).contains("Stopped."))
    }

    private func permissionRequest() -> AgentPermissionRequest {
        AgentPermissionRequest(
            turnToken: AgentTurnToken(),
            requestID: .string("trash-permission"),
            toolCall: AgentToolCallUpdate(id: "trash", title: "Move downloads"),
            options: [
                AgentPermissionOption(id: "once", label: "Allow once", kind: .allowOnce),
                AgentPermissionOption(id: "deny", label: "Deny", kind: .rejectOnce),
            ],
            presentationText: AgentPermissionPresentationText(
                title: "Move 43 old downloads to Trash?",
                description: nil))
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
