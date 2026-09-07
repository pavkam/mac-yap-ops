// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import YapOpsCore

/// Renders the portable SF Symbol or emoji configured for a profile.
struct ProfileIconGlyph: View {
    let icon: ProfileIcon

    var body: some View {
        switch icon {
        case .systemSymbol(let name):
            Image(systemName: name)
        case .emoji(let value):
            Text(value)
        }
    }
}
