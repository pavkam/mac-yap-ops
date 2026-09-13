// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

struct AgentRunPanelBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let accent: Color

    var body: some View {
        ZStack(alignment: .top) {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                Rectangle().fill(Design.Material.panel)
            }

            // The accent lights the panel rather than tinting it: a radial wash
            // gathered behind the header, and a one-point specular inset along
            // the top edge. Both stay well under 30%.
            Design.Wash.panelHeader(accent)

            Design.Wash.panelSpecular
                .frame(height: Design.Space.hairline)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A phase pip that breathes while the conversation is live.
///
/// Motion here means the same thing it means on the orb: the conversation is
/// open and working. A terminal or paused phase is deliberately inert, and
/// Reduce Motion removes the animation rather than shortening it — an ambient
/// breathe at 0.12s reads as a glitch.
struct AgentRunPhasePip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tint: Color
    let isLive: Bool

    @State private var isBreathing = false

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: Design.Space.micro, height: Design.Space.micro)
            .opacity(pipOpacity)
            .animation(breatheAnimation, value: isBreathing)
            .onAppear { isBreathing = isLive }
            .onChange(of: isLive) { _, live in isBreathing = live }
            .accessibilityHidden(true)
    }

    private var pipOpacity: Double {
        guard isLive else { return Design.Alpha.phasePipResting }
        return isBreathing && !reduceMotion ? 1 : Design.Alpha.phasePipResting
    }

    private var breatheAnimation: Animation? {
        guard isLive, !reduceMotion else { return nil }
        return Design.Motion.pulse.repeatForever(autoreverses: true)
    }
}

struct AgentRunWorkingGlyph: View {
    let tint: Color
    let size: CGFloat

    var body: some View {
        ProgressView()
            .controlSize(size < 24 ? .mini : .small)
            .tint(tint)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
