// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationApp
@testable import VoiceActivationCore

@Suite(.timeLimit(.minutes(1)))
struct AgentRunPresentationRestorationOwnershipTests {
    @MainActor @Test
    func historyCompletion_WhenToolIDAndPlanCollide_PreservesBothSourcesExactly() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        let token = AgentRestorationToken()
        presentation.start(
            runID: runID,
            profile: try makeAgentProfile(),
            prompt: "Current request")
        presentation.beginHistoryRestoration(
            runID: runID,
            token: token,
            sessionID: "saved-session")

        presentation.receiveRestored(
            runID: runID,
            token: token,
            event: .toolCall(AgentToolCall(
                id: "shared-tool",
                title: "Historical tool",
                kind: .read,
                status: .inProgress)))
        presentation.receiveRestored(
            runID: runID,
            token: token,
            event: .plan([
                AgentPlanEntry(
                    content: "Historical plan",
                    priority: .low,
                    status: .inProgress),
            ]))
        presentation.receive(
            runID: runID,
            event: .toolCall(AgentToolCall(
                id: "shared-tool",
                title: "Current tool",
                kind: .execute,
                status: .inProgress)))
        presentation.receive(
            runID: runID,
            event: .plan([
                AgentPlanEntry(
                    content: "Current plan",
                    priority: .high,
                    status: .inProgress),
            ]))
        presentation.completeHistoryRestoration(
            runID: runID,
            token: token,
            activation: .loaded(sessionID: "saved-session"))

        let snapshot = try #require(presentation.snapshot)
        #expect(snapshot.tools.map(\.title) == ["Historical tool", "Current tool"])
        #expect(snapshot.tools.map(\.status) == [.interrupted, .inProgress])
        #expect(snapshot.plan.map(\.content) == ["Historical plan", "Current plan"])
        #expect(snapshot.plan.map(\.status) == [.interrupted, .inProgress])
        #expect(timelineTools(in: snapshot).map(\.title) == [
            "Historical tool", "Current tool",
        ])
        #expect(timelineTools(in: snapshot).map(\.status) == [.interrupted, .inProgress])

        presentation.receive(
            runID: runID,
            event: .toolCallUpdate(AgentToolCallUpdate(
                id: "shared-tool",
                title: "Current tool finished",
                status: .completed)))

        #expect(presentation.snapshot?.tools.map(\.title) == [
            "Historical tool", "Current tool finished",
        ])
        #expect(presentation.snapshot?.tools.map(\.status) == [.interrupted, .completed])
        #expect(presentation.snapshot.map { timelineTools(in: $0) }?.map(\.status) == [
            .interrupted, .completed,
        ])
    }

    @MainActor @Test
    func historyReplay_WhenMoreThanToolCapArrives_BoundsOwnershipWithRetainedRows()
        throws
    {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        let token = AgentRestorationToken()
        presentation.start(
            runID: runID,
            profile: try makeAgentProfile(),
            prompt: "Current request")
        presentation.beginHistoryRestoration(
            runID: runID,
            token: token,
            sessionID: "saved-session")

        for index in 0..<40 {
            presentation.receiveRestored(
                runID: runID,
                token: token,
                event: .toolCall(AgentToolCall(
                    id: "tool-\(index)",
                    title: "Tool \(index)",
                    kind: .read,
                    status: .inProgress)))
        }
        presentation.receiveRestored(
            runID: runID,
            token: token,
            event: .toolCallUpdate(AgentToolCallUpdate(
                id: "tool-0",
                title: "Evicted update",
                status: .completed)))
        presentation.receiveRestored(
            runID: runID,
            token: token,
            event: .toolCallUpdate(AgentToolCallUpdate(
                id: "tool-39",
                title: "Retained update")))

        #expect(presentation.restorationState?.tools.count == 32)
        presentation.completeHistoryRestoration(
            runID: runID,
            token: token,
            activation: .loaded(sessionID: "saved-session"))

        let snapshot = try #require(presentation.snapshot)
        #expect(snapshot.tools.count == 32)
        #expect(snapshot.tools.first?.title == "Tool 8")
        #expect(snapshot.tools.last?.title == "Retained update")
        #expect(snapshot.tools.allSatisfy { $0.status == .interrupted })
        #expect(timelineTools(in: snapshot).map(\.id) == snapshot.tools.map(\.id))
    }

    @MainActor @Test
    func historyAbort_WhenToolReplayExceedsCap_RemovesOnlyAttemptRows() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        let token = AgentRestorationToken()
        presentation.start(
            runID: runID,
            profile: try makeAgentProfile(),
            prompt: "Current request")
        presentation.receive(
            runID: runID,
            event: .toolCall(AgentToolCall(
                id: "current-tool",
                title: "Current tool",
                kind: .execute,
                status: .inProgress)))
        presentation.receive(
            runID: runID,
            event: .plan([
                AgentPlanEntry(
                    content: "Current plan",
                    priority: .high,
                    status: .inProgress),
            ]))
        let before = try #require(presentation.snapshot)
        presentation.beginHistoryRestoration(
            runID: runID,
            token: token,
            sessionID: "saved-session")

        for index in 0..<40 {
            presentation.receiveRestored(
                runID: runID,
                token: token,
                event: .toolCall(AgentToolCall(
                    id: "historical-\(index)",
                    title: "Historical \(index)",
                    kind: .read,
                    status: .inProgress)))
        }
        presentation.receiveRestored(
            runID: runID,
            token: token,
            event: .plan([
                AgentPlanEntry(
                    content: "Partial historical plan",
                    priority: .low,
                    status: .inProgress),
            ]))
        presentation.abortHistoryRestoration(runID: runID, token: token)

        let after = try #require(presentation.snapshot)
        #expect(after.tools == before.tools)
        #expect(after.plan == before.plan)
        #expect(after.timeline == before.timeline)
        #expect(after.evictedToolCount == before.evictedToolCount)
    }

    @MainActor @Test
    func historyAbort_WhenLiveToolAndPlanArriveDuringReplay_PreservesLiveSources() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        let token = AgentRestorationToken()
        presentation.start(
            runID: runID,
            profile: try makeAgentProfile(),
            prompt: "Current request")
        presentation.beginHistoryRestoration(
            runID: runID,
            token: token,
            sessionID: "saved-session")
        presentation.receiveRestored(
            runID: runID,
            token: token,
            event: .toolCall(AgentToolCall(
                id: "shared-tool",
                title: "Partial historical tool",
                kind: .read,
                status: .inProgress)))
        presentation.receiveRestored(
            runID: runID,
            token: token,
            event: .plan([
                AgentPlanEntry(
                    content: "Partial historical plan",
                    priority: .low,
                    status: .inProgress),
            ]))
        presentation.receive(
            runID: runID,
            event: .toolCall(AgentToolCall(
                id: "shared-tool",
                title: "Current tool",
                kind: .execute,
                status: .inProgress)))
        presentation.receive(
            runID: runID,
            event: .plan([
                AgentPlanEntry(
                    content: "Current plan",
                    priority: .high,
                    status: .inProgress),
            ]))

        presentation.abortHistoryRestoration(runID: runID, token: token)

        let snapshot = try #require(presentation.snapshot)
        #expect(snapshot.tools.map(\.title) == ["Current tool"])
        #expect(snapshot.tools.map(\.status) == [.inProgress])
        #expect(snapshot.plan.map(\.content) == ["Current plan"])
        #expect(snapshot.plan.map(\.status) == [.inProgress])
        #expect(timelineTools(in: snapshot).map(\.title) == ["Current tool"])
        #expect(snapshot.timeline.contains(.historyBoundary) == false)
    }

    @MainActor @Test
    func historyCompletion_WhenOnlyOrphanToolUpdateArrives_ShowsNoHistoryDivider()
        throws
    {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        let token = AgentRestorationToken()
        presentation.start(
            runID: runID,
            profile: try makeAgentProfile(),
            prompt: "Current request")
        presentation.beginHistoryRestoration(
            runID: runID,
            token: token,
            sessionID: "saved-session")

        presentation.receiveRestored(
            runID: runID,
            token: token,
            event: .toolCallUpdate(AgentToolCallUpdate(
                id: "orphan",
                title: "Never visible",
                status: .completed)))
        presentation.completeHistoryRestoration(
            runID: runID,
            token: token,
            activation: .loaded(sessionID: "saved-session"))

        #expect(presentation.snapshot?.tools.isEmpty == true)
        #expect(presentation.snapshot?.timeline.contains(.historyBoundary) == false)
    }

    @MainActor @Test
    func historyReplay_WhenRequestIsTrimmed_CoalescesLaterDeltaByPreservedMessageID()
        throws
    {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        let token = AgentRestorationToken()
        presentation.start(
            runID: runID,
            profile: try makeAgentProfile(),
            prompt: "Current request")
        presentation.beginHistoryRestoration(
            runID: runID,
            token: token,
            sessionID: "saved-session")

        presentation.receiveRestored(
            runID: runID,
            token: token,
            event: .userMessageDelta(
                messageID: "historical-request",
                text: String(repeating: "x", count: 70 * 1_024)))
        presentation.receiveRestored(
            runID: runID,
            token: token,
            event: .userMessageDelta(
                messageID: "historical-request",
                text: " retained-tail"))

        let messages: [AgentUserMessagePresentation]? =
            presentation.snapshot?.timeline.compactMap { item in
            guard case .userMessage(let message) = item else { return nil }
            return message
        }
        #expect(messages?.count == 1)
        #expect(messages?.first?.messageID == "historical-request")
        #expect(messages?.first?.text.hasSuffix(" retained-tail") == true)
    }

    @MainActor
    private func timelineTools(in snapshot: AgentRunSnapshot) -> [AgentToolPresentation] {
        snapshot.timeline.flatMap { item -> [AgentToolPresentation] in
            guard case .thinking(let thinking) = item else { return [] }
            return thinking.details.compactMap { detail in
                guard case .tool(let tool) = detail else { return nil }
                return tool
            }
        }
    }

    @MainActor
    private func makeAgentProfile() throws -> WakeProfile {
        try WakeProfile(
            wakePhrase: "agent",
            action: .agent(AgentHarnessConfiguration(
                preset: .codex,
                displayName: "Codex",
                executablePath: "/usr/bin/true",
                arguments: [],
                workingDirectory: "/tmp",
                permissionPolicy: .ask)),
            accent: .purple)
    }
}
