// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import VoiceActivationApp

private struct TextToSpeechCatalogStub: ElevenLabsVoiceCatalogLoading {
    let values: [ElevenLabsVoice]

    func voices(apiKey: String) async throws -> [ElevenLabsVoice] {
        values
    }
}

private actor TextToSpeechSynthesizerSpy: ElevenLabsSpeechSynthesizing {
    private(set) var text: String?
    private(set) var apiKey: String?
    private(set) var voiceID: String?

    func audio(text: String, apiKey: String, voiceID: String) async throws -> Data {
        self.text = text
        self.apiKey = apiKey
        self.voiceID = voiceID
        return Data("audio".utf8)
    }
}

@Suite
struct TextToSpeechBackendTests {
    @Test func systemCatalog_DeduplicatesAndSortsInstalledVoiceIdentifiers() async throws {
        let backend = SystemTextToSpeechBackend {
            [
                TextToSpeechVoice(id: "z", name: "Zoe", localeID: "en-US"),
                TextToSpeechVoice(id: "a", name: "Alex", localeID: "en-GB"),
                TextToSpeechVoice(id: "a", name: "Duplicate", localeID: "en-GB"),
            ]
        }

        let voices = try await backend.availableVoices(credential: "ignored")

        #expect(voices.map(\.id) == ["a", "z"])
    }

    @Test func elevenLabsCatalog_MapsProviderVoicesToTheCommonCatalog() async throws {
        let backend = ElevenLabsTextToSpeechBackend(
            catalog: TextToSpeechCatalogStub(values: [
                ElevenLabsVoice(
                    id: "voice-1",
                    name: "Narrator",
                    category: "premade",
                    description: nil)
            ]))

        let voices = try await backend.availableVoices(credential: " global-key ")

        #expect(voices == [
            TextToSpeechVoice(id: "voice-1", name: "Narrator", localeID: nil)
        ])
    }

    @Test func elevenLabsPreparation_UsesTheCommonRequestAndReturnsAudio() async throws {
        let synthesizer = TextToSpeechSynthesizerSpy()
        let backend = ElevenLabsTextToSpeechBackend(
            catalog: TextToSpeechCatalogStub(values: []),
            synthesizer: synthesizer)

        let preparation = try await backend.prepare(
            TextToSpeechPreparationRequest(
                text: "Read this.",
                localeID: "en-GB",
                voiceID: "voice-2"),
            credential: "global-key")

        #expect(preparation == .audio(Data("audio".utf8)))
        #expect(await synthesizer.text == "Read this.")
        #expect(await synthesizer.apiKey == "global-key")
        #expect(await synthesizer.voiceID == "voice-2")
    }

    @Test func elevenLabsPreparation_RejectsMissingGlobalCredential() async {
        let backend = ElevenLabsTextToSpeechBackend(
            catalog: TextToSpeechCatalogStub(values: []))

        await #expect(throws: TextToSpeechBackendError.credentialRequired(.elevenLabs)) {
            _ = try await backend.prepare(
                TextToSpeechPreparationRequest(
                    text: "Read this.",
                    localeID: "en-GB",
                    voiceID: "voice-2"),
                credential: "  ")
        }
    }
}
