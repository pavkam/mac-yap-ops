// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import YapOpsCore

extension YapOpsCoordinatorTests {
    @MainActor @Test func contextFeedback_CancelledCaptureCannotPublishLateSummary() async throws {
        let target = MacContextTarget(
            processIdentifier: 42, applicationName: "Editor", bundleIdentifier: nil)
        let context = ControlledMacContextCapturer(
            target: target, snapshot: makeMacContextSnapshot(target: target, selectedText: "late"))
        context.suspendsCaptures = true
        context.resolvesCancellation = false
        let fixture = try Fixture(profiles: [try makeAgentProfile()], contextCapturer: context)
        var summaries: [AgentInputContextSummary] = []
        fixture.coordinator.onAgentRunEvent = { event in
            if case .inputContextCaptured(_, _, let summary) = event { summaries.append(summary) }
        }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent summarize this", isFinal: true)
        await context.waitUntilCaptureCount(1)
        let execution = fixture.coordinator.executionTask

        fixture.coordinator.cancelAgentRun()
        context.completeCapture(at: 0)
        await execution?.value

        #expect(summaries.isEmpty)
        #expect(await fixture.agentRunner.recordedInvocations().isEmpty)
        fixture.coordinator.stop()
    }

    @MainActor @Test
    func contextFeedback_InitialAndInjectedFollowUpRetainCapturedIdentity() async throws {
        let editor = MacContextTarget(
            processIdentifier: 42, applicationName: "Editor", bundleIdentifier: nil)
        let finder = MacContextTarget(
            processIdentifier: 43, applicationName: "Finder", bundleIdentifier: nil)
        let first = makeMacContextSnapshot(target: editor, selectedText: "first")
        let second = makeMacContextSnapshot(target: finder, selectedText: "second")
        let context = ControlledMacContextCapturer(target: editor, snapshot: first)
        let fixture = try Fixture(profiles: [try makeAgentProfile()], contextCapturer: context)
        await fixture.agentRunner.enqueueMidTurnResults([.injected])
        var events: [AgentRunLifecycleEvent] = []
        fixture.coordinator.onAgentRunEvent = { events.append($0) }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent summarize this", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        let runID = try #require(fixture.coordinator.activeAgentRunID)
        #expect(events.contains(.inputContextCaptured(
            runID: runID, inputID: nil, summary: .init(context: first))))

        context.target = finder
        context.nextSnapshot = second
        fixture.speech.emit("and this", isFinal: true)
        await waitUntil {
            events.contains { event in
                if case .followUpDispositionChanged(_, _, .injected) = event { return true }
                return false
            }
        }
        let inputID = try #require(events.compactMap { event in
            if case .followUpSubmitted(_, let inputID, _, _) = event { return inputID }
            return nil
        }.first)
        #expect(events.contains(.inputContextCaptured(
            runID: runID, inputID: inputID, summary: .init(context: second))))
        await fixture.agentRunner.complete(runIndex: 0)
        fixture.coordinator.stop()
    }

    @MainActor @Test func contextFeedback_NoCaptureReportsAbsence() async throws {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        var events: [AgentRunLifecycleEvent] = []
        fixture.coordinator.onAgentRunEvent = { events.append($0) }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent explain this", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        let runID = try #require(fixture.coordinator.activeAgentRunID)

        #expect(events.contains(.inputContextCaptured(
            runID: runID, inputID: nil, summary: .init(context: nil))))
        await fixture.agentRunner.complete(runIndex: 0)
        fixture.coordinator.stop()
    }
}
