// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import VoiceActivationCore

@MainActor
final class AgentSpeechSettingsState {
    private(set) var configuration: AgentSpeechConfiguration
    private var elevenLabsAPIKey: String

    init(
        provider: AgentSpeechProvider,
        elevenLabsAPIKey: String,
        elevenLabsVoiceID: String)
    {
        self.elevenLabsAPIKey = elevenLabsAPIKey
        configuration = AgentSpeechConfiguration(
            provider: provider,
            elevenLabsAPIKey: elevenLabsAPIKey,
            elevenLabsVoiceID: elevenLabsVoiceID)
    }

    func update(
        provider: AgentSpeechProvider,
        elevenLabsAPIKey: String,
        elevenLabsVoiceID: String)
    {
        self.elevenLabsAPIKey = elevenLabsAPIKey
        configuration = AgentSpeechConfiguration(
            provider: provider,
            elevenLabsAPIKey: elevenLabsAPIKey,
            elevenLabsVoiceID: elevenLabsVoiceID)
    }

    func configuration(
        for preference: ProfileSpeechPreference,
        readsInheritedReplies: Bool
    ) -> AgentSpeechConfiguration? {
        let selection: TextToSpeechVoiceSelection
        switch preference {
        case .inherit:
            guard readsInheritedReplies else { return nil }
            selection = configuration.selection
        case .disabled:
            return nil
        case .voice(let selectedVoice):
            selection = selectedVoice
        }
        return AgentSpeechConfiguration(
            selection: selection,
            credential: credential(for: selection.backendID))
    }

    private func credential(for backendID: TextToSpeechBackendID) -> String? {
        backendID == .elevenLabs ? elevenLabsAPIKey : nil
    }
}
