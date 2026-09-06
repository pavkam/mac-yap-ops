// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Darwin
import Foundation
import SwiftUI
import VoiceActivationCore

@main
struct VoiceActivationApp: App {
    @State private var model: AppModel
    @State private var launchAtLogin: LaunchAtLoginSetting
    @State private var applicationActivationMonitor: ApplicationActivationMonitor

    @MainActor
    init() {
        let diagnostics = VoiceActivationDiagnostics.shared
        do {
            let recorder = try JSONLVoiceActivationDiagnosticRecorder()
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
                "Unable to initialize Voice Activation diagnostics: "
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
        let macContextSnapshotter = SystemMacContextSnapshotter()
        let macContextAccess = MacContextAccessController()
        let model = AppModel(
            preferences: preferences,
            agentSpeechCredentialStore: credentialStore,
            macContextAccess: macContextAccess,
            macContextCapturer: macContextSnapshotter,
            diagnostics: diagnostics)
        let applicationActivationMonitor = ApplicationActivationMonitor()
        applicationActivationMonitor.start(model: model)
        _model = State(initialValue: model)
        _launchAtLogin = State(
            initialValue: LaunchAtLoginSetting(diagnostics: diagnostics))
        _applicationActivationMonitor = State(initialValue: applicationActivationMonitor)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            let presentation = model.statusPresentation

            Image(systemName: presentation.symbolName)
                .accessibilityLabel(presentation.title)
        }
        .menuBarExtraStyle(.window)
        .windowStyle(.plain)

        Window("Voice Activation Settings", id: SettingsWindowPresenter.windowID) {
            SettingsView(model: model, launchAtLogin: launchAtLogin)
                .background(SettingsWindowFrontingView())
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)
    }
}
