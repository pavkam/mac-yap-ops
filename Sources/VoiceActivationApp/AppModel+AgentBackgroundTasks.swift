// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import VoiceActivationCore

struct AgentBackgroundSessionMenuItem: Identifiable, Equatable, Sendable {
    var id: AgentSessionPresentationKey { key }
    let key: AgentSessionPresentationKey
    let runID: UUID
    let profileName: String
    let activeTaskCount: Int
}

extension AppModel {
    var activeAgentBackgroundSessions: [AgentBackgroundSessionMenuItem] {
        agentSessionPresentationRegistry.activeEntries.compactMap { entry in
            guard let snapshot = entry.presentation.snapshot else { return nil }
            return AgentBackgroundSessionMenuItem(
                key: entry.key,
                runID: entry.runID,
                profileName: snapshot.profileName,
                activeTaskCount: snapshot.backgroundTasks.count(where: \.isActive))
        }
    }

    func bindAgentRunPresentation(_ presentation: AgentRunPresentation) {
        presentation.onPublication = { [weak self, weak presentation] snapshot in
            guard let self, let presentation,
                self.agentRunPresentation === presentation
            else { return }
            self.publishAgentRun(snapshot)
        }
    }

    func prepareAgentPresentation(runID: UUID, profile: WakeProfile) {
        if let snapshot = agentRunPresentation.snapshot,
            snapshot.runID != runID,
            snapshot.hasActiveBackgroundTasks
        {
            let presentation = AgentRunPresentation(diagnostics: diagnostics)
            bindAgentRunPresentation(presentation)
            agentRunPresentation = presentation
        } else if let snapshot = agentRunPresentation.snapshot,
            snapshot.runID != runID
        {
            agentSessionPresentationRegistry.remove(runID: snapshot.runID)
        }
        agentSessionAppRunGeneration &+= 1
        agentPresentationProfile = profile
    }

    func registerAgentSession(runID: UUID, sessionID: String) {
        guard agentRunPresentation.snapshot?.runID == runID,
            let profile = agentPresentationProfile,
            profile.id == agentRunPresentation.snapshot?.profileID
        else { return }
        agentRunPresentation.bindSession(
            sessionID: sessionID,
            appRunGeneration: agentSessionAppRunGeneration)
        _ = agentSessionPresentationRegistry.register(
            presentation: agentRunPresentation,
            profile: profile,
            sessionID: sessionID,
            appRunGeneration: agentSessionAppRunGeneration)
    }

    func installAgentSessionEventHandler() async {
        agentSessionHandlerGeneration &+= 1
        let handlerGeneration = agentSessionHandlerGeneration
        let scheduler = agentSessionEventScheduler
        await agentRunner.setSessionEventHandler { [weak self] envelope in
            scheduler.schedule { [weak self] in
                self?.handleAgentSessionEvent(
                    envelope,
                    handlerGeneration: handlerGeneration)
            }
        }
    }

    func handleAgentSessionEvent(
        _ envelope: AgentSessionEventEnvelope,
        handlerGeneration: UInt64
    ) {
        guard !isShutdown,
            agentSessionHandlerGeneration == handlerGeneration
        else { return }
        let key = AgentSessionPresentationKey(
            profileID: envelope.profileID,
            sessionID: envelope.sessionID)
        guard let entry = agentSessionPresentationRegistry.entry(for: key) else { return }
        let effect = entry.presentation.applySessionEvent(
            envelope,
            appRunGeneration: entry.appRunGeneration)
        guard case .narrate(let event) = effect,
            agentSessionPresentationRegistry.visibleKey == key,
            agentRunPresentation === entry.presentation
        else { return }
        agentConversationAudioPresenter.handleSessionEvent(event, runID: entry.runID)
    }

    func showAgentBackgroundSession(_ key: AgentSessionPresentationKey) {
        guard let entry = agentSessionPresentationRegistry.select(key),
            let snapshot = entry.presentation.snapshot
        else { return }
        agentRunPresentation = entry.presentation
        agentPresentationProfile = entry.profile
        agentSessionAppRunGeneration = entry.appRunGeneration
        agentRunSnapshot = snapshot
        agentRunPanelPresenter.begin(snapshot, from: nil)
        agentRunPanelPresenter.show(runID: snapshot.runID)
    }

    func stopBackgroundTask(runID: UUID, taskID: AgentBackgroundTaskID) {
        guard let entry = agentSessionPresentationRegistry.entry(runID: runID),
            agentSessionPresentationRegistry.visibleKey == entry.key,
            agentRunPresentation === entry.presentation,
            entry.presentation.beginBackgroundTaskStop(taskID: taskID)
        else { return }

        Task { @MainActor [weak self, agentRunner] in
            let accepted: Bool
            do {
                accepted = try await agentRunner.stopBackgroundTask(
                    profileID: entry.key.profileID,
                    sessionID: entry.key.sessionID,
                    taskID: taskID)
            } catch {
                accepted = false
            }
            guard let self,
                let current = self.agentSessionPresentationRegistry.entry(runID: runID),
                current.key == entry.key,
                current.appRunGeneration == entry.appRunGeneration,
                current.presentation === entry.presentation
            else { return }
            current.presentation.finishBackgroundTaskStop(
                taskID: taskID,
                accepted: accepted)
        }
    }
}
