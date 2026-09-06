// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationCore

extension VoiceActivationCoordinatorTests {
    @MainActor
    @Test func cancelAgentRun_WhenCaptureCancellationRuns_HasAlreadyRetiredActiveInput()
        async throws
    {
        let target = MacContextTarget(
            processIdentifier: 42,
            applicationName: "Safari",
            bundleIdentifier: nil)
        let context = ControlledMacContextCapturer(target: target)
        let probe = ContextCancellationOwnershipProbe()
        context.suspendsCaptures = true
        let fixture = try Fixture(
            profiles: [try makeAgentProfile()],
            contextCapturer: context)
        let coordinator = fixture.coordinator
        context.onCaptureCancellation = { @Sendable captureIndex in
            MainActor.assumeIsolated {
                probe.append(.init(
                    captureIndex: captureIndex,
                    hasActiveInput: coordinator.activeAgentInput != nil,
                    pendingInputCount: coordinator.pendingAgentPrompts.count,
                    executionGeneration: coordinator.executionGeneration))
            }
        }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent inspect this", isFinal: true)
        await waitUntil { context.capturedTargets.count == 1 }
        let generation = fixture.coordinator.executionGeneration

        fixture.coordinator.cancelAgentRun()
        await waitUntil { !probe.observations().isEmpty }

        #expect(probe.observations() == [
            .init(
                captureIndex: 0,
                hasActiveInput: false,
                pendingInputCount: 0,
                executionGeneration: generation + 1),
        ])
    }

    @MainActor
    @Test func endAgentConversation_WhenQueuedCaptureCancellationRuns_HasRetiredAllInputs()
        async throws
    {
        let target = MacContextTarget(
            processIdentifier: 42,
            applicationName: "Safari",
            bundleIdentifier: nil)
        let context = ControlledMacContextCapturer(
            target: target,
            snapshot: makeMacContextSnapshot(target: target))
        let probe = ContextCancellationOwnershipProbe()
        let fixture = try Fixture(
            profiles: [try makeAgentProfile()],
            contextCapturer: context)
        let coordinator = fixture.coordinator
        context.onCaptureCancellation = { @Sendable captureIndex in
            MainActor.assumeIsolated {
                probe.append(.init(
                    captureIndex: captureIndex,
                    hasActiveInput: coordinator.activeAgentInput != nil,
                    pendingInputCount: coordinator.pendingAgentPrompts.count,
                    executionGeneration: coordinator.executionGeneration))
            }
        }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent inspect this", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        await fixture.agentRunner.delayCancellation()
        context.suspendsCaptures = true
        fixture.speech.emit("also inspect this", isFinal: true)
        await waitUntil {
            let cancelCount = await fixture.agentRunner.cancelCount
            return context.capturedTargets.count == 2 && cancelCount == 1
        }
        let generation = fixture.coordinator.executionGeneration

        fixture.coordinator.endAgentConversation()
        await waitUntil { !probe.observations().isEmpty }

        #expect(probe.observations().contains(
            .init(
                captureIndex: 1,
                hasActiveInput: false,
                pendingInputCount: 0,
                executionGeneration: generation + 1)))
        await fixture.agentRunner.releaseCancellation()
        await fixture.agentRunner.complete(runIndex: 0)
    }

    @MainActor
    @Test func agentTurn_WhenGenerationRetiresAtRunnerAdmission_NeverEntersRunner()
        async throws
    {
        let gate = AgentAdmissionDiagnosticGate()
        let fixture = try Fixture(
            profiles: [try makeAgentProfile()],
            diagnostics: gate)
        await fixture.agentRunner.completeRunsImmediately()
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent stale turn", isFinal: true)
        await waitUntil { gate.isBlocked() }

        fixture.coordinator.executionGeneration &+= 1
        let executionTask = fixture.coordinator.executionTask
        gate.release()
        await executionTask?.value

        #expect(await fixture.agentRunner.recordedRunAttemptCount() == 0)
        fixture.coordinator.stop()
    }

    @MainActor
    @Test func followUps_WhenMultipleItemsQueue_DeliverFIFOWithOwnedFrozenContext()
        async throws
    {
        let safari = MacContextTarget(
            processIdentifier: 1,
            applicationName: "Safari",
            bundleIdentifier: "com.apple.Safari")
        let finder = MacContextTarget(
            processIdentifier: 2,
            applicationName: "Finder",
            bundleIdentifier: "com.apple.finder")
        let notes = MacContextTarget(
            processIdentifier: 3,
            applicationName: "Notes",
            bundleIdentifier: "com.apple.Notes")
        let context = ControlledMacContextCapturer(
            target: safari,
            snapshot: makeMacContextSnapshot(target: safari, selectedText: "initial"))
        let fixture = try Fixture(
            profiles: [try makeAgentProfile()],
            contextCapturer: context)
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent first", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        await fixture.agentRunner.delayCancellation()

        context.target = finder
        context.nextSnapshot = makeMacContextSnapshot(target: finder, selectedText: "second")
        fixture.speech.emit("second", isFinal: true)
        await waitUntil {
            let cancelCount = await fixture.agentRunner.cancelCount
            return context.capturedTargets.count == 2 && cancelCount == 1
        }
        context.target = notes
        context.nextSnapshot = makeMacContextSnapshot(target: notes, selectedText: "third")
        fixture.speech.emit("third", isFinal: true)
        await waitUntil { context.capturedTargets.count == 3 }

        await fixture.agentRunner.releaseCancellation()
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 2 }
        await fixture.agentRunner.complete(runIndex: 1)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 3 }

        let prompts = await fixture.agentRunner.recordedInvocations().map(\.prompt)
        #expect(prompts.map(\.request) == ["first", "second", "third"])
        #expect(prompts.map { $0.context?.applicationName } == ["Safari", "Finder", "Notes"])
        #expect(prompts.map { $0.context?.selectedText } == ["initial", "second", "third"])
        #expect(context.currentTargetCallCount == 3)
        #expect(context.capturedTargets == [safari, finder, notes])
        await fixture.agentRunner.complete(runIndex: 0)
        await fixture.agentRunner.complete(runIndex: 2)
    }
}
