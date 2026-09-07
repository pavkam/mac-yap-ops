// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import YapOpsApp
@testable import YapOpsCore

struct AgentRunPresentationInputDispositionTests {
    @MainActor @Test
    func followUpDisposition_WhenInputMatches_UpdatesOnlyThatTimelineRow() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        presentation.start(runID: runID, profile: try agentProfile(), prompt: "Start")
        presentation.submitFollowUp(
            runID: runID,
            inputID: firstID,
            prompt: "also add tests",
            disposition: .routing)
        presentation.submitFollowUp(
            runID: runID,
            inputID: secondID,
            prompt: "and run them",
            disposition: .routing)

        presentation.updateFollowUp(
            runID: runID,
            inputID: firstID,
            disposition: .injected)

        let messages: [AgentUserMessagePresentation]? = presentation.snapshot?.timeline.compactMap { item in
            guard case .userMessage(let message) = item else { return nil }
            return message
        }
        #expect(messages?.map(\.id) == [firstID, secondID])
        #expect(messages?.map(\.disposition) == [.injected, .routing])
    }

    @MainActor @Test
    func followUpDisposition_WhenRunOrInputIsStale_DoesNotMutateSnapshot() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        let inputID = UUID()
        presentation.start(runID: runID, profile: try agentProfile(), prompt: "Start")
        presentation.submitFollowUp(
            runID: runID,
            inputID: inputID,
            prompt: "Keep this",
            disposition: .routing)
        let original = presentation.snapshot

        presentation.updateFollowUp(
            runID: UUID(),
            inputID: inputID,
            disposition: .injected)
        presentation.updateFollowUp(
            runID: runID,
            inputID: UUID(),
            disposition: .failed)

        #expect(presentation.snapshot == original)
    }

    @Test(arguments: [
        (AgentConversationInputDisposition.routing, "Routing…"),
        (.injected, "Added to current turn"),
        (.queued, "Queued for next turn"),
        (.prompted, "Started as next turn"),
        (.failed, "Delivery failed — say it again"),
    ])
    func presentationLabel_WhenDispositionIsKnown_DescribesTransportExactly(
        disposition: AgentConversationInputDisposition,
        expected: String
    ) {
        #expect(disposition.presentationLabel == expected)
    }

    @MainActor @Test
    func restoredUserMessage_WhenHistoryLoads_HasNoCurrentTransportDisposition() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        let token = AgentRestorationToken()
        presentation.start(runID: runID, profile: try agentProfile(), prompt: "Start")
        presentation.beginHistoryRestoration(
            runID: runID,
            token: token,
            sessionID: "restored-session")
        presentation.receiveRestored(
            runID: runID,
            token: token,
            event: .userMessageDelta(messageID: "historical", text: "Old request"))
        presentation.completeHistoryRestoration(
            runID: runID,
            token: token,
            activation: .loaded(sessionID: "restored-session"))

        let messages: [AgentUserMessagePresentation]? = presentation.snapshot?.timeline.compactMap { item in
            guard case .userMessage(let message) = item else { return nil }
            return message
        }
        let historical = try #require(messages?.first)
        #expect(historical.disposition == nil)
    }

    private func agentProfile() throws -> WakeProfile {
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
