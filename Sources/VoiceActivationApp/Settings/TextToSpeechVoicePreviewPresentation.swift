// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import VoiceActivationCore

enum TextToSpeechVoicePreviewContext: Hashable, Sendable {
    case defaultVoice
    case profile(UUID)
}

struct TextToSpeechVoicePreviewFeedback: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case success
        case failure
    }

    let kind: Kind
    let title: String
    let detail: String

    static func success(backendName: String) -> Self {
        Self(
            kind: .success,
            title: "Preview finished",
            detail: "The \(backendName) voice is ready to use.")
    }

    static func failure(_ error: any Error) -> Self {
        switch error {
        case TextToSpeechBackendError.credentialRequired:
            Self(
                kind: .failure,
                title: "Add an ElevenLabs API key",
                detail: "The global Keychain credential is shared by every profile.")
        case TextToSpeechBackendError.voiceRequired:
            Self(
                kind: .failure,
                title: "Choose a voice",
                detail: "Select a voice before starting a preview.")
        case ElevenLabsSpeechClientError.httpStatus(401):
            Self(
                kind: .failure,
                title: "Check the ElevenLabs API key",
                detail: "ElevenLabs could not authenticate the global credential.")
        case ElevenLabsSpeechClientError.httpStatus(402):
            Self(
                kind: .failure,
                title: "ElevenLabs needs credits",
                detail: "This request needs available credits or a plan that supports the selected voice.")
        case ElevenLabsSpeechClientError.httpStatus(403):
            Self(
                kind: .failure,
                title: "Voice access denied",
                detail: "This API key or plan cannot use the selected voice.")
        case ElevenLabsSpeechClientError.httpStatus(429):
            Self(
                kind: .failure,
                title: "ElevenLabs is busy",
                detail: "Wait a moment for another request to finish, then try again.")
        case ElevenLabsSpeechClientError.httpStatus(let status) where status >= 500:
            Self(
                kind: .failure,
                title: "ElevenLabs is unavailable",
                detail: "The service could not prepare this preview. Try again shortly.")
        case TextToSpeechVoicePreviewError.playbackFailed:
            Self(
                kind: .failure,
                title: "Preview could not play",
                detail: "Check the selected audio output and try again.")
        case is URLError:
            Self(
                kind: .failure,
                title: "Could not reach the voice service",
                detail: "Check the network connection and try again.")
        default:
            Self(
                kind: .failure,
                title: "Voice preview failed",
                detail: "Try again. If it keeps failing, check the app diagnostics.")
        }
    }
}
