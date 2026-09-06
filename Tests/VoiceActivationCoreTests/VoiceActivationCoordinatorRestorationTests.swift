// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationCore

extension VoiceActivationCoordinatorTests {
    @MainActor @Test
    func agentExecution_WhenRestorationStreams_MapsSourceQualifiedLifecycle() async throws {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        var lifecycleEvents: [AgentRunLifecycleEvent] = []
        fixture.coordinator.onAgentRunEvent = { lifecycleEvents.append($0) }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent continue", isFinal: true)
        await fixture.agentRunner.waitForInvocationCount(1)
        guard case let .started(runID, _, _) = lifecycleEvents.first else {
            Issue.record("Expected an agent run start")
            return
        }
        let token = AgentRestorationToken()

        await fixture.agentRunner.emitStream(
            .restorationStarted(token: token, sessionID: "saved-session"),
            from: 0)
        await fixture.agentRunner.emitStream(
            .restored(
                token: token,
                event: .agentMessageDelta(messageID: "history", text: "Earlier answer")),
            from: 0)
        await fixture.agentRunner.emitStream(
            .restorationCompleted(
                token: token,
                activation: .loaded(sessionID: "saved-session")),
            from: 0)
        await fixture.agentRunner.emit(
            .agentMessageDelta(messageID: "live", text: "Current answer"),
            from: 0)

        #expect(Array(lifecycleEvents.dropFirst()) == [
            .historyRestorationStarted(
                runID: runID,
                token: token,
                sessionID: "saved-session"),
            .historyEvent(
                runID: runID,
                token: token,
                event: .agentMessageDelta(messageID: "history", text: "Earlier answer")),
            .historyRestorationCompleted(
                runID: runID,
                token: token,
                activation: .loaded(sessionID: "saved-session")),
            .event(
                runID: runID,
                event: .agentMessageDelta(messageID: "live", text: "Current answer")),
        ])
        await fixture.agentRunner.complete(runIndex: 0)
    }

    @MainActor @Test
    func agentExecution_WhenOldRestorationTokenEmitsLate_IgnoresIt() async throws {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        var lifecycleEvents: [AgentRunLifecycleEvent] = []
        fixture.coordinator.onAgentRunEvent = { lifecycleEvents.append($0) }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent continue", isFinal: true)
        await fixture.agentRunner.waitForInvocationCount(1)
        guard case let .started(runID, _, _) = lifecycleEvents.first else {
            Issue.record("Expected an agent run start")
            return
        }
        let oldToken = AgentRestorationToken()
        let currentToken = AgentRestorationToken()

        await fixture.agentRunner.emitStream(
            .restorationStarted(token: oldToken, sessionID: "old"),
            from: 0)
        await fixture.agentRunner.emitStream(
            .restorationAborted(token: oldToken),
            from: 0)
        await fixture.agentRunner.emitStream(
            .restorationStarted(token: currentToken, sessionID: "current"),
            from: 0)
        await fixture.agentRunner.emitStream(
            .restored(
                token: oldToken,
                event: .agentMessageDelta(messageID: "late", text: "Late old history")),
            from: 0)
        await fixture.agentRunner.emitStream(
            .restorationCompleted(
                token: oldToken,
                activation: .loaded(sessionID: "old")),
            from: 0)
        await fixture.agentRunner.emitStream(
            .restored(
                token: currentToken,
                event: .agentMessageDelta(messageID: "kept", text: "Current history")),
            from: 0)

        #expect(lifecycleEvents.contains(.historyRestorationAborted(
            runID: runID,
            token: oldToken)))
        #expect(!lifecycleEvents.contains(.historyEvent(
            runID: runID,
            token: oldToken,
            event: .agentMessageDelta(messageID: "late", text: "Late old history"))))
        #expect(!lifecycleEvents.contains(.historyRestorationCompleted(
            runID: runID,
            token: oldToken,
            activation: .loaded(sessionID: "old"))))
        #expect(lifecycleEvents.contains(.historyEvent(
            runID: runID,
            token: currentToken,
            event: .agentMessageDelta(messageID: "kept", text: "Current history"))))
        await fixture.agentRunner.complete(runIndex: 0)
    }

    @MainActor @Test
    func agentExecution_WhenRunIsRetired_IgnoresLateRestorationLifecycle() async throws {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        var lifecycleEvents: [AgentRunLifecycleEvent] = []
        var cancellationContinuation: CheckedContinuation<Void, Never>?
        fixture.coordinator.onAgentRunEvent = { event in
            lifecycleEvents.append(event)
            if case .turnCompleted = event, let continuation = cancellationContinuation {
                cancellationContinuation = nil
                continuation.resume()
            }
        }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent continue", isFinal: true)
        await fixture.agentRunner.waitForInvocationCount(1)
        guard case let .started(runID, _, _) = lifecycleEvents.first else {
            Issue.record("Expected an agent run start")
            return
        }
        await withCheckedContinuation { continuation in
            cancellationContinuation = continuation
            fixture.coordinator.cancelAgentRun()
        }
        #expect(await fixture.agentRunner.cancelCount == 1)
        #expect(lifecycleEvents.contains(.turnCompleted(
            runID: runID,
            result: AgentRunResult(stopReason: .cancelled))))
        let countAfterCancellation = lifecycleEvents.count
        let token = AgentRestorationToken()

        await fixture.agentRunner.emitStream(
            .restorationStarted(token: token, sessionID: "retired-session"),
            from: 0)
        await fixture.agentRunner.emitStream(
            .restored(
                token: token,
                event: .agentMessageDelta(messageID: "late", text: "Late history")),
            from: 0)
        await fixture.agentRunner.emitStream(
            .restorationCompleted(
                token: token,
                activation: .loaded(sessionID: "retired-session")),
            from: 0)

        #expect(lifecycleEvents.count == countAfterCancellation)
        await fixture.agentRunner.complete(runIndex: 0)
    }
}
