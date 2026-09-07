// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

/// A stable identifier for a text-to-speech backend compiled into the app.
public struct TextToSpeechBackendID:
    RawRepresentable,
    Codable,
    Hashable,
    Sendable
{
    /// Apple's local speech synthesizer.
    public static let system = TextToSpeechBackendID(rawValue: "system")
    /// ElevenLabs cloud speech synthesis.
    public static let elevenLabs = TextToSpeechBackendID(rawValue: "elevenLabs")

    /// The persisted backend identifier.
    public let rawValue: String

    /// Creates an identifier from its stable persisted value.
    ///
    /// - Parameter rawValue: The backend identifier supplied by its implementation.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
