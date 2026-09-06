// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationApp
@testable import VoiceActivationCore

@Suite(.timeLimit(.minutes(1)))
struct AgentConversationAudioResponseChannelTests {
    @MainActor @Test
    func spokenDelta_IsVisibleButDoesNotSpeakBeforeReady() throws {
        let (presenter, player, runID) = try makePresenter()

        presenter.handle(.event(
            runID: runID,
            event: .agentSpokenMessageDelta(messageID: "answer", text: "Say this")))

        #expect(player.spoken.isEmpty)
    }

    @MainActor @Test
    func spokenReady_NarratesOneVerbatimUnit() throws {
        let (presenter, player, runID) = try makePresenter()
        let text = "  Say **this** exactly.\nKeep spacing.  "

        presenter.handle(.event(
            runID: runID,
            event: .agentSpokenNarrationReady(messageID: "answer", text: text)))

        #expect(player.spoken.map(\.text) == [text])
        #expect(player.spokenFormats == [.agentAuthoredPlainText])
        #expect(player.spokenPolicies == [.agentAuthoredVerbatim])
    }

    @MainActor @Test
    func displayDelta_DoesNotNarrate() throws {
        let (presenter, player, runID) = try makePresenter()

        presenter.handle(.event(
            runID: runID,
            event: .agentDisplayMessageDelta(messageID: "answer", text: "**Visual only.**")))

        #expect(player.spoken.isEmpty)
    }

    @MainActor @Test
    func legacyDelta_RetainsMarkdownNarration() throws {
        let (presenter, player, runID) = try makePresenter()

        presenter.handle(.event(
            runID: runID,
            event: .agentMessageDelta(messageID: "answer", text: "**Legacy done.**")))
        presenter.handle(.turnCompleted(
            runID: runID,
            result: AgentRunResult(stopReason: .endTurn)))

        #expect(player.spoken.map(\.text) == ["Legacy done."])
        #expect(player.spokenFormats == [.legacyMarkdown])
        #expect(player.spokenPolicies == [.legacyNormalized])
    }

    @MainActor @Test
    func oversizeOrDroppedSpokenUnit_IsRejectedWhole() throws {
        let (presenter, player, runID) = try makePresenter()

        presenter.handle(.event(
            runID: runID,
            event: .agentSpokenNarrationSuppressed(
                messageID: "oversized",
                reason: .oversized)))
        presenter.handle(.event(
            runID: runID,
            event: .agentSpokenNarrationSuppressed(
                messageID: "dropped",
                reason: .incompleteDelivery)))

        #expect(player.spoken.isEmpty)
    }

    @MainActor @Test
    func restoredSpokenUnit_RemainsSilent() throws {
        let (presenter, player, runID) = try makePresenter()
        let token = AgentRestorationToken()

        presenter.handle(.historyEvent(
            runID: runID,
            token: token,
            event: .agentSpokenNarrationReady(messageID: "history", text: "Old news")))

        #expect(player.spoken.isEmpty)
    }

    @MainActor @Test
    func backgroundLiveSpokenUnit_NarratesOnceWithoutStartingWorkingPulse() throws {
        let (presenter, player, runID) = try makePresenter()
        presenter.handle(.turnCompleted(
            runID: runID,
            result: AgentRunResult(stopReason: .endTurn)))
        let workingStates = player.workingStates

        presenter.handle(.event(
            runID: runID,
            event: .agentSpokenMessageDelta(messageID: "background", text: "Task finished.")))
        presenter.handle(.event(
            runID: runID,
            event: .agentSpokenNarrationReady(messageID: "background", text: "Task finished.")))

        #expect(player.spoken.map(\.text) == ["Task finished."])
        #expect(player.workingStates == workingStates)
    }

    @MainActor @Test
    func cancelledRun_RejectsLateSpokenDelta() throws {
        let (presenter, player, runID) = try makePresenter()
        presenter.handle(.turnCancellationStarted(runID: runID))
        presenter.handle(.turnCompleted(
            runID: runID,
            result: AgentRunResult(stopReason: .endTurn)))

        presenter.handle(.event(
            runID: runID,
            event: .agentSpokenNarrationReady(messageID: "late", text: "Too late.")))

        #expect(player.spoken.isEmpty)
    }

    @MainActor
    private func makePresenter() throws -> (
        AgentConversationAudioPresenter,
        AgentConversationAudioSpy,
        UUID
    ) {
        let player = AgentConversationAudioSpy()
        let presenter = AgentConversationAudioPresenter(
            player: player,
            readsReplies: { true },
            playsWorkingSound: { true },
            localeID: { "en-US" })
        let runID = UUID()
        presenter.handle(.started(
            runID: runID,
            profile: try profile(),
            prompt: "Question"))
        return (presenter, player, runID)
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
