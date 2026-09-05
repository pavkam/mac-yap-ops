// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

/// A backend and optional stable voice identifier selected for speech output.
public struct TextToSpeechVoiceSelection: Codable, Equatable, Sendable {
    /// The backend that owns the selected voice.
    public let backendID: TextToSpeechBackendID
    /// The backend-specific voice identifier, or `nil` for its automatic voice.
    public let voiceID: String?

    /// Creates a provider-neutral voice selection.
    ///
    /// - Parameters:
    ///   - backendID: The backend that owns the voice.
    ///   - voiceID: A backend-specific identifier, or `nil` for automatic selection.
    public init(backendID: TextToSpeechBackendID, voiceID: String?) {
        self.backendID = backendID
        let normalized = voiceID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.voiceID = normalized?.isEmpty == false ? normalized : nil
    }
}

/// A profile's relationship to the global text-to-speech default.
public enum ProfileSpeechPreference: Codable, Equatable, Sendable {
    /// Use the app-wide default backend and voice.
    case inherit
    /// Never narrate replies for this profile.
    case disabled
    /// Use this explicit backend and voice for the profile.
    case voice(TextToSpeechVoiceSelection)
}
