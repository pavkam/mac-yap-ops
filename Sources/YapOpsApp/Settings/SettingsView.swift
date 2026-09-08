// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import YapOpsCore

struct SettingsView: View {
    @Bindable var model: AppModel
    @Bindable var launchAtLogin: LaunchAtLoginSetting
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var saved = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    applicationSection
                    voiceSection
                    conversationSection
                    privacyNote
                }
                .padding(28)
            }
            .disabled(model.isSavingSettings || !model.isStartupReady)

            Divider()
            footer
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background {
                    if reduceTransparency {
                        Color(nsColor: .windowBackgroundColor)
                    } else {
                        Rectangle().fill(.bar)
                    }
                }
        }
        .frame(width: 720, height: 740)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.wakeProfiles) { saved = false }
        .onChange(of: model.localeID) { saved = false }
        .onChange(of: model.readsAgentRepliesAloud) { saved = false }
        .onChange(of: model.playsAgentWorkingSound) { saved = false }
        .onChange(of: model.capturesMacContext) { saved = false }
        .onChange(of: model.defaultSpeechVoice) { saved = false }
        .onChange(of: model.elevenLabsAPIKey) { saved = false }
        .task(id: model.isStartupReady) {
            guard model.isStartupReady else { return }
            await launchAtLogin.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            YapOpsMark(tint: headerTint)
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("YapOps")
                    .font(.title2.weight(.semibold))
                Text("Use your voice to work with what’s on your Mac.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(
                model.statusPresentation.title,
                systemImage: model.statusPresentation.symbolName)
                .font(.caption.weight(.medium))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(statusColor.opacity(0.12), in: Capsule())
        }
    }

    private var applicationSection: some View {
        SettingsCard(
            title: "Application settings",
            subtitle: "Control how YapOps integrates with macOS.",
            systemImage: SettingsSectionSymbol.application.rawValue)
        {
            SettingsToggleRow(
                title: "Launch at Login",
                detail: "Start YapOps when you log in to your Mac. Changes apply immediately.",
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { enabled in
                        Task { await launchAtLogin.setEnabled(enabled) }
                    }),
                isBusy: launchAtLogin.isBusy)

            if let error = launchAtLogin.errorMessage {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            MacContextSettingsSection(model: model)
        }
    }

    private var conversationSection: some View {
        SettingsCard(
            title: "Speech and activity",
            subtitle: "Choose how your assistants sound and when they speak.",
            systemImage: SettingsSectionSymbol.agentConversation.rawValue)
        {
            SpeechSettingsContent(model: model)
        }
    }

    private var voiceSection: some View {
        SettingsCard(
            title: "Profiles",
            subtitle: "Give each assistant its own identity, trigger, action, and voice.",
            systemImage: SettingsSectionSymbol.voiceTrigger.rawValue)
        {
            SpeechLocalePicker(localeID: $model.localeID)

            Divider()

            VStack(spacing: 12) {
                ForEach($model.wakeProfiles) { $profile in
                    ProfileSettingsEditor(model: model, profile: $profile)
                }

                Button {
                    model.wakeProfiles.append(WakeProfileDraft(
                        wakePhrase: "",
                        urlTemplate: "https://www.google.com/search?q={urlText}",
                        accent: nextAccent))
                } label: {
                    Label("Add profile", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            SettingsToggleRow(
                title: "Always listen for wake phrases",
                detail: "Recognition stays on-device. Changes apply immediately.",
                isOn: Binding(
                    get: { model.passiveEnabled },
                    set: { model.setPassiveEnabled($0) }))
        }
    }

    private var privacyNote: some View {
        Label {
            Text("Push to talk may use Apple’s speech service when on-device recognition is unavailable.")
        } icon: {
            Image(systemName: "lock.shield")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private var footer: some View {
        HStack {
            if let error = model.settingsError {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if saved {
                Label("Settings saved", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                Text("Save to apply profile, speech, and context changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Save Settings") {
                Task { @MainActor in
                    saved = await SettingsSaveHandler.perform(
                        save: model.saveSettings,
                        close: {
                            dismissWindow(id: SettingsWindowPresenter.windowID)
                        })
                }
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .disabled(model.isSavingSettings || !model.isStartupReady)
        }
    }

    private var statusColor: Color {
        switch model.state {
        case .failed:
            .red
        case .capturing, .executing:
            .orange
        case .listening:
            .green
        case .disabled:
            .secondary
        }
    }

    private var headerTint: Color {
        model.wakeProfiles.first(where: \WakeProfileDraft.isEnabled)?.accent.swiftUIColor
            ?? .cyan
    }

    private var nextAccent: WakeProfileAccent {
        let accents = WakeProfileAccent.allCases
        return accents[model.wakeProfiles.count % accents.count]
    }
}

extension WakeProfileAccent {
    var displayName: String { rawValue.capitalized }

    var swiftUIColor: Color {
        switch self {
        case .cyan: .cyan
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .orange: .orange
        case .green: .green
        }
    }
}

struct SettingsCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content
        }
        .padding(18)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor))
            } else {
                RoundedRectangle(cornerRadius: 14).fill(.regularMaterial)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    contrast == .increased
                        ? Color.primary.opacity(0.5)
                        : Color(nsColor: .separatorColor).opacity(0.65),
                    lineWidth: 1)
        }
    }
}
