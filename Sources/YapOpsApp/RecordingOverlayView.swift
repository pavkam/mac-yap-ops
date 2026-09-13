// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI

struct RecordingOverlayView: View {
    @Bindable var model: RecordingOverlayModel

    var body: some View {
        ZStack {
            capsuleBackground
                .opacity(isExpanded ? 1 : 0)
                .scaleEffect(
                    x: isExpanded ? 1 : 0.28,
                    y: isExpanded ? 1 : 0.78,
                    anchor: .center)

            HStack(spacing: isExpanded ? Design.Space.overlayGutter : 0) {
                microphoneOrb(
                    size: isExpanded ? Design.Layout.orbExpanded : Design.Layout.orbIdle)
                    .fixedSize()

                if isExpanded {
                    transcriptContent
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .padding(
                .horizontal,
                isExpanded ? Design.Space.overlayGutter : Design.Space.overlayCollapsedGutter)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: isExpanded ? .leading : .center)

            cancelButton
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: isExpanded ? .trailing : .topTrailing)
                .padding(
                    isExpanded
                        ? Design.Space.overlayCancelInset
                        : Design.Space.overlayCancelInsetCollapsed)
        }
        .animation(
            .smooth(duration: RecordingOverlayLayout.transitionDuration),
            value: isExpanded)
    }

    private var isExpanded: Bool {
        !model.transcript.isEmpty
    }

    private var transcriptContent: some View {
        VStack(alignment: .leading, spacing: Design.Space.micro) {
            Text("Listening")
                .font(Design.Text.eyebrowOverlay)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(Design.Tracking.overlay)

            Text(RecordingTranscriptTail.format(model.transcript))
                .font(Design.Text.transcript)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .contentTransition(.interpolate)
                .animation(Design.Motion.snappy, value: model.transcript)
        }
        .padding(.trailing, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var capsuleBackground: some View {
        RoundedRectangle(cornerRadius: Design.Radius.capsule, style: .continuous)
            .fill(Design.Material.floating)
            .overlay {
                Design.Wash.overlay(accent: accentColor, highlight: accentHighlight)
                    .clipShape(
                        RoundedRectangle(cornerRadius: Design.Radius.capsule, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Design.Radius.capsule, style: .continuous)
                    .stroke(
                        Design.Wash.overlayRim(accent: accentColor),
                        lineWidth: Design.Border.strong)
            }
    }

    private func microphoneOrb(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Design.Material.orb)

            Circle()
                .fill(AngularGradient(
                    colors: [
                        accentColor,
                        accentHighlight,
                        accentColor.opacity(Design.Alpha.orbCoreFalloff),
                        accentColor,
                    ],
                    center: .center))
                .padding(Design.Space.micro)
                .shadow(
                    color: accentColor.opacity(Design.Glow.orb.alpha),
                    radius: Design.Glow.orb.radius)

            Circle()
                .stroke(accentColor.opacity(Design.Alpha.captureRing), lineWidth: 3)
                .scaleEffect(model.isRecording ? 1.14 : 0.88)
                .opacity(
                    model.isRecording
                        ? Design.Alpha.captureRingFaded
                        : Design.Alpha.captureRingResting)
                .animation(
                    model.isRecording
                        ? Design.Motion.pulse.repeatForever(autoreverses: false)
                        : Design.Motion.overlayOut,
                    value: model.isRecording)

            Image(systemName: "mic.fill")
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(
                    .pulse,
                    options: .repeat(.continuous),
                    isActive: model.isRecording)
        }
        .frame(width: size, height: size)
    }

    private var accentColor: Color {
        model.accent.swiftUIColor
    }

    private var accentHighlight: Color {
        model.accent.highlightColor
    }

    private var cancelButton: some View {
        Button {
            model.onCancel?()
        } label: {
            Image(systemName: "xmark")
                .font(Design.Text.glyph(11, weight: .bold))
                .foregroundStyle(.primary.opacity(Design.Alpha.inkOverlayCancel))
                .frame(width: Design.Layout.hitTarget, height: Design.Layout.hitTarget)
                .background(Design.Material.panel, in: Circle())
                .overlay {
                    Circle()
                        .stroke(
                            .white.opacity(Design.Alpha.hairlineBright),
                            lineWidth: Design.Border.default)
                }
        }
        .buttonStyle(.plain)
        .help("Cancel recording")
        .accessibilityLabel("Cancel recording")
    }
}
