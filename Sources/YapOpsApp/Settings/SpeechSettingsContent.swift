// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import YapOpsCore

struct SpeechSettingsContent: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            Section {
                SettingsToggleRow(
                    title: "Read replies aloud",
                    detail: "Profiles set to Inherit use this app-wide voice.",
                    isOn: $model.readsAgentRepliesAloud)

                if model.readsAgentRepliesAloud {
                    TextToSpeechVoiceSelectionEditor(
                        model: model,
                        selection: $model.defaultSpeechVoice,
                        previewContext: .defaultVoice)
                        .transition(.opacity)
                }
            } header: {
                Label("Spoken replies", systemImage: "speaker.wave.2")
            }

            Section {
                SecureField("API key", text: $model.elevenLabsAPIKey, prompt: Text("sk_…"))
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("ElevenLabs API key")
            } header: {
                Label("ElevenLabs API key", systemImage: "key")
            } footer: {
                Text("Optional. Stored in macOS Keychain and shared by profiles using ElevenLabs.")
            }

            Section {
                SettingsToggleRow(
                    title: "Agent activity sounds",
                    detail: "Plays distinct thinking, tool-start, completion, and failure cues.",
                    isOn: $model.playsAgentWorkingSound)
            } header: {
                Label("Activity sounds", systemImage: "bell")
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.readsAgentRepliesAloud)
        .task {
            for backend in model.textToSpeechBackends where !backend.requiresCredential {
                await model.loadTextToSpeechVoices(for: backend.id)
            }
        }
        .task(id: model.elevenLabsAPIKey) {
            guard !model.elevenLabsAPIKey.trimmingCharacters(
                in: .whitespacesAndNewlines).isEmpty
            else { return }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await model.loadTextToSpeechVoices(for: .elevenLabs)
        }
    }
}
