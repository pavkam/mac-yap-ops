// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationCore

extension VoiceActivationCoordinatorTests {
    @MainActor
    @Test func agentConversation_WhenSteeringRequiresPrompt_QueuesThenStartsAfterCompletion()
        async throws
    {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        await fixture.agentRunner.enqueueMidTurnResults([.promptRequired])
        var events: [AgentRunLifecycleEvent] = []
        fixture.coordinator.onAgentRunEvent = { events.append($0) }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent first", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }

        fixture.speech.emit("second", isFinal: true)
        await waitUntil {
            events.contains { event in
                guard case .followUpDispositionChanged(_, _, .queued) = event else {
                    return false
                }
                return true
            }
        }
        #expect(await fixture.agentRunner.cancelCount == 0)
        #expect(await fixture.agentRunner.recordedInvocations().count == 1)

        await fixture.agentRunner.complete(runIndex: 0)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 2 }
        #expect(await fixture.agentRunner.recordedInvocations().map(\.prompt.request) == [
            "first", "second",
        ])
        #expect(events.contains { event in
            guard case .followUpDispositionChanged(_, _, .prompted) = event else {
                return false
            }
            return true
        })
        await fixture.agentRunner.complete(runIndex: 1)
    }

    @MainActor
    @Test func agentConversation_WhenThreeInputsArrive_PreservesFIFOAcrossSteeringAndPrompts()
        async throws
    {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        await fixture.agentRunner.enqueueMidTurnResults([.injected, .promptRequired])
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent first", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }

        for prompt in ["one", "two", "three"] {
            fixture.speech.emit(prompt, isFinal: true)
        }
        await waitUntil { await fixture.agentRunner.recordedMidTurnOffers().count == 2 }
        #expect(await fixture.agentRunner.recordedMidTurnOffers().map(\.prompt.request) == [
            "one", "two",
        ])

        await fixture.agentRunner.complete(runIndex: 0)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 2 }
        await fixture.agentRunner.complete(runIndex: 1)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 3 }
        #expect(await fixture.agentRunner.recordedInvocations().map(\.prompt.request) == [
            "first", "two", "three",
        ])
        await fixture.agentRunner.complete(runIndex: 2)
    }

    @MainActor
    @Test func agentConversation_WhenSteeringFails_DropsOnlyAmbiguousHeadWithoutReplay()
        async throws
    {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        await fixture.agentRunner.enqueueMidTurnOutcomes([.failure])
        var events: [AgentRunLifecycleEvent] = []
        fixture.coordinator.onAgentRunEvent = { events.append($0) }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent first", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }

        fixture.speech.emit("ambiguous", isFinal: true)
        fixture.speech.emit("safe next", isFinal: true)
        await waitUntil {
            events.contains { event in
                guard case let .notice(_, message) = event else { return false }
                return message == "Delivery failed — say it again."
            }
        }
        #expect(await fixture.agentRunner.recordedMidTurnOffers().map(\.prompt.request) == [
            "ambiguous",
        ])

        await fixture.agentRunner.complete(runIndex: 0)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 2 }
        #expect(await fixture.agentRunner.recordedInvocations().map(\.prompt.request) == [
            "first", "safe next",
        ])
        await fixture.agentRunner.complete(runIndex: 1)
    }

    @MainActor
    @Test func agentConversation_WhenConversationEnds_IgnoresLateRoutingCompletion() async throws {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        await fixture.agentRunner.delayMidTurnOffers()
        var dispositions: [AgentConversationInputDisposition] = []
        fixture.coordinator.onAgentRunEvent = { event in
            guard case let .followUpDispositionChanged(_, _, disposition) = event else {
                return
            }
            dispositions.append(disposition)
        }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent first", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        fixture.speech.emit("late", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedMidTurnOffers().count == 1 }

        fixture.coordinator.endAgentConversation()
        await waitUntil { await fixture.agentRunner.cancelCount == 1 }
        await fixture.agentRunner.releaseMidTurnOffers()
        try await Task.sleep(for: .milliseconds(30))

        #expect(dispositions.isEmpty)
        #expect(fixture.coordinator.agentInputRoutingTask == nil)
        #expect(fixture.coordinator.pendingAgentPrompts.isEmpty)
        await fixture.agentRunner.complete(runIndex: 0)
    }

    @MainActor
    @Test func agentConversation_WhenStopTurnIsClicked_PreservesQueuedInputForNextTurn()
        async throws
    {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        await fixture.agentRunner.enqueueMidTurnResults([.promptRequired])
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent first", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        fixture.speech.emit("next", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedMidTurnOffers().count == 1 }

        fixture.coordinator.cancelAgentRun()
        await waitUntil {
            let cancelCount = await fixture.agentRunner.cancelCount
            let invocationCount = await fixture.agentRunner.recordedInvocations().count
            return cancelCount == 1 && invocationCount == 2
        }
        #expect(await fixture.agentRunner.recordedInvocations().map(\.prompt.request) == [
            "first", "next",
        ])
        await fixture.agentRunner.complete(runIndex: 0)
        await fixture.agentRunner.complete(runIndex: 1)
    }

    @MainActor
    @Test func agentConversation_WhenPromptFallsBack_ReusesSingleCapturedContext() async throws {
        let target = MacContextTarget(
            processIdentifier: 42,
            applicationName: "Safari",
            bundleIdentifier: "com.apple.Safari")
        let context = ControlledMacContextCapturer(
            target: target,
            snapshot: makeMacContextSnapshot(target: target))
        let fixture = try Fixture(
            profiles: [try makeAgentProfile()],
            contextCapturer: context)
        await fixture.agentRunner.enqueueMidTurnResults([.promptRequired])
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent first", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        fixture.speech.emit("next", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedMidTurnOffers().count == 1 }
        let offeredPrompt = try #require(
            await fixture.agentRunner.recordedMidTurnOffers().first?.prompt)

        await fixture.agentRunner.complete(runIndex: 0)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 2 }
        #expect(await fixture.agentRunner.recordedInvocations()[1].prompt == offeredPrompt)
        #expect(context.currentTargetCallCount == 2)
        #expect(context.capturedTargets.count == 2)
        await fixture.agentRunner.complete(runIndex: 1)
    }

    @MainActor
    @Test func agentConversation_WhenUserBargesIn_StopsSpeechWithoutCancellingAgentTurn()
        async throws
    {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        await fixture.agentRunner.enqueueMidTurnResults([.injected])
        var speechCancellationCount = 0
        fixture.coordinator.onAgentSpeechCancellation = {
            speechCancellationCount += 1
        }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent first", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }

        fixture.coordinator.setAgentSpeechOutputActive(true)
        fixture.speech.emit("also check tests", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedMidTurnOffers().count == 1 }

        #expect(speechCancellationCount == 1)
        #expect(await fixture.agentRunner.cancelCount == 0)
        #expect(await fixture.agentRunner.recordedInvocations().count == 1)
        await fixture.agentRunner.complete(runIndex: 0)
    }

    @MainActor
    @Test func agentConversation_WhenFollowUpExceedsByteLimit_RejectsBeforeCaptureOrOffer()
        async throws
    {
        let context = ControlledMacContextCapturer()
        let fixture = try Fixture(
            profiles: [try makeAgentProfile()],
            contextCapturer: context)
        var notices: [String] = []
        fixture.coordinator.onAgentRunEvent = { event in
            guard case let .notice(_, message) = event else { return }
            notices.append(message)
        }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent first", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        let initialTargetCalls = context.currentTargetCallCount
        context.target = MacContextTarget(
            processIdentifier: 42,
            applicationName: "Safari",
            bundleIdentifier: "com.apple.Safari")

        fixture.speech.emit(
            String(repeating: "é", count: ACPClientConnection.maximumPromptBytes / 2 + 1),
            isFinal: true)
        try await Task.sleep(for: .milliseconds(30))

        #expect(context.currentTargetCallCount == initialTargetCalls)
        #expect(context.capturedTargets.isEmpty)
        #expect(fixture.coordinator.pendingAgentPrompts.isEmpty)
        #expect(await fixture.agentRunner.recordedMidTurnOffers().isEmpty)
        #expect(notices == ["That follow-up is too long. Shorten it and try again."])
        await fixture.agentRunner.complete(runIndex: 0)
    }
}
