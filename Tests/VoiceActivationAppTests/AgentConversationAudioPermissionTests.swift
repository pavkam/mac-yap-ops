// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationApp
@testable import VoiceActivationCore

struct AgentConversationAudioPermissionTests {
    @MainActor @Test
    func extendedPrompt_SpeaksExactFieldsAndOptionsInWireOrder() throws {
        let player = AgentConversationAudioSpy()
        let presenter = makePresenter(player: player)
        let runID = UUID()
        presenter.handle(.started(runID: runID, profile: try profile(), prompt: "Clean up"))

        presenter.handle(.event(
            runID: runID,
            event: .permissionRequested(request(
                turnToken: AgentTurnToken(),
                requestID: .integer(11),
                title: "  Move files?  ",
                description: "Keep them recoverable.",
                toolTitle: "Ignored fallback"))))

        #expect(player.spoken.map(\.text) == [
            "  Move files?  ", "Keep them recoverable.", "Allow once", "Deny",
        ])
        #expect(player.spokenFormats == Array(
            repeating: .agentAuthoredPlainText,
            count: 4))
        #expect(player.spokenPolicies == Array(
            repeating: .agentAuthoredVerbatim,
            count: 4))
    }

    @MainActor @Test
    func standardFallback_SpeaksOnlyExactPortableFields() throws {
        let player = AgentConversationAudioSpy()
        let presenter = makePresenter(player: player)
        let runID = UUID()
        presenter.handle(.started(runID: runID, profile: try profile(), prompt: "Edit"))

        presenter.handle(.event(
            runID: runID,
            event: .permissionRequested(request(
                turnToken: AgentTurnToken(),
                requestID: .string("standard"),
                title: nil,
                description: nil,
                toolTitle: "Edit settings"))))

        #expect(player.spoken.map(\.text) == ["Edit settings", "Allow once", "Deny"])
    }

    @MainActor @Test
    func resolvingExactRequest_RequeuesOnlyRemainingPromptsInArrivalOrder() throws {
        let player = AgentConversationAudioSpy()
        let presenter = makePresenter(player: player)
        let runID = UUID()
        let turn = AgentTurnToken()
        presenter.handle(.started(runID: runID, profile: try profile(), prompt: "Work"))
        presenter.handle(.event(
            runID: runID,
            event: .permissionRequested(request(
                turnToken: turn,
                requestID: .string("first"),
                title: "First?",
                description: nil,
                toolTitle: nil))))
        presenter.handle(.event(
            runID: runID,
            event: .permissionRequested(request(
                turnToken: turn,
                requestID: .string("second"),
                title: "Second?",
                description: nil,
                toolTitle: nil))))
        let spokenBeforeResolution = player.spoken.count

        presenter.permissionResolutionBegan(
            runID: runID,
            turnToken: turn,
            requestID: .string("first"))

        #expect(player.stopSpeakingCount == 2)
        #expect(Array(player.spoken.dropFirst(spokenBeforeResolution).map(\.text)) == [
            "Second?", "Allow once", "Deny",
        ])
        #expect(player.workingStates.last == false)
    }

    @MainActor @Test
    func staleResolution_DoesNotStopOrRemoveCurrentPrompt() throws {
        let player = AgentConversationAudioSpy()
        let presenter = makePresenter(player: player)
        let runID = UUID()
        let turn = AgentTurnToken()
        presenter.handle(.started(runID: runID, profile: try profile(), prompt: "Work"))
        presenter.handle(.event(
            runID: runID,
            event: .permissionRequested(request(
                turnToken: turn,
                requestID: .string("reused"),
                title: "Current?",
                description: nil,
                toolTitle: nil))))
        let stopCount = player.stopSpeakingCount

        presenter.permissionResolutionBegan(
            runID: runID,
            turnToken: AgentTurnToken(),
            requestID: .string("reused"))

        #expect(player.stopSpeakingCount == stopCount)
        #expect(player.workingStates.last == false)
    }

    @MainActor @Test
    func oversizedOrDisabledPrompt_SpeaksNothing() throws {
        let enabledPlayer = AgentConversationAudioSpy()
        let enabledPresenter = makePresenter(player: enabledPlayer)
        let runID = UUID()
        enabledPresenter.handle(.started(
            runID: runID,
            profile: try profile(),
            prompt: "Work"))
        enabledPresenter.handle(.event(
            runID: runID,
            event: .permissionRequested(request(
                turnToken: AgentTurnToken(),
                requestID: .integer(1),
                title: String(repeating: "x", count: 19_999),
                description: nil,
                toolTitle: nil))))

        let disabledPlayer = AgentConversationAudioSpy()
        disabledPlayer.beginsWithSpeechEnabled = false
        let disabledPresenter = makePresenter(player: disabledPlayer)
        let disabledRunID = UUID()
        disabledPresenter.handle(.started(
            runID: disabledRunID,
            profile: try profile(),
            prompt: "Work"))
        disabledPresenter.handle(.event(
            runID: disabledRunID,
            event: .permissionRequested(request(
                turnToken: AgentTurnToken(),
                requestID: .integer(2),
                title: "Speak?",
                description: nil,
                toolTitle: nil))))

        #expect(enabledPlayer.spoken.isEmpty)
        #expect(disabledPlayer.spoken.isEmpty)
    }

    @MainActor @Test
    func cancellation_ClearsPromptSpeechWithoutAppAuthoredAcknowledgement() throws {
        let player = AgentConversationAudioSpy()
        let presenter = makePresenter(player: player)
        let runID = UUID()
        presenter.handle(.started(runID: runID, profile: try profile(), prompt: "Work"))
        presenter.handle(.event(
            runID: runID,
            event: .permissionRequested(request(
                turnToken: AgentTurnToken(),
                requestID: .integer(1),
                title: "Proceed?",
                description: nil,
                toolTitle: nil))))
        let spokenBeforeCancellation = player.spoken.map(\.text)

        presenter.handle(.turnCancellationStarted(runID: runID))
        presenter.handle(.event(
            runID: runID,
            event: .permissionRequested(request(
                turnToken: AgentTurnToken(),
                requestID: .integer(2),
                title: "Late retired prompt?",
                description: nil,
                toolTitle: nil))))
        presenter.handle(.completed(
            runID: runID,
            result: AgentRunResult(stopReason: .cancelled)))

        #expect(player.spoken.map(\.text) == spokenBeforeCancellation)
        #expect(!player.spoken.map(\.text).contains("Stopped."))
    }

    @MainActor @Test
    func pendingNarration_WhenThirtyThirdRequestArrives_SuppressesTheExcess() throws {
        let player = AgentConversationAudioSpy()
        let presenter = makePresenter(player: player)
        let runID = UUID()
        let turn = AgentTurnToken()
        presenter.handle(.started(runID: runID, profile: try profile(), prompt: "Work"))

        for index in 0..<33 {
            presenter.handle(.event(
                runID: runID,
                event: .permissionRequested(request(
                    turnToken: turn,
                    requestID: .integer(Int64(index)),
                    title: "Request \(index)?",
                    description: nil,
                    toolTitle: nil))))
        }

        #expect(player.verbatimBatches.count == 32)
        #expect(player.verbatimBatches.last?.first == "Request 31?")
    }

    @MainActor
    private func makePresenter(
        player: AgentConversationAudioSpy
    ) -> AgentConversationAudioPresenter {
        AgentConversationAudioPresenter(
            player: player,
            readsReplies: { true },
            playsWorkingSound: { true },
            localeID: { "en-US" })
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
