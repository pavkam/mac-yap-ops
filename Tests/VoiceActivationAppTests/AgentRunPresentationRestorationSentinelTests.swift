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
    func historyCompletion_WhenLoadedTwice_PreservesOneCorrectlyPlacedBoundary()
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
            event: .agentMessageDelta(messageID: "live", text: "Live"))

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
        #expect(snapshot.timeline.map(timelineLabel) == [
            "History two", "History one", "boundary", "Live",
        ])
        #expect(snapshot.timeline.filter { $0 == .historyBoundary }.count == 1)
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
