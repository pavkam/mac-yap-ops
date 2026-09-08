// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AppKit
import Foundation
import Testing
@testable import YapOpsCore


extension YapOpsCoordinatorTests {
    @MainActor
    @Test func agentConversation_WhenUtteranceCompletes_AttachesFrozenMacContext() async throws {
        let target = MacContextTarget(
            processIdentifier: 42,
            applicationName: "Safari",
            bundleIdentifier: "com.apple.Safari")
        let context = ControlledMacContextCapturer(
            target: target,
            snapshot: makeMacContextSnapshot(target: target, selectedText: "selected"))
        let fixture = try Fixture(
            profiles: [try makeAgentProfile()],
            contextCapturer: context)
        fixture.coordinator.setPassiveEnabled(true)

        fixture.speech.emit("agent summarize this", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }

        let invocation = try #require(await fixture.agentRunner.recordedInvocations().first)
        #expect(context.currentTargetCallCount == 1)
        #expect(context.capturedTargets == [target])
        #expect(invocation.prompt.request == "summarize this")
        #expect(invocation.prompt.context?.selectedText == "selected")
        await fixture.agentRunner.complete(runIndex: 0)
    }

    @MainActor
    @Test func agentConversation_WhenFollowUpIsQueued_UsesContextFrozenAtAdmission() async throws {
        let safari = MacContextTarget(
            processIdentifier: 42,
            applicationName: "Safari",
            bundleIdentifier: "com.apple.Safari")
        let finder = MacContextTarget(
            processIdentifier: 84,
            applicationName: "Finder",
            bundleIdentifier: "com.apple.finder")
        let context = ControlledMacContextCapturer(
            target: safari,
            snapshot: makeMacContextSnapshot(target: safari, selectedText: "Safari selection"))
        let fixture = try Fixture(
            profiles: [try makeAgentProfile()],
            contextCapturer: context)
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent inspect this", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }

        context.target = finder
        context.nextSnapshot = makeMacContextSnapshot(
            target: finder,
            selectedText: "Finder selection at admission")
        context.suspendsCaptures = true
        fixture.speech.emit("also inspect these", isFinal: true)
        await waitUntil { context.capturedTargets.count == 2 }
        context.nextSnapshot = makeMacContextSnapshot(
            target: finder,
            selectedText: "Finder selection after admission")
        context.completeCapture(at: 1)
        await waitUntil { await fixture.agentRunner.recordedMidTurnOffers().count == 1 }
        await fixture.agentRunner.complete(runIndex: 0)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 2 }

        let invocations = await fixture.agentRunner.recordedInvocations()
        #expect(invocations[1].prompt.context?.applicationName == "Finder")
        #expect(invocations[1].prompt.context?.selectedText == "Finder selection at admission")
        await fixture.agentRunner.complete(runIndex: 1)
    }

    @MainActor
    @Test func agentConversation_WhenContextCaptureTimesOut_AttachesTimedOutSnapshot() async throws {
        let target = MacContextTarget(
            processIdentifier: 42,
            applicationName: "Safari",
            bundleIdentifier: "com.apple.Safari")
        let context = ControlledMacContextCapturer(
            target: target,
            snapshot: makeMacContextSnapshot(target: target, state: .timedOut))
        let fixture = try Fixture(
            profiles: [try makeAgentProfile()],
            contextCapturer: context)
        fixture.coordinator.setPassiveEnabled(true)

        fixture.speech.emit("agent explain this", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }

        let invocation = try #require(await fixture.agentRunner.recordedInvocations().first)
        #expect(invocation.prompt.context?.captureState == .timedOut)
        #expect(invocation.prompt.context?.applicationName == "Safari")
        await fixture.agentRunner.complete(runIndex: 0)
    }

    @MainActor
    @Test func cancelAgentRun_WhenContextCaptureIsPending_NeverEntersRunner() async throws {
        let target = MacContextTarget(
            processIdentifier: 42,
            applicationName: "Safari",
            bundleIdentifier: nil)
        let context = ControlledMacContextCapturer(target: target)
        context.suspendsCaptures = true
        let fixture = try Fixture(
            profiles: [try makeAgentProfile()],
            contextCapturer: context)
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent never start", isFinal: true)
        await waitUntil { context.capturedTargets.count == 1 }

        fixture.coordinator.cancelAgentRun()
        await waitUntil {
            let cancelCount = await fixture.agentRunner.cancelCount
            return context.cancelledCaptureIndices == [0] && cancelCount == 1
        }

        #expect(await fixture.agentRunner.recordedInvocations().isEmpty)
        #expect(await fixture.agentRunner.recordedRunAttemptCount() == 0)
    }

    @MainActor
    @Test func agentConversation_WhenOldCaptureCompletesLate_DoesNotPopulateLaterTurn() async throws {
        let safari = MacContextTarget(
            processIdentifier: 42,
            applicationName: "Safari",
            bundleIdentifier: nil)
        let finder = MacContextTarget(
            processIdentifier: 84,
            applicationName: "Finder",
            bundleIdentifier: nil)
        let context = ControlledMacContextCapturer(target: safari)
        context.suspendsCaptures = true
        context.resolvesCancellation = false
        let fixture = try Fixture(
            profiles: [try makeAgentProfile()],
            contextCapturer: context)
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent old request", isFinal: true)
        await waitUntil { context.capturedTargets.count == 1 }
        fixture.coordinator.cancelAgentRun()
        await waitUntil {
            await fixture.agentRunner.cancelCount == 1
                && fixture.coordinator.agentCancellationTask == nil
        }
        #expect(fixture.coordinator.resumeAgentConversationListening())

        context.target = finder
        context.nextSnapshot = makeMacContextSnapshot(target: finder, selectedText: "new")
        fixture.speech.emit("new request", isFinal: true)
        await waitUntil { context.capturedTargets.count == 2 }
        context.completeCapture(at: 1)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        context.completeCapture(
            at: 0,
            with: makeMacContextSnapshot(target: safari, selectedText: "old"))
        try await Task.sleep(for: .milliseconds(30))

        let invocations = await fixture.agentRunner.recordedInvocations()
        #expect(await fixture.agentRunner.recordedRunAttemptCount() == 1)
        #expect(invocations.map(\.prompt.request) == ["new request"])
        #expect(invocations.first?.prompt.context?.selectedText == "new")
        await fixture.agentRunner.complete(runIndex: 0)
    }

    @MainActor
    @Test func agentExecution_WhenAppKitTracksEvents_PublishesStreamingOutputImmediately()
        async throws
    {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        var streamedText = ""
        fixture.coordinator.onAgentRunEvent = { event in
            guard case .event(_, .agentMessageDelta(_, let text)) = event else { return }
            streamedText.append(text)
        }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent inspect this", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        Task.detached {
            try? await Task.sleep(for: .milliseconds(10))
            await fixture.agentRunner.emit(
                .agentMessageDelta(messageID: "answer", text: "Streaming now"),
                from: 0)
        }

        runCoordinatorEventTrackingLoop {
            streamedText.isEmpty
        }
        fixture.coordinator.cancelAgentRun()

        #expect(streamedText == "Streaming now")
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func agentExecution_WhenConversationRecognitionStartBlocks_StartsRunnerConcurrently()
        async throws
    {
        let profile = try makeAgentProfile()
        let fixture = try Fixture(profiles: [profile])
        let gate = ConversationStartGate()
        fixture.speech.blockNextConversationStart(using: gate)
        fixture.coordinator.setPassiveEnabled(true)

        let runnerStartedBeforeSpeechReturned = Task.detached {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(1))
            while clock.now < deadline {
                if await fixture.agentRunner.recordedInvocations().count == 1 {
                    gate.release()
                    return true
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
            gate.release()
            return false
        }

        fixture.speech.emit("agent inspect the parser", isFinal: true)

        #expect(await runnerStartedBeforeSpeechReturned.value)
        await waitUntil {
            await fixture.agentRunner.recordedInvocations().count == 1
        }
        await fixture.agentRunner.complete(runIndex: 0)
    }

    @MainActor
    @Test func execution_WhenProfileUsesAgent_RoutesTranscriptAndPublishesEventsInOrder() async throws {
        let commandProfile = try WakeProfile(
            wakePhrase: "computer",
            urlTemplate: "https://example.com/?q={urlText}",
            accent: .blue)
        let agentProfile = try makeAgentProfile()
        let fixture = try Fixture(profiles: [commandProfile, agentProfile])
        var lifecycleEvents: [AgentRunLifecycleEvent] = []
        fixture.coordinator.onAgentRunEvent = { lifecycleEvents.append($0) }
        fixture.coordinator.setPassiveEnabled(true)

        fixture.speech.emit("agent inspect the parser", isFinal: true)
        await waitUntil {
            await fixture.agentRunner.recordedInvocations().count == 1
        }
        await fixture.agentRunner.emit(
            .connected(agentName: "Codex", sessionID: "session-1"),
            from: 0)
        await fixture.agentRunner.emit(
            .agentMessageDelta(messageID: "message-1", text: "Checking"),
            from: 0)

        #expect(await fixture.runner.recordedTranscripts().isEmpty)
        #expect(await fixture.agentRunner.recordedInvocations() == [
            ControlledAgentRunner.Invocation(
                profileID: agentProfile.id,
                configuration: try makeAgentConfiguration(),
                prompt: AgentPrompt(request: "inspect the parser", context: nil),
                restorationNeed: .fresh,
                runContinuity: AgentRunContinuityRequest()),
        ])
        guard case let .started(runID, startedProfile, prompt) = lifecycleEvents.first else {
            Issue.record("Expected an agent run start")
            return
        }
        #expect(startedProfile == agentProfile)
        #expect(prompt == "inspect the parser")
        #expect(Array(lifecycleEvents.dropFirst()) == [
            .inputContextCaptured(runID: runID, inputID: nil, summary: .init(context: nil)),
            .event(
                runID: runID,
                event: .connected(agentName: "Codex", sessionID: "session-1")),
            .event(
                runID: runID,
                event: .agentMessageDelta(messageID: "message-1", text: "Checking")),
        ])

        await fixture.agentRunner.complete(runIndex: 0)
        await waitUntil {
            lifecycleEvents.last == .turnCompleted(
                runID: runID,
                result: AgentRunResult(stopReason: .endTurn))
                && fixture.speech.mode == .conversation
        }
        #expect(fixture.coordinator.state == .executing)
    }

    @MainActor
    @Test func agentConversation_WhenFollowUpIsSpoken_ReusesConversationAndAgentSession() async throws {
        let profile = try makeAgentProfile()
        let fixture = try Fixture(profiles: [profile])
        var lifecycleEvents: [AgentRunLifecycleEvent] = []
        fixture.coordinator.onAgentRunEvent = { lifecycleEvents.append($0) }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent inspect the parser", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        guard case let .started(runID, _, _) = lifecycleEvents.first else {
            Issue.record("Expected conversation start")
            return
        }
        await fixture.agentRunner.complete(runIndex: 0)
        await waitUntil { fixture.speech.mode == .conversation }

        fixture.speech.emit("now show me the tests", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 2 }

        #expect(await fixture.agentRunner.recordedInvocations().map(\.prompt) == [
            AgentPrompt(request: "inspect the parser", context: nil),
            AgentPrompt(request: "now show me the tests", context: nil),
        ])
        #expect(lifecycleEvents.contains { event in
            guard case let .followUpSubmitted(
                submittedRunID, _, prompt, disposition) = event
            else { return false }
            return submittedRunID == runID
                && prompt == "now show me the tests"
                && disposition == .routing
        })
        #expect(lifecycleEvents.contains(.turnStarted(runID: runID)))
        await fixture.agentRunner.complete(runIndex: 1)
    }

    @MainActor
    @Test func agentConversation_WhenActiveTurnAcceptsInput_SteersWithoutCancellation() async throws {
        let profile = try makeAgentProfile()
        let fixture = try Fixture(profiles: [profile])
        await fixture.agentRunner.enqueueMidTurnResults([.injected])
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent inspect this", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }

        fixture.speech.emit("also add tests", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedMidTurnOffers().count == 1 }

        #expect(await fixture.agentRunner.cancelCount == 0)
        #expect(await fixture.agentRunner.recordedInvocations().count == 1)
        #expect(await fixture.agentRunner.recordedMidTurnOffers() == [
            ControlledAgentRunner.MidTurnOffer(
                profileID: profile.id,
                prompt: AgentPrompt(request: "also add tests", context: nil)),
        ])
        await fixture.agentRunner.complete(runIndex: 0)
    }

    @MainActor
    @Test func agentConversation_WhenStopIsSpoken_EndsConversationAndReturnsToPassiveWake() async throws {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        var lifecycleEvents: [AgentRunLifecycleEvent] = []
        fixture.coordinator.onAgentRunEvent = { lifecycleEvents.append($0) }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent inspect this", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        guard case let .started(runID, _, _) = lifecycleEvents.first else {
            Issue.record("Expected conversation start")
            return
        }

        fixture.speech.emit("stop", isFinal: true)
        await waitUntil {
            await fixture.agentRunner.cancelCount == 1
                && lifecycleEvents.contains(.completed(
                    runID: runID,
                    result: AgentRunResult(stopReason: .cancelled)))
                && fixture.speech.mode == .passiveWake
        }

        #expect(fixture.speech.mode == .passiveWake)
        #expect(fixture.coordinator.state == .listening)
        #expect(await fixture.agentRunner.recordedInvocations().count == 1)
        await fixture.agentRunner.complete(runIndex: 0)
    }

    @MainActor
    @Test func endAgentConversation_WhenWaitingForFollowUp_ReturnsToPassiveWake() async throws {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        var turnCompleted = false
        fixture.coordinator.onAgentRunEvent = { event in
            if case .turnCompleted = event {
                turnCompleted = true
            }
        }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent inspect this", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        await fixture.agentRunner.complete(runIndex: 0)
        await waitUntil { turnCompleted }

        fixture.coordinator.endAgentConversation()
        await waitUntil { fixture.speech.mode == .passiveWake }

        #expect(fixture.coordinator.state == .listening)
    }

    @MainActor
    @Test func agentConversation_WhenCancelIsSpokenWhileIdle_EndsConversation() async throws {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        var turnCompleted = false
        var lifecycleEvents: [AgentRunLifecycleEvent] = []
        fixture.coordinator.onAgentRunEvent = { event in
            lifecycleEvents.append(event)
            if case .turnCompleted = event {
                turnCompleted = true
            }
        }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent inspect this", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        await fixture.agentRunner.complete(runIndex: 0)
        await waitUntil { turnCompleted }

        fixture.speech.emit("cancel", isFinal: true)
        await waitUntil { fixture.speech.mode == .passiveWake }

        #expect(fixture.coordinator.state == .listening)
        #expect(await fixture.agentRunner.cancelCount == 0)
        guard case let .started(runID, _, _) = lifecycleEvents.first else {
            Issue.record("Expected conversation start")
            return
        }
        #expect(lifecycleEvents.contains(.completed(
            runID: runID,
            result: AgentRunResult(stopReason: .cancelled))))
    }

    @MainActor
    @Test func agentConversation_WhenReplyIsPlaying_DiscardsEchoAndResumesFreshCapture() async throws {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        defer { fixture.coordinator.stop() }
        var speechCancellationCount = 0
        fixture.coordinator.onAgentSpeechCancellation = { speechCancellationCount += 1 }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent explain this", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        fixture.speech.emit("partial microphone input")

        fixture.coordinator.setAgentSpeechOutputActive(true)
        #expect(fixture.speech.mode == nil)
        fixture.speech.emit("speaker echo", isFinal: true)
        fixture.speech.emitFromRetiredSession("late echo", isFinal: true)
        fixture.coordinator.startConversationListening()
        #expect(fixture.speech.mode == nil)
        #expect(fixture.coordinator.pendingAgentPrompts.isEmpty)
        #expect(fixture.coordinator.currentTranscript.isEmpty)
        #expect(speechCancellationCount == 0)

        fixture.coordinator.setAgentSpeechOutputActive(false)
        #expect(fixture.speech.mode == .conversation)
        fixture.speech.emitFromRetiredSession("delayed echo", isFinal: true)
        fixture.speech.emit("fresh follow up", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedMidTurnOffers().count == 1 }
        #expect(await fixture.agentRunner.recordedMidTurnOffers().map(\.prompt.request) == [
            "fresh follow up",
        ])
        await fixture.agentRunner.complete(runIndex: 0)
    }

    @MainActor
    @Test func agentConversation_WhenReplyPlaybackStarts_StopsRecognition() async throws {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        var turnCompleted = false
        fixture.coordinator.onAgentRunEvent = { event in
            if case .turnCompleted = event {
                turnCompleted = true
            }
        }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent explain this", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        await fixture.agentRunner.complete(runIndex: 0)
        await waitUntil { turnCompleted }
        let startCount = fixture.speech.startCount

        fixture.coordinator.setAgentSpeechOutputActive(true)

        #expect(fixture.speech.startCount == startCount)
        #expect(fixture.speech.mode == nil)
    }

    @MainActor
    @Test func agentConversation_WhenReplyIsBeingRead_PushToTalkInterruptsAndLetsStopEndConversation() async throws {
        let profile = try makeAgentProfile()
        let fixture = try Fixture(profiles: [profile])
        var speechCancellationCount = 0
        var turnCompleted = false
        fixture.coordinator.onAgentSpeechCancellation = { speechCancellationCount += 1 }
        fixture.coordinator.onAgentRunEvent = { event in
            if case .turnCompleted = event {
                turnCompleted = true
            }
        }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent explain this", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        await fixture.agentRunner.complete(runIndex: 0)
        await waitUntil { turnCompleted }
        fixture.coordinator.setAgentSpeechOutputActive(true)

        fixture.coordinator.pushToTalkPressed(profileID: profile.id)
        #expect(speechCancellationCount == 1)
        #expect(fixture.speech.mode == .pushToTalk)
        fixture.speech.emit("stop", isFinal: true)
        await waitUntil { fixture.speech.mode == .passiveWake }

        #expect(speechCancellationCount == 1)
        #expect(fixture.coordinator.state == .listening)
    }

    @MainActor
    @Test func agentConversation_WhenVoiceUtteranceIsConsumed_DoesNotSubmitItAsFollowUp() async throws {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        var consumedUtterances: [String] = []
        var turnCompleted = false
        fixture.coordinator.onAgentVoiceUtterance = { utterance in
            consumedUtterances.append(utterance)
            return true
        }
        fixture.coordinator.onAgentRunEvent = { event in
            if case .turnCompleted = event {
                turnCompleted = true
            }
        }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent request access", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        await fixture.agentRunner.complete(runIndex: 0)
        await waitUntil { turnCompleted }

        fixture.speech.emit("allow all", isFinal: true)
        try await Task.sleep(for: .milliseconds(30))

        #expect(consumedUtterances == ["allow all"])
        #expect(await fixture.agentRunner.recordedInvocations().count == 1)
        #expect(fixture.speech.contextualStrings.contains("allow all"))
    }

    @MainActor
    @Test func endAgentConversation_WhenTerminalEventStartsAcknowledgement_DoesNotRestartConversationCapture() async throws {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        var turnCompleted = false
        fixture.coordinator.onAgentRunEvent = { event in
            if case .turnCompleted = event {
                turnCompleted = true
            }
            if case .completed = event {
                fixture.coordinator.setAgentSpeechOutputActive(true)
            }
        }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent explain this", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        await fixture.agentRunner.complete(runIndex: 0)
        await waitUntil { turnCompleted }
        fixture.coordinator.setAgentSpeechOutputActive(true)
        let startCountBeforeEnding = fixture.speech.startCount

        fixture.coordinator.endAgentConversation()
        await waitUntil { fixture.speech.mode == .passiveWake }

        #expect(fixture.speech.startCount == startCountBeforeEnding + 1)
    }

    @MainActor @Test func resolveAgentPermission_WhenRunIsCurrent_ForwardsExactTuple() async throws {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        var lifecycleEvents: [AgentRunLifecycleEvent] = []
        fixture.coordinator.onAgentRunEvent = { lifecycleEvents.append($0) }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent request access", isFinal: true)
        await waitUntil {
            await fixture.agentRunner.recordedInvocations().count == 1
        }
        guard case let .started(runID, _, _) = lifecycleEvents.first else {
            Issue.record("Expected an agent run start")
            return
        }
        let turnToken = AgentTurnToken()
        let requestID = ACPRequestID.string("permission-42")

        fixture.coordinator.resolveAgentPermission(
            runID: runID,
            turnToken: turnToken,
            requestID: requestID,
            optionID: "allow-once")
        await waitUntil {
            await fixture.agentRunner.recordedPermissionResolutions().count == 1
        }

        #expect(await fixture.agentRunner.recordedPermissionResolutions() == [
            ControlledAgentRunner.PermissionResolution(
                turnToken: turnToken,
                requestID: requestID,
                optionID: "allow-once"),
        ])
        await fixture.agentRunner.complete(runIndex: 0)
    }

    @MainActor @Test func execution_WhenProfileUsesCommand_PreservesExistingCommandPath() async throws {
        let profile = try WakeProfile(
            wakePhrase: "computer",
            urlTemplate: "https://example.com/?q={urlText}",
            accent: .blue)
        let target = MacContextTarget(
            processIdentifier: 42,
            applicationName: "Safari",
            bundleIdentifier: nil)
        let context = ControlledMacContextCapturer(target: target)
        let fixture = try Fixture(profiles: [profile], contextCapturer: context)
        fixture.coordinator.setPassiveEnabled(true)

        fixture.speech.emit("computer preserve this", isFinal: true)
        await waitUntil {
            await fixture.runner.recordedTranscripts() == ["preserve this"]
        }

        let expectedTemplate = try profile.commandTemplate
        #expect(await fixture.agentRunner.recordedInvocations().isEmpty)
        #expect(await fixture.runner.recordedTemplates().first == expectedTemplate)
        #expect(context.currentTargetCallCount == 0)
        #expect(context.capturedTargets.isEmpty)
    }

    @MainActor @Test func agentEvent_WhenExecutionGenerationIsStale_IsIgnored() async throws {
        let profile = try makeAgentProfile()
        let fixture = try Fixture(profiles: [profile])
        var lifecycleEvents: [AgentRunLifecycleEvent] = []
        fixture.coordinator.onAgentRunEvent = { event in
            if case .inputContextCaptured = event { return }
            lifecycleEvents.append(event)
        }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent old run", isFinal: true)
        await waitUntil {
            await fixture.agentRunner.recordedInvocations().count == 1
        }

        fixture.coordinator.cancelAgentRun()
        await fixture.agentRunner.emit(.diagnostic("late"), from: 0)
        await fixture.agentRunner.complete(runIndex: 0)
        try await Task.sleep(for: .milliseconds(30))

        #expect(lifecycleEvents.count == 3)
        guard case let .started(runID, _, _) = lifecycleEvents.first else {
            Issue.record("Expected an agent run start")
            return
        }
        #expect(lifecycleEvents[1] == .turnCancellationStarted(runID: runID))
        #expect(lifecycleEvents.last == .turnCompleted(
            runID: runID,
            result: AgentRunResult(stopReason: .cancelled)))
    }

}

@MainActor
private func runCoordinatorEventTrackingLoop(while condition: () -> Bool) {
    let deadline = Date(timeIntervalSinceNow: 0.25)
    while condition(), Date() < deadline {
        _ = RunLoop.main.run(
            mode: .eventTracking,
            before: min(deadline, Date(timeIntervalSinceNow: 0.01)))
    }
}
