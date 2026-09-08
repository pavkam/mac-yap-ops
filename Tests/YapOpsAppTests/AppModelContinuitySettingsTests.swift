// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import YapOpsApp
@testable import YapOpsCore

extension AppModelTests {
    enum AgentProfileInvalidationEdit: CaseIterable, Sendable {
        case fingerprintChanged
        case removed
    }

    @MainActor @Test(arguments: AgentProfileInvalidationEdit.allCases)
    func saveSettings_WhenAgentProfileInvalidates_FencesItsScheduledContextTurn(
        edit: AgentProfileInvalidationEdit
    ) async throws {
        let profile = try makeAgentProfile(
            displayName: "Agent",
            executablePath: "/agents/original",
            pushToTalkHotKey: .defaultValue)
        let retained = try commandProfile()
        let store = AppModelContinuityStoreSpy(
            bookmarks: [try continuityBookmark(for: profile)],
            markers: [continuityMarker(for: profile, index: 1)])
        let runner = AppModelAgentRunnerSpy(continuityStore: store)
        let target = MacContextTarget(
            processIdentifier: 42,
            applicationName: "Safari",
            bundleIdentifier: "com.apple.Safari")
        let context = MacContextCapturerSpy(target: target)
        context.delayCapture()
        let fixture = try Fixture(
            profiles: [profile, retained],
            agentRunner: runner,
            continuityStore: store,
            macContextCapturer: context,
            isExecutableFile: { _ in true },
            isDirectory: { _ in true })
        #expect(await fixture.model.start())
        fixture.model.coordinator.pushToTalkPressed(profileID: profile.id)
        fixture.speech.emit("inspect this")
        fixture.model.coordinator.pushToTalkReleased()
        await context.waitUntilCapturing()
        let scheduledTurn = fixture.model.coordinator.executionTask
        switch edit {
        case .fingerprintChanged:
            fixture.model.wakeProfiles[0].agentHarness.executablePath = "/agents/replacement"
        case .removed:
            fixture.model.wakeProfiles = [WakeProfileDraft(profile: retained)]
        }

        #expect(await fixture.model.saveSettings())
        context.releaseCapture()
        await scheduledTurn?.value

        #expect(context.captureCancellationCount == 1)
        #expect(await runner.recordedInvocations().isEmpty)
        #expect((await store.snapshot()).bookmarks.isEmpty)
        #expect((await store.snapshot()).interruptedWork.isEmpty)
    }

    @MainActor @Test
    func saveSettings_WhenAgentProfileIsRemoved_ResetsItsSessionAndBookmark() async throws {
        let removed = try makeAgentProfile()
        let retained = try commandProfile()
        let bookmark = try continuityBookmark(for: removed)
        let marker = continuityMarker(for: removed, index: 1)
        let store = AppModelContinuityStoreSpy(bookmarks: [bookmark], markers: [marker])
        let runner = AppModelAgentRunnerSpy(continuityStore: store)
        let fixture = try Fixture(
            profiles: [removed, retained],
            agentRunner: runner,
            continuityStore: store,
            isExecutableFile: { _ in true },
            isDirectory: { _ in true })
        await fixture.startForExternalActions()
        fixture.model.wakeProfiles = [WakeProfileDraft(profile: retained)]

        let saved = await fixture.model.saveSettings()

        #expect(saved)
        #expect(await runner.recordedResets() == [[removed.id]])
        #expect((await store.snapshot()).bookmarks.isEmpty)
        #expect((await store.snapshot()).interruptedWork.isEmpty)
        #expect(fixture.model.activeWakeProfiles == [retained])
    }

    @MainActor @Test
    func saveSettings_WhenProviderFingerprintChanges_ResetsItsSessionAndBookmark()
        async throws
    {
        let profile = try makeAgentProfile(executablePath: "/agents/original")
        let bookmark = try continuityBookmark(for: profile)
        let marker = continuityMarker(for: profile, index: 1)
        let store = AppModelContinuityStoreSpy(bookmarks: [bookmark], markers: [marker])
        let runner = AppModelAgentRunnerSpy(continuityStore: store)
        let fixture = try Fixture(
            profiles: [profile],
            agentRunner: runner,
            continuityStore: store,
            isExecutableFile: { _ in true },
            isDirectory: { _ in true })
        await fixture.startForExternalActions()
        fixture.model.wakeProfiles[0].agentHarness.executablePath = "/agents/replacement"

        let saved = await fixture.model.saveSettings()

        #expect(saved)
        #expect(await runner.recordedResets() == [[profile.id]])
        #expect((await store.snapshot()).bookmarks.isEmpty)
        #expect((await store.snapshot()).interruptedWork.isEmpty)
    }

    @MainActor @Test
    func saveSettings_WhenOnlyWakePhraseChanges_PreservesSessionBookmark() async throws {
        let profile = try makeAgentProfile()
        let bookmark = try continuityBookmark(for: profile)
        let store = AppModelContinuityStoreSpy(bookmarks: [bookmark])
        let runner = AppModelAgentRunnerSpy(continuityStore: store)
        let fixture = try Fixture(
            profiles: [profile],
            agentRunner: runner,
            continuityStore: store,
            isExecutableFile: { _ in true },
            isDirectory: { _ in true })
        await fixture.startForExternalActions()
        fixture.model.wakeProfiles[0].wakePhrase = "renamed agent"

        let saved = await fixture.model.saveSettings()

        #expect(saved)
        #expect(await runner.recordedResets().isEmpty)
        #expect((await store.snapshot()).bookmarks == [bookmark])
    }

    @MainActor @Test
    func saveSettings_WhenOnlyNonSessionAgentSettingsChange_PreservesSessionBookmark()
        async throws
    {
        let profile = try makeAgentProfile(displayName: "Before")
        let bookmark = try continuityBookmark(for: profile)
        let store = AppModelContinuityStoreSpy(bookmarks: [bookmark])
        let runner = AppModelAgentRunnerSpy(continuityStore: store)
        let fixture = try Fixture(
            profiles: [profile],
            agentRunner: runner,
            continuityStore: store,
            isExecutableFile: { _ in true },
            isDirectory: { _ in true })
        await fixture.startForExternalActions()
        fixture.model.wakeProfiles[0].agentHarness.permissionPolicy = .rejectAlways
        fixture.model.wakeProfiles[0].accent = .green
        fixture.model.wakeProfiles[0].speechPreference = .disabled

        let saved = await fixture.model.saveSettings()

        #expect(saved)
        #expect(await runner.recordedResets().isEmpty)
        #expect((await store.snapshot()).bookmarks == [bookmark])
    }

    @MainActor @Test
    func saveSettings_WhenValidationFails_PerformsNoContinuityReset() async throws {
        let profile = try makeAgentProfile()
        let bookmark = try continuityBookmark(for: profile)
        let store = AppModelContinuityStoreSpy(bookmarks: [bookmark])
        let runner = AppModelAgentRunnerSpy(continuityStore: store)
        let fixture = try Fixture(
            profiles: [profile],
            agentRunner: runner,
            continuityStore: store,
            isExecutableFile: { _ in false },
            isDirectory: { _ in true })
        await fixture.startForExternalActions()
        fixture.model.wakeProfiles[0].agentHarness.executablePath = "/agents/invalid"

        #expect(!(await fixture.model.saveSettings()))
        #expect(await runner.recordedResets().isEmpty)
        #expect((await store.snapshot()).bookmarks == [bookmark])
    }

    @MainActor @Test
    func saveSettings_WhenHotKeyApplyFails_PerformsNoContinuityReset() async throws {
        let profile = try makeAgentProfile()
        let bookmark = try continuityBookmark(for: profile)
        let store = AppModelContinuityStoreSpy(bookmarks: [bookmark])
        let runner = AppModelAgentRunnerSpy(continuityStore: store)
        let fixture = try Fixture(
            profiles: [profile],
            agentRunner: runner,
            continuityStore: store,
            isExecutableFile: { _ in true },
            isDirectory: { _ in true })
        await fixture.startForExternalActions()
        fixture.model.wakeProfiles[0].agentHarness.executablePath = "/agents/replacement"
        fixture.shortcut.failNextStart = true

        #expect(!(await fixture.model.saveSettings()))
        #expect(await runner.recordedResets().isEmpty)
        #expect((await store.snapshot()).bookmarks == [bookmark])
    }

    @MainActor @Test
    func saveSettings_WhenCredentialStorageFails_PerformsNoContinuityReset() async throws {
        let profile = try makeAgentProfile()
        let bookmark = try continuityBookmark(for: profile)
        let store = AppModelContinuityStoreSpy(bookmarks: [bookmark])
        let runner = AppModelAgentRunnerSpy(continuityStore: store)
        let fixture = try Fixture(
            profiles: [profile],
            agentRunner: runner,
            continuityStore: store,
            agentSpeechCredentialStore: ContinuityCredentialStoreFailure(),
            isExecutableFile: { _ in true },
            isDirectory: { _ in true })
        await fixture.startForExternalActions()
        fixture.model.wakeProfiles[0].agentHarness.executablePath = "/agents/replacement"

        #expect(!(await fixture.model.saveSettings()))
        #expect(await runner.recordedResets().isEmpty)
        #expect((await store.snapshot()).bookmarks == [bookmark])
    }

    @MainActor @Test
    func saveSettings_WhenResetFails_CommitsValidatedProfileAndReportsContentFreeFailure()
        async throws
    {
        let profile = try makeAgentProfile(executablePath: "/agents/original")
        let bookmark = try continuityBookmark(for: profile)
        let store = AppModelContinuityStoreSpy(bookmarks: [bookmark])
        await store.failRemoval()
        let diagnostics = AppDiagnosticRecorderSpy()
        let runner = ACPAgentRunner(
            continuityStore: store,
            diagnostics: diagnostics)
        let fixture = try Fixture(
            profiles: [profile],
            agentRunner: runner,
            continuityStore: store,
            isExecutableFile: { _ in true },
            isDirectory: { _ in true },
            diagnostics: diagnostics)
        await fixture.startForExternalActions()
        fixture.model.wakeProfiles[0].agentHarness.executablePath = "/agents/replacement"

        let saved = await fixture.model.saveSettings()

        #expect(saved)
        #expect(fixture.model.activeWakeProfiles[0].action.agentConfiguration?.executablePath
            == "/agents/replacement")
        #expect((await store.snapshot()).bookmarks == [bookmark])
        let failures = diagnostics.snapshot().filter {
            $0.event == "continuity_store.save_failed"
        }
        #expect(failures.map(\.fields) == [["failure_category": "remove"]])
    }

    @MainActor @Test
    func saveSettings_WhenCancelledBeforeReset_PreservesContinuityRecords()
        async throws
    {
        let profile = try makeAgentProfile(executablePath: "/agents/original")
        let bookmark = try continuityBookmark(for: profile)
        let marker = continuityMarker(for: profile, index: 1)
        let store = AppModelContinuityStoreSpy(bookmarks: [bookmark], markers: [marker])
        let runner = AppModelAgentRunnerSpy(continuityStore: store)
        let fixture = try Fixture(
            profiles: [profile],
            agentRunner: runner,
            continuityStore: store,
            isExecutableFile: { _ in true },
            isDirectory: { _ in true })
        await fixture.startForExternalActions()
        fixture.model.wakeProfiles[0].agentHarness.executablePath = "/agents/replacement"
        let entry = AppModelSaveEntryGate()
        let save = Task { @MainActor in
            await entry.wait()
            return await fixture.model.saveSettings()
        }
        await entry.waitUntilEntered()

        save.cancel()
        await entry.open()

        #expect(!(await save.value))
        #expect(await runner.recordedResets().isEmpty)
        #expect((await store.snapshot()).bookmarks == [bookmark])
        #expect((await store.snapshot()).interruptedWork == [marker])
        #expect(fixture.model.activeWakeProfiles == [profile])
        #expect(fixture.preferences.wakeProfiles == [profile])
    }

    @MainActor @Test
    func saveSettings_WhenCancelledAfterResetBegins_CommitsSnapshotAndPreservesNewDraft()
        async throws
    {
        let profile = try makeAgentProfile(executablePath: "/agents/original")
        let bookmark = try continuityBookmark(for: profile)
        let marker = continuityMarker(for: profile, index: 1)
        let store = AppModelContinuityStoreSpy(bookmarks: [bookmark], markers: [marker])
        let runner = AppModelAgentRunnerSpy(continuityStore: store)
        await runner.delayReset()
        let credentials = AgentSpeechCredentialStoreSpy()
        let fixture = try Fixture(
            profiles: [profile],
            agentRunner: runner,
            continuityStore: store,
            agentSpeechCredentialStore: credentials,
            isExecutableFile: { _ in true },
            isDirectory: { _ in true })
        await fixture.startForExternalActions()
        fixture.model.wakeProfiles[0].agentHarness.executablePath = "/agents/first-draft"
        fixture.model.capturesMacContext = false
        fixture.model.elevenLabsAPIKey = " captured-key "
        let save = Task { @MainActor in await fixture.model.saveSettings() }
        await runner.waitUntilResetIsWaiting()

        fixture.model.wakeProfiles[0].agentHarness.executablePath = "/agents/newer-draft"
        fixture.model.elevenLabsAPIKey = "newer-key"
        save.cancel()
        let overlappingSave = await fixture.model.saveSettings()
        await runner.releaseReset()

        #expect(!overlappingSave)
        #expect(await save.value)
        #expect(fixture.model.activeWakeProfiles[0].action.agentConfiguration?.executablePath
            == "/agents/first-draft")
        #expect(fixture.preferences.wakeProfiles[0].action.agentConfiguration?.executablePath
            == "/agents/first-draft")
        #expect(fixture.model.wakeProfiles[0].agentHarness.executablePath == "/agents/newer-draft")
        #expect(fixture.model.elevenLabsAPIKey == "newer-key")
        #expect(credentials.apiKey == "captured-key")
        #expect(!fixture.preferences.capturesMacContext)
        #expect(fixture.shortcut.registeredProfiles[0].action.agentConfiguration?.executablePath
            == "/agents/first-draft")
        #expect((await store.snapshot()).bookmarks.isEmpty)
        #expect((await store.snapshot()).interruptedWork.isEmpty)
    }

    @MainActor @Test
    func saveSettings_WhenDirectCommandChanges_DoesNotResetAgentContinuity() async throws {
        let command = try commandProfile()
        let runner = AppModelAgentRunnerSpy()
        let fixture = try Fixture(
            profiles: [command],
            agentRunner: runner,
            isExecutableFile: { _ in true })
        await fixture.startForExternalActions()
        fixture.model.wakeProfiles[0].executablePath = "/usr/bin/printf"

        #expect(await fixture.model.saveSettings())
        #expect(await runner.recordedResets().isEmpty)
    }

    private func continuityBookmark(for profile: WakeProfile) throws -> AgentSessionBookmark {
        let configuration = try #require(profile.action.agentConfiguration)
        return AgentSessionBookmark(
            profileID: profile.id,
            sessionID: "saved-session",
            providerFingerprint: AgentProviderFingerprint.make(configuration: configuration),
            lastAccessOrdinal: 1)
    }

    private func continuityMarker(
        for profile: WakeProfile,
        index: Int
    ) -> AgentInterruptedWorkMarker {
        AgentInterruptedWorkMarker(
            key: .init(
                profileID: profile.id,
                sessionID: "saved-session",
                occurrenceID: UUID()),
            state: .interruptedByProcessExit)
    }

    private func commandProfile() throws -> WakeProfile {
        try WakeProfile(
            wakePhrase: "search",
            executablePath: "/usr/bin/open",
            argumentTemplates: ["https://example.com/?q={urlText}"],
            accent: .green)
    }
}

private actor AppModelSaveEntryGate {
    private var isOpen = false
    private var didEnter = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var blocked: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        didEnter = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        waiters.forEach { $0.resume() }
        guard !isOpen else { return }
        await withCheckedContinuation { blocked.append($0) }
    }

    func waitUntilEntered() async {
        guard !didEnter else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func open() {
        isOpen = true
        let waiters = blocked
        blocked.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private enum ContinuityCredentialStoreError: Error {
    case saveFailed
}

@MainActor
private final class ContinuityCredentialStoreFailure: AgentSpeechCredentialStoring {
    func loadElevenLabsAPIKey() async throws -> String? { nil }
    func saveElevenLabsAPIKey(_ apiKey: String?) throws {
        throw ContinuityCredentialStoreError.saveFailed
    }
}

private extension WakeProfileAction {
    var agentConfiguration: AgentHarnessConfiguration? {
        guard case .agent(let configuration) = self else { return nil }
        return configuration
    }
}
