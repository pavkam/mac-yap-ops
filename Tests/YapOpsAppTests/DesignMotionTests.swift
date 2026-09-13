// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import Testing

@testable import YapOpsApp

@Suite struct DesignMotionTests {
    /// The only transform in the application. A press settles inward; nothing
    /// pops outward to 1.05.
    @Test func pressScaleSettlesInward() {
        #expect(Design.Motion.pressScale == 0.98)
        #expect(Design.Motion.pressScale < 1)
    }

    /// Every animated view declares a reduce-motion path, and for an
    /// interactive curve it is always the 0.12s ease-out rather than nothing.
    @Test func reduceMotionSubstitutesThePressCurve() {
        #expect(
            Design.Motion.resolved(Design.Motion.snappy, reduceMotion: true)
                == Design.Motion.press)
        #expect(
            Design.Motion.resolved(Design.Motion.dock, reduceMotion: true)
                == Design.Motion.press)
        #expect(
            Design.Motion.resolved(Design.Motion.snappy, reduceMotion: false)
                == Design.Motion.snappy)
    }

    /// Ambient motion means "the microphone is open, nothing said yet". Under
    /// Reduce Motion it is removed outright, not shortened — a slow breathe at
    /// 0.12s would read as a glitch.
    @Test func reduceMotionRemovesAmbientMotionEntirely() {
        #expect(Design.Motion.resolvedAmbient(Design.Motion.pulse, reduceMotion: true) == nil)
        #expect(
            Design.Motion.resolvedAmbient(Design.Motion.pulse, reduceMotion: false)
                == Design.Motion.pulse)
    }

    /// Four curves and eight durations, all distinct.
    @Test func curvesAreDistinct() {
        let curves: [Animation] = [
            Design.Motion.press,
            Design.Motion.quick,
            Design.Motion.overlayOut,
            Design.Motion.settle,
            Design.Motion.settleSlow,
            Design.Motion.snappy,
            Design.Motion.disclosure,
            Design.Motion.dock,
            Design.Motion.pulse,
        ]

        #expect(Set(curves).count == curves.count)
    }
}
