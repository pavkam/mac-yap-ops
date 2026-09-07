// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import YapOpsApp
@testable import YapOpsCore

@Suite(.timeLimit(.minutes(1)))
struct AgentRunPresentationRestorationTests {
    @MainActor @Test
    func handleLifecycle_WhenEventIsHistorical_UpdatesPresentationWithoutCallingAudioPlayer()
        throws
    {
        let profile = try makeAgentProfile()
        let player = AgentConversationAudioSpy()
        let fixture = try AppModelTests.Fixture(
            profiles: [profile],
            agentConversationAudioPlayer: player)
        let runID = UUID()
        let token = AgentRestorationToken()
        fixture.model.handleAgentRunLifecycleEvent(
            .started(runID: runID, profile: profile, prompt: "Current request"))
        let baseline = AudioPlayerState(player)

        fixture.model.handleAgentRunLifecycleEvent(
            .historyRestorationStarted(
                runID: runID,
                token: token,
                sessionID: "restored-session"))
        fixture.model.handleAgentRunLifecycleEvent(
            .historyEvent(
                runID: runID,
                token: token,
                event: .agentMessageDelta(messageID: "history", text: "Historical answer")))
        fixture.model.handleAgentRunLifecycleEvent(
            .historyEvent(
                runID: runID,
                token: token,
                event: .connected(agentName: "Codex", sessionID: "restored-session")))

        #expect(fixture.model.agentRunSnapshot?.output == "Historical answer")
        #expect(AudioPlayerState(player) == baseline)
    }

    @MainActor @Test
    func handleLifecycle_WhenHistoryCompletes_MarksHistoricalRunningToolsInterrupted()
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
            event: .toolCall(AgentToolCall(
                id: "running-tool",
                title: "Read files",
                kind: .read,
                status: .inProgress)))
        presentation.receiveRestored(
            runID: runID,
            token: token,
            event: .plan([
                AgentPlanEntry(content: "Wait", priority: .low, status: .pending),
                AgentPlanEntry(content: "Inspect", priority: .high, status: .inProgress),
                AgentPlanEntry(content: "Explain", priority: .medium, status: .completed),
            ]))

        presentation.completeHistoryRestoration(
            runID: runID,
            token: token,
            activation: .loaded(sessionID: "saved-session"))

        let snapshot = try #require(presentation.snapshot)
        #expect(snapshot.tools.first?.status == .interrupted)
        #expect(snapshot.tools.first?.isWorking == false)
        #expect(snapshot.plan.map(\.status) == [.pending, .interrupted, .completed])
        #expect(snapshot.timeline.contains(.historyBoundary))
        guard case let .some(.thinking(currentWork)) = snapshot.timeline.last else {
            Issue.record("Expected a fresh current-turn thinking group after restored history")
            return
        }
        #expect(currentWork.isWorking)
    }

    @MainActor @Test
    func historyCompletion_WhenPlanWasNotRestored_DoesNotInterruptCurrentPlan() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        let token = AgentRestorationToken()
        presentation.start(
            runID: runID,
            profile: try makeAgentProfile(),
            prompt: "Current request")
        presentation.receive(
            runID: runID,
            event: .plan([
                AgentPlanEntry(
                    content: "Current live work",
                    priority: .high,
                    status: .inProgress),
            ]))
        presentation.beginHistoryRestoration(
            runID: runID,
            token: token,
            sessionID: "saved-session")
        presentation.receiveRestored(
            runID: runID,
            token: token,
            event: .toolCall(AgentToolCall(
                id: "historical-tool",
                title: "Read files",
                kind: .read,
                status: .inProgress)))

        presentation.completeHistoryRestoration(
            runID: runID,
            token: token,
            activation: .loaded(sessionID: "saved-session"))

        #expect(presentation.snapshot?.plan.map(\.status) == [.inProgress])
    }

    @MainActor @Test
    func handleLifecycle_WhenResumeHasNoReplay_ShowsProviderHistoryNotice() throws {
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

        presentation.completeHistoryRestoration(
            runID: runID,
            token: token,
            activation: .resumed(sessionID: "saved-session"))

        #expect(presentation.snapshot?.notices == [
            "Previous history is available to the agent but this provider cannot replay it.",
        ])
    }

    @MainActor @Test
    func handleLifecycle_WhenRestoreUnsupported_ShowsFreshConversationNotice() throws {
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

        presentation.completeHistoryRestoration(
            runID: runID,
            token: token,
            activation: .freshBecauseRestorationUnsupported(sessionID: "fresh-session"))

        #expect(presentation.snapshot?.notices == [
            "This provider cannot restore previous history, so a fresh conversation was started.",
        ])
    }

    @MainActor @Test
    func handleLifecycle_WhenRestorationTokenIsStale_IgnoresHistory() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        presentation.start(
            runID: runID,
            profile: try makeAgentProfile(),
            prompt: "Current request")
        presentation.beginHistoryRestoration(
            runID: runID,
            token: AgentRestorationToken(),
            sessionID: "saved-session")

        presentation.receiveRestored(
            runID: runID,
            token: AgentRestorationToken(),
            event: .agentMessageDelta(messageID: "stale", text: "Stale history"))

        #expect(presentation.snapshot?.output.isEmpty == true)
    }

    @MainActor @Test
    func handleLifecycle_WhenFirstAttemptAborts_ClearsItsPartialRowsBeforeFallback()
        throws
    {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        let firstToken = AgentRestorationToken()
        presentation.start(
            runID: runID,
            profile: try makeAgentProfile(),
            prompt: "Current request")
        presentation.receive(
            runID: runID,
            event: .agentMessageDelta(messageID: "live", text: "Already live"))
        presentation.beginHistoryRestoration(
            runID: runID,
            token: firstToken,
            sessionID: "missing-session")
        presentation.receiveRestored(
            runID: runID,
            token: firstToken,
            event: .userMessageDelta(messageID: "old-request", text: "Partial request"))
        presentation.receiveRestored(
            runID: runID,
            token: firstToken,
            event: .agentMessageDelta(messageID: "old-answer", text: "Partial answer"))

        presentation.abortHistoryRestoration(runID: runID, token: firstToken)
        presentation.receive(
            runID: runID,
            event: .metadata(
                kind: AgentRunMetadataKind.sessionRecovered,
                summary: "A fresh agent session was started."))

        let snapshot = try #require(presentation.snapshot)
        #expect(snapshot.output == "Already live")
        #expect(snapshot.notices == ["A fresh agent session was started."])
        #expect(!snapshot.timeline.contains { item in
            switch item {
            case .message(let message): message.text.contains("Partial")
            case .userMessage(let message): message.text.contains("Partial")
            case .thinking, .historyBoundary, .omitted: false
            }
        })
    }

    @MainActor @Test
    func handleLifecycle_WhenNewLiveAnswerArrives_SpeaksOnlyThatAnswer() throws {
        let player = AgentConversationAudioSpy()
        let presenter = AgentConversationAudioPresenter(
            player: player,
            readsReplies: { true },
            playsWorkingSound: { true },
            localeID: { "en-US" })
        let runID = UUID()
        let token = AgentRestorationToken()
        presenter.handle(.started(
            runID: runID,
            profile: try makeAgentProfile(),
            prompt: "Current request"))

        presenter.handle(.historyRestorationStarted(
            runID: runID,
            token: token,
            sessionID: "saved-session"))
        presenter.handle(.historyEvent(
            runID: runID,
            token: token,
            event: .agentMessageDelta(messageID: "history", text: "Historical answer.")))
        presenter.handle(.historyRestorationCompleted(
            runID: runID,
            token: token,
            activation: .loaded(sessionID: "saved-session")))
        presenter.handle(.event(
            runID: runID,
            event: .agentMessageDelta(messageID: "live", text: "Current answer.")))

        #expect(player.spoken.map(\.text) == ["Current answer."])
    }

    @MainActor @Test
    func historyLifecycle_WhenToolAndPermissionRestore_ProducesNoAudioOrActivePermission()
        throws
    {
        let profile = try makeAgentProfile()
        let player = AgentConversationAudioSpy()
        let fixture = try AppModelTests.Fixture(
            profiles: [profile],
            agentConversationAudioPlayer: player)
        let runID = UUID()
        let token = AgentRestorationToken()
        fixture.model.handleAgentRunLifecycleEvent(
            .started(runID: runID, profile: profile, prompt: "Current request"))
        let baseline = AudioPlayerState(player)
        fixture.model.handleAgentRunLifecycleEvent(.historyRestorationStarted(
            runID: runID,
            token: token,
            sessionID: "saved-session"))
        fixture.model.handleAgentRunLifecycleEvent(.historyEvent(
            runID: runID,
            token: token,
            event: .toolCall(AgentToolCall(
                id: "tool",
                title: "Edit file",
                kind: .edit,
                status: .inProgress))))
        fixture.model.handleAgentRunLifecycleEvent(.historyEvent(
            runID: runID,
            token: token,
            event: .permissionRequested(permissionRequest())))
        fixture.model.handleAgentRunLifecycleEvent(.historyRestorationCompleted(
            runID: runID,
            token: token,
            activation: .loaded(sessionID: "saved-session")))

        #expect(fixture.model.agentRunSnapshot?.permissions.isEmpty == true)
        #expect(AudioPlayerState(player) == baseline)
    }

    @MainActor @Test
    func historyLifecycle_WhenOldTokenArrivesAfterReplacement_IgnoresEveryLateMutation()
        throws
    {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        let oldToken = AgentRestorationToken()
        let currentToken = AgentRestorationToken()
        presentation.start(
            runID: runID,
            profile: try makeAgentProfile(),
            prompt: "Current request")
        presentation.beginHistoryRestoration(
            runID: runID,
            token: oldToken,
            sessionID: "old-session")
        presentation.abortHistoryRestoration(runID: runID, token: oldToken)
        presentation.beginHistoryRestoration(
            runID: runID,
            token: currentToken,
            sessionID: "current-session")

        presentation.receiveRestored(
            runID: runID,
            token: oldToken,
            event: .agentMessageDelta(messageID: "late", text: "Late old history"))
        presentation.completeHistoryRestoration(
            runID: runID,
            token: oldToken,
            activation: .loaded(sessionID: "old-session"))
        presentation.abortHistoryRestoration(runID: runID, token: oldToken)
        presentation.receiveRestored(
            runID: runID,
            token: currentToken,
            event: .agentMessageDelta(messageID: "current", text: "Current history"))
        presentation.completeHistoryRestoration(
            runID: runID,
            token: currentToken,
            activation: .loaded(sessionID: "current-session"))

        #expect(presentation.snapshot?.output == "Current history")
    }

    @MainActor @Test
    func historyLifecycle_WhenReplayIsLarge_PreservesBoundedOrderAndExistingCaps() throws {
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

        for index in 0...AgentRunPresentation.maximumTimelineItems {
            presentation.receiveRestored(
                runID: runID,
                token: token,
                event: .userMessageDelta(messageID: "request-\(index)", text: "Request \(index)"))
        }
        presentation.receiveRestored(
            runID: runID,
            token: token,
            event: .agentMessageDelta(
                messageID: "large-answer",
                text: String(repeating: "x", count: 600_000) + "newest-marker"))
        presentation.completeHistoryRestoration(
            runID: runID,
            token: token,
            activation: .loaded(sessionID: "saved-session"))

        let snapshot = try #require(presentation.snapshot)
        #expect(snapshot.output.utf8.count <= AgentRunPresentation.maximumOutputBytes)
        #expect(snapshot.output.hasSuffix("newest-marker"))
        #expect(snapshot.timeline.count <= AgentRunPresentation.maximumTimelineItems)
        #expect(snapshot.timeline.first == .omitted)
        #expect(snapshot.timeline.contains(.historyBoundary))
        #expect(snapshot.timeline.last?.id != .historyBoundary)
    }

    @MainActor @Test
    func historyLifecycle_WhenUserChunkRoleIsNotRequest_SuppressesItBeforePresentation()
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
        let updates = [
            #"{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"Missing role"},"messageId":"missing"}"#,
            #"{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"Instruction","_meta":{"ciobanu.org.yapOps":{"promptBlockRole":"instruction"}}},"messageId":"instruction"}"#,
            #"{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"Kept request","_meta":{"ciobanu.org.yapOps":{"promptBlockRole":"request"}}},"messageId":"request"}"#,
        ]

        for update in updates {
            if let event = try ACPEventDecoder().event(from: message(update: update)) {
                presentation.receiveRestored(runID: runID, token: token, event: event)
            }
        }
        presentation.completeHistoryRestoration(
            runID: runID,
            token: token,
            activation: .loaded(sessionID: "saved-session"))

        let userMessages = presentation.snapshot?.timeline.compactMap { item -> String? in
            guard case .userMessage(let message) = item else { return nil }
            return message.text
        }
        #expect(userMessages == ["Kept request"])
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

    private func permissionRequest() -> AgentPermissionRequest {
        AgentPermissionRequest(
            turnToken: AgentTurnToken(),
            requestID: .string("historical-permission"),
            toolCall: AgentToolCallUpdate(
                id: "tool",
                title: "Edit file",
                kind: .edit,
                status: .inProgress),
            options: [
                AgentPermissionOption(id: "allow", label: "Allow", kind: .allowOnce),
            ])
    }

    private func message(update: String) throws -> ACPMessage {
        let data = Data(
            #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"saved-session","update":\#(update)}}"#.utf8)
        return try JSONDecoder().decode(ACPMessage.self, from: data)
    }
}

@MainActor
private struct AudioPlayerState: Equatable {
    let begunProfileCount: Int
    let endConversationCount: Int
    let workingStates: [Bool]
    let activitySounds: [AgentActivitySound]
    let spokenText: [String]
    let stopSpeakingCount: Int
    let stopAllCount: Int

    init(_ player: AgentConversationAudioSpy) {
        begunProfileCount = player.begunProfiles.count
        endConversationCount = player.endConversationCount
        workingStates = player.workingStates
        activitySounds = player.activitySounds
        spokenText = player.spoken.map(\.text)
        stopSpeakingCount = player.stopSpeakingCount
        stopAllCount = player.stopAllCount
    }
}
