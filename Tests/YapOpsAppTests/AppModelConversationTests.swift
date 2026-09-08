// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import YapOpsApp
@testable import YapOpsCore


extension AppModelTests {
    @MainActor @Test func agentLifecycle_WhenRunStreams_OpensUpdatesAndRetainsPanel() throws {
        let profile = try makeAgentProfile(displayName: "Codex")
        let panel = AppModelAgentPanelSpy()
        let fixture = try Fixture(profiles: [profile], agentRunPanel: panel)
        let runID = UUID()

        fixture.model.handleAgentRunLifecycleEvent(
            .started(
                runID: runID,
                profile: profile,
                prompt: "Explain the change"))
        fixture.model.handleAgentRunLifecycleEvent(
            .event(
                runID: runID,
                event: .agentMessageDelta(messageID: nil, text: "Done")))
        fixture.model.handleAgentRunLifecycleEvent(
            .completed(
                runID: runID,
                result: AgentRunResult(stopReason: .endTurn)))
        fixture.model.showAgentRun()

        #expect(panel.began.count == 1)
        #expect(fixture.model.agentRunSnapshot?.output == "Done")
        #expect(fixture.model.agentRunSnapshot?.phase == .completed(.endTurn))
        #expect(panel.shown == [runID])
    }

    @MainActor @Test func deleteAgentRun_WhenConversationIsTerminal_DiscardsPanelState()
        throws
    {
        let profile = try makeAgentProfile(displayName: "Codex")
        let panel = AppModelAgentPanelSpy()
        let fixture = try Fixture(profiles: [profile], agentRunPanel: panel)
        let runID = UUID()
        fixture.model.handleAgentRunLifecycleEvent(
            .started(
                runID: runID,
                profile: profile,
                prompt: "Explain the change"))
        fixture.model.handleAgentRunLifecycleEvent(
            .completed(
                runID: runID,
                result: AgentRunResult(stopReason: .endTurn)))

        fixture.model.deleteAgentRun()
        fixture.model.handleAgentRunLifecycleEvent(
            .event(
                runID: runID,
                event: .agentMessageDelta(messageID: "late", text: "Do not restore")))

        #expect(fixture.model.agentRunSnapshot == nil)
        #expect(panel.discarded == [runID])
        #expect(panel.hidden.isEmpty)
    }

    @MainActor @Test func agentLifecycle_WhenEventIsStale_IgnoresIt() throws {
        let profile = try makeAgentProfile(displayName: "Codex")
        let fixture = try Fixture(profiles: [profile])
        let runID = UUID()
        fixture.model.handleAgentRunLifecycleEvent(
            .started(
                runID: runID,
                profile: profile,
                prompt: "Current"))

        fixture.model.handleAgentRunLifecycleEvent(
            .event(
                runID: UUID(),
                event: .agentMessageDelta(messageID: nil, text: "stale")))

        #expect(fixture.model.agentRunSnapshot?.output == "")
    }

    @MainActor @Test func agentLifecycle_WhenNoticeArrives_PublishesItInCurrentRun() throws {
        let profile = try makeAgentProfile(displayName: "Codex")
        let fixture = try Fixture(profiles: [profile])
        let runID = UUID()
        fixture.model.handleAgentRunLifecycleEvent(
            .started(
                runID: runID,
                profile: profile,
                prompt: "Current"))

        fixture.model.handleAgentRunLifecycleEvent(
            .notice(
                runID: runID,
                message: "Wait for the agent."))

        #expect(fixture.model.agentRunSnapshot?.notices == ["Wait for the agent."])
    }

    @MainActor @Test
    func conversation_StopAndResumeKeepMicrophoneAndPresentationInSync() async throws {
        let profile = try makeAgentProfile(displayName: "Codex")
        let fixture = try Fixture(profiles: [profile])
        await fixture.model.start()
        fixture.speech.emit("Codex explain this", isFinal: true)
        await waitUntil { fixture.model.agentRunSnapshot?.phase == .listening }
        let runID = try #require(fixture.model.agentRunSnapshot?.runID)

        fixture.model.cancelAgentRun(runID: runID)
        #expect(fixture.model.agentRunSnapshot?.phase == .paused)
        #expect(fixture.speech.mode == nil)
        #expect(fixture.model.statusPresentation.detail == "Microphone off · Resume when ready")
        fixture.model.resumeAgentConversationListening(runID: UUID())
        #expect(fixture.speech.mode == nil)
        fixture.model.resumeAgentConversationListening(runID: runID)
        #expect(fixture.model.agentRunSnapshot?.phase == .listening)
        #expect(fixture.speech.mode == .conversation)
        await fixture.model.shutdown()
    }

    @MainActor @Test func agentConversation_WhenSpeechIsPartial_ShowsLiveFollowUpText() async throws
    {
        let profile = try makeAgentProfile(displayName: "Codex")
        let fixture = try Fixture(profiles: [profile])
        await fixture.model.start()
        fixture.speech.emit("Codex explain this", isFinal: true)
        await waitUntil {
            fixture.model.agentRunSnapshot?.phase == .listening
                && fixture.speech.mode == .conversation
        }

        fixture.speech.emit("also check the tests")

        #expect(fixture.model.agentRunSnapshot?.voiceInput == "also check the tests")
    }

    @MainActor @Test
    func agentConversation_WhenAgentReplies_ReadsRenderedReplyWithoutUsingTestAudio()
        async throws
    {
        let profile = try makeAgentProfile(displayName: "Codex")
        let runner = AppModelAgentRunnerSpy(events: [
            .agentMessageDelta(messageID: "answer", text: "**All done**")
        ])
        let audio = AppModelAgentConversationAudioSpy()
        let fixture = try Fixture(
            profiles: [profile],
            agentRunner: runner,
            agentConversationAudioPlayer: audio)
        await fixture.model.start()

        fixture.speech.emit("Codex check this", isFinal: true)
        await waitUntil { audio.spoken.count == 1 }

        #expect(audio.spoken.first?.text == "All done")
        #expect(audio.spoken.first?.localeID == fixture.preferences.localeID)
        #expect(fixture.model.agentRunSnapshot?.phase == .listening)
    }

    @MainActor @Test func saveSettings_WhenConversationAudioChanges_PersistsOnlyOnSave()
        async throws
    {
        let credentials = AgentSpeechCredentialStoreSpy(apiKey: "saved-key")
        let fixture = try Fixture(agentSpeechCredentialStore: credentials)
        await fixture.startForExternalActions()
        fixture.model.readsAgentRepliesAloud = false
        fixture.model.playsAgentWorkingSound = false
        fixture.model.agentSpeechProvider = .elevenLabs
        fixture.model.elevenLabsVoiceID = "voice-123"
        fixture.model.elevenLabsAPIKey = "new-key"

        #expect(fixture.preferences.readsAgentRepliesAloud)
        #expect(fixture.preferences.playsAgentWorkingSound)
        #expect(fixture.preferences.agentSpeechProvider == .system)
        #expect(credentials.apiKey == "saved-key")

        #expect(await fixture.model.saveSettings())
        #expect(!fixture.preferences.readsAgentRepliesAloud)
        #expect(!fixture.preferences.playsAgentWorkingSound)
        #expect(fixture.preferences.agentSpeechProvider == .elevenLabs)
        #expect(fixture.preferences.elevenLabsVoiceID == "voice-123")
        #expect(credentials.apiKey == "new-key")
    }

    @MainActor @Test
    func initialization_WhenCredentialExists_DefersReadingItUntilRuntimeStarts() async throws {
        let credentials = AgentSpeechCredentialStoreSpy(apiKey: "saved-key")
        let fixture = try Fixture(agentSpeechCredentialStore: credentials)

        #expect(credentials.loadCount == 0)
        #expect(fixture.model.elevenLabsAPIKey.isEmpty)

        await fixture.model.start()
        await waitUntil { credentials.loadCount == 1 }
        await waitUntil { fixture.model.elevenLabsAPIKey == "saved-key" }
    }

    @MainActor @Test func voicePreview_WhenProfileVoiceIsSelected_UsesDraftCredentials()
        async throws
    {
        let preview = AppModelTextToSpeechVoicePreviewSpy()
        let fixture = try Fixture(textToSpeechVoicePreview: preview)
        await fixture.startForExternalActions()
        fixture.model.elevenLabsAPIKey = "draft-key"
        let selection = TextToSpeechVoiceSelection(
            backendID: .elevenLabs,
            voiceID: "voice-42")
        let context = TextToSpeechVoicePreviewContext.profile(UUID())

        await fixture.model.previewTextToSpeechVoice(selection, in: context)

        #expect(preview.requests.count == 1)
        #expect(preview.requests.first?.credential == "draft-key")
        #expect(preview.requests.first?.selection == selection)
        #expect(fixture.model.activeTextToSpeechVoicePreviewContext == nil)
        #expect(fixture.model.textToSpeechVoicePreviewFeedback[context]?.kind == .success)
        #expect(
            fixture.model.textToSpeechVoicePreviewFeedback[context]?.detail
                == "The ElevenLabs voice is ready to use.")
    }

    @MainActor @Test
    func voicePreview_WhenElevenLabsRequiresPayment_ShowsActionableProfileFeedback()
        async throws
    {
        let preview = AppModelTextToSpeechVoicePreviewSpy()
        preview.failure = ElevenLabsSpeechClientError.httpStatus(402)
        let fixture = try Fixture(textToSpeechVoicePreview: preview)
        await fixture.startForExternalActions()
        fixture.model.elevenLabsAPIKey = "draft-key"
        let context = TextToSpeechVoicePreviewContext.profile(UUID())
        let otherContext = TextToSpeechVoicePreviewContext.profile(UUID())

        await fixture.model.previewTextToSpeechVoice(
            TextToSpeechVoiceSelection(
                backendID: .elevenLabs,
                voiceID: "voice-42"),
            in: context)

        let feedback = try #require(
            fixture.model.textToSpeechVoicePreviewFeedback[context])
        #expect(feedback.kind == .failure)
        #expect(feedback.title == "ElevenLabs needs credits")
        #expect(feedback.detail.contains("available credits"))
        #expect(fixture.model.textToSpeechVoicePreviewFeedback[otherContext] == nil)
    }

    @MainActor @Test
    func voicePreviewFeedback_WhenSelectionChanges_ClearsOnlyThatProfile() async throws {
        let fixture = try Fixture()
        let context = TextToSpeechVoicePreviewContext.profile(UUID())
        let otherContext = TextToSpeechVoicePreviewContext.profile(UUID())
        fixture.model.textToSpeechVoicePreviewFeedback[context] = .failure(
            ElevenLabsSpeechClientError.httpStatus(402))
        fixture.model.textToSpeechVoicePreviewFeedback[otherContext] = .failure(
            ElevenLabsSpeechClientError.httpStatus(403))

        fixture.model.clearTextToSpeechVoicePreviewFeedback(in: context)

        #expect(fixture.model.textToSpeechVoicePreviewFeedback[context] == nil)
        #expect(fixture.model.textToSpeechVoicePreviewFeedback[otherContext] != nil)
    }

    @MainActor @Test func agentPermission_WhenUserSaysAllowAll_ResolvesAndCollapsesPrompt()
        async throws
    {
        let profile = try makeAgentProfile(displayName: "Codex")
        let runner = AppModelPermissionAgentRunnerSpy()
        let fixture = try Fixture(profiles: [profile], agentRunner: runner)
        await fixture.model.start()
        fixture.speech.emit("Codex edit my settings", isFinal: true)
        await waitUntil {
            fixture.model.agentRunSnapshot?.permissions.count == 1
                && fixture.speech.mode == .conversation
        }

        fixture.speech.emit("allow all", isFinal: true)
        await waitUntil { await runner.recordedResolutions().count == 1 }

        let resolution = try #require(await runner.recordedResolutions().first)
        #expect(resolution.turnToken == runner.turnToken)
        #expect(resolution.requestID == runner.requestID)
        #expect(resolution.optionID == "allow-always")
        #expect(fixture.model.agentRunSnapshot?.permissions.isEmpty == true)
    }

    @MainActor @Test
    func agentPermission_WhenButtonSelectsOption_ForwardsExactIdentityToAudioAndRunner()
        async throws
    {
        let profile = try makeAgentProfile(displayName: "Codex")
        let runner = AppModelPermissionAgentRunnerSpy()
        let audio = AppModelAgentConversationAudioSpy()
        let fixture = try Fixture(
            profiles: [profile],
            agentRunner: runner,
            agentConversationAudioPlayer: audio)
        await fixture.model.start()
        fixture.speech.emit("Codex edit my settings", isFinal: true)
        await waitUntil { fixture.model.agentRunSnapshot?.permissions.count == 1 }
        let snapshot = try #require(fixture.model.agentRunSnapshot)
        let permission = try #require(snapshot.permissions.first)
        let stopCount = audio.stopSpeakingCount

        fixture.model.resolveAgentPermission(
            runID: snapshot.runID,
            key: permission.key,
            optionID: "allow-once")
        await waitUntil { await runner.recordedResolutions().count == 1 }

        let resolution = try #require(await runner.recordedResolutions().first)
        #expect(resolution.turnToken == runner.turnToken)
        #expect(resolution.requestID == runner.requestID)
        #expect(resolution.optionID == "allow-once")
        #expect(audio.stopSpeakingCount == stopCount + 1)
    }

    @MainActor @Test
    func agentPermission_WhenDenyHasNoOfferedReject_LeavesPermissionUnresolved()
        async throws
    {
        let profile = try makeAgentProfile(displayName: "Codex")
        let runner = AppModelPermissionAgentRunnerSpy(options: [
            AgentPermissionOption(id: "allow", label: "Allow", kind: .allowOnce),
        ])
        let audio = AppModelAgentConversationAudioSpy()
        let fixture = try Fixture(
            profiles: [profile],
            agentRunner: runner,
            agentConversationAudioPlayer: audio)
        await fixture.model.start()
        fixture.speech.emit("Codex edit my settings", isFinal: true)
        await waitUntil { fixture.model.agentRunSnapshot?.permissions.count == 1 }
        let stopCount = audio.stopSpeakingCount

        let handled = fixture.model.handleAgentVoiceUtterance("deny")

        #expect(!handled)
        #expect(await runner.recordedResolutions().isEmpty)
        #expect(audio.stopSpeakingCount == stopCount)
        #expect(fixture.model.agentRunSnapshot?.permissions.count == 1)
    }

    @MainActor @Test func saveSettings_WhenElevenLabsKeyIsEmpty_PreservesSavedSpeechSettings()
        async throws
    {
        let credentials = AgentSpeechCredentialStoreSpy(apiKey: "saved-key")
        let fixture = try Fixture(agentSpeechCredentialStore: credentials)
        await fixture.startForExternalActions()
        fixture.model.agentSpeechProvider = .elevenLabs
        fixture.model.elevenLabsAPIKey = "   "

        #expect(!(await fixture.model.saveSettings()))
        #expect(fixture.preferences.agentSpeechProvider == .system)
        #expect(credentials.apiKey == "saved-key")
        #expect(fixture.model.settingsError == "ElevenLabs requires an API key.")
    }

}
