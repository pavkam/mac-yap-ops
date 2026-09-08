// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import YapOpsCore

extension YapOpsCoordinatorTests {
    @MainActor @Test
    func stopTurn_KeepsMicrophoneOffAfterCancellationAndLatePlaybackCompletion() async throws {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        defer { fixture.coordinator.stop() }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent first", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        fixture.coordinator.cancelAgentRun()
        await waitUntil { fixture.coordinator.agentCancellationTask == nil }

        #expect(fixture.speech.mode == nil)
        fixture.coordinator.setAgentSpeechOutputActive(true)
        fixture.coordinator.setAgentSpeechOutputActive(false)
        fixture.coordinator.startConversationListening()
        fixture.speech.emitFromRetiredSession("late input", isFinal: true)
        #expect(fixture.speech.mode == nil)
        #expect(fixture.coordinator.pendingAgentPrompts.isEmpty)
        #expect(fixture.coordinator.isAgentConversationActive)
        await fixture.agentRunner.complete(runIndex: 0)
    }

    @MainActor @Test
    func stopTurn_WhileWaitingForFollowUp_StopsCaptureWithoutCallingProviderCancel() async throws {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        defer { fixture.coordinator.stop() }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent first", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        await fixture.agentRunner.complete(runIndex: 0)
        await waitUntil { fixture.coordinator.executionTask == nil }

        fixture.coordinator.cancelAgentRun()
        #expect(fixture.speech.mode == nil)
        #expect(fixture.coordinator.isAgentConversationActive)
        #expect(await fixture.agentRunner.cancelCount == 0)
    }
    @MainActor @Test
    func pausedConversation_ResumesOnlyForExplicitResumeOrNonemptyPushToTalk() async throws {
        let profile = try makeAgentProfile()
        let fixture = try Fixture(profiles: [profile])
        defer { fixture.coordinator.stop() }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent first", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        fixture.coordinator.cancelAgentRun()
        await waitUntil { fixture.coordinator.agentCancellationTask == nil }
        #expect(fixture.coordinator.resumeAgentConversationListening())
        #expect(!fixture.coordinator.resumeAgentConversationListening())
        #expect(fixture.speech.mode == .conversation)
        fixture.coordinator.cancelAgentRun()
        #expect(fixture.speech.mode == nil)

        fixture.coordinator.pushToTalkPressed(profileID: profile.id)
        fixture.coordinator.pushToTalkReleased()
        #expect(fixture.speech.mode == nil)
        fixture.coordinator.pushToTalkPressed(profileID: profile.id)
        fixture.speech.emit("continue", isFinal: true)
        fixture.coordinator.pushToTalkReleased()
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 2 }
        #expect(fixture.speech.mode == .conversation)
        await fixture.agentRunner.complete(runIndex: 0)
        await fixture.agentRunner.complete(runIndex: 1)
    }

}
