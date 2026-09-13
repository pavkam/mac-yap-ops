// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Testing

@testable import YapOpsApp

/// `Font` exposes no readable point size, so the roles in `Design.Text` cannot
/// be asserted here; the guard for those is `scripts/check-design-tokens.sh`
/// plus review of the migration diff. The values that *are* readable — glyph
/// sizes and tracking — are pinned below.
@Suite struct DesignTypographyTests {
    @Test func glyphSizesMatchTheTranscribedLiterals() {
        #expect(Design.Glyph.micro == 9)
        #expect(Design.Glyph.row == 14)
        #expect(Design.Glyph.status == 17)
        #expect(Design.Glyph.badge == 18)
        #expect(Design.Glyph.providerMark == 20)
        #expect(Design.Glyph.artifactFallback == 36)
    }

    /// Tracking is applied to exactly one thing: a 10pt uppercase eyebrow. It is
    /// only ever positive, and nothing above 10pt is ever uppercased.
    @Test func trackingIsPositiveAndSmall() {
        #expect(Design.Tracking.eyebrow == 0.8)
        #expect(Design.Tracking.overlay == 1.2)
        #expect(Design.Tracking.codeTag == 0.7)

        for tracking in [
            Design.Tracking.eyebrow,
            Design.Tracking.overlay,
            Design.Tracking.codeTag,
        ] {
            #expect(tracking > 0)
            #expect(tracking <= 1.2)
        }
    }
}
