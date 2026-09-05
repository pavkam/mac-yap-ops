// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import VoiceActivationCore

enum TextToSpeechBackendRegistryError: Error, Equatable, LocalizedError {
    case duplicateBackend(TextToSpeechBackendID)
    case unknownBackend(TextToSpeechBackendID)

    var errorDescription: String? {
        switch self {
        case .duplicateBackend(let id):
            "The text-to-speech backend ID \(id.rawValue) is registered more than once."
        case .unknownBackend(let id):
            "The text-to-speech backend \(id.rawValue) is not available."
        }
    }
}

struct TextToSpeechBackendRegistry: Sendable {
    let descriptors: [TextToSpeechBackendDescriptor]

    private let backends: [TextToSpeechBackendID: any TextToSpeechBackend]

    init(backends: [any TextToSpeechBackend]) throws {
        var indexed: [TextToSpeechBackendID: any TextToSpeechBackend] = [:]
        for backend in backends {
            let id = backend.descriptor.id
            guard indexed.updateValue(backend, forKey: id) == nil else {
                throw TextToSpeechBackendRegistryError.duplicateBackend(id)
            }
        }
        self.backends = indexed
        descriptors = indexed.values
            .map(\.descriptor)
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    static func live(
        elevenLabsSynthesizer: any ElevenLabsSpeechSynthesizing = ElevenLabsSpeechClient(),
        elevenLabsCatalog: any ElevenLabsVoiceCatalogLoading = ElevenLabsVoiceCatalogClient()
    ) -> Self {
        Self(
            uniqueBackends: [
                SystemTextToSpeechBackend(),
                ElevenLabsTextToSpeechBackend(
                    catalog: elevenLabsCatalog,
                    synthesizer: elevenLabsSynthesizer),
            ])
    }

    func availableVoices(
        backendID: TextToSpeechBackendID,
        credential: String?
    ) async throws -> [TextToSpeechVoice] {
        try await backend(id: backendID).availableVoices(credential: credential)
    }

    func prepare(
        _ request: TextToSpeechPreparationRequest,
        backendID: TextToSpeechBackendID,
        credential: String?
    ) async throws -> PreparedTextToSpeech {
        try await backend(id: backendID).prepare(request, credential: credential)
    }

    private func backend(id: TextToSpeechBackendID) throws -> any TextToSpeechBackend {
        guard let backend = backends[id] else {
            throw TextToSpeechBackendRegistryError.unknownBackend(id)
        }
        return backend
    }

    private init(uniqueBackends: [any TextToSpeechBackend]) {
        backends = Dictionary(
            uniqueKeysWithValues: uniqueBackends.map { ($0.descriptor.id, $0) })
        descriptors = uniqueBackends
            .map(\.descriptor)
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }
}
