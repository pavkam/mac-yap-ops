// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Darwin
import Foundation
import SwiftUI
import YapOpsCore

@main
struct YapOpsApp: App {
    @State private var model: AppModel
    @State private var launchAtLogin: LaunchAtLoginSetting
    @State private var applicationStartup: ApplicationStartup
    @State private var preferences: AppPreferences
    @AppStorage("settingsPane") private var settingsPane: SettingsPane = .general
    @Environment(\.openWindow) private var openWindow

    @MainActor
    init() {
        let diagnostics = YapOpsDiagnostics.shared
        do {
            let recorder = try JSONLYapOpsDiagnosticRecorder()
            diagnostics.install(recorder)
            diagnostics.record(
                category: .app,
                event: "application.launched",
                fields: [
                    "app_version": Bundle.main.object(
                        forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                    "build_version": Bundle.main.object(
                        forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                    "operating_system": ProcessInfo.processInfo.operatingSystemVersionString,
                    "log_path": recorder.currentLogURL.path,
                ])
        } catch {
            let message = Data(
                "Unable to initialize YapOps diagnostics: "
                    .appending(error.localizedDescription)
                    .appending("\n")
                    .utf8)
            try? FileHandle.standardError.write(contentsOf: message)
        }

        let credentialStore = KeychainAgentSpeechCredentialStore()
        if CommandLine.arguments.dropFirst().contains(AgentSpeechCredentialBootstrap.argument) {
            diagnostics.record(
                category: .app,
                event: "credential_import.started")
            do {
                if try AgentSpeechCredentialBootstrap.importIfRequested(
                    arguments: CommandLine.arguments,
                    readCredential: { readLine() },
                    store: credentialStore)
                {
                    diagnostics.record(
                        category: .app,
                        event: "credential_import.finished")
                    diagnostics.flush()
                    exit(EXIT_SUCCESS)
                }
            } catch {
                diagnostics.record(
                    category: .app,
                    event: "credential_import.failed",
                    level: .error,
                    fields: ["error_type": String(describing: type(of: error))])
                diagnostics.flush()
                let message = Data("Unable to store the ElevenLabs credential.\n".utf8)
                try? FileHandle.standardError.write(contentsOf: message)
                exit(EXIT_FAILURE)
            }
        }

        let preferences = AppPreferences()
        let continuityStore = UserDefaultsAgentContinuityStore(
            defaults: .standard,
            diagnostics: diagnostics)
        let macContextSnapshotter = SystemMacContextSnapshotter()
        let macContextAccess = MacContextAccessController()
        let composition = YapOpsAppComposition.make(
            continuityStore: continuityStore,
            activationMonitor: ApplicationActivationMonitor(),
            makeAgentRunner: { sharedStore in
                ACPAgentRunner(
                    continuityStore: sharedStore,
                    diagnostics: diagnostics)
            },
            makeModel: { agentRunner, sharedStore in
                AppModel(
                    preferences: preferences,
                    agentRunner: agentRunner,
                    continuityStore: sharedStore,
                    agentSpeechCredentialStore: credentialStore,
                    macContextAccess: macContextAccess,
                    macContextCapturer: macContextSnapshotter,
                    startsAutomatically: false,
                    diagnostics: diagnostics)
            })
        _model = State(initialValue: composition.model)
        _launchAtLogin = State(
            initialValue: LaunchAtLoginSetting(diagnostics: diagnostics))
        _applicationStartup = State(initialValue: composition.startup)
        _preferences = State(initialValue: preferences)
        composition.startup.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            let presentation = model.statusPresentation

            // The label renders at launch regardless of whether the menu is
            // ever opened; MenuBarExtra's content closure does not build until
            // the user clicks the status item, so first run cannot trigger
            // from there.
            Image(systemName: presentation.symbolName)
                .accessibilityLabel(presentation.title)
                .task {
                    // openWindow is unusable for a moment after launch, before
                    // SwiftUI finishes building the scene graph. This is
                    // deliberately independent of AppModel's own startup
                    // (permissions, credential loading): a first-run user by
                    // definition has no stored credential yet, so gating a
                    // welcome window on that chain would make it least likely
                    // to appear for exactly the audience it is for.
                    try? await Task.sleep(for: .milliseconds(200))
                    presentFirstRunIfNeeded()
                }
        }
        .menuBarExtraStyle(.window)
        .windowStyle(.plain)

        Settings {
            SettingsView(model: model, launchAtLogin: launchAtLogin, selectedPane: $settingsPane)
                .background(SettingsWindowFrontingView())
        }
        .windowResizability(.contentSize)

        Window("Welcome to YapOps", id: FirstRunPresenter.windowID) {
            FirstRunView {
                preferences.hasCompletedFirstRun = true
                FirstRunPresenter.dismiss()
            }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

extension YapOpsApp {
    /// Opens the first-run window once, on the first launch only.
    ///
    /// Called from `.onAppear` on the menu content, which is the earliest
    /// SwiftUI gives an `openWindow` action a body to run in — the `init`
    /// above runs before the environment exists.
    @MainActor
    func presentFirstRunIfNeeded() {
        guard !preferences.hasCompletedFirstRun else { return }
        FirstRunPresenter.present(with: openWindow)
    }
}
