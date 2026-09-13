// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI

/// The one empty-state recipe.
///
/// An empty list previously rendered as literally nothing, which reads as a
/// loading failure rather than as an empty set. One recipe, used wherever a
/// list, result set or conversation has no content.
struct SettingsEmptyState: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: Design.Space.section) {
            Image(systemName: symbol)
                .font(Design.Text.glyph(Design.Glyph.artifactFallback, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: Design.Space.micro) {
                Text(title)
                    .font(Design.Text.rowTitle)
                    .foregroundStyle(.secondary)

                Text(detail)
                    .font(Design.Text.statusDetail)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }
}
