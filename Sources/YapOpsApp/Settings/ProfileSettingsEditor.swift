// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import YapOpsCore

struct ProfileSettingsEditor: View {
    private static let curatedSymbols = [
        "sparkles", "waveform", "brain.head.profile", "terminal", "hammer",
        "magnifyingglass", "doc.text", "lightbulb", "music.note", "wand.and.stars",
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    let model: AppModel
    @Binding var profile: WakeProfileDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            identityHeader
            Divider()
            triggerEditor
            iconEditor
            targetEditor
            Divider()
            speechEditor
            Divider()
            shortcutEditor
        }
        .padding(15)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    contrast == .increased ? Color.primary.opacity(0.5)
                        : Color(nsColor: .separatorColor),
                    lineWidth: 1)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: profile.targetKind)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: speechMode)
    }

    private var identityHeader: some View {
        HStack(spacing: 11) {
            ProfileIconBadge(icon: profile.icon, accent: profile.accent)
            TextField("Profile name", text: $profile.name)
                .accessibilityLabel("Profile name")
                .font(.headline)
                .textFieldStyle(.roundedBorder)
            Toggle("Enabled", isOn: $profile.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .help(profile.isEnabled ? "Disable profile" : "Enable profile")
            Picker("Color", selection: $profile.accent) {
                ForEach(WakeProfileAccent.allCases, id: \.self) { accent in
                    Label {
                        Text(accent.displayName)
                    } icon: {
                        Image(nsImage: WakeProfileAccentSwatch.image(for: accent))
                            .renderingMode(.original)
                    }
                    .tag(accent)
                }
            }
            .labelsHidden()
            .frame(width: 110)
            Button(role: .destructive) {
                model.wakeProfiles.removeAll { $0.id == profile.id }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(model.wakeProfiles.count == 1)
            .help("Remove profile")
            .accessibilityLabel("Remove profile")
        }
    }

    private var triggerEditor: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Trigger phrase")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField("computer", text: $profile.wakePhrase)
                .accessibilityLabel("Trigger phrase")
                .textFieldStyle(.roundedBorder)
            Text("Detecting this phrase selects the profile for the entire conversation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var iconEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Icon")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Picker("Icon kind", selection: iconKind) {
                    Text("SF Symbol").tag(ProfileIconKind.systemSymbol)
                    Text("Emoji").tag(ProfileIconKind.emoji)
                }
                .labelsHidden()
                .frame(width: 110)

                switch profile.icon {
                case .systemSymbol:
                    TextField("SF Symbol name", text: systemSymbolName)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                    Menu {
                        ForEach(Self.curatedSymbols, id: \.self) { name in
                            Button { profile.icon = .systemSymbol(name) } label: {
                                Label(name, systemImage: name)
                            }
                        }
                    } label: {
                        Label("Browse", systemImage: "square.grid.2x2")
                    }
                case .emoji:
                    TextField("Emoji", text: emoji)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }
            }
        }
    }

    @ViewBuilder
    private var targetEditor: some View {
        Picker("Target", selection: targetKind) {
            Text("Command").tag(WakeProfileTargetKind.command)
            Text("Agent").tag(WakeProfileTargetKind.agent)
        }
        .pickerStyle(.segmented)

        switch profile.targetKind {
        case .command:
            commandEditor
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
        case .agent:
            AgentHarnessSettingsView(profile: $profile)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
        }
    }

    private var speechEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reply voice").fontWeight(.medium)
                    Text("Pinned when this profile starts a conversation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Reply voice", selection: speechModeBinding) {
                    Text("Inherit").tag(ProfileSpeechMode.inherit)
                    Text("Off").tag(ProfileSpeechMode.disabled)
                    Text("Custom").tag(ProfileSpeechMode.voice)
                }
                .labelsHidden()
                .frame(width: 150)
            }

            if speechMode == .voice {
                TextToSpeechVoiceSelectionEditor(
                    model: model,
                    selection: explicitSpeechSelection,
                    previewContext: .profile(profile.id))
                    .padding(.leading, 8)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var shortcutEditor: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Push to talk").fontWeight(.medium)
                Text("This shortcut selects the same profile without a wake phrase.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HotKeyRecorderView(
                hotKey: profile.pushToTalkHotKey,
                onChange: { model.setPushToTalkHotKey($0, for: profile.id) },
                onClear: { model.setPushToTalkHotKey(nil, for: profile.id) },
                onRecordingChange: model.setPushToTalkShortcutRecording)
        }
    }

    private var commandEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            labeledTextField(
                "Executable",
                hint: "/usr/bin/open",
                text: $profile.executablePath)
            ArgumentDraftEditor(arguments: $profile.commandArguments)
            Text("Use {text} for literal speech or {urlText} for URL-encoded speech.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func labeledTextField(
        _ title: String,
        hint: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            TextField(hint, text: text)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
        }
    }

    private var targetKind: Binding<WakeProfileTargetKind> {
        Binding(
            get: { profile.targetKind },
            set: { profile.selectTarget($0) })
    }

    private var iconKind: Binding<ProfileIconKind> {
        Binding(
            get: {
                switch profile.icon {
                case .systemSymbol: .systemSymbol
                case .emoji: .emoji
                }
            },
            set: {
                profile.icon = $0 == .systemSymbol
                    ? .systemSymbol("sparkles")
                    : .emoji("🤖")
            })
    }

    private var systemSymbolName: Binding<String> {
        Binding(
            get: {
                guard case .systemSymbol(let name) = profile.icon else { return "" }
                return name
            },
            set: { profile.icon = .systemSymbol($0) })
    }

    private var emoji: Binding<String> {
        Binding(
            get: {
                guard case .emoji(let value) = profile.icon else { return "" }
                return value
            },
            set: { profile.icon = .emoji(String($0.prefix(1))) })
    }

    private var speechMode: ProfileSpeechMode {
        switch profile.speechPreference {
        case .inherit: .inherit
        case .disabled: .disabled
        case .voice: .voice
        }
    }

    private var speechModeBinding: Binding<ProfileSpeechMode> {
        Binding(
            get: { speechMode },
            set: {
                switch $0 {
                case .inherit: profile.speechPreference = .inherit
                case .disabled: profile.speechPreference = .disabled
                case .voice: profile.speechPreference = .voice(model.defaultSpeechVoice)
                }
            })
    }

    private var explicitSpeechSelection: Binding<TextToSpeechVoiceSelection> {
        Binding(
            get: {
                guard case .voice(let selection) = profile.speechPreference else {
                    return model.defaultSpeechVoice
                }
                return selection
            },
            set: { profile.speechPreference = .voice($0) })
    }
}

private enum ProfileIconKind: Hashable {
    case systemSymbol
    case emoji
}

private enum ProfileSpeechMode: Hashable {
    case inherit
    case disabled
    case voice
}

private struct ProfileIconBadge: View {
    let icon: ProfileIcon
    let accent: WakeProfileAccent

    var body: some View {
        ProfileIconGlyph(icon: icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(accent.swiftUIColor)
            .frame(width: 36, height: 36)
            .background(
                accent.swiftUIColor.opacity(0.13),
                in: RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("Profile icon")
    }
}

private struct ArgumentDraftEditor: View {
    @Binding var arguments: ArgumentDraftCollection

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Argument templates")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            ForEach($arguments.rows) { $argument in
                HStack(spacing: 6) {
                    TextField("Argument containing {text}", text: $argument.value)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) {
                        arguments.remove(id: argument.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button { arguments.append() } label: {
                Label("Add argument", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}
