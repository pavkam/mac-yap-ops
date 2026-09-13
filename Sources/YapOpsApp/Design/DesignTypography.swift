// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI

extension Design {
    /// The type ramp.
    ///
    /// Three faces, all Apple system, no bundled font: `.rounded` (SF Pro
    /// Rounded) names things — status titles, profile names, transcripts,
    /// eyebrows; the default design (SF Pro Text) is for reading; `.monospaced`
    /// (SF Mono) is for anything the shell reads literally and anything that
    /// must not reflow.
    ///
    /// Tracking is applied to exactly one thing: the 10pt uppercase eyebrow.
    /// Nothing else is tracked and nothing above 10pt is ever uppercased.
    enum Text {
        /// Menu status title. 16pt semibold rounded.
        static let statusTitle = Font.system(size: 16, weight: .semibold, design: .rounded)
        /// Menu status detail. 12pt.
        static let statusDetail = Font.system(size: 12)
        /// Recording overlay transcript. 17pt semibold rounded.
        static let transcript = Font.system(size: 17, weight: .semibold, design: .rounded)
        /// Uppercase section label. Pair with `Tracking.eyebrow`.
        static let eyebrow = Font.system(size: 10, weight: .bold, design: .rounded)
        /// Compact control label inside a section header.
        static let eyebrowControl = Font.system(size: 10, weight: .semibold, design: .rounded)
        /// Recording overlay eyebrow. One step larger than the menu's, because
        /// the overlay is read at a glance from across a screen.
        static let eyebrowOverlay = Font.system(size: 11, weight: .bold, design: .rounded)
        /// Profile row title. 14pt semibold rounded.
        static let rowTitle = Font.system(size: 14, weight: .semibold, design: .rounded)
        /// Profile row detail. 11pt.
        static let rowDetail = Font.system(size: 11)
        /// Last-command transcript summary. 13pt medium rounded.
        static let rowTranscript = Font.system(size: 13, weight: .medium, design: .rounded)
        /// Profile badge name. 11pt bold rounded.
        static let badgeTitle = Font.system(size: 11, weight: .bold, design: .rounded)
        /// Menu footer controls. 12pt medium.
        static let footer = Font.system(size: 12, weight: .medium)
        /// Emphatic action label. 13pt semibold.
        static let actionLabel = Font.system(size: 13, weight: .semibold)
        /// Compact rounded caption. 10pt medium rounded.
        static let captionRounded = Font.system(size: 10, weight: .medium, design: .rounded)
        /// Provider chip and segment label. 12pt semibold rounded.
        static let chipLabel = Font.system(size: 12, weight: .semibold, design: .rounded)
        /// Elapsed time. Monospaced so a running counter does not reflow.
        static let elapsed = Font.system(size: 12, weight: .medium, design: .monospaced)
        /// Markdown code-block language tag. Pair with `Tracking.codeTag`.
        static let codeTag = Font.system(size: 8, weight: .bold, design: .rounded)
        /// Artifact fallback glyph.
        ///
        /// The only `.light` weight in the application. The design system
        /// records weights as 400/500/600/700 and missed this one; it is
        /// deliberate here, because a 36pt glyph at semibold reads as an error
        /// state rather than a placeholder.
        static let artifactFallback = Font.system(size: 36, weight: .light)
        /// First-run step glyph. `.light` for the same reason as the artifact
        /// fallback: a large glyph at semibold reads as an alert.
        static let onboardingStep = Font.system(size: 44, weight: .light)

        /// A glyph sized to sit with neighbouring text.
        ///
        /// Symbols are always semibold or medium and tinted by
        /// `.foregroundStyle`, never recoloured by a custom modifier.
        static func glyph(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight)
        }
    }

    /// Glyph point sizes, matched to the text they accompany.
    enum Glyph {
        /// Count badge on a panel header control.
        ///
        /// The design system's ladder omits 9pt; this site is real and predates
        /// it. Kept rather than rounded to 8 or 10, because the badge has to sit
        /// optically inside a 22pt slot.
        static let micro: CGFloat = 9
        /// Profile row icon.
        static let row: CGFloat = 14
        /// Status header symbol, row checkmark.
        static let status: CGFloat = 17
        /// Profile icon badge.
        static let badge: CGFloat = 18
        /// Provider mark.
        static let providerMark: CGFloat = 20
        /// Artifact fallback.
        static let artifactFallback: CGFloat = 36
    }

    /// Letter spacing. Only ever applied to a 10pt uppercase eyebrow.
    enum Tracking {
        /// Menu section labels.
        static let eyebrow: CGFloat = 0.8
        /// Recording overlay eyebrow.
        static let overlay: CGFloat = 1.2
        /// Markdown code-block language tag.
        static let codeTag: CGFloat = 0.7
    }
}
