// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

struct ElevenLabsTextToSpeechBackend: TextToSpeechBackend {
    let descriptor = TextToSpeechBackendDescriptor(
        id: .elevenLabs,
        displayName: "ElevenLabs",
        requiresCredential: true)

    private let catalog: any ElevenLabsVoiceCatalogLoading
    private let synthesizer: any ElevenLabsSpeechSynthesizing

    init(
        catalog: any ElevenLabsVoiceCatalogLoading = ElevenLabsVoiceCatalogClient(),
        synthesizer: any ElevenLabsSpeechSynthesizing = ElevenLabsSpeechClient()
    ) {
        self.catalog = catalog
        self.synthesizer = synthesizer
    }

    func availableVoices(credential: String?) async throws -> [TextToSpeechVoice] {
        let credential = try requiredCredential(credential)
        return try await catalog.voices(apiKey: credential).map {
            TextToSpeechVoice(id: $0.id, name: $0.name, localeID: nil)
        }
    }

    func prepare(
        _ request: TextToSpeechPreparationRequest,
        credential: String?
    ) async throws -> PreparedTextToSpeech {
        let credential = try requiredCredential(credential)
        guard let voiceID = request.voiceID?.trimmingCharacters(in: .whitespacesAndNewlines),
            !voiceID.isEmpty
        else {
            throw TextToSpeechBackendError.voiceRequired(.elevenLabs)
        }
        let data = try await synthesizer.audio(
            text: request.text,
            apiKey: credential,
            voiceID: voiceID)
        return .audio(data)
    }

    private func requiredCredential(_ credential: String?) throws -> String {
        let credential = credential?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !credential.isEmpty else {
            throw TextToSpeechBackendError.credentialRequired(.elevenLabs)
        }
        return credential
    }
}
