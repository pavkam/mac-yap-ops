// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import VoiceActivationApp
@testable import VoiceActivationCore

@MainActor
private final class AgentSpeechConfigurationBox {
    var value: AgentSpeechConfiguration

    init(_ value: AgentSpeechConfiguration) {
        self.value = value
    }
}

extension AgentConversationAudioPresenterTests {
    @MainActor @Test
    func orchestrator_WhenSettingsChange_KeepsTheConversationSpeechSnapshot() throws {
        let first = AgentSpeechConfiguration(
            selection: TextToSpeechVoiceSelection(
                backendID: .system,
                voiceID: "voice-one"),
            credential: nil)
        let second = AgentSpeechConfiguration(
            selection: TextToSpeechVoiceSelection(
                backendID: .elevenLabs,
                voiceID: "voice-two"),
            credential: "global-key")
        let current = AgentSpeechConfigurationBox(first)
        let queue = AgentSpeechQueueSpy()
        let player = AgentConversationAudioOrchestrator(
            speechConfiguration: { _, _ in current.value },
            speechQueue: queue,
            activityLoop: AgentActivitySoundLoopSpy())

        #expect(player.beginConversation(
            profile: try agentProfile(),
            readsInheritedReplies: true))
        player.speak("First.", localeID: "en-GB")
        current.value = second
        player.speak("Follow-up.", localeID: "en-GB")

        #expect(queue.requests.map(\.configuration) == [first, first])
    }

    @MainActor @Test
    func lifecycle_WhenFollowUpArrives_DoesNotSelectTheProfileAgain() throws {
        let player = AgentConversationAudioSpy()
        let presenter = AgentConversationAudioPresenter(
            player: player,
            readsReplies: { true },
            playsWorkingSound: { true },
            localeID: { "en-GB" })
        let runID = UUID()
        let profile = try agentProfile()

        presenter.handle(.started(runID: runID, profile: profile, prompt: "First"))
        presenter.handle(.followUpSubmitted(runID: runID, prompt: "Again"))

        #expect(player.begunProfiles == [profile])
    }

    @MainActor @Test
    func speechSettings_ExplicitProfileVoiceUsesItsBackendGlobalCredential() {
        let state = AgentSpeechSettingsState(
            provider: .system,
            elevenLabsAPIKey: "global-key",
            elevenLabsVoiceID: "global-voice")
        let selection = TextToSpeechVoiceSelection(
            backendID: .elevenLabs,
            voiceID: "profile-voice")

        let resolved = state.configuration(
            for: .voice(selection),
            readsInheritedReplies: false)

        #expect(resolved == AgentSpeechConfiguration(
            selection: selection,
            credential: "global-key"))
    }

    @MainActor @Test func speechSettings_DisabledOrGloballyMutedInheritanceDoesNotSpeak() {
        let state = AgentSpeechSettingsState(
            provider: .system,
            elevenLabsAPIKey: "global-key",
            elevenLabsVoiceID: "global-voice")

        #expect(state.configuration(
            for: .disabled,
            readsInheritedReplies: true) == nil)
        #expect(state.configuration(
            for: .inherit,
            readsInheritedReplies: false) == nil)
    }
}
