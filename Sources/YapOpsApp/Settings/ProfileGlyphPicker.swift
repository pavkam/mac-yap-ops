// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import YapOpsCore

/// Picks a profile's icon from the curated symbol set, or an emoji.
///
/// The previous editor asked you to type an SF Symbol name into a monospaced
/// field and offered a Browse menu beside it, so choosing a glyph meant either
/// knowing Apple's catalogue by heart or opening a menu to see ten options the
/// editor already knew about. Showing the ten beats typing one blind, and it
/// removes a mode switch: a profile icon is one of two payloads, not a mode you
/// select first.
struct ProfileGlyphPicker: View {
    /// The ten symbols the editor has always offered. `ProfileIcon` accepts any
    /// SF Symbol, but these are the ones that read correctly at badge size.
    static let curatedSymbols = [
        "sparkles", "waveform", "brain.head.profile", "terminal", "hammer",
        "magnifyingglass", "doc.text", "lightbulb", "music.note", "wand.and.stars",
    ]

    @Binding var icon: ProfileIcon
    let accent: WakeProfileAccent

    private let columns = Array(
        repeating: GridItem(.fixed(Design.Layout.profileAvatar), spacing: Design.Space.micro),
        count: 10)

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.small) {
            Text("Icon")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: Design.Space.micro) {
                ForEach(Self.curatedSymbols, id: \.self) { name in
                    glyphButton(name)
                }
            }

            HStack(spacing: Design.Space.small) {
                Text("or an emoji")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("🙂", text: emojiBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .accessibilityLabel("Profile emoji")

                if case .emoji = icon {
                    Text("Emoji replaces the symbol.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func glyphButton(_ name: String) -> some View {
        let isSelected = selectedSymbol == name

        return Button {
            icon = .systemSymbol(name)
        } label: {
            Image(systemName: name)
                .font(Design.Text.glyph(Design.Glyph.row))
                .foregroundStyle(isSelected ? accent.swiftUIColor : Color.secondary)
                .frame(width: Design.Layout.profileAvatar, height: Design.Layout.profileAvatar)
                .background(
                    isSelected
                        ? accent.swiftUIColor.opacity(Design.Alpha.selectionFill)
                        : Color.primary.opacity(Design.Alpha.fill),
                    in: RoundedRectangle(cornerRadius: Design.Radius.field))
                .overlay {
                    RoundedRectangle(cornerRadius: Design.Radius.field)
                        .stroke(
                            isSelected
                                ? accent.swiftUIColor.opacity(Design.Alpha.selectionBorder)
                                : Color.white.opacity(Design.Alpha.hairline),
                            lineWidth: Design.Border.default)
                }
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var selectedSymbol: String? {
        if case let .systemSymbol(name) = icon { name } else { nil }
    }

    private var emojiBinding: Binding<String> {
        Binding(
            get: { if case let .emoji(value) = icon { value } else { "" } },
            set: { newValue in
                // One extended grapheme cluster: an emoji is a single glyph, and
                // a pasted string would render as a ragged badge.
                guard let first = newValue.first else { return }
                icon = .emoji(String(first))
            })
    }
}
