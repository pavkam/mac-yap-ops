// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

struct AgentRunPanelBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
