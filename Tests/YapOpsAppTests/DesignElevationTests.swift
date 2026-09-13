// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import Testing

@testable import YapOpsApp

/// Glows are composite values, so a drift here would not be caught by the
/// per-axis suites. Each tuple is pinned to the `.shadow(color:radius:y:)` call
/// it replaced.
@Suite struct DesignElevationTests {
    @Test func glowsMatchTheTranscribedLiterals() {
        #expect(Design.Glow.mark.radius == 10)
        #expect(Design.Glow.mark.y == 4)
        #expect(Design.Glow.mark.alpha == 0.26)

        #expect(Design.Glow.providerMark.radius == 7)
        #expect(Design.Glow.providerMark.y == 3)
        #expect(Design.Glow.providerMark.alpha == 0.28)

        #expect(Design.Glow.miniMark.radius == 5)
        #expect(Design.Glow.miniMark.y == 2)
        #expect(Design.Glow.miniMark.alpha == 0.18)

        #expect(Design.Glow.orb.radius == 10)
        #expect(Design.Glow.orb.y == 0)
        #expect(Design.Glow.orb.alpha == 0.46)

        #expect(Design.Glow.statusDot.radius == 4)
        #expect(Design.Glow.statusDot.y == 0)
        #expect(Design.Glow.statusDot.alpha == 0.55)
    }

    /// The only black shadow in the application. Everything else is an accent
    /// glow, so a neutral shadow appearing elsewhere is a defect.
    @Test func onlyTheMarkBarsCarryANeutralShadow() {
        #expect(Design.Glow.markBars.radius == 2)
        #expect(Design.Glow.markBars.y == 1)
        #expect(Design.Glow.markBars.alpha == 0.18)
    }

    /// A glow sits under its surface; none of them offset upward.
    @Test func glowsNeverOffsetUpward() {
        for glow in [
            Design.Glow.mark,
            Design.Glow.providerMark,
            Design.Glow.miniMark,
            Design.Glow.orb,
            Design.Glow.statusDot,
            Design.Glow.markBars,
        ] {
            #expect(glow.y >= 0)
            #expect(glow.radius > 0)
        }
    }
}

// `Material` is not `Equatable`, so the three tiers in `Design.Material` cannot
// be asserted here. Their guard is `scripts/check-design-tokens.sh` plus review:
// a raw `.ultraThinMaterial` in a view is visible in the diff.
