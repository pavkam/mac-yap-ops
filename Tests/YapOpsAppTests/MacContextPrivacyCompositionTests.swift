// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AppKit
import Testing

@testable import YapOpsApp
@testable import YapOpsCore

extension AppModelTests {
    @MainActor @Test
    func saveSettings_WhileAgentResetIsSuspended_KeepsMacContextStateUntilCommit()
        async throws
    {
        let profile = try makeAgentProfile(executablePath: "/agents/original")
        let runner = AppModelAgentRunnerSpy()
        await runner.delayReset()
        let target = macContextTarget()
        let capturer = MacContextCapturerSpy(target: target)
        let fixture = try Fixture(
            profiles: [profile],
            agentRunner: runner,
            macContextCapturer: capturer,
            isExecutableFile: { _ in true },
            isDirectory: { _ in true })
        await fixture.startForExternalActions()
        fixture.model.wakeProfiles[0].agentHarness.executablePath = "/agents/changed"
        fixture.model.capturesMacContext = false

        let save = Task { @MainActor in await fixture.model.saveSettings() }
        await runner.waitUntilResetIsWaiting()

        #expect(fixture.preferences.capturesMacContext)
        #expect(fixture.model.coordinator.macContextCapturer.currentTarget() == target)

        await runner.releaseReset()
        #expect(await save.value)
        #expect(!fixture.preferences.capturesMacContext)
        #expect(fixture.model.coordinator.macContextCapturer.currentTarget() == nil)
    }

    @MainActor @Test
    func saveSettings_WhenHotKeyApplyFails_PreservesPersistedAndRuntimeMacContextState()
        async throws
    {
        let target = macContextTarget()
        let capturer = MacContextCapturerSpy(target: target)
        let fixture = try Fixture(macContextCapturer: capturer)
        await fixture.startForExternalActions()
        fixture.model.capturesMacContext = false
        fixture.shortcut.failNextStart = true

        let saved = await fixture.model.saveSettings()

        #expect(!saved)
        #expect(fixture.preferences.capturesMacContext)
        #expect(fixture.model.coordinator.macContextCapturer.currentTarget() == target)
    }

    @MainActor @Test
    func saveSettings_WhenCredentialStorageFails_PreservesPersistedAndRuntimeMacContextState()
        async throws
    {
        let target = macContextTarget()
        let capturer = MacContextCapturerSpy(target: target)
        let fixture = try Fixture(
            agentSpeechCredentialStore: FailingMacContextCredentialStore(),
            macContextCapturer: capturer)
        await fixture.startForExternalActions()
        fixture.model.capturesMacContext = false

        let saved = await fixture.model.saveSettings()

        #expect(!saved)
        #expect(fixture.preferences.capturesMacContext)
        #expect(fixture.model.coordinator.macContextCapturer.currentTarget() == target)
    }

    @MainActor @Test
    func applicationActivationMonitor_WhenNotificationsArrive_RefreshesOncePerActiveEventOnly()
        async throws
    {
        let notificationCenter = NotificationCenter()
        let access = MacContextAccessSpy(status: .authorized)
        let fixture = try Fixture(macContextAccess: access)
        #expect(await fixture.model.start())
        let startupStatusChecks = access.statusChecks
        let monitor = ApplicationActivationMonitor(notificationCenter: notificationCenter)
        monitor.start(model: fixture.model)

        notificationCenter.post(name: NSApplication.didResignActiveNotification, object: nil)
        notificationCenter.post(name: NSApplication.didHideNotification, object: nil)
        #expect(access.statusChecks == startupStatusChecks)

        notificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        notificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        #expect(access.statusChecks == startupStatusChecks + 2)
        #expect(access.promptingChecks == 0)
        #expect(fixture.model.macContextAccessStatus == .authorized)
        monitor.stop()
    }

    @MainActor
    private func macContextTarget() -> MacContextTarget {
        MacContextTarget(
            processIdentifier: 42,
            applicationName: "Safari",
            bundleIdentifier: "com.apple.Safari")
    }
}

@MainActor
private final class FailingMacContextCredentialStore: AgentSpeechCredentialStoring {
    func loadElevenLabsAPIKey() async throws -> String? {
        nil
    }

    func saveElevenLabsAPIKey(_ apiKey: String?) throws {
        throw MacContextCredentialTestError.storageFailed
    }
}

private enum MacContextCredentialTestError: Error {
    case storageFailed
}
