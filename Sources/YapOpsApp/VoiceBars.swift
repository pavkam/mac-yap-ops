// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI

/// A live input-level readout.
///
/// The source pulses a mic glyph, which proves the app *thinks* it is
/// recording; bars prove audio is *arriving*. That is the question the whole
/// product hinges on — did it hear me? — and it is the one thing a static
/// glyph cannot answer.
///
/// Bars derive entirely from `levels`; there is no independent animation to
/// suppress or reconcile. When every level is at rest, they read as a flat
/// line rather than a shape that had to be turned off.
struct VoiceBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One value per bar, each in `0...1`. `SpeechAudioLevelMeter.barCount`
    /// bars is the shape this view is tuned for; other counts still render.
    let levels: [Double]
    let tint: Color
    /// Height of the tallest possible bar.
    var height: CGFloat = 16

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(tint)
                    .frame(width: 2.5, height: barHeight(for: levels[index]))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
        .animation(
            reduceMotion ? nil : Design.Motion.settle,
            value: levels)
    }

    private func barHeight(for level: Double) -> CGFloat {
        let minimum = height * 0.18
        return minimum + (height - minimum) * CGFloat(max(0, min(1, level)))
    }
}
