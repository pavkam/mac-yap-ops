// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import YapOpsApp
@testable import YapOpsCore

extension AppModelTests {
    @MainActor @Test
    func start_WhenWorkMarkerWasActive_PublishesInterruptedStateBeforeListening() async throws {
        let marker = interruptedMarker(profileID: UUID(), index: 1, state: .active)
        let store = AppModelContinuityStoreSpy(markers: [marker])
        await store.delayReconciliation()
        let permission = PermissionRequestGate()
        let credentials = AgentSpeechCredentialStoreSpy(apiKey: "configured")
        let fixture = try Fixture(
            continuityStore: store,
            agentSpeechCredentialStore: credentials,
            permissionRequest: { await permission.request() })

        let start = Task { @MainActor in await fixture.model.start() }
        await store.waitUntilReconciling()

        #expect(fixture.shortcut.startedProfiles.isEmpty)
        #expect(permission.requestCount == 0)
        #expect(fixture.speech.startCount == 0)
        #expect(fixture.macContextAccess.statusChecks == 0)
        #expect(credentials.loadCount == 0)
        await store.releaseReconciliation()
        await permission.waitUntilWaiting()
        permission.resolve(true)
        _ = await start.value

        let interrupted = AgentInterruptedWorkMarker(
            key: marker.key,
            turnID: marker.turnID,
            providerTaskID: marker.providerTaskID,
            state: .interruptedByProcessExit)
        #expect(await store.recordedCalls().first == .reconcile)
        #expect(fixture.model.interruptedAgentWork == [interrupted])
        #expect(fixture.speech.startCount == 1)
    }

    @MainActor @Test func start_WhenCalledTwice_ReconcilesExactlyOnce() async throws {
        let store = AppModelContinuityStoreSpy()
        let fixture = try Fixture(continuityStore: store)

        await fixture.model.start()
        await fixture.model.start()

        #expect(await store.recordedCalls().filter { $0 == .reconcile }.count == 1)
    }

    @MainActor @Test
    func start_WhenReconciliationFails_StillStartsListeningAndReportsSafeDiagnostic()
        async throws
    {
        let marker = interruptedMarker(profileID: UUID(), index: 1, state: .active)
        let store = AppModelContinuityStoreSpy(markers: [marker])
        await store.failReconciliation()
        let diagnostics = AppDiagnosticRecorderSpy()
        let fixture = try Fixture(continuityStore: store, diagnostics: diagnostics)
        let savedProfiles = fixture.preferences.wakeProfiles

        await fixture.model.start()

        #expect(fixture.model.state == .listening)
        #expect(fixture.speech.startCount == 1)
        #expect(fixture.preferences.wakeProfiles == savedProfiles)
        #expect((await store.snapshot()).interruptedWork == [marker])
        let failures = diagnostics.snapshot().filter {
            $0.event == "continuity_store.read_failed"
        }
        #expect(failures.count == 1)
        #expect(failures.first?.fields == ["failure_category": "launch_reconcile"])
    }

    @MainActor @Test
    func start_WhenCancelledDuringReconciliation_StopsWithoutEffectsAndCanRetry()
        async throws
    {
        let store = AppModelContinuityStoreSpy()
        await store.delayReconciliation()
        let diagnostics = AppDiagnosticRecorderSpy()
        let credentials = AgentSpeechCredentialStoreSpy(apiKey: "configured")
        let fixture = try Fixture(
            continuityStore: store,
            agentSpeechCredentialStore: credentials,
            diagnostics: diagnostics)
        let startup = Task { @MainActor in await fixture.model.start() }
        await store.waitUntilReconciling()

        startup.cancel()
        await store.releaseReconciliation()
        let firstResult = await startup.value

        #expect(!firstResult)
        #expect(!fixture.model.isStartupReady)
        #expect(fixture.macContextAccess.statusChecks == 0)
        #expect(credentials.loadCount == 0)
        #expect(fixture.shortcut.startedProfiles.isEmpty)
        #expect(fixture.speech.startCount == 0)
        #expect(diagnostics.snapshot().allSatisfy {
            $0.event != "continuity_store.read_failed"
        })

        let secondResult = await fixture.model.start()

        #expect(secondResult)
        #expect(fixture.model.isStartupReady)
        #expect(await store.recordedCalls().filter { $0 == .reconcile }.count == 2)
        #expect(fixture.speech.startCount == 1)
    }

    @MainActor @Test
    func externalActivationToggleAndPushToTalk_BeforeReconciliation_HaveNoRuntimeEffects()
        async throws
    {
        let profile = try makeAgentProfile(pushToTalkHotKey: .defaultValue)
        let store = AppModelContinuityStoreSpy()
        await store.delayReconciliation()
        let permission = PermissionRequestGate()
        let fixture = try Fixture(
            profiles: [profile],
            continuityStore: store,
            permissionRequest: { await permission.request() },
            isExecutableFile: { _ in true },
            isDirectory: { _ in true })
        let startup = Task { @MainActor in await fixture.model.start() }
        await store.waitUntilReconciling()

        fixture.model.applicationDidBecomeActive()
        fixture.model.setPassiveEnabled(false)
        fixture.model.setPassiveEnabled(true)
        fixture.model.pushToTalkPressed(profileID: profile.id)

        #expect(fixture.macContextAccess.statusChecks == 0)
        #expect(fixture.model.heldHotKeyProfileID == nil)
        #expect(fixture.shortcut.startedProfiles.isEmpty)
        #expect(fixture.speech.startCount == 0)
        #expect(fixture.model.passiveEnabled)
        #expect(fixture.preferences.passiveEnabled)

        await store.releaseReconciliation()
        await permission.waitUntilWaiting()
        #expect(permission.requestCount == 1)
        permission.resolve(true)
        #expect(await startup.value)
        #expect(fixture.model.isStartupReady)
        #expect(fixture.speech.startCount == 1)
    }

    @MainActor @Test
    func start_WhenReconciliationExceedsBound_UsesDeterministicProfileAndKeyPrefix()
        async throws
    {
        let markers = (0..<70).map {
            interruptedMarker(profileID: deterministicProfileID($0), index: $0)
        }
        let store = AppModelContinuityStoreSpy(reconciledOverride: markers)
        let fixture = try Fixture(continuityStore: store)
        fixture.model.setPassiveEnabled(false)

        await fixture.model.start()

        #expect(fixture.model.interruptedAgentWork == Array(markers.prefix(64)))
        let retained = fixture.model.agentRunContinuityRequest(
            for: deterministicProfileID(63))
        let evicted = fixture.model.agentRunContinuityRequest(
            for: deterministicProfileID(64))
        #expect(retained.ordinaryInterruptedWorkKeys == [markers[63].key])
        #expect(evicted.ordinaryInterruptedWorkKeys.isEmpty)
        #expect(!evicted.previousTurnInterrupted)
    }

    @MainActor @Test
    func start_WhenProviderTaskWasInterrupted_RetainsMarkerOutsideOrdinaryPromptHandoff()
        async throws
    {
        let profileID = UUID()
        let marker = interruptedMarker(
            profileID: profileID,
            index: 1,
            providerTaskID: "provider-task")
        let store = AppModelContinuityStoreSpy(markers: [marker])
        let fixture = try Fixture(continuityStore: store)

        await fixture.model.start()

        let request = fixture.model.agentRunContinuityRequest(for: profileID)
        #expect(fixture.model.interruptedAgentWork == [marker])
        #expect(!request.previousTurnInterrupted)
        #expect(request.ordinaryInterruptedWorkKeys.isEmpty)
        #expect((await store.snapshot()).interruptedWork == [marker])
    }

    @MainActor @Test
    func firstPostLaunchPrompt_WhenProfileWasInterrupted_CarriesConsumeOnceFlag()
        async throws
    {
        let profile = try makeAgentProfile(pushToTalkHotKey: .defaultValue)
        let marker = interruptedMarker(profileID: profile.id, index: 1)
        let unrelated = interruptedMarker(profileID: UUID(), index: 2)
        let store = AppModelContinuityStoreSpy(markers: [marker, unrelated])
        let runner = AppModelAgentRunnerSpy(continuityStore: store)
        let fixture = try Fixture(
            profiles: [profile],
            agentRunner: runner,
            continuityStore: store,
            isExecutableFile: { _ in true },
            isDirectory: { _ in true })
        await fixture.model.start()

        try await submitPrompt("continue", profile: profile, fixture: fixture)
        await runner.waitUntilInvocationCount(1)
        await fixture.agentRunPanel.waitUntilPhase(.listening)

        let invocation = try #require(await runner.recordedInvocations().first)
        #expect(invocation.runContinuity.previousTurnInterrupted)
        #expect(invocation.runContinuity.ordinaryInterruptedWorkKeys == [marker.key])
        #expect(fixture.model.agentRunContinuityRequest(for: profile.id)
            .ordinaryInterruptedWorkKeys.isEmpty)
        #expect(fixture.model.interruptedAgentWork == [unrelated])
        #expect(fixture.model.agentRunContinuityRequest(for: unrelated.key.profileID)
            .ordinaryInterruptedWorkKeys == [unrelated.key])
    }

    @MainActor @Test
    func secondPostLaunchPrompt_DoesNotRepeatInterruptedFlag() async throws {
        let profile = try makeAgentProfile(pushToTalkHotKey: .defaultValue)
        let marker = interruptedMarker(profileID: profile.id, index: 1)
        let store = AppModelContinuityStoreSpy(markers: [marker])
        let runner = AppModelAgentRunnerSpy(continuityStore: store)
        let fixture = try Fixture(
            profiles: [profile],
            agentRunner: runner,
            continuityStore: store,
            isExecutableFile: { _ in true },
            isDirectory: { _ in true })
        await fixture.model.start()

        try await submitPrompt("first", profile: profile, fixture: fixture)
        await runner.waitUntilInvocationCount(1)
        await fixture.agentRunPanel.waitUntilPhase(.listening)
        fixture.model.coordinator.submitAgentFollowUp("second")
        await runner.waitUntilInvocationCount(2)

        let invocations = await runner.recordedInvocations()
        #expect(invocations[0].runContinuity.previousTurnInterrupted)
        #expect(!invocations[1].runContinuity.previousTurnInterrupted)
        #expect(invocations[1].runContinuity.ordinaryInterruptedWorkKeys.isEmpty)
    }

    @MainActor @Test
    func firstPostLaunchPrompt_WhenFrameWriteFails_RetainsInterruptedFlag() async throws {
        let profile = try makeAgentProfile(pushToTalkHotKey: .defaultValue)
        let marker = interruptedMarker(profileID: profile.id, index: 1)
        let store = AppModelContinuityStoreSpy(markers: [marker])
        let runner = AppModelAgentRunnerSpy(publicationBehavior: .failBeforePublication)
        let fixture = try Fixture(
            profiles: [profile],
            agentRunner: runner,
            continuityStore: store,
            isExecutableFile: { _ in true },
            isDirectory: { _ in true })
        await fixture.model.start()

        try await submitPrompt("continue", profile: profile, fixture: fixture)
        await runner.waitUntilInvocationCount(1)
        await fixture.agentRunPanel.waitUntilTerminal()
        let failure = try #require(fixture.model.agentRunSnapshot?.phase)
        guard case .failed = failure else {
            Issue.record("Expected failed conversation after prepublication error")
            return
        }

        let request = fixture.model.agentRunContinuityRequest(for: profile.id)
        #expect(request.previousTurnInterrupted)
        #expect(request.ordinaryInterruptedWorkKeys == [marker.key])
        #expect(fixture.model.interruptedAgentWork == [marker])
    }

    @MainActor @Test
    func postpublicationAcknowledgement_WhenCallbackIsStale_DoesNotConsumeNewerPendingKeys()
        async throws
    {
        let profileID = UUID()
        let old = interruptedMarker(profileID: profileID, index: 1)
        let new = interruptedMarker(profileID: profileID, index: 2)
        let fixture = try Fixture(continuityStore: AppModelContinuityStoreSpy(markers: [old]))
        await fixture.model.start()
        let staleRequest = fixture.model.agentRunContinuityRequest(for: profileID)
        fixture.model.publishInterruptedAgentWork([new])

        await staleRequest.confirmPublishedAcknowledgement([old.key])
        await staleRequest.confirmPublishedAcknowledgement([old.key])

        let current = fixture.model.agentRunContinuityRequest(for: profileID)
        #expect(current.previousTurnInterrupted)
        #expect(current.ordinaryInterruptedWorkKeys == [new.key])
        #expect(fixture.model.interruptedAgentWork == [new])
    }

    private func interruptedMarker(
        profileID: UUID,
        index: Int,
        providerTaskID: String? = nil,
        state: AgentInterruptedWorkState = .interruptedByProcessExit
    ) -> AgentInterruptedWorkMarker {
        AgentInterruptedWorkMarker(
            key: AgentInterruptedWorkKey(
                profileID: profileID,
                sessionID: "session-\(index)",
                occurrenceID: deterministicUUID(namespace: 0x01, index: index)),
            turnID: "turn-\(index)",
            providerTaskID: providerTaskID,
            state: state)
    }

    private func deterministicProfileID(_ index: Int) -> UUID {
        deterministicUUID(namespace: 0x10, index: index)
    }

    private func deterministicUUID(namespace: UInt8, index: Int) -> UUID {
        UUID(uuid: (
            namespace, 0, 0, 0,
            0, 0,
            0, 0,
            0, 0,
            0, 0, 0, 0, 0, UInt8(index)))
    }

    @MainActor
    private func submitPrompt(
        _ text: String,
        profile: WakeProfile,
        fixture: Fixture
    ) async throws {
        fixture.model.coordinator.pushToTalkPressed(profileID: profile.id)
        #expect(fixture.speech.mode == .pushToTalk)
        fixture.speech.emit(text)
        fixture.model.coordinator.pushToTalkReleased()
        #expect(fixture.model.agentRunSnapshot?.prompt == text)
    }
}
