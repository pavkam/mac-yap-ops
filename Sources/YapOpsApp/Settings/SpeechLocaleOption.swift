// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

struct SpeechLocaleOption: Identifiable, Equatable {
    let id: String

    var title: String {
        Locale(identifier: "en").localizedString(forIdentifier: id) ?? id
    }

    static func options(supportedIdentifiers: [String], selectedIdentifier: String) -> [Self] {
        var identifiers = Set(supportedIdentifiers.map {
            Locale(identifier: $0).identifier(.bcp47)
        })
        // A saved underscore-style identifier must remain the Picker's exact selection tag.
        identifiers.remove(Locale(identifier: selectedIdentifier).identifier(.bcp47))
        identifiers.insert(selectedIdentifier)
        return identifiers.map { Self(id: $0) }.sorted {
            let order = $0.title.compare($1.title, options: .caseInsensitive, locale: Locale(identifier: "en"))
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}
