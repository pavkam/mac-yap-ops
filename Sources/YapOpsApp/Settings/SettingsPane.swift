// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

/// The stable pane identifiers also restore the last selected Settings tab.
enum SettingsPane: String, CaseIterable {
    case general
    case profiles
    case speech

    var title: String {
        switch self {
        case .general: "General"
        case .profiles: "Profiles"
        case .speech: "Speech & Audio"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .profiles: "person.2"
        case .speech: "waveform"
        }
    }
}
