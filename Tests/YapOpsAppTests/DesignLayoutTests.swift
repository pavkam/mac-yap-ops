// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Testing

@testable import YapOpsApp

@Suite struct DesignLayoutTests {
    @Test func windowSizesMatchTheTranscribedLiterals() {
        #expect(Design.Layout.menuWidth == 356)
        #expect(Design.Layout.settingsWidth == 720)
        #expect(Design.Layout.settingsHeightGeneral == 420)
        #expect(Design.Layout.settingsHeightTall == 660)
    }

    @Test func elementSizesMatchTheTranscribedLiterals() {
        #expect(Design.Layout.statusOrb == 44)
        #expect(Design.Layout.statusDot == 8)
        #expect(Design.Layout.profileAvatar == 34)
        #expect(Design.Layout.iconBadge == 36)
        #expect(Design.Layout.providerMark == 44)
        #expect(Design.Layout.miniMark == 27)
        #expect(Design.Layout.orbExpanded == 72)
        #expect(Design.Layout.orbIdle == 92)
        #expect(Design.Layout.glyphSlot == 22)
        #expect(Design.Layout.artifactPreview == 128)
        #expect(Design.Layout.hitTarget == 28)
    }

    /// The orb shrinks when a transcript appears beside it, so the collapsed
    /// state must stay the larger of the two.
    @Test func orbShrinksOnceATranscriptIsVisible() {
        #expect(Design.Layout.orbIdle > Design.Layout.orbExpanded)
    }

    /// 28pt is Apple's accessibility floor for a pointer target, and the overlay
    /// cancel button sits exactly on it.
    @Test func hitTargetMeetsTheAccessibilityFloor() {
        #expect(Design.Layout.hitTarget >= 28)
    }
}
