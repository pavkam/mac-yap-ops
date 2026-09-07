// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import YapOpsCore

extension YapOpsCoordinatorTests {
    @MainActor @Test
    func invalidateAgentProfiles_WhenMatchingTurnAwaitsContext_PreventsRunnerAdmission()
        async throws
    {
        let profile = try makeAgentProfile()
        let target = MacContextTarget(
            processIdentifier: 42,
            applicationName: "Safari",
            bundleIdentifier: "com.apple.Safari")
        let context = ControlledMacContextCapturer(target: target)
        context.suspendsCaptures = true
        context.resolvesCancellation = false
        let fixture = try Fixture(profiles: [profile], contextCapturer: context)
        await fixture.agentRunner.completeRunsImmediately()
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent inspect this", isFinal: true)
        await context.waitUntilCaptureCount(1)
        let scheduledTurn = fixture.coordinator.executionTask

        fixture.coordinator.invalidateAgentProfiles([profile.id])
        await context.waitUntilCancellationCount(1)
        context.completeCapture(at: 0)
        await scheduledTurn?.value

        #expect(await fixture.agentRunner.recordedRunAttemptCount() == 0)
        #expect(await fixture.agentRunner.recordedInvocations().isEmpty)
        #expect(fixture.coordinator.activeAgentInput == nil)
        #expect(fixture.coordinator.pendingAgentPrompts.isEmpty)
    }

    @MainActor @Test
    func invalidateAgentProfiles_WhenAnotherProfileIsActive_LeavesItsTurnUntouched()
        async throws
    {
        let active = try makeAgentProfile(
            wakePhrase: "active agent",
            displayName: "Active agent")
        let unrelated = try makeAgentProfile(
            wakePhrase: "unrelated agent",
            displayName: "Unrelated agent")
        let target = MacContextTarget(
            processIdentifier: 42,
            applicationName: "Safari",
            bundleIdentifier: "com.apple.Safari")
        let context = ControlledMacContextCapturer(target: target)
        context.suspendsCaptures = true
        let fixture = try Fixture(
            profiles: [active, unrelated],
            contextCapturer: context)
        await fixture.agentRunner.completeRunsImmediately()
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("active agent inspect this", isFinal: true)
        await context.waitUntilCaptureCount(1)

        fixture.coordinator.invalidateAgentProfiles([unrelated.id])

        #expect(context.cancelledCaptureIndices.isEmpty)
        context.completeCapture(at: 0)
        await fixture.agentRunner.waitForInvocationCount(1)
        #expect(await fixture.agentRunner.recordedInvocations().map(\.profileID) == [active.id])
    }

    @MainActor @Test
    func invalidateAgentProfiles_WhenConversationHasPendingInput_RetiresEveryAdmission()
        async throws
    {
        let profile = try makeAgentProfile()
        let target = MacContextTarget(
            processIdentifier: 42,
            applicationName: "Safari",
            bundleIdentifier: "com.apple.Safari")
        let context = ControlledMacContextCapturer(
            target: target,
            snapshot: makeMacContextSnapshot(target: target))
        let fixture = try Fixture(profiles: [profile], contextCapturer: context)
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent first", isFinal: true)
        await fixture.agentRunner.waitForInvocationCount(1)
        await fixture.agentRunner.delayCancellation()
        context.suspendsCaptures = true
        context.resolvesCancellation = false
        fixture.coordinator.submitAgentFollowUp("second")
        await context.waitUntilCaptureCount(2)

        fixture.coordinator.invalidateAgentProfiles([profile.id])
        await context.waitUntilCancellationCount(1)
        context.completeCapture(at: 1)
        await fixture.agentRunner.releaseCancellation()

        #expect(fixture.coordinator.activeAgentInput == nil)
        #expect(fixture.coordinator.pendingAgentPrompts.isEmpty)
        #expect(await fixture.agentRunner.recordedInvocations().count == 1)
        await fixture.agentRunner.complete(runIndex: 0)
    }
}
