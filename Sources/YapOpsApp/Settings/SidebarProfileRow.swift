// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import YapOpsCore

/// One profile in the Settings sidebar.
///
/// Selection is an accent *wash* with accent ink, not a solid fill — the solid
/// treatment belongs to segmented controls, and the two are not
/// interchangeable. Hover changes the fill only: no lift, no shadow, no colour
/// shift.
struct SidebarProfileRow: View {
    let profile: WakeProfileDraft
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Space.section) {
                ProfileIconGlyph(icon: profile.icon)
                    .font(Design.Text.glyph(Design.Glyph.row))
                    .foregroundStyle(glyphStyle)
                    .frame(width: Design.Layout.profileAvatar - 8, height: Design.Layout.profileAvatar - 8)
                    .background(
                        accent.opacity(
                            profile.isEnabled
                                ? Design.Alpha.accentWashAvatar
                                : Design.Alpha.accentWashAvatarDisabled),
                        in: RoundedRectangle(cornerRadius: Design.Radius.field))

                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName)
                        .font(Design.Text.rowTitle)
                        .foregroundStyle(isSelected ? AnyShapeStyle(accent) : AnyShapeStyle(.primary))
                        .lineLimit(1)

                    Text(subtitle)
                        .font(Design.Text.rowDetail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if !profile.isEnabled {
                    Image(systemName: "pause.circle")
                        .font(Design.Text.glyph(Design.Glyph.micro, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .help("Paused")
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Design.Space.section)
            .padding(.vertical, Design.Space.row)
            .contentShape(RoundedRectangle(cornerRadius: Design.Radius.innerCard))
            .background(rowFill, in: RoundedRectangle(cornerRadius: Design.Radius.innerCard))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Design.Radius.innerCard)
                        .stroke(
                            accent.opacity(Design.Alpha.selectionBorder),
                            lineWidth: Design.Border.default)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(displayName)
        .accessibilityValue(profile.isEnabled ? "Enabled" : "Paused")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var accent: Color {
        profile.accent.swiftUIColor
    }

    private var glyphStyle: Color {
        profile.isEnabled ? accent : Design.Color.accentFallback
    }

    private var rowFill: Color {
        if isSelected {
            accent.opacity(Design.Alpha.selectionFill)
        } else if isHovering {
            Color.primary.opacity(Design.Alpha.fillHover)
        } else {
            Color.clear
        }
    }

    private var displayName: String {
        profile.name.isEmpty ? "Untitled profile" : profile.name
    }

    /// The wake phrase is what you *say*, so it keeps its curly quotes even at
    /// this size. An empty phrase is called out rather than rendered as `“”`.
    private var subtitle: String {
        profile.wakePhrase.isEmpty ? "No trigger phrase" : "“\(profile.wakePhrase)”"
    }
}
