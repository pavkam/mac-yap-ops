// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AVFoundation
import Foundation

struct SystemTextToSpeechBackend: TextToSpeechBackend {
    typealias VoiceLoader = @Sendable () -> [TextToSpeechVoice]

    let descriptor = TextToSpeechBackendDescriptor(
        id: .system,
        displayName: "macOS",
        requiresCredential: false)

    private let voiceLoader: VoiceLoader

    init(voiceLoader: @escaping VoiceLoader = Self.installedVoices) {
        self.voiceLoader = voiceLoader
    }

    func availableVoices(credential: String?) async throws -> [TextToSpeechVoice] {
        var seenIDs: Set<String> = []
        return voiceLoader()
            .filter { !$0.id.isEmpty && seenIDs.insert($0.id).inserted }
            .sorted {
                let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }
                return $0.id < $1.id
            }
    }

    func prepare(
        _ request: TextToSpeechPreparationRequest,
        credential: String?
    ) async throws -> PreparedTextToSpeech {
        .systemVoice(identifier: request.voiceID)
    }

    private static func installedVoices() -> [TextToSpeechVoice] {
        AVSpeechSynthesisVoice.speechVoices().map {
            TextToSpeechVoice(id: $0.identifier, name: $0.name, localeID: $0.language)
        }
    }
}
