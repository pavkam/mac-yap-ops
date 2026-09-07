// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

/// A portable visual identity rendered for a profile throughout the app.
public enum ProfileIcon: Codable, Equatable, Sendable {
    /// An SF Symbol identifier resolved by the app on the running macOS version.
    case systemSymbol(String)
    /// One extended-grapheme emoji.
    case emoji(String)

    /// The stable default used when migrating profiles without an icon.
    public static let defaultValue = ProfileIcon.systemSymbol("sparkles")

    /// Whether the payload is bounded and structurally valid for its representation.
    public var isValid: Bool {
        switch self {
        case .systemSymbol(let name):
            let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return !value.isEmpty
                && value.count <= 128
                && value.allSatisfy {
                    $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_"
                }
        case .emoji(let emoji):
            let value = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.count == 1
                && value.unicodeScalars.contains { $0.properties.isEmoji }
        }
    }
}
