// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI
import YapOpsCore

struct MenuContentView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            statusHeader

            if !model.lastTranscript.isEmpty {
                lastCommand
            }

            if let snapshot = model.agentRunSnapshot {
                agentRunControls(snapshot)
            }

            if !model.activeAgentBackgroundSessions.isEmpty {
                backgroundSessions
            }

            if model.interruptedAgentWork.contains(where: { $0.providerTaskID != nil }) {
                interruptedBackgroundWork
            }

            profileList

            if model.state == .capturing {
                cancelButton
            }

            footer
        }
        .frame(width: Design.Layout.menuWidth)
        .profileAccent(headerAccent)
        .background(panelBackground)
        .background {
            MenuWindowConfigurationView(layoutIdentity: layoutIdentity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var statusHeader: some View {
        let presentation = model.statusPresentation

        return HStack(spacing: Design.Space.header) {
            ZStack {
                Circle()
                    .fill(headerAccent.opacity(Design.Alpha.accentWashHeader))

                Circle()
                    .stroke(
                        headerAccent.opacity(Design.Alpha.accentBorder),
                        lineWidth: Design.Border.strong)

                Image(systemName: presentation.symbolName)
                    .font(Design.Text.glyph(Design.Glyph.status))
                    .foregroundStyle(presentation.isError ? Design.Color.danger : headerAccent)
                    .symbolEffect(.variableColor.iterative, isActive: model.state == .capturing)
            }
            .frame(width: Design.Layout.statusOrb, height: Design.Layout.statusOrb)

            VStack(alignment: .leading, spacing: Design.Space.hairline) {
                Text(presentation.title)
                    .font(Design.Text.statusTitle)

                Text(presentation.detail)
                    .font(Design.Text.statusDetail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Design.Space.small)

            Circle()
                .fill(presentation.isError ? Design.Color.danger : headerAccent)
                .frame(width: Design.Layout.statusDot, height: Design.Layout.statusDot)
                .shadow(
                    color: (presentation.isError ? Design.Color.danger : headerAccent)
                        .opacity(Design.Glow.statusDot.alpha),
                    radius: Design.Glow.statusDot.radius)
        }
        .padding(.horizontal, Design.Space.panelGutter)
        .padding(.top, Design.Space.menuHeaderTop)
        .padding(.bottom, Design.Space.menuGutter)
    }

    private var lastCommand: some View {
        VStack(alignment: .leading, spacing: Design.Space.micro) {
            Label("Last command", systemImage: "text.quote")
                .font(Design.Text.eyebrow)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(Design.Tracking.eyebrow)

            Text(MenuTranscriptSummary.format(model.lastTranscript, maximumLength: 92))
                .font(Design.Text.rowTranscript)
                .foregroundStyle(.primary.opacity(Design.Alpha.inkTranscript))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Space.card)
        .background(
            .primary.opacity(Design.Alpha.fillChip),
            in: RoundedRectangle(cornerRadius: Design.Radius.row))
        .padding(.horizontal, Design.Space.menuGutter)
        .padding(.bottom, Design.Space.card)
    }

    private var profileList: some View {
        let listeningControl = MenuListeningControlPresentation.make(
            isListening: model.passiveEnabled)

        return VStack(alignment: .leading, spacing: Design.Space.row) {
            HStack(spacing: Design.Space.small) {
                Text("Profiles")
                    .font(Design.Text.eyebrow)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(Design.Tracking.eyebrow)

                Spacer()

                Button {
                    model.togglePassiveListening()
                } label: {
                    Label(listeningControl.title, systemImage: listeningControl.symbolName)
                        .font(Design.Text.eyebrowControl)
                        .padding(.horizontal, Design.Space.small)
                        .padding(.vertical, Design.Space.tiny)
                        .foregroundStyle(
                            model.passiveEnabled ? Design.Color.accentFallback : headerAccent)
                        .background(.primary.opacity(Design.Alpha.fillChip), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(
                                    .white.opacity(Design.Alpha.hairlineChip),
                                    lineWidth: Design.Border.default)
                        }
                }
                .buttonStyle(.plain)
                .help("\(listeningControl.title) wake phrase listening")
                .accessibilityLabel("\(listeningControl.title) wake phrase listening")
            }
            .padding(.horizontal, Design.Space.tiny)

            ScrollView {
                LazyVStack(spacing: Design.Space.row) {
                    ForEach(model.activeWakeProfiles) { profile in
                        MenuProfileRow(profile: profile) {
                            model.setWakeProfileEnabled(profile.id, enabled: !profile.isEnabled)
                        }
                    }
                }
            }
            .frame(height: MenuProfileListLayout.height(
                profileCount: model.activeWakeProfiles.count))
        }
        .padding(.horizontal, Design.Space.menuGutter)
        .padding(.bottom, Design.Space.menuGutter)
    }

    private func agentRunControls(_ snapshot: AgentRunSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.small) {
            HStack {
                Label {
                    Text(snapshot.profileName)
                } icon: {
                    ProfileIconGlyph(icon: snapshot.profileIcon)
                }
                    .font(Design.Text.badgeTitle)
                    .foregroundStyle(snapshot.accent.swiftUIColor)
                Spacer()
                Text(snapshot.hasActiveBackgroundTasks && snapshot.phase != .running
                    ? "Working in background"
                    : agentRunPhaseLabel(snapshot.phase))
                    .font(Design.Text.eyebrowControl)
                    .foregroundStyle(.secondary)
            }

            if snapshot.phase.isTerminal && snapshot.canCloseOrDelete {
                HStack(spacing: Design.Space.small) {
                    Spacer(minLength: 0)

                    Button(role: .destructive) {
                        model.deleteAgentRun()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        model.showAgentRun()
                    } label: {
                        Label("Open", systemImage: "rectangle.on.rectangle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(snapshot.accent.swiftUIColor)
                }
            } else {
                HStack(spacing: Design.Space.small) {
                    Spacer(minLength: 0)

                    Button {
                        model.showAgentRun()
                    } label: {
                        Label("Open", systemImage: "rectangle.on.rectangle")
                    }
                    .buttonStyle(.bordered)

                    if snapshot.phase == .running || snapshot.phase == .listening {
                        Button {
                            model.cancelAgentRun(runID: snapshot.runID)
                        } label: {
                            Label(snapshot.phase == .listening ? "Stop listening" : "Stop turn",
                                systemImage: "stop.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Design.Color.danger.opacity(Design.Alpha.inkStopTurn))
                    } else if snapshot.phase == .paused {
                        Button("Resume listening", systemImage: "mic") {
                            model.resumeAgentConversationListening(runID: snapshot.runID)
                        }
                        .buttonStyle(.borderedProminent)
                    } else if snapshot.phase == .cancelling {
                        Button("Cancelling…") {}
                            .buttonStyle(.bordered)
                            .disabled(true)
                    }
                }

                HStack {
                    Spacer(minLength: 0)

                    Button {
                        model.endAgentConversation(runID: snapshot.runID)
                    } label: {
                        Label(
                            "End conversation",
                            systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(Design.Space.card)
        .background(
            snapshot.accent.swiftUIColor.opacity(Design.Alpha.accentWashCard),
            in: RoundedRectangle(cornerRadius: Design.Radius.row))
        .overlay {
            RoundedRectangle(cornerRadius: Design.Radius.row)
                .stroke(
                    snapshot.accent.swiftUIColor.opacity(Design.Alpha.accentWashHeader),
                    lineWidth: Design.Border.default)
        }
        .padding(.horizontal, Design.Space.menuGutter)
        .padding(.bottom, Design.Space.card)
    }

    private var backgroundSessions: some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text("Background sessions")
                .font(Design.Text.eyebrow)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(Design.Tracking.eyebrow)
            ForEach(model.activeAgentBackgroundSessions) { session in
                Button {
                    model.showAgentBackgroundSession(session.key)
                } label: {
                    HStack {
                        Label(session.profileName, systemImage: "clock.arrow.2.circlepath")
                        Spacer()
                        Text("\(session.activeTaskCount)")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(session.profileName), \(session.activeTaskCount) active background tasks")
            }
        }
        .padding(Design.Space.card)
        .background(
            .primary.opacity(Design.Alpha.fillField),
            in: RoundedRectangle(cornerRadius: Design.Radius.row))
        .padding(.horizontal, Design.Space.menuGutter)
        .padding(.bottom, Design.Space.card)
    }

    private var interruptedBackgroundWork: some View {
        Label("Interrupted when YapOps exited", systemImage: "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Design.Space.panelGutter)
            .padding(.bottom, Design.Space.card)
    }

    private func agentRunPhaseLabel(_ phase: AgentRunPhase) -> String {
        switch phase {
        case .listening: "Listening"
        case .paused: "Paused · Microphone off"
        case .running: "Running"
        case .cancelling: "Cancelling"
        case let .completed(reason): reason == .cancelled ? "Cancelled" : "Completed"
        case .failed: "Failed"
        }
    }

    private var cancelButton: some View {
        Button {
            model.cancelCapture()
        } label: {
            Label("Cancel recording", systemImage: "xmark.circle.fill")
                .font(Design.Text.actionLabel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Space.row)
        }
        .buttonStyle(.borderedProminent)
        .tint(Design.Color.danger.opacity(Design.Alpha.inkCancel))
        .keyboardShortcut(.cancelAction)
        .padding(.horizontal, Design.Space.menuGutter)
        .padding(.bottom, Design.Space.menuGutter)
    }

    private var footer: some View {
        HStack(spacing: Design.Space.small) {
            Button {
                dismiss()
                SettingsWindowPresenter.live.open {
                    openSettings()
                }
            } label: {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .keyboardShortcut(",")

            Spacer()

            Button {
                Task { @MainActor in
                    await model.shutdown()
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("q")
        }
        .font(Design.Text.footer)
        .buttonStyle(.plain)
        .padding(.horizontal, Design.Space.panelGutter)
        .padding(.vertical, Design.Space.header)
        .background(.primary.opacity(Design.Alpha.fill))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var panelBackground: some View {
        ZStack {
            Rectangle()
                .fill(Design.Material.floating)

            Design.Wash.menu(headerAccent)
        }
    }

    private var headerAccent: Color {
        model.activeWakeProfiles.first(where: \.isEnabled)?.accent.swiftUIColor
            ?? Design.Color.accentFallback
    }

    private var layoutIdentity: MenuContentLayoutIdentity {
        let agentControls: MenuContentLayoutIdentity.AgentControls
        if let snapshot = model.agentRunSnapshot {
            agentControls = snapshot.phase.isTerminal ? .terminal : .active
        } else {
            agentControls = .hidden
        }
        return MenuContentLayoutIdentity(
            showsLastCommand: !model.lastTranscript.isEmpty,
            agentControls: agentControls,
            profileCount: model.activeWakeProfiles.count,
            showsCaptureCancellation: model.state == .capturing)
    }
}

private struct MenuProfileRow: View {
    let profile: WakeProfile
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Space.cardTight) {
                ZStack {
                    Circle()
                        .fill(profile.accent.swiftUIColor.opacity(
                            profile.isEnabled
                                ? Design.Alpha.accentWashAvatar
                                : Design.Alpha.accentWashAvatarDisabled))

                    profileIcon
                        .font(Design.Text.glyph(Design.Glyph.row))
                        .foregroundStyle(
                            profile.isEnabled ? profile.accent.swiftUIColor : .secondary)
                }
                .frame(width: Design.Layout.profileAvatar, height: Design.Layout.profileAvatar)

                VStack(alignment: .leading, spacing: Design.Space.hairline) {
                    Text(profile.name)
                        .font(Design.Text.rowTitle)
                        .foregroundStyle(.primary)

                    Text("“\(profile.wakePhrase)” · \(profileDetail)")
                        .font(Design.Text.rowDetail)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: Design.Space.small)

                Image(systemName: profile.isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(Design.Text.glyph(Design.Glyph.status, weight: .medium))
                    .foregroundStyle(
                        profile.isEnabled
                            ? profile.accent.swiftUIColor
                            : Design.Color.accentFallback.opacity(Design.Alpha.inkMuted))
            }
            .padding(.horizontal, Design.Space.rowInset)
            .padding(.vertical, Design.Space.small)
            .contentShape(RoundedRectangle(cornerRadius: Design.Radius.row))
            .background(
                Color.primary.opacity(
                    isHovering ? Design.Alpha.fillHover : Design.Alpha.fill),
                in: RoundedRectangle(cornerRadius: Design.Radius.row))
            .overlay {
                RoundedRectangle(cornerRadius: Design.Radius.row)
                    .stroke(
                        .white.opacity(
                            isHovering ? Design.Alpha.hairlineHover : Design.Alpha.hairline),
                        lineWidth: Design.Border.default)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(profile.name), trigger phrase \(profile.wakePhrase)")
        .accessibilityValue(profile.isEnabled ? "Enabled" : "Disabled")
    }

    private var profileDetail: String {
        if let hotKey = profile.pushToTalkHotKey {
            "\(hotKey.displayName)  ·  Hold to talk"
        } else {
            profile.isEnabled ? "Wake phrase active" : "Wake phrase paused"
        }
    }

    @ViewBuilder
    private var profileIcon: some View {
        if profile.isEnabled {
            ProfileIconGlyph(icon: profile.icon)
        } else {
            Image(systemName: "slash.circle")
        }
    }
}
