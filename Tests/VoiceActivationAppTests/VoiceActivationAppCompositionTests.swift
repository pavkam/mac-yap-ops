// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AppKit
import Foundation
import Testing

@testable import VoiceActivationApp
@testable import VoiceActivationCore

extension AppModelTests {
    @MainActor @Test
    func compositionStartup_WhenReconciliationSuspends_BlocksExternalEffectsUntilReady()
        async throws
    {
        let profile = try makeAgentProfile()
        let store = AppModelContinuityStoreSpy()
        await store.delayReconciliation()
        let preferences = try compositionPreferences(profiles: [profile], passiveEnabled: false)
        let notificationCenter = NotificationCenter()
        let access = MacContextAccessSpy(status: .authorized)
        let speech = AppModelSpeechSessionSpy()
        let shortcut = ShortcutSpy()
        let permission = PermissionRequestGate()
        let composition = VoiceActivationAppComposition.make(
            continuityStore: store,
            activationMonitor: ApplicationActivationMonitor(
                notificationCenter: notificationCenter),
            makeAgentRunner: { _ in AppModelAgentRunnerSpy() },
            makeModel: { runner, sharedStore in
                AppModel(
                    preferences: preferences,
                    recordingOverlay: AppModelOverlayStub(),
                    agentRunPanel: AppModelAgentPanelSpy(),
                    shortcut: shortcut,
                    speechSession: speech,
                    agentRunner: runner,
                    continuityStore: sharedStore,
                    permissionRequest: { await permission.request() },
                    soundPlayer: SilentCaptureSoundPlayer(),
                    agentConversationAudioPlayer: SilentAgentConversationAudioPlayer(),
                    agentSpeechCredentialStore: AgentSpeechCredentialStoreSpy(),
                    elevenLabsVoiceCatalog: AppModelElevenLabsVoiceCatalogSpy(voices: []),
                    elevenLabsVoicePreview: AppModelElevenLabsVoicePreviewSpy(),
                    macContextAccess: access,
                    macContextCapturer: MacContextCapturerSpy(),
                    isExecutableFile: { _ in true },
                    isDirectory: { _ in true },
                    startsAutomatically: false)
            })
        let startup = Task { @MainActor in await composition.startup.run() }
        await store.waitUntilReconciling()

        notificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        composition.model.setPassiveEnabled(true)
        composition.model.pushToTalkPressed(profileID: profile.id)
        #expect(access.statusChecks == 0)
        #expect(permission.requestCount == 0)
        #expect(shortcut.startedProfiles.isEmpty)
        #expect(speech.startCount == 0)
        #expect(composition.model.heldHotKeyProfileID == nil)

        await store.releaseReconciliation()
        await permission.waitUntilWaiting()
        #expect(permission.requestCount == 1)
        permission.resolve(true)
        #expect(await startup.value)
        #expect(access.statusChecks == 1)
        #expect(!shortcut.startedProfiles.isEmpty)
        #expect(speech.startCount == 1)
        notificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        #expect(access.statusChecks == 2)
    }

    @MainActor @Test
    func compositionPrompt_WhenInterrupted_UsesSameStoreAndConsumesOnlyAfterFrameAndAck()
        async throws
    {
        let profile = try makeAgentProfile(pushToTalkHotKey: .defaultValue)
        let marker = AgentInterruptedWorkMarker(
            key: AgentInterruptedWorkKey(
                profileID: profile.id,
                sessionID: "saved-session",
                occurrenceID: UUID()),
            state: .interruptedByProcessExit)
        let store = AppModelContinuityStoreSpy(markers: [marker])
        let frame = CompositionRunGate()
        let acknowledgement = CompositionRunGate()
        var runnerStoreWasShared = false
        var modelStoreWasShared = false
        var composedRunner: CompositionContinuityRunner?
        let preferences = try compositionPreferences(profiles: [profile], passiveEnabled: false)
        let speech = AppModelSpeechSessionSpy()
        let panel = AppModelAgentPanelSpy()
        let composition = VoiceActivationAppComposition.make(
            continuityStore: store,
            activationMonitor: ApplicationActivationMonitor(
                notificationCenter: NotificationCenter()),
            makeAgentRunner: { sharedStore in
                runnerStoreWasShared = (sharedStore as? AppModelContinuityStoreSpy) === store
                let runner = CompositionContinuityRunner(
                    continuityStore: sharedStore,
                    frame: frame,
                    acknowledgement: acknowledgement)
                composedRunner = runner
                return runner
            },
            makeModel: { runner, sharedStore in
                modelStoreWasShared = (sharedStore as? AppModelContinuityStoreSpy) === store
                return AppModel(
                    preferences: preferences,
                    recordingOverlay: AppModelOverlayStub(),
                    agentRunPanel: panel,
                    shortcut: ShortcutSpy(),
                    speechSession: speech,
                    agentRunner: runner,
                    continuityStore: sharedStore,
                    permissionRequest: { true },
                    soundPlayer: SilentCaptureSoundPlayer(),
                    agentConversationAudioPlayer: SilentAgentConversationAudioPlayer(),
                    agentSpeechCredentialStore: AgentSpeechCredentialStoreSpy(),
                    elevenLabsVoiceCatalog: AppModelElevenLabsVoiceCatalogSpy(voices: []),
                    elevenLabsVoicePreview: AppModelElevenLabsVoicePreviewSpy(),
                    macContextAccess: MacContextAccessSpy(),
                    macContextCapturer: MacContextCapturerSpy(),
                    isExecutableFile: { _ in true },
                    isDirectory: { _ in true },
                    startsAutomatically: false)
            })
        #expect(await composition.startup.run())
        let runner = try #require(composedRunner)

        composition.model.coordinator.pushToTalkPressed(profileID: profile.id)
        speech.emit("continue")
        composition.model.coordinator.pushToTalkReleased()
        await frame.waitUntilEntered()

        #expect(runnerStoreWasShared)
        #expect(modelStoreWasShared)
        #expect(composition.model.interruptedAgentWork == [marker])
        #expect((await store.snapshot()).interruptedWork == [marker])
        await frame.open()
        await acknowledgement.waitUntilEntered()
        #expect(composition.model.interruptedAgentWork == [marker])
        #expect((await store.snapshot()).interruptedWork == [marker])

        await acknowledgement.open()
        await runner.waitUntilFinished()
        await panel.waitUntilPhase(.listening)
        #expect(composition.model.interruptedAgentWork.isEmpty)
        #expect((await store.snapshot()).interruptedWork.isEmpty)
    }

    @MainActor
    private func compositionPreferences(
        profiles: [WakeProfile],
        passiveEnabled: Bool
    ) throws -> AppPreferences {
        let suite = "VoiceActivationCompositionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let preferences = AppPreferences(defaults: defaults)
        preferences.wakeProfiles = profiles
        preferences.passiveEnabled = passiveEnabled
        return preferences
    }
}

private actor CompositionRunGate {
    private var entered = false
    private var isOpen = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var blocked: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        waiters.forEach { $0.resume() }
        guard !isOpen else { return }
        await withCheckedContinuation { blocked.append($0) }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func open() {
        isOpen = true
        let waiters = blocked
        blocked.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private actor CompositionContinuityRunner: AgentHarnessRunning {
    private let continuityStore: any AgentContinuityStoring
    private let frame: CompositionRunGate
    private let acknowledgement: CompositionRunGate
    private var finished = false
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        continuityStore: any AgentContinuityStoring,
        frame: CompositionRunGate,
        acknowledgement: CompositionRunGate
    ) {
        self.continuityStore = continuityStore
        self.frame = frame
        self.acknowledgement = acknowledgement
    }

    func run(
        admission: AgentRunAdmission,
        profileID: UUID,
        configuration: AgentHarnessConfiguration,
        prompt: AgentPrompt,
        restorationNeed: AgentSessionRestorationNeed,
        runContinuity: AgentRunContinuityRequest,
        onEvent: @escaping @Sendable (AgentRunStreamEvent) async -> Void
    ) async throws -> AgentRunResult {
        guard admission.claim() else { throw CancellationError() }
        await frame.wait()
        await acknowledgement.wait()
        try await continuityStore.acknowledgeInterruptedWork(
            runContinuity.ordinaryInterruptedWorkKeys)
        await runContinuity.confirmPublishedAcknowledgement(
            runContinuity.ordinaryInterruptedWorkKeys)
        finished = true
        let waiters = finishWaiters
        finishWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return AgentRunResult(stopReason: .endTurn)
    }

    func resolvePermission(
        turnToken: AgentTurnToken,
        requestID: ACPRequestID,
        optionID: String?
    ) async {}

    func cancel() async {}
    func reset(profileIDs: Set<UUID>) async {}
    func shutdown() async {}

    func waitUntilFinished() async {
        guard !finished else { return }
        await withCheckedContinuation { finishWaiters.append($0) }
    }
}
