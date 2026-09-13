// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import YapOpsCore

extension Design {
    /// Opacity values for fills, hairlines and accent washes.
    ///
    /// These are named rather than wrapped in a `ShapeStyle` so that a call site
    /// keeps the hierarchical style it already used. `.primary.opacity(_:)` and
    /// `Color.primary.opacity(_:)` do not resolve identically in every context,
    /// and this layer must not change what is rendered.
    enum Alpha {
        // Neutral fills, layered on a vibrancy ground as white or label alpha.

        /// Menu footer, profile row at rest, collapsed thinking block.
        static let fill: Double = 0.035
        /// Background session card, text field ground.
        static let fillField: Double = 0.045
        /// Last-command card, listening chip, agent message block.
        static let fillChip: Double = 0.055
        /// Quaternary card fill.
        static let fillSoft: Double = 0.06
        /// Profile row and chip under the pointer.
        static let fillHover: Double = 0.075
        /// Quaternary fill.
        static let fillQuaternary: Double = 0.08
        /// Strongest neutral fill in the application.
        static let fillStrong: Double = 0.11
        /// Markdown code block, which darkens rather than lightens.
        static let fillCodeBlock: Double = 0.16

        // Hairlines.

        /// Resting border on rows and chips.
        static let hairline: Double = 0.07
        /// Capsule chip border.
        static let hairlineChip: Double = 0.08
        /// Card border.
        static let hairlineCard: Double = 0.1
        /// Row border under the pointer.
        static let hairlineHover: Double = 0.14
        /// App mark and orb edge.
        static let hairlineBright: Double = 0.28
        /// Brightest overlay stroke.
        static let hairlineBrightest: Double = 0.5

        // Accent-derived washes. The accent is identity, so these stay low:
        // nothing accent-tinted exceeds 0.28 outside the listening layer.

        /// Trailing stop of the menu panel wash.
        static let accentWashFaint: Double = 0.04
        /// Agent-run control card fill.
        static let accentWashCard: Double = 0.075
        /// Leading stop of the menu panel wash.
        static let accentWashMenu: Double = 0.11
        /// Status header disc, card border.
        static let accentWashHeader: Double = 0.16
        /// Enabled profile avatar disc.
        static let accentWashAvatar: Double = 0.18
        /// Disabled profile avatar disc.
        static let accentWashAvatarDisabled: Double = 0.07
        /// Status header ring, mark stroke.
        static let accentBorder: Double = 0.28
        /// Recording orb glow.
        static let accentGlowOrb: Double = 0.46
        /// Status dot glow.
        static let accentGlowDot: Double = 0.55

        // The listening layer. Listening is the product, so the overlay is the
        // one place the system is expressive rather than merely correct — but
        // nothing here exceeds 0.5, and motion still means the mic is open.

        /// Leading stop of the overlay capsule wash.
        static let overlayWashLeading: Double = 0.18
        /// Middle stop of the overlay capsule wash.
        static let overlayWashMid: Double = 0.08
        /// Trailing highlight stop of the overlay capsule wash.
        static let overlayWashTrailing: Double = 0.16
        /// Third stop of the orb's angular core.
        static let orbCoreFalloff: Double = 0.75
        /// Capture ring stroke.
        static let captureRing: Double = 0.5
        /// Capture ring at the end of its expansion, where it fades out.
        static let captureRingFaded: Double = 0.05
        /// Capture ring at rest.
        static let captureRingResting: Double = 0.7
        /// Overlay cancel glyph.
        static let inkOverlayCancel: Double = 0.78

        // Ink adjustments, where the application dims a semantic colour rather
        // than substituting a different one.

        /// Inactive checkmark.
        static let inkMuted: Double = 0.55
        /// Stop-turn button tint.
        static let inkStopTurn: Double = 0.84
        /// Cancel-recording button tint.
        static let inkCancel: Double = 0.86
        /// Last-command transcript.
        static let inkTranscript: Double = 0.88
    }

    /// Semantic colours.
    ///
    /// Nothing here constructs a colour from components. The six profile accents
    /// and every status colour are macOS system colours, requested by name so
    /// they continue to track appearance, Increase Contrast and future releases.
    /// The hex values in the design system's `tokens/colors.css` are that
    /// palette's *web* rendering and must never be transcribed into Swift.
    enum Color {
        /// Failures, destructive actions and stop.
        static let danger = SwiftUI.Color.red
        /// Partial capture and shortcut recording.
        static let warning = SwiftUI.Color.orange
        /// Ready and saved.
        static let success = SwiftUI.Color.green
        /// The app mark's fixed gradient end stop. Never a profile accent.
        static let markGradientEnd = SwiftUI.Color.indigo
        /// Stands in for the accent when no profile is active.
        static let accentFallback = SwiftUI.Color.secondary
    }
}

extension WakeProfileAccent {
    /// The macOS system colour this accent names.
    var swiftUIColor: Color {
        switch self {
        case .cyan: .cyan
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .orange: .orange
        case .green: .green
        }
    }

    /// The second stop used wherever an accent is rendered as a gradient.
    ///
    /// The recording overlay's capsule wash and the orb's angular core both run
    /// from the accent to this partner, so an accent reads as a lit surface
    /// rather than a flat tint. Pairings are fixed per accent, not derived, and
    /// this is the only place they are declared.
    var highlightColor: Color {
        switch self {
        case .cyan: .blue
        case .blue: .indigo
        case .purple: .pink
        case .pink: .purple
        case .orange: .pink
        case .green: .cyan
        }
    }
}
