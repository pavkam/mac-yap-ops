// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI

extension Design {
    /// Animation curves and durations.
    ///
    /// Four curves and eight durations, no more: `.smooth` for a surface
    /// morphing, `.snappy` for anything interactive, `.easeOut` for presses and
    /// every Reduce Motion substitution, and one `repeatForever` `.easeOut` for
    /// the capture ring.
    ///
    /// Nothing overshoots its target and nothing bounces. The capture ring
    /// expands outward and fades; it never pulses inward. These run for as long
    /// as someone is speaking, so they have to be calm enough to live with.
    enum Motion {
        /// Button press, and the Reduce Motion substitute for every curve here.
        static let press = Animation.easeOut(duration: 0.12)
        /// Action dock replacement.
        static let quick = Animation.easeOut(duration: 0.14)
        /// Overlay dismissal.
        static let overlayOut = Animation.easeOut(duration: 0.15)
        /// Scroll and text settlement.
        static let settle = Animation.easeOut(duration: 0.16)
        /// Content settlement with a longer tail.
        static let settleSlow = Animation.easeOut(duration: 0.18)
        /// Transcript updates, permission arrival.
        static let snappy = Animation.snappy(duration: 0.2)
        /// Disclosure, target switch.
        static let disclosure = Animation.snappy(duration: 0.22)
        /// Action dock.
        static let dock = Animation.snappy(duration: 0.30)
        /// The capture ring, repeating for as long as the microphone is open.
        static let pulse = Animation.easeOut(duration: 1.15)

        /// Press feedback scale. The only transform in the application.
        static let pressScale: CGFloat = 0.98

        /// Resolves an animation against Reduce Motion.
        ///
        /// Every animated view in this application declares a reduce-motion
        /// path, and it is always either `nil` or `press`. Route through this
        /// rather than re-deriving the rule at each surface.
        static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
            reduceMotion ? press : animation
        }

        /// Resolves a repeating or spatial animation against Reduce Motion.
        ///
        /// Ambient motion means "the microphone is open, nothing said yet", so
        /// under Reduce Motion it is removed outright rather than shortened.
        static func resolvedAmbient(_ animation: Animation, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : animation
        }
    }
}
