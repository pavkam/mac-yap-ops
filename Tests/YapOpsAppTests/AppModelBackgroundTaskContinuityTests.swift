// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import YapOpsApp
@testable import YapOpsCore

@Suite(.serialized, .timeLimit(.minutes(1)))
struct AppModelBackgroundTaskContinuityTests {
    @MainActor @Test
    func backgroundUpdate_HopsThroughModeAwareMainRunLoopBeforePresentationMutation()
        async throws
    {
        let fixture = try await makeFixture()
        establishSession(fixture, sessionID: "session-a")

        await fixture.runner.emitSessionEvent(envelope(
            profileID: fixture.profile.id,
            sessionID: "session-a",
            event: .backgroundTask(spawn(id: "watch"))))

        #expect(fixture.scheduler.pendingCount == 1)
        #expect(fixture.model.agentRunSnapshot?.backgroundTasks.isEmpty == true)
        fixture.scheduler.drain()
        #expect(fixture.model.agentRunSnapshot?.backgroundTasks.map(\.id.rawValue) == ["watch"])
    }

    @MainActor @Test
    func backgroundUpdateForDifferentSession_DoesNotMutatePresentation() async throws {
        let fixture = try await makeFixture()
        establishSession(fixture, sessionID: "session-a")

        await fixture.runner.emitSessionEvent(envelope(
            profileID: fixture.profile.id,
            sessionID: "session-b",
            event: .backgroundTask(spawn(id: "wrong"))))
        fixture.scheduler.drain()

        #expect(fixture.model.agentRunSnapshot?.backgroundTasks.isEmpty == true)
    }

    @MainActor @Test
    func hiddenPanel_BackgroundUpdateStillMutatesMatchingPresentation() async throws {
        let fixture = try await makeFixture()
        establishSession(fixture, sessionID: "session-a")
        fixture.model.agentRunPanelPresenter.hide(runID: fixture.runID)

        await fixture.runner.emitSessionEvent(envelope(
            profileID: fixture.profile.id,
            sessionID: "session-a",
            event: .backgroundTask(spawn(id: "watch"))))
        fixture.scheduler.drain()

        #expect(fixture.panel.hidden == [fixture.runID])
        #expect(fixture.model.agentRunSnapshot?.hasActiveBackgroundTasks == true)
    }

    @MainActor @Test
    func newVisibleConversation_DoesNotDiscardOtherActiveSessionPresentation()
        async throws
    {
        let fixture = try await makeFixture()
        establishSession(fixture, sessionID: "session-a")
        await fixture.runner.emitSessionEvent(envelope(
            profileID: fixture.profile.id,
            sessionID: "session-a",
            event: .backgroundTask(spawn(id: "watch"))))
        fixture.scheduler.drain()
        let secondRunID = UUID()
        let secondProfile = try AppModelTests().makeAgentProfile(displayName: "Second")

        fixture.model.handleAgentRunLifecycleEvent(.started(
            runID: secondRunID,
            profile: secondProfile,
            prompt: "New request"))
        fixture.model.handleAgentRunLifecycleEvent(.event(
            runID: secondRunID,
            event: .connected(agentName: "Agent", sessionID: "session-b")))

        #expect(fixture.model.agentRunSnapshot?.runID == secondRunID)
        #expect(fixture.model.activeAgentBackgroundSessions.map(\.runID) == [fixture.runID])
    }

    @MainActor @Test
    func backgroundLiveMessage_NarratesOnceWithoutStartingPromptWorkingPulse()
        async throws
    {
        let audio = AgentConversationAudioSpy()
        let fixture = try await makeFixture(audio: audio)
        fixture.preferences.readsAgentRepliesAloud = true
        establishSession(fixture, sessionID: "session-a")
        fixture.model.handleAgentRunLifecycleEvent(.turnCompleted(
            runID: fixture.runID,
            result: AgentRunResult(stopReason: .endTurn)))
        let workingStates = audio.workingStates

        await fixture.runner.emitSessionEvent(envelope(
            profileID: fixture.profile.id,
            sessionID: "session-a",
            event: .agentMessageDelta(messageID: "result", text: "Build finished.")))
        fixture.scheduler.drain()

        #expect(audio.spoken.map(\.text).filter { $0 == "Build finished." }.count == 1)
        #expect(audio.workingStates == workingStates)
    }

    @MainActor @Test
    func restoredMessage_NeverEntersBackgroundNarration() async throws {
        let audio = AgentConversationAudioSpy()
        let fixture = try await makeFixture(audio: audio)
        fixture.preferences.readsAgentRepliesAloud = true
        establishSession(fixture, sessionID: "session-a")

        await fixture.runner.emitSessionEvent(AgentSessionEventEnvelope(
            profileID: fixture.profile.id,
            sessionID: "session-a",
            streamEvent: .restored(
                token: AgentRestorationToken(),
                event: .agentMessageDelta(messageID: "old", text: "Historical."))))
        fixture.scheduler.drain()

        #expect(audio.spoken.isEmpty)
        #expect(fixture.model.agentRunSnapshot?.output.isEmpty == true)
    }

    @MainActor @Test
    func stopBackgroundTask_RoutesVisibleTaskIdentityOnce() async throws {
        let fixture = try await makeFixture()
        establishSession(fixture, sessionID: "session-a")
        await emitTask(fixture, id: "watch")
        let taskID = AgentBackgroundTaskID(rawValue: "watch")

        fixture.model.stopBackgroundTask(runID: fixture.runID, taskID: taskID)
        fixture.model.stopBackgroundTask(runID: fixture.runID, taskID: taskID)
        await AppModelTests().waitUntil {
            await fixture.runner.recordedBackgroundTaskStops().count == 1
        }

        let calls = await fixture.runner.recordedBackgroundTaskStops()
        #expect(calls.count == 1)
        #expect(calls.first?.0 == fixture.profile.id)
        #expect(calls.first?.1 == "session-a")
        #expect(calls.first?.2 == taskID)
        #expect(fixture.model.agentRunSnapshot?.backgroundTasks.first?.stopState == .requested)
    }

    @MainActor @Test
    func stopBackgroundTask_WhenResponseIsFalse_RestoresActionAndShowsFailure()
        async throws
    {
        let fixture = try await makeFixture()
        await fixture.runner.setBackgroundTaskStopResult(false)
        establishSession(fixture, sessionID: "session-a")
        await emitTask(fixture, id: "watch")

        fixture.model.stopBackgroundTask(
            runID: fixture.runID,
            taskID: AgentBackgroundTaskID(rawValue: "watch"))
        await AppModelTests().waitUntil {
            fixture.model.agentRunSnapshot?.backgroundTasks.first?.stopState == .failed
        }

        let task = try #require(fixture.model.agentRunSnapshot?.backgroundTasks.first)
        #expect(task.statusLabel == "Couldn’t stop task")
        #expect(task.offersStopAction)
    }

    @MainActor @Test
    func shutdown_DetachesSessionHandlerAndRejectsCapturedCallback() async throws {
        let fixture = try await makeFixture()
        establishSession(fixture, sessionID: "session-a")

        await fixture.model.shutdown()
        await fixture.runner.emitCapturedSessionEvent(envelope(
            profileID: fixture.profile.id,
            sessionID: "session-a",
            event: .backgroundTask(spawn(id: "late"))))
        fixture.scheduler.drain()

        #expect(await fixture.runner.recordedSessionHandlerInstallStates() == [true, false])
        #expect(fixture.model.agentRunSnapshot == nil)
    }

    @MainActor @Test
    func restoredInterruptedTask_ShowsInterruptedWithoutActiveControls() async throws {
        let fixture = try await makeFixture()
        fixture.model.publishInterruptedAgentWork([
            interruptedMarker(profileID: fixture.profile.id, taskID: "watch")
        ])

        fixture.model.handleAgentRunLifecycleEvent(.started(
            runID: fixture.runID,
            profile: fixture.profile,
            prompt: "Continue"))

        #expect(fixture.model.agentRunSnapshot?.notices == [
            "Interrupted when YapOps exited"
        ])
        #expect(fixture.model.agentRunSnapshot?.backgroundTasks.isEmpty == true)
    }

    @MainActor @Test
    func freshLiveTaskEventAfterResume_CreatesNewCurrentOccurrence() async throws {
        let fixture = try await makeFixture()
        fixture.model.publishInterruptedAgentWork([
            interruptedMarker(profileID: fixture.profile.id, taskID: "watch")
        ])
        establishSession(fixture, sessionID: "session-a")

        await emitTask(fixture, id: "watch")

        #expect(fixture.model.agentRunSnapshot?.notices == [
            "Interrupted when YapOps exited"
        ])
        #expect(fixture.model.agentRunSnapshot?.backgroundTasks.map(\.id.rawValue) == ["watch"])
        #expect(fixture.model.agentRunSnapshot?.hasActiveBackgroundTasks == true)
    }

    @MainActor
    private func makeFixture(
        audio: AgentConversationAudioSpy = AgentConversationAudioSpy()
    ) async throws -> Fixture {
        let runner = AppModelAgentRunnerSpy()
        let scheduler = ControlledAgentSessionEventScheduler()
        let panel = AppModelAgentPanelSpy()
        let profile = try AppModelTests().makeAgentProfile(displayName: "Codex")
        let app = try AppModelTests.Fixture(
            profiles: [profile],
            agentRunner: runner,
            agentRunPanel: panel,
            agentConversationAudioPlayer: audio,
            isExecutableFile: { _ in true },
            isDirectory: { _ in true },
            agentSessionEventScheduler: scheduler)
        #expect(await app.model.start())
        return Fixture(
            model: app.model,
            preferences: app.preferences,
            runner: runner,
            scheduler: scheduler,
            panel: panel,
            audio: audio,
            profile: profile,
            runID: UUID())
    }

    @MainActor
    private func establishSession(_ fixture: Fixture, sessionID: String) {
        fixture.model.handleAgentRunLifecycleEvent(.started(
            runID: fixture.runID,
            profile: fixture.profile,
            prompt: "Watch the build"))
        fixture.model.handleAgentRunLifecycleEvent(.event(
            runID: fixture.runID,
            event: .connected(agentName: "Agent", sessionID: sessionID)))
    }

    @MainActor
    private func emitTask(_ fixture: Fixture, id: String) async {
        await fixture.runner.emitSessionEvent(envelope(
            profileID: fixture.profile.id,
            sessionID: "session-a",
            event: .backgroundTask(spawn(id: id))))
        fixture.scheduler.drain()
    }

    private func envelope(
        profileID: UUID,
        sessionID: String,
        event: AgentRunEvent
    ) -> AgentSessionEventEnvelope {
        AgentSessionEventEnvelope(
            profileID: profileID,
            sessionID: sessionID,
            streamEvent: .live(event))
    }

    private func spawn(id: String) -> AgentBackgroundTaskUpdate {
        .spawned(
            id: AgentBackgroundTaskID(rawValue: id),
            name: "Watch build",
            taskType: "watcher",
            description: "Waiting for CI",
            showInTranscript: true,
            canStop: true,
            outputFilePath: nil,
            toolCallID: nil)
    }

    private func interruptedMarker(
        profileID: UUID,
        taskID: String
    ) -> AgentInterruptedWorkMarker {
        AgentInterruptedWorkMarker(
            key: AgentInterruptedWorkKey(
                profileID: profileID,
                sessionID: "session-a",
                occurrenceID: UUID()),
            providerTaskID: taskID,
            state: .interruptedByProcessExit)
    }
}

@MainActor
private struct Fixture {
    let model: AppModel
    let preferences: AppPreferences
    let runner: AppModelAgentRunnerSpy
    let scheduler: ControlledAgentSessionEventScheduler
    let panel: AppModelAgentPanelSpy
    let audio: AgentConversationAudioSpy
    let profile: WakeProfile
    let runID: UUID
}

private final class ControlledAgentSessionEventScheduler:
    AgentSessionEventScheduling, @unchecked Sendable
{
    private let lock = NSLock()
    private var operations: [@MainActor @Sendable () -> Void] = []

    var pendingCount: Int {
        lock.withLock { operations.count }
    }

    func schedule(_ operation: @escaping @MainActor @Sendable () -> Void) {
        lock.withLock { operations.append(operation) }
    }

    @MainActor
    func drain() {
        let pending = lock.withLock {
            let pending = operations
            operations.removeAll(keepingCapacity: true)
            return pending
        }
        pending.forEach { $0() }
    }
}
