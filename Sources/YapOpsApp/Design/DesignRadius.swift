// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import CoreGraphics

/// Namespace for the YapOps design tokens.
///
/// Values are transcribed from the SwiftUI literals the application already
/// rendered; adopting a token must never change appearance. See
/// `.agents/skills/design/references/tokens.md` for the rules that govern
/// adding to this layer.
enum Design {}

extension Design {
    /// The eleven corner radii, ordered by the scale of the surface they clip.
    ///
    /// There are exactly eleven and they encode hierarchy: the larger the
    /// surface, the softer its corner. Naming one radius per call site would
    /// grow this to thirty within a release and destroy that property, so a new
    /// surface picks the tier it belongs to rather than adding a twelfth
    /// constant. Every use is `style: .continuous`.
    enum Radius {
        /// Artifact preview thumbnail clip.
        static let thumbnail: CGFloat = 7
        /// Path field, provider preset button.
        static let field: CGFloat = 8
        /// Notice card, system-prompt editor, code block.
        static let notice: CGFloat = 9
        /// User bubble, plan and task card, settings editor card.
        static let innerCard: CGFloat = 10
        /// Artifact card.
        static let artifact: CGFloat = 11
        /// Menu row, last-command card, agent-run controls.
        static let row: CGFloat = 12
        /// Provider hero block.
        static let hero: CGFloat = 13
        /// Agent message block, app mark.
        static let message: CGFloat = 15
        /// Minimized conversation panel.
        static let panelCompact: CGFloat = 18
        /// Expanded conversation panel.
        static let panelExpanded: CGFloat = 22
        /// Recording overlay capsule.
        static let capsule: CGFloat = 32
    }

    /// Stroke widths for hairlines and borders.
    ///
    /// A border restores edge definition against a vibrancy material; it is not
    /// decoration, and nothing in the application strokes wider than `strong`
    /// outside the increased-contrast path.
    enum Border {
        /// Panel `strokeBorder` at normal contrast.
        static let hairline: CGFloat = 0.5
        /// Message block, mini mark.
        static let thin: CGFloat = 0.7
        /// Menu row, chip, overlay cancel button.
        static let `default`: CGFloat = 0.75
        /// App mark, permission card, failure card, provider hero.
        static let strong: CGFloat = 1
        /// Panel border when Increase Contrast is enabled.
        static let contrast: CGFloat = 1.5
    }
}
