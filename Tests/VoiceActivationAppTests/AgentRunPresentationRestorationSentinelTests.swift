// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationApp
@testable import VoiceActivationCore

@Suite(.timeLimit(.minutes(1)))
struct AgentRunPresentationRestorationSentinelTests {
    @MainActor @Test
    func historyProjection_WhenBothSourcesAreTruncated_UsesOneGlobalOmissionMarker()
        throws
    {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        presentation.start(
            runID: runID,
            profile: try makeAgentProfile(),
            prompt: "Current request")

        for index in 0...AgentRunPresentation.maximumTimelineItems {
            presentation.receive(
                runID: runID,
                event: .agentMessageDelta(
                    messageID: "live-\(index)",
                    text: "Live \(index)"))
        }

        let token = AgentRestorationToken()
        presentation.beginHistoryRestoration(
            runID: runID,
            token: token,
            sessionID: "saved-session")
        for index in 0...AgentRunPresentation.maximumTimelineItems {
            presentation.receiveRestored(
                runID: runID,
                token: token,
                event: .userMessageDelta(
                    messageID: "history-\(index)",
                    text: "History \(index)"))
        }

        let snapshot = try #require(presentation.snapshot)
        #expect(snapshot.timeline.count == AgentRunPresentation.maximumTimelineItems)
        #expect(snapshot.timeline.filter { $0 == .omitted }.count == 1)
        #expect(Set(snapshot.timeline.map(\.id)).count == snapshot.timeline.count)
        let retainedLiveMessages = snapshot.timeline.compactMap { item -> String? in
            guard case .message(let message) = item else { return nil }
            return message.text
        }
        #expect(retainedLiveMessages.count == AgentRunPresentation.maximumTimelineItems - 1)
        #expect(retainedLiveMessages.first == "Live 2")
        #expect(retainedLiveMessages.last ==
            "Live \(AgentRunPresentation.maximumTimelineItems)")
    }

    @MainActor @Test
    func historyCompletion_WhenLoadedTwice_ReplacesPriorAuthoritativeHistory()
        throws
    {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        presentation.start(
            runID: runID,
            profile: try makeAgentProfile(),
            prompt: "Current request")
        presentation.receive(
            runID: runID,
            event: .agentMessageDelta(messageID: "live-1", text: "Live one"))
        presentation.receive(
            runID: runID,
            event: .agentMessageDelta(messageID: "live-2", text: "Live two"))
        let livePresentationIDs = try #require(presentation.snapshot).timeline.compactMap {
            item -> UUID? in
            guard case .message(let message) = item else { return nil }
            return message.id
        }

        let firstToken = AgentRestorationToken()
        presentation.beginHistoryRestoration(
            runID: runID,
            token: firstToken,
            sessionID: "saved-session")
        for index in 0...AgentRunPresentation.maximumTimelineItems {
            presentation.receiveRestored(
                runID: runID,
                token: firstToken,
                event: .userMessageDelta(
                    messageID: "history-1-\(index)",
                    text: "History one \(index)"))
        }
        presentation.completeHistoryRestoration(
            runID: runID,
            token: firstToken,
            activation: .loaded(sessionID: "saved-session"))
        #expect(presentation.snapshot?.timeline.first == .omitted)

        let secondToken = AgentRestorationToken()
        presentation.beginHistoryRestoration(
            runID: runID,
            token: secondToken,
            sessionID: "saved-session")
        presentation.receiveRestored(
            runID: runID,
            token: secondToken,
            event: .userMessageDelta(messageID: "history-2", text: "History two"))
        presentation.completeHistoryRestoration(
            runID: runID,
            token: secondToken,
            activation: .loaded(sessionID: "saved-session"))

        let snapshot = try #require(presentation.snapshot)
        let labels = snapshot.timeline.map(timelineLabel)
        #expect(labels.count == 4)
        #expect(labels.contains { $0.hasPrefix("History one") } == false)
        #expect(Array(labels.prefix(4)) == [
            "History two", "boundary", "Live one", "Live two",
        ])
        #expect(snapshot.timeline.filter { $0 == .omitted }.isEmpty)
        #expect(snapshot.timeline.filter { $0 == .historyBoundary }.count == 1)
        #expect(Set(snapshot.timeline.map(\.id)).count == snapshot.timeline.count)
        #expect(snapshot.timeline.compactMap { item -> UUID? in
            guard case .message(let message) = item else { return nil }
            return message.id
        } == livePresentationIDs)
    }

    @MainActor @Test
    func historyCompletion_WhenLiveWasTruncatedBeforeRepeatedLoads_PreservesOmission()
        throws
    {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        presentation.start(
            runID: runID,
            profile: try makeAgentProfile(),
            prompt: "Current request")
        for index in 0...AgentRunPresentation.maximumTimelineItems {
            presentation.receive(
                runID: runID,
                event: .toolCall(AgentToolCall(
                    id: "live-tool-\(index)",
                    title: "Live tool \(index)",
                    kind: .read,
                    status: .completed)))
        }
        presentation.receive(
            runID: runID,
            event: .agentMessageDelta(messageID: "live-2", text: "Live tail"))
        let retainedLive = try #require(presentation.snapshot).timeline.filter { item in
            item != .omitted
        }
        #expect(presentation.snapshot?.timeline.first == .omitted)

        for (token, messageID, text) in [
            (AgentRestorationToken(), "history-1", "History one"),
            (AgentRestorationToken(), "history-2", "History two"),
        ] {
            presentation.beginHistoryRestoration(
                runID: runID,
                token: token,
                sessionID: "saved-session")
            presentation.receiveRestored(
                runID: runID,
                token: token,
                event: .userMessageDelta(messageID: messageID, text: text))
            presentation.completeHistoryRestoration(
                runID: runID,
                token: token,
                activation: .loaded(sessionID: "saved-session"))
        }

        let snapshot = try #require(presentation.snapshot)
        #expect(snapshot.timeline.count == 5)
        #expect(snapshot.timeline.first == .omitted)
        #expect(snapshot.timeline.filter { $0 == .omitted }.count == 1)
        #expect(snapshot.timeline.filter { $0 == .historyBoundary }.count == 1)
        #expect(snapshot.timeline.compactMap { item -> String? in
            guard case .userMessage(let message) = item else { return nil }
            return message.text
        } == ["History two"])
        #expect(Array(snapshot.timeline.suffix(retainedLive.count)) == retainedLive)
        #expect(Set(snapshot.timeline.map(\.id)).count == snapshot.timeline.count)
    }

    @MainActor
    private func timelineLabel(_ item: AgentRunTimelineItem) -> String {
        switch item {
        case .omitted:
            "omitted"
        case .historyBoundary:
            "boundary"
        case .message(let message):
            message.text
        case .userMessage(let message):
            message.text
        case .thinking:
            "thinking"
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
