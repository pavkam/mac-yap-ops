// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import YapOpsApp
@testable import YapOpsCore

@Suite(.timeLimit(.minutes(1)))
struct AgentRunPresentationResponseChannelTests {
    @MainActor @Test
    func spokenAndDisplayDeltas_RemainSeparatelyVisibleAndCopyable() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        presentation.start(runID: runID, profile: try profile(), prompt: "Question")

        presentation.receive(
            runID: runID,
            event: .agentSpokenMessageDelta(
                messageID: "spoken",
                text: "  Spoken exactly.  "))
        presentation.receive(
            runID: runID,
            event: .agentDisplayMessageDelta(
                messageID: "display",
                text: "**Rich display.**"))

        let snapshot = try #require(presentation.snapshot)
        #expect(snapshot.spokenOutput == "  Spoken exactly.  ")
        #expect(snapshot.output == "**Rich display.**")
        #expect(snapshot.copyText.contains("Spoken response\n  Spoken exactly.  "))
        #expect(snapshot.copyText.contains("Response\n**Rich display.**"))
        let messages = snapshot.timeline.compactMap { item -> AgentMessagePresentation? in
            guard case .message(let message) = item else { return nil }
            return message
        }
        #expect(messages.map(\.kind) == [.spokenResponse, .response])
        #expect(messages.map(\.text) == ["  Spoken exactly.  ", "**Rich display.**"])
    }

    @MainActor @Test
    func spokenOutput_TruncatesAtBound() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        presentation.start(runID: runID, profile: try profile(), prompt: "Question")

        presentation.receive(
            runID: runID,
            event: .agentSpokenMessageDelta(
                messageID: "spoken",
                text: String(repeating: "x", count: AgentRunPresentation.maximumSpokenOutputBytes)
                    + "🧪"))

        let spokenOutput = try #require(presentation.snapshot?.spokenOutput)
        #expect(spokenOutput.utf8.count <= AgentRunPresentation.maximumSpokenOutputBytes)
        #expect(spokenOutput.hasPrefix("… earlier spoken response omitted …"))
        #expect(spokenOutput.hasSuffix("🧪"))
    }

    @MainActor @Test
    func staleRun_CannotAppendEitherChannel() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        let restorationToken = AgentRestorationToken()
        presentation.start(runID: runID, profile: try profile(), prompt: "Question")
        presentation.beginHistoryRestoration(
            runID: runID,
            token: restorationToken,
            sessionID: "session")

        presentation.receive(
            runID: UUID(),
            event: .agentSpokenMessageDelta(messageID: "stale", text: "Stale spoken"))
        presentation.receive(
            runID: UUID(),
            event: .agentDisplayMessageDelta(messageID: "stale", text: "Stale display"))
        presentation.receiveRestored(
            runID: runID,
            token: AgentRestorationToken(),
            event: .agentSpokenMessageDelta(messageID: "stale-history", text: "Old spoken"))
        presentation.receiveRestored(
            runID: runID,
            token: AgentRestorationToken(),
            event: .agentDisplayMessageDelta(messageID: "stale-history", text: "Old display"))
        presentation.complete(
            runID: runID,
            result: AgentRunResult(stopReason: .endTurn))
        presentation.receive(
            runID: runID,
            event: .agentSpokenMessageDelta(messageID: "retired", text: "Retired spoken"))
        presentation.receive(
            runID: runID,
            event: .agentDisplayMessageDelta(messageID: "retired", text: "Retired display"))

        #expect(presentation.snapshot?.spokenOutput == "")
        #expect(presentation.snapshot?.output == "")
    }

    private func profile() throws -> WakeProfile {
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
