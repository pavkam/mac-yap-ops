// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import Testing

@testable import YapOpsApp
@testable import YapOpsCore

@Suite struct DesignColorTests {
    @Test func neutralFillsMatchTheTranscribedLiterals() {
        #expect(Design.Alpha.fill == 0.035)
        #expect(Design.Alpha.fillField == 0.045)
        #expect(Design.Alpha.fillChip == 0.055)
        #expect(Design.Alpha.fillSoft == 0.06)
        #expect(Design.Alpha.fillHover == 0.075)
        #expect(Design.Alpha.fillQuaternary == 0.08)
        #expect(Design.Alpha.fillStrong == 0.11)
        #expect(Design.Alpha.fillCodeBlock == 0.16)
    }

    @Test func hairlinesMatchTheTranscribedLiterals() {
        #expect(Design.Alpha.hairline == 0.07)
        #expect(Design.Alpha.hairlineChip == 0.08)
        #expect(Design.Alpha.hairlineCard == 0.1)
        #expect(Design.Alpha.hairlineHover == 0.14)
        #expect(Design.Alpha.hairlineBright == 0.28)
        #expect(Design.Alpha.hairlineBrightest == 0.5)
    }

    @Test func accentWashesMatchTheTranscribedLiterals() {
        #expect(Design.Alpha.accentWashFaint == 0.04)
        #expect(Design.Alpha.accentWashCard == 0.075)
        #expect(Design.Alpha.accentWashMenu == 0.11)
        #expect(Design.Alpha.accentWashHeader == 0.16)
        #expect(Design.Alpha.accentWashAvatar == 0.18)
        #expect(Design.Alpha.accentWashAvatarDisabled == 0.07)
        #expect(Design.Alpha.accentBorder == 0.28)
        #expect(Design.Alpha.accentGlowOrb == 0.46)
        #expect(Design.Alpha.accentGlowDot == 0.55)
    }

    @Test func listeningLayerAlphasMatchTheTranscribedLiterals() {
        #expect(Design.Alpha.overlayWashLeading == 0.18)
        #expect(Design.Alpha.overlayWashMid == 0.08)
        #expect(Design.Alpha.overlayWashTrailing == 0.16)
        #expect(Design.Alpha.orbCoreFalloff == 0.75)
        #expect(Design.Alpha.captureRing == 0.5)
        #expect(Design.Alpha.captureRingFaded == 0.05)
        #expect(Design.Alpha.captureRingResting == 0.7)
        #expect(Design.Alpha.inkOverlayCancel == 0.78)
    }

    @Test func inkAdjustmentsMatchTheTranscribedLiterals() {
        #expect(Design.Alpha.inkMuted == 0.55)
        #expect(Design.Alpha.inkStopTurn == 0.84)
        #expect(Design.Alpha.inkCancel == 0.86)
        #expect(Design.Alpha.inkTranscript == 0.88)
    }

    /// The accent is identity: every case must resolve to the macOS system
    /// colour it names, and no two profiles may render the same.
    @Test func everyAccentResolvesToADistinctSystemColour() {
        let resolved = WakeProfileAccent.allCases.map(\.swiftUIColor)

        #expect(resolved.count == 6)
        #expect(Set(resolved).count == 6)
        #expect(WakeProfileAccent.cyan.swiftUIColor == Color.cyan)
        #expect(WakeProfileAccent.blue.swiftUIColor == Color.blue)
        #expect(WakeProfileAccent.purple.swiftUIColor == Color.purple)
        #expect(WakeProfileAccent.pink.swiftUIColor == Color.pink)
        #expect(WakeProfileAccent.orange.swiftUIColor == Color.orange)
        #expect(WakeProfileAccent.green.swiftUIColor == Color.green)
    }

    /// A gradient whose two stops are the same colour renders as a flat tint and
    /// loses the lit read the overlay depends on.
    @Test func everyAccentHighlightDiffersFromItsAccent() {
        for accent in WakeProfileAccent.allCases {
            #expect(accent.highlightColor != accent.swiftUIColor)
        }

        #expect(WakeProfileAccent.cyan.highlightColor == Color.blue)
        #expect(WakeProfileAccent.blue.highlightColor == Color.indigo)
        #expect(WakeProfileAccent.purple.highlightColor == Color.pink)
        #expect(WakeProfileAccent.pink.highlightColor == Color.purple)
        #expect(WakeProfileAccent.orange.highlightColor == Color.pink)
        #expect(WakeProfileAccent.green.highlightColor == Color.cyan)
    }

    /// Semantic colour is fixed and never per-profile.
    @Test func semanticColoursAreSystemColours() {
        #expect(Design.Color.danger == Color.red)
        #expect(Design.Color.warning == Color.orange)
        #expect(Design.Color.success == Color.green)
        #expect(Design.Color.markGradientEnd == Color.indigo)
        #expect(Design.Color.accentFallback == Color.secondary)
    }
}
