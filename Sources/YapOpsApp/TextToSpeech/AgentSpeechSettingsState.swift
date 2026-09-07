// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import YapOpsCore

@MainActor
final class AgentSpeechSettingsState {
    private(set) var configuration: AgentSpeechConfiguration
    private var elevenLabsAPIKey: String

    init(
        provider: AgentSpeechProvider,
        elevenLabsAPIKey: String,
        elevenLabsVoiceID: String)
    {
        let backendID: TextToSpeechBackendID = provider == .system ? .system : .elevenLabs
        self.elevenLabsAPIKey = elevenLabsAPIKey
        configuration = AgentSpeechConfiguration(
            selection: TextToSpeechVoiceSelection(
                backendID: backendID,
                voiceID: provider == .system ? nil : elevenLabsVoiceID),
            credential: provider == .elevenLabs ? elevenLabsAPIKey : nil)
    }

    init(
        defaultSelection: TextToSpeechVoiceSelection,
        elevenLabsAPIKey: String
    ) {
        self.elevenLabsAPIKey = elevenLabsAPIKey
        configuration = AgentSpeechConfiguration(
            selection: defaultSelection,
            credential: defaultSelection.backendID == .elevenLabs
                ? elevenLabsAPIKey
                : nil)
    }

    func update(
        provider: AgentSpeechProvider,
        elevenLabsAPIKey: String,
        elevenLabsVoiceID: String)
    {
        let backendID: TextToSpeechBackendID = provider == .system ? .system : .elevenLabs
        update(
            defaultSelection: TextToSpeechVoiceSelection(
                backendID: backendID,
                voiceID: provider == .system ? nil : elevenLabsVoiceID),
            elevenLabsAPIKey: elevenLabsAPIKey)
    }

    func update(
        defaultSelection: TextToSpeechVoiceSelection,
        elevenLabsAPIKey: String
    ) {
        self.elevenLabsAPIKey = elevenLabsAPIKey
        configuration = AgentSpeechConfiguration(
            selection: defaultSelection,
            credential: credential(for: defaultSelection.backendID))
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
