// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import VoiceActivationCore

struct TextToSpeechVoiceSelectionEditor: View {
    @Bindable var model: AppModel
    @Binding var selection: TextToSpeechVoiceSelection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Backend")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Backend", selection: backendID) {
                    ForEach(model.textToSpeechBackends) { backend in
                        Text(backend.displayName).tag(backend.id)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }

            HStack(spacing: 8) {
                Text("Voice")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                voiceControl
                if model.isLoadingTextToSpeechVoices(selection.backendID) {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await model.loadTextToSpeechVoices(for: selection.backendID) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh voices")
                .disabled(model.isLoadingTextToSpeechVoices(selection.backendID))
                if selection.backendID == .elevenLabs {
                    Button {
                        Task {
                            await model.previewElevenLabsVoice(
                                voiceID: selection.voiceID ?? "")
                        }
                    } label: {
                        Image(systemName: model.isPreviewingElevenLabsVoice
                            ? "waveform"
                            : "play.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Test voice")
                    .disabled(
                        model.isPreviewingElevenLabsVoice
                            || selection.voiceID == nil
                            || model.elevenLabsAPIKey.trimmingCharacters(
                                in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let error = model.textToSpeechVoiceErrors[selection.backendID] {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var voiceControl: some View {
        let voices = model.availableTextToSpeechVoices(for: selection.backendID)
        if voices.isEmpty {
            TextField("Voice identifier", text: voiceID)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
        } else {
            Picker("Voice", selection: voiceID) {
                if selection.backendID == .system {
                    Text("Automatic for locale").tag("")
                }
                if let selectedID = selection.voiceID,
                    !voices.contains(where: { $0.id == selectedID })
                {
                    Text("Saved voice · \(selectedID)").tag(selectedID)
                }
                ForEach(voices) { voice in
                    Text(voiceLabel(voice)).tag(voice.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 300)
        }
    }

    private var backendID: Binding<TextToSpeechBackendID> {
        Binding(
            get: { selection.backendID },
            set: { backendID in
                let rememberedVoiceID = backendID == .elevenLabs
                    ? model.elevenLabsVoiceID
                    : nil
                selection = TextToSpeechVoiceSelection(
                    backendID: backendID,
                    voiceID: rememberedVoiceID)
            })
    }

    private var voiceID: Binding<String> {
        Binding(
            get: { selection.voiceID ?? "" },
            set: {
                selection = TextToSpeechVoiceSelection(
                    backendID: selection.backendID,
                    voiceID: $0)
            })
    }

    private func voiceLabel(_ voice: TextToSpeechVoice) -> String {
        guard let localeID = voice.localeID else { return voice.name }
        return "\(voice.name) · \(localeID)"
    }
}
