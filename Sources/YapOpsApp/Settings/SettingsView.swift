// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import YapOpsCore

struct SettingsView: View {
    @Bindable var model: AppModel
    @Bindable var launchAtLogin: LaunchAtLoginSetting
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var saved = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    MacContextSettingsSection(model: model)
                    voiceSection
                    conversationSection
                    applicationSection
                    privacyNote
                }
                .padding(28)
            }
            .disabled(model.isSavingSettings || !model.isStartupReady)

            Divider()
            footer
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(.bar)
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
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Launch at Login")
                        .fontWeight(.medium)
                    Text("Managed by macOS in System Settings › General › Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if launchAtLogin.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }

                Toggle(
                    "",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { enabled in
                            Task { await launchAtLogin.setEnabled(enabled) }
                        }))
                    .labelsHidden()
                    .disabled(launchAtLogin.isBusy)
            }

            if let error = launchAtLogin.errorMessage {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
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
            settingsField("Speech locale", hint: "en-US", text: $model.localeID)
                .frame(width: 170)

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

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Always listen for wake phrases")
                        .fontWeight(.medium)
                    Text("Recognition stays on-device while passive listening is enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle(
                    "",
                    isOn: Binding(
                        get: { model.passiveEnabled },
                        set: { model.setPassiveEnabled($0) }))
                    .labelsHidden()
            }
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

    private func settingsField(
        _ title: String,
        hint: String,
        text: Binding<String>,
        monospaced: Bool = false) -> some View
    {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(hint, text: text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textFieldStyle(.roundedBorder)
        }
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

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
    }
}
