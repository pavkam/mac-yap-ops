// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import VoiceActivationCore

struct TextToSpeechBackendDescriptor: Equatable, Identifiable, Sendable {
    let id: TextToSpeechBackendID
    let displayName: String
    let requiresCredential: Bool
}

struct TextToSpeechVoice: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let localeID: String?
}

struct TextToSpeechPreparationRequest: Equatable, Sendable {
    let text: String
    let localeID: String
    let voiceID: String?
}

enum PreparedTextToSpeech: Equatable, Sendable {
    case systemVoice(identifier: String?)
    case audio(Data)
}

protocol TextToSpeechBackend: Sendable {
    var descriptor: TextToSpeechBackendDescriptor { get }

    func availableVoices(credential: String?) async throws -> [TextToSpeechVoice]
    func prepare(
        _ request: TextToSpeechPreparationRequest,
        credential: String?
    ) async throws -> PreparedTextToSpeech
}

enum TextToSpeechBackendError: Error, Equatable, LocalizedError {
    case credentialRequired(TextToSpeechBackendID)
    case voiceRequired(TextToSpeechBackendID)

    var errorDescription: String? {
        switch self {
        case .credentialRequired(let backendID):
            "A credential is required for the \(backendID.rawValue) speech backend."
        case .voiceRequired(let backendID):
            "Select a voice for the \(backendID.rawValue) speech backend."
        }
    }
}
