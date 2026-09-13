// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import YapOpsCore

/// The first-run flow.
///
/// Absent from the source: YapOps today requests Microphone and Speech
/// Recognition lazily, on the first spoken command, and reports denial only
/// as a "Needs attention" menu status — silent unless something has already
/// gone wrong. This explains the product before that first command, using the
/// same words `docs/getting-started.md` uses for a person building from
/// source, and it does not change when permissions are requested: the two
/// steps below describe the lazy model rather than front-loading it.
struct FirstRunView: View {
    let onFinish: () -> Void

    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let steps: [FirstRunStep] = [
        FirstRunStep(
            symbol: "waveform",
            title: "YapOps",
            detail: "You declare profiles, each with a wake phrase, an icon, "
                + "an accent and a target. Say the phrase, then speak, and "
                + "YapOps sends what you said to a command or an agent."),
        FirstRunStep(
            symbol: "mic.circle",
            title: "Permissions, when needed",
            detail: "The first spoken command requests Microphone and Speech "
                + "Recognition access. Recognition stays on-device. If either "
                + "is denied, enable YapOps in Privacy & Security, then quit "
                + "and reopen it."),
        FirstRunStep(
            symbol: "checkmark.circle",
            title: "Ready",
            detail: "The default profile opens a Google search: say "
                + "“computer”, wait for the recording overlay, then speak a "
                + "query. Change the wake phrase and its target anytime in "
                + "Settings."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .frame(width: 420, height: 360)
        .background(Design.Material.floating)
    }

    private var content: some View {
        VStack(spacing: Design.Space.panelContent) {
            let current = Self.steps[step]

            Image(systemName: current.symbol)
                .font(Design.Text.onboardingStep)
                .foregroundStyle(.tint)
                .frame(height: 60)
                .accessibilityHidden(true)

            VStack(spacing: Design.Space.section) {
                Text(current.title)
                    .font(Design.Text.statusTitle)

                Text(current.detail)
                    .font(Design.Text.statusDetail)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320)
            }
            .id(step)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
        }
        .padding(Design.Space.panelContent)
        .animation(Design.Motion.resolved(Design.Motion.settleSlow, reduceMotion: reduceMotion), value: step)
    }

    private var footer: some View {
        VStack(spacing: Design.Space.card) {
            HStack(spacing: Design.Space.tiny) {
                ForEach(Self.steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: index == step ? 16 : 6, height: 6)
                }
            }
            .accessibilityHidden(true)

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                } else {
                    Spacer(minLength: 0)
                }

                Spacer()

                Button(step == Self.steps.count - 1 ? "Get started" : "Continue") {
                    if step == Self.steps.count - 1 {
                        onFinish()
                    } else {
                        step += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, Design.Space.panelContent)
        .padding(.bottom, Design.Space.panelContent)
    }
}

private struct FirstRunStep {
    let symbol: String
    let title: String
    let detail: String
}
