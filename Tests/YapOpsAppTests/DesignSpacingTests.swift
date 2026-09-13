// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import CoreGraphics
import Testing

@testable import YapOpsApp

@Suite struct DesignSpacingTests {
    @Test func scaleMatchesTheTranscribedLiterals() {
        #expect(Design.Space.hairline == 2)
        #expect(Design.Space.tiny == 4)
        #expect(Design.Space.micro == 5)
        #expect(Design.Space.row == 7)
        #expect(Design.Space.small == 8)
        #expect(Design.Space.section == 9)
        #expect(Design.Space.rowInset == 10)
        #expect(Design.Space.cardTight == 11)
        #expect(Design.Space.card == 12)
        #expect(Design.Space.header == 13)
        #expect(Design.Space.menuGutter == 14)
        #expect(Design.Space.settingsCard == 15)
        #expect(Design.Space.panelCompactInset == 16)
        #expect(Design.Space.menuHeaderTop == 17)
        #expect(Design.Space.panelGutter == 18)
        #expect(Design.Space.panelContent == 20)
    }

    @Test func overlayInsetsMatchTheTranscribedLiterals() {
        #expect(Design.Space.overlayGutter == 16)
        #expect(Design.Space.overlayCollapsedGutter == 13)
        #expect(Design.Space.overlayCancelInset == 14)
        #expect(Design.Space.overlayCancelInsetCollapsed == 5)
    }

    /// The scale is deliberately off-grid. Rounding 7, 9, 11, 13, 15 or 17 to a
    /// 4- or 8-point grid is the single change that would make these panels stop
    /// reading as native macOS, so assert the odd values survive.
    @Test func scaleRetainsItsOffGridSteps() {
        let offGrid: [CGFloat] = [
            Design.Space.row,
            Design.Space.section,
            Design.Space.cardTight,
            Design.Space.header,
            Design.Space.settingsCard,
            Design.Space.menuHeaderTop,
        ]

        for step in offGrid {
            #expect(step.truncatingRemainder(dividingBy: 4) != 0)
        }
    }
}
