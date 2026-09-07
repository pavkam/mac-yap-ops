// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI

struct MacContextSettingsPresentation {
    let accessStatus: MacContextAccessStatus

    let toggleLabel = "Include focused Mac context in agent requests"
    let disclosureText = "When enabled, YapOps sends the focused app’s name and bundle identifier, focused window title and document URL, selected text, and up to eight selected resource links outside YapOps to the selected ACP provider."

    var accessStatusText: String {
        switch accessStatus {
        case .notAuthorized:
            "Accessibility not authorized"
        case .authorized:
            "Accessibility authorized"
        }
    }

    var showsEnableAccessibilityButton: Bool {
        accessStatus == .notAuthorized
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

    private var presentation: MacContextSettingsPresentation {
        MacContextSettingsPresentation(accessStatus: model.macContextAccessStatus)
    }

    private var actions: MacContextSettingsActions {
        MacContextSettingsActions(model: model)
    }

    var body: some View {
        SettingsCard(
            title: "Mac context",
            subtitle: "Choose whether agent requests include context from the focused app.",
            systemImage: "hand.raised.fill")
        {
            Toggle(presentation.toggleLabel, isOn: $model.capturesMacContext)
                .fontWeight(.medium)

            Text(presentation.disclosureText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Label(
                    presentation.accessStatusText,
                    systemImage: model.macContextAccessStatus == .authorized
                        ? "checkmark.shield.fill"
                        : "exclamationmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if presentation.showsEnableAccessibilityButton {
                    Button("Enable Accessibility…", action: actions.enableAccessibility)
                }
            }
        }
        .onAppear(perform: actions.appear)
    }
}
