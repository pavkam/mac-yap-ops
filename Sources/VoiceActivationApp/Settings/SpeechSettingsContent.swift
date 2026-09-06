// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import VoiceActivationCore

struct SpeechSettingsContent: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsToggle(
                title: "Read inherited replies aloud",
                detail: "Profiles set to Inherit use this app-wide voice.",
                isOn: $model.readsAgentRepliesAloud)

            if model.readsAgentRepliesAloud {
                Divider()
                TextToSpeechVoiceSelectionEditor(
                    model: model,
                    selection: $model.defaultSpeechVoice,
                    previewContext: .defaultVoice)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text("Global ElevenLabs credential")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                SecureField("sk_…", text: $model.elevenLabsAPIKey)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                Label(
                    "Stored once in macOS Keychain and shared by profiles using ElevenLabs.",
                    systemImage: "key.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            settingsToggle(
                title: "Agent activity sounds",
                detail: "Plays distinct thinking, tool-start, completion, and failure cues.",
                isOn: $model.playsAgentWorkingSound)
        }
        .animation(.snappy(duration: 0.22), value: model.readsAgentRepliesAloud)
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

    private func settingsToggle(
        title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden()
        }
    }
}
