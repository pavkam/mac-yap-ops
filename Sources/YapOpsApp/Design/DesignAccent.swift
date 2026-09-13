// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import YapOpsCore

/// The profile accent in force for the surrounding surface.
///
/// The accent is identity, not decoration: the profile a conversation belongs to
/// propagates through its badge, its menu row, the panel's background wash, the
/// recording orb's gradient, its provider mark and its permission borders. A
/// surface that hard-codes one accent is wrong.
///
/// Setting it once at a surface root means a descendant reads the correct accent
/// without the value being threaded through every intervening view, and makes a
/// literal accent at a call site unambiguously a defect.
private struct ProfileAccentKey: EnvironmentKey {
    static let defaultValue: Color = Design.Color.accentFallback
}

extension EnvironmentValues {
    /// The accent of the profile owning this surface.
    ///
    /// Defaults to `Design.Color.accentFallback` where no profile is active,
    /// which is what the menu header renders when nothing is enabled.
    var profileAccent: Color {
        get { self[ProfileAccentKey.self] }
        set { self[ProfileAccentKey.self] = newValue }
    }
}

extension View {
    /// Establishes the profile accent for this surface and everything below it.
    ///
    /// Call once at a surface root — the menu panel, the recording overlay, the
    /// conversation panel, the Settings detail pane — not at each leaf.
    func profileAccent(_ accent: Color) -> some View {
        environment(\.profileAccent, accent)
    }

    /// Establishes the profile accent from a profile's declared accent.
    func profileAccent(_ accent: WakeProfileAccent) -> some View {
        environment(\.profileAccent, accent.swiftUIColor)
    }
}
