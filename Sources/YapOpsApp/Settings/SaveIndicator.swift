// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI

/// The autosave receipt.
///
/// Mandatory wherever autosave is used. It answers one question — did that
/// write happen? — and it never says more than it knows: "Saving…" while the
/// write is in flight, the real validation message when one is rejected.
struct SaveIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let status: SettingsAutosave.Status

    var body: some View {
        HStack(spacing: Design.Space.micro) {
            glyph
            Text(message)
                .font(.callout)
                .foregroundStyle(tint)
                .lineLimit(2)
        }
        .animation(
            Design.Motion.resolved(Design.Motion.snappy, reduceMotion: reduceMotion),
            value: status)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    @ViewBuilder
    private var glyph: some View {
        switch status {
        case .idle:
            EmptyView()
        case .saving:
            ProgressView()
                .controlSize(.mini)
                .accessibilityHidden(true)
        case .saved:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Design.Color.success)
                .accessibilityHidden(true)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Design.Color.danger)
                .accessibilityHidden(true)
        }
    }

    private var message: String {
        switch status {
        case .idle: "Changes save automatically."
        case .saving: "Saving…"
        case .saved: "Settings saved"
        case let .failed(reason): reason
        }
    }

    private var tint: Color {
        switch status {
        case .idle, .saving: .secondary
        case .saved: Design.Color.success
        case .failed: Design.Color.danger
        }
    }
}
