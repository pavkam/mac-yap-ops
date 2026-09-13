// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import CoreGraphics

extension Design {
    /// Padding and stack spacing.
    ///
    /// This scale is deliberately off-grid: 7, 9, 11, 13, 15 and 17 are all real
    /// literals in the application. Snapping them to a 4- or 8-point grid is the
    /// one change guaranteed to make these panels stop reading as native macOS,
    /// so a new surface reuses a value here rather than rounding to a neighbour.
    enum Space {
        /// Tight label stacks inside a row.
        static let hairline: CGFloat = 2
        /// Eyebrow to its content.
        static let micro: CGFloat = 5
        /// Chip vertical padding.
        static let tiny: CGFloat = 4
        /// Profile list rows, section stacks.
        static let row: CGFloat = 7
        /// Control groups, chip horizontal padding.
        static let small: CGFloat = 8
        /// Panel section spacing.
        static let section: CGFloat = 9
        /// Row horizontal inset.
        static let rowInset: CGFloat = 10
        /// Profile row content, tight card inset.
        static let cardTight: CGFloat = 11
        /// Card inset, block separation.
        static let card: CGFloat = 12
        /// Status header spacing, menu footer vertical inset.
        static let header: CGFloat = 13
        /// Menu gutter, settings editor stack.
        static let menuGutter: CGFloat = 14
        /// Settings card inset.
        static let settingsCard: CGFloat = 15
        /// Compact panel screen inset.
        static let panelCompactInset: CGFloat = 16
        /// Menu header top inset.
        static let menuHeaderTop: CGFloat = 17
        /// Menu and panel header gutter, timeline block spacing.
        static let panelGutter: CGFloat = 18
        /// Panel scroll content gutter.
        static let panelContent: CGFloat = 20

        // The recording overlay is the one surface that changes its own insets
        // between states, so its four values are named rather than shared.

        /// Overlay content gutter once a transcript is visible.
        static let overlayGutter: CGFloat = 16
        /// Overlay content gutter while collapsed to the bare orb.
        static let overlayCollapsedGutter: CGFloat = 13
        /// Overlay cancel-button inset once expanded.
        static let overlayCancelInset: CGFloat = 14
        /// Overlay cancel-button inset while collapsed.
        static let overlayCancelInsetCollapsed: CGFloat = 5
    }
}
