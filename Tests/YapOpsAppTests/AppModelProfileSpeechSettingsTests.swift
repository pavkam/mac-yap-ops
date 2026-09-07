// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import YapOpsApp
@testable import YapOpsCore

private struct AppModelTextToSpeechBackendStub: TextToSpeechBackend {
    let descriptor: TextToSpeechBackendDescriptor
    let voices: [TextToSpeechVoice]

    init(id: TextToSpeechBackendID, voices: [TextToSpeechVoice]) {
        descriptor = TextToSpeechBackendDescriptor(
            id: id,
            displayName: id.rawValue,
            requiresCredential: false)
        self.voices = voices
    }

    func availableVoices(credential: String?) async throws -> [TextToSpeechVoice] {
        voices
    }

    func prepare(
        _ request: TextToSpeechPreparationRequest,
        credential: String?
    ) async throws -> PreparedTextToSpeech {
        .systemVoice(identifier: request.voiceID)
    }
}

extension AppModelTests {
    @MainActor @Test func voiceCatalog_UsesTheCommonBackendRegistry() async throws {
        let voices = [
            TextToSpeechVoice(id: "voice-1", name: "Daniel", localeID: "en-GB")
        ]
        let registry = try TextToSpeechBackendRegistry(backends: [
            AppModelTextToSpeechBackendStub(id: .system, voices: voices)
        ])
        let fixture = try Fixture(textToSpeechBackendRegistry: registry)
        await fixture.startForExternalActions()

        await fixture.model.loadTextToSpeechVoices(for: .system)

        #expect(fixture.model.availableTextToSpeechVoices(for: .system) == voices)
        #expect(!fixture.model.isLoadingTextToSpeechVoices(.system))
    }

    @MainActor @Test func saveSettings_PersistsTheGlobalDefaultAndProfileIdentity()
        async throws
    {
        let fixture = try Fixture()
        await fixture.startForExternalActions()
        let defaultVoice = TextToSpeechVoiceSelection(
            backendID: .system,
            voiceID: "com.apple.voice.compact.en-GB.Daniel")
        fixture.model.defaultSpeechVoice = defaultVoice
        fixture.model.wakeProfiles[0].name = "Research assistant"
        fixture.model.wakeProfiles[0].icon = .emoji("🔬")

        #expect(await fixture.model.saveSettings())

        #expect(fixture.preferences.defaultSpeechVoice == defaultVoice)
        #expect(fixture.preferences.wakeProfiles[0].name == "Research assistant")
        #expect(fixture.preferences.wakeProfiles[0].icon == .emoji("🔬"))
    }

    @MainActor @Test
    func saveSettings_WhenProfileUsesElevenLabs_ValidatesTheGlobalCredential() async throws {
        let credentials = AgentSpeechCredentialStoreSpy(apiKey: "saved-key")
        let fixture = try Fixture(agentSpeechCredentialStore: credentials)
        await fixture.startForExternalActions()
        let selection = TextToSpeechVoiceSelection(
            backendID: .elevenLabs,
            voiceID: "profile-voice")
        fixture.model.wakeProfiles[0].speechPreference = .voice(selection)
        fixture.model.elevenLabsAPIKey = "  "

        #expect(!(await fixture.model.saveSettings()))
        #expect(fixture.model.settingsError == "ElevenLabs requires an API key.")
        #expect(credentials.apiKey == "saved-key")

        fixture.model.elevenLabsAPIKey = "global-key"
        #expect(await fixture.model.saveSettings())
        #expect(fixture.preferences.wakeProfiles[0].speechPreference == .voice(selection))
        #expect(credentials.apiKey == "global-key")
    }
}
