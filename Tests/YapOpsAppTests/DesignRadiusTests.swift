// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import CoreGraphics
import Testing

@testable import YapOpsApp

/// Guards the radius ladder against the one failure mode this migration has:
/// a token whose value drifts from the SwiftUI literal it replaced, changing
/// appearance while every build stays green.
@Suite struct DesignRadiusTests {
    @Test func ladderMatchesTheTranscribedLiterals() {
        #expect(Design.Radius.thumbnail == 7)
        #expect(Design.Radius.field == 8)
        #expect(Design.Radius.notice == 9)
        #expect(Design.Radius.innerCard == 10)
        #expect(Design.Radius.artifact == 11)
        #expect(Design.Radius.row == 12)
        #expect(Design.Radius.hero == 13)
        #expect(Design.Radius.message == 15)
        #expect(Design.Radius.panelCompact == 18)
        #expect(Design.Radius.panelExpanded == 22)
        #expect(Design.Radius.capsule == 32)
    }

    /// The ladder encodes scale: a larger surface takes a softer corner. A new
    /// radius inserted out of order would break the property the tiers exist to
    /// express, so assert the ordering rather than only the values.
    @Test func ladderAscendsWithSurfaceScale() {
        let ladder: [CGFloat] = [
            Design.Radius.thumbnail,
            Design.Radius.field,
            Design.Radius.notice,
            Design.Radius.innerCard,
            Design.Radius.artifact,
            Design.Radius.row,
            Design.Radius.hero,
            Design.Radius.message,
            Design.Radius.panelCompact,
            Design.Radius.panelExpanded,
            Design.Radius.capsule,
        ]

        #expect(ladder == ladder.sorted())
        #expect(Set(ladder).count == ladder.count)
        #expect(ladder.count == 11)
    }

    @Test func borderWeightsMatchTheTranscribedLiterals() {
        #expect(Design.Border.hairline == 0.5)
        #expect(Design.Border.thin == 0.7)
        #expect(Design.Border.default == 0.75)
        #expect(Design.Border.strong == 1)
        #expect(Design.Border.contrast == 1.5)
    }
}
