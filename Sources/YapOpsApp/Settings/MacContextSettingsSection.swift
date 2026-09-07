// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI

struct MacContextSettingsPresentation {
    enum State {
        case off
        case appOnly
        case ready
    }

    let accessStatus: MacContextAccessStatus
    var isEnabled = true

    let toggleLabel = "Include focused Mac context in agent requests"
    let disclosureText = "When enabled, YapOps sends the focused app’s name and bundle identifier, focused window title and document URL, selected text, and up to eight selected resource links outside YapOps to the selected ACP provider."

    var state: State {
        guard isEnabled else { return .off }
        return accessStatus == .authorized ? .ready : .appOnly
    }

    var accessStatusText: String {
        switch state {
        case .off: "Mac context is off"
        case .appOnly: "App name only"
        case .ready: "Ready for Mac context"
        }
    }

    var detailText: String {
        switch state {
        case .off:
            "Agent requests use only what you say. Turn context on to refer to the app you’re using."
        case .appOnly:
            "Enable Accessibility to include window details, selected text, and selected files."
        case .ready:
            "Say “summarize this” or “use these files.” YapOps includes the selection your app makes available."
        }
    }

    var symbolName: String {
        switch state {
        case .off: "rectangle.slash"
        case .appOnly: "exclamationmark.circle.fill"
        case .ready: "checkmark.circle.fill"
        }
    }

    var showsEnableAccessibilityButton: Bool {
        state == .appOnly
    }
}

@MainActor
struct MacContextSettingsActions {
    let enableAccessibility: () -> Void
    let appear: () -> Void

    init(model: AppModel) {
        enableAccessibility = model.requestMacContextAccess
        appear = model.settingsDidAppear
    }
}

struct MacContextSettingsSection: View {
    @Bindable var model: AppModel

    private var actions: MacContextSettingsActions {
        MacContextSettingsActions(model: model)
    }

    var body: some View {
        MacContextSettingsCard(
            isEnabled: $model.capturesMacContext,
            accessStatus: model.macContextAccessStatus,
            enableAccessibility: actions.enableAccessibility)
            .onAppear(perform: actions.appear)
    }
}

struct MacContextSettingsCard: View {
    @Binding var isEnabled: Bool
    let accessStatus: MacContextAccessStatus
    let enableAccessibility: () -> Void

    private var presentation: MacContextSettingsPresentation {
        MacContextSettingsPresentation(accessStatus: accessStatus, isEnabled: isEnabled)
    }

    private var statusColor: Color {
        switch presentation.state {
        case .off: .secondary
        case .appOnly: .orange
        case .ready: .green
        }
    }

    var body: some View {
        SettingsCard(
            title: "Mac context",
            subtitle: "Give your agent the app, text, and files you’re working with.",
            systemImage: "macwindow")
        {
            Toggle(presentation.toggleLabel, isOn: $isEnabled)
                .fontWeight(.medium)

            HStack(alignment: .top, spacing: 11) {
                Image(systemName: presentation.symbolName)
                    .font(.title3)
                    .foregroundStyle(statusColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.accessStatusText)
                        .font(.callout.weight(.semibold))
                    Text(presentation.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)

            if presentation.showsEnableAccessibilityButton {
                Button("Enable Accessibility…", action: enableAccessibility)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                Text("Approve YapOps in System Settings, then return here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup("What your agent receives") {
                Text(presentation.disclosureText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .font(.caption)

            Text("Save Settings to apply changes. Screenshots and clipboard content are not included.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
