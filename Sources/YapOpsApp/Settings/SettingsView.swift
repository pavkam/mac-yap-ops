// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import YapOpsCore

struct SettingsView: View {
    @Bindable var model: AppModel
    @Bindable var launchAtLogin: LaunchAtLoginSetting
    @Binding var selectedPane: SettingsPane
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var saved = false

    var body: some View {
        TabView(selection: $selectedPane) {
            Tab(SettingsPane.general.title, systemImage: SettingsPane.general.symbol, value: .general) {
                pane { generalSettings }
            }
            Tab(SettingsPane.profiles.title, systemImage: SettingsPane.profiles.symbol, value: .profiles) {
                pane { profileSettings }
            }
            Tab(SettingsPane.speech.title, systemImage: SettingsPane.speech.symbol, value: .speech) {
                pane { speechSettings }
            }
        }
        .frame(width: 720, height: selectedPane == .general ? 420 : 660)
        .navigationTitle(selectedPane.title)
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

    private func pane<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
                .disabled(model.isSavingSettings || !model.isStartupReady)
            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var generalSettings: some View {
        Form {
            Section {
                SettingsToggleRow(
                    title: "Launch at Login",
                    detail: "Start YapOps when you log in. Changes apply immediately.",
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
            } header: {
                Label("Startup", systemImage: "power")
            }
            Section {
                MacContextSettingsSection(model: model)
            } header: {
                Label("Mac context", systemImage: "macwindow")
            }
        }
        .formStyle(.grouped)
    }

    private var profileSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your assistants")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text("Set each profile’s trigger, action, shortcut, and reply voice.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        model.wakeProfiles.append(WakeProfileDraft(
                            wakePhrase: "",
                            urlTemplate: "https://www.google.com/search?q={urlText}",
                            accent: nextAccent))
                    } label: {
                        Label("Add Profile", systemImage: "plus")
                    }
                }
                ForEach($model.wakeProfiles) { $profile in
                    ProfileSettingsEditor(model: model, profile: $profile)
                }
            }
            .padding(20)
        }
    }

    private var speechSettings: some View {
        Form {
            Section {
                SpeechLocalePicker(localeID: $model.localeID)
                SettingsToggleRow(
                    title: "Always listen for wake phrases",
                    detail: "Recognition stays on-device. Changes apply immediately.",
                    isOn: Binding(
                        get: { model.passiveEnabled },
                        set: { model.setPassiveEnabled($0) }))
            } header: {
                Label("Listening", systemImage: "mic")
            } footer: {
                Label(
                    "Push to talk may use Apple’s speech service when on-device recognition is unavailable.",
                    systemImage: "lock.shield")
            }
            SpeechSettingsContent(model: model)
        }
        .formStyle(.grouped)
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
                Text("Save applies changes in all tabs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Save Settings") {
                Task { @MainActor in
                    saved = await SettingsSaveHandler.perform(
                        save: model.saveSettings,
                        close: {
                            dismissWindow()
                        })
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(model.isSavingSettings || !model.isStartupReady)
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
