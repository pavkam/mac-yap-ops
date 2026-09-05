// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import VoiceActivationCore

extension AppModel {
    var textToSpeechBackends: [TextToSpeechBackendDescriptor] {
        textToSpeechBackendRegistry.descriptors
    }

    func availableTextToSpeechVoices(
        for backendID: TextToSpeechBackendID
    ) -> [TextToSpeechVoice] {
        textToSpeechVoicesByBackend[backendID] ?? []
    }

    func isLoadingTextToSpeechVoices(_ backendID: TextToSpeechBackendID) -> Bool {
        loadingTextToSpeechBackendIDs.contains(backendID)
    }

    func loadTextToSpeechVoices(for backendID: TextToSpeechBackendID) async {
        let generation = (textToSpeechVoiceCatalogGenerations[backendID] ?? 0) &+ 1
        textToSpeechVoiceCatalogGenerations[backendID] = generation
        loadingTextToSpeechBackendIDs.insert(backendID)
        textToSpeechVoiceErrors[backendID] = nil
        diagnostics.record(
            category: .settings,
            event: "app_model.tts_catalog_requested",
            fields: [
                "backend": backendID.rawValue,
                "generation": String(generation),
            ])
        do {
            let voices = try await textToSpeechBackendRegistry.availableVoices(
                backendID: backendID,
                credential: textToSpeechCredential(for: backendID))
            try Task.checkCancellation()
            guard textToSpeechVoiceCatalogGenerations[backendID] == generation else { return }
            textToSpeechVoicesByBackend[backendID] = voices
            diagnostics.record(
                category: .settings,
                event: "app_model.tts_catalog_loaded",
                fields: [
                    "backend": backendID.rawValue,
                    "generation": String(generation),
                    "voice_count": String(voices.count),
                ])
        } catch is CancellationError {
            diagnostics.record(
                category: .settings,
                event: "app_model.tts_catalog_cancelled",
                fields: ["backend": backendID.rawValue])
        } catch {
            guard textToSpeechVoiceCatalogGenerations[backendID] == generation else { return }
            textToSpeechVoicesByBackend[backendID] = []
            textToSpeechVoiceErrors[backendID] = error.localizedDescription
            diagnostics.record(
                category: .settings,
                event: "app_model.tts_catalog_failed",
                level: .error,
                fields: [
                    "backend": backendID.rawValue,
                    "error_type": String(describing: type(of: error)),
                ])
        }
        if textToSpeechVoiceCatalogGenerations[backendID] == generation {
            loadingTextToSpeechBackendIDs.remove(backendID)
        }
    }

    func textToSpeechCredential(for backendID: TextToSpeechBackendID) -> String? {
        backendID == .elevenLabs ? elevenLabsAPIKey : nil
    }
}
