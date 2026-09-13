// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import YapOpsCore

/// The Profiles pane, as a master–detail split.
///
/// The previous pane stacked every field of every profile in one `ScrollView`,
/// which grows without bound: with three profiles you scroll past roughly
/// seventy-five controls, and you cannot compare two profiles at all. The
/// sidebar makes the profile set legible at a glance and the detail column
/// edits exactly one profile.
struct ProfilesPane: View {
    @Bindable var model: AppModel
    @State private var selection: WakeProfileDraft.ID?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Design.Layout.settingsSidebar)

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear(perform: selectFirstIfNeeded)
        .onChange(of: model.wakeProfiles.map(\.id), keepSelectionValid)
    }

    // MARK: - Master

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Profiles")
                .font(Design.Text.eyebrow)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(Design.Tracking.eyebrow)
                .padding(.horizontal, Design.Space.menuGutter)
                .padding(.top, Design.Space.menuGutter)
                .padding(.bottom, Design.Space.small)
                .accessibilityAddTraits(.isHeader)

            ScrollView {
                LazyVStack(spacing: Design.Space.tiny) {
                    ForEach($model.wakeProfiles) { $profile in
                        SidebarProfileRow(
                            profile: profile,
                            isSelected: profile.id == selection)
                        {
                            selection = profile.id
                        }
                    }
                }
                .padding(.horizontal, Design.Space.small)
            }

            Divider()

            sidebarFooter
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebarFooter: some View {
        HStack(spacing: Design.Space.tiny) {
            Button(action: addProfile) {
                Image(systemName: "plus")
                    .frame(width: Design.Space.panelGutter, height: Design.Space.panelGutter)
            }
            .buttonStyle(.borderless)
            .help("Add profile")
            .accessibilityLabel("Add profile")

            Button(action: removeSelectedProfile) {
                Image(systemName: "minus")
                    .frame(width: Design.Space.panelGutter, height: Design.Space.panelGutter)
            }
            .buttonStyle(.borderless)
            .disabled(selection == nil || model.wakeProfiles.count == 1)
            .help("Remove profile")
            .accessibilityLabel("Remove profile")

            Spacer()

            Text(profileCountLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Design.Space.card)
        .padding(.vertical, Design.Space.small)
    }

    private var profileCountLabel: String {
        model.wakeProfiles.count == 1 ? "1 profile" : "\(model.wakeProfiles.count) profiles"
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let index = selectedIndex {
            ScrollView {
                ProfileSettingsEditor(model: model, profile: $model.wakeProfiles[index])
                    .padding(Design.Space.panelContent)
            }
            .profileAccent(model.wakeProfiles[index].accent)
        } else {
            SettingsEmptyState(
                symbol: "person.crop.circle.badge.plus",
                title: "No profile selected",
                detail: "Choose a profile to edit, or add one to start listening.")
        }
    }

    private var selectedIndex: Int? {
        guard let selection else { return nil }
        return model.wakeProfiles.firstIndex { $0.id == selection }
    }

    // MARK: - Selection

    private func selectFirstIfNeeded() {
        guard selection == nil else { return }
        selection = model.wakeProfiles.first?.id
    }

    private func keepSelectionValid() {
        guard let selection, model.wakeProfiles.contains(where: { $0.id == selection }) else {
            self.selection = model.wakeProfiles.first?.id
            return
        }
    }

    private func addProfile() {
        let draft = WakeProfileDraft(
            wakePhrase: "",
            urlTemplate: "https://www.google.com/search?q={urlText}",
            accent: nextAccent)
        model.wakeProfiles.append(draft)
        selection = draft.id
    }

    private func removeSelectedProfile() {
        guard let selection, model.wakeProfiles.count > 1 else { return }
        model.wakeProfiles.removeAll { $0.id == selection }
    }

    private var nextAccent: WakeProfileAccent {
        let accents = WakeProfileAccent.allCases
        return accents[model.wakeProfiles.count % accents.count]
    }
}
