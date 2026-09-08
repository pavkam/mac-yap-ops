// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import YapOpsCore

struct TextToSpeechVoiceSelectionEditor: View {
    @Bindable var model: AppModel
    @Binding var selection: TextToSpeechVoiceSelection
    let previewContext: TextToSpeechVoicePreviewContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Voice provider")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Voice provider", selection: backendID) {
                    ForEach(model.textToSpeechBackends) { backend in
                        Text(backend.displayName).tag(backend.id)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }

            HStack(spacing: 10) {
                Text("Voice")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                voiceControl
                if model.isLoadingTextToSpeechVoices(selection.backendID) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading voices")
                }
                Button {
                    Task { await model.loadTextToSpeechVoices(for: selection.backendID) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Refresh voices")
                .help("Refresh \(selectedBackendName) voices")
                .disabled(model.isLoadingTextToSpeechVoices(selection.backendID))

                Button {
                    if isPreviewing {
                        model.stopTextToSpeechVoicePreview()
                    } else {
                        Task {
                            await model.previewTextToSpeechVoice(
                                selection,
                                in: previewContext)
                        }
                    }
                } label: {
                    Label(
                        isPreviewing ? "Stop" : "Test voice",
                        systemImage: isPreviewing ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(isPreviewing ? .secondary : .accentColor)
                .frame(minWidth: 88)
                .help(isPreviewing ? "Stop voice preview" : "Play a short voice preview")
            }

            if let error = model.textToSpeechVoiceErrors[selection.backendID] {
                VoiceSelectionStatus(
                    kind: .failure,
                    title: "Voices could not load",
                    detail: error)
                    .transition(.opacity)
            } else if isPreviewing {
                VoiceSelectionStatus(
                    kind: .progress,
                    title: "Testing \(selectedBackendName) voice",
                    detail: "Preparing a short sample, then playing it through the current output.")
                    .transition(.opacity)
            } else if let feedback = model.textToSpeechVoicePreviewFeedback[previewContext] {
                VoiceSelectionStatus(
                    kind: feedback.kind == .success ? .success : .failure,
                    title: feedback.title,
                    detail: feedback.detail)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.16), value: isPreviewing)
        .animation(
            .easeOut(duration: 0.16),
            value: model.textToSpeechVoicePreviewFeedback[previewContext])
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
                    Text("Match speech language").tag("")
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
            .frame(minWidth: 220, maxWidth: 340)
        }
    }

    private var backendID: Binding<TextToSpeechBackendID> {
        Binding(
            get: { selection.backendID },
            set: { backendID in
                model.clearTextToSpeechVoicePreviewFeedback(in: previewContext)
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
                model.clearTextToSpeechVoicePreviewFeedback(in: previewContext)
                selection = TextToSpeechVoiceSelection(
                    backendID: selection.backendID,
                    voiceID: $0)
            })
    }

    private func voiceLabel(_ voice: TextToSpeechVoice) -> String {
        guard let localeID = voice.localeID else { return voice.name }
        return "\(voice.name) · \(localeID)"
    }

    private var isPreviewing: Bool {
        model.isPreviewingTextToSpeechVoice(in: previewContext)
    }

    private var selectedBackendName: String {
        model.textToSpeechBackends.first(where: { $0.id == selection.backendID })?.displayName
            ?? selection.backendID.rawValue
    }
}

private struct VoiceSelectionStatus: View {
    enum Kind {
        case progress
        case success
        case failure
    }

    let kind: Kind
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            statusSymbol
                .frame(width: 16, height: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(titleColor)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusSymbol: some View {
        switch kind {
        case .progress:
            ProgressView().controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var titleColor: Color {
        kind == .failure ? .red : .primary
    }

    private var backgroundColor: Color {
        switch kind {
        case .progress: .secondary.opacity(0.08)
        case .success: .green.opacity(0.08)
        case .failure: .red.opacity(0.08)
        }
    }
}
