// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import VoiceActivationCore

enum AgentSessionEventEffect: Equatable, Sendable {
    case ignored
    case presentationUpdated
    case narrate(AgentRunEvent)
}

extension AgentRunPresentation {
    static let maximumBackgroundTasks = 32

    var hasActiveBackgroundTasks: Bool {
        backgroundTasks.contains(where: \.isActive)
    }

    func bindSession(sessionID: String, appRunGeneration: UInt64) {
        self.sessionID = sessionID
        sessionAppRunGeneration = appRunGeneration
    }

    @discardableResult
    func applySessionEvent(
        _ envelope: AgentSessionEventEnvelope,
        appRunGeneration: UInt64
    ) -> AgentSessionEventEffect {
        guard profileID == envelope.profileID,
            sessionID == envelope.sessionID,
            sessionAppRunGeneration == appRunGeneration,
            runID != nil,
            case .live(let event) = envelope.streamEvent
        else { return .ignored }

        switch event {
        case .backgroundTask(let update):
            applyBackgroundTaskUpdate(update)
            publishNow()
            return .presentationUpdated
        case .agentMessageDelta, .agentSpokenNarrationReady:
            apply(event)
            publishNow()
            return .narrate(event)
        case .agentSpokenMessageDelta, .agentDisplayMessageDelta:
            apply(event)
            publishNow()
            return .presentationUpdated
        case .connected, .userMessageDelta, .agentSpokenNarrationSuppressed,
            .thoughtDelta, .artifact, .toolCall, .toolCallUpdate, .plan,
            .metadata, .diagnostic, .permissionRequested, .unknown, .deliveryNotice:
            return .ignored
        }
    }

    func applyBackgroundTaskUpdate(_ update: AgentBackgroundTaskUpdate) {
        let taskID = update.presentationTaskID
        if let index = backgroundTasks.firstIndex(where: { $0.id == taskID }) {
            backgroundTasks[index].apply(update)
            return
        }

        if backgroundTasks.count == Self.maximumBackgroundTasks {
            guard let terminalIndex = backgroundTasks.firstIndex(where: { !$0.isActive }) else {
                ignoredBackgroundTaskCount = saturatingIncrement(ignoredBackgroundTaskCount)
                diagnosticsRecorder.record(
                    category: .ui,
                    event: "agent_presentation.background_task_ignored",
                    level: .warning,
                    fields: ["reason": "active_limit"])
                return
            }
            backgroundTasks.remove(at: terminalIndex)
        }

        var task = AgentBackgroundTaskPresentation(id: taskID)
        task.apply(update)
        backgroundTasks.append(task)
    }

    @discardableResult
    func beginBackgroundTaskStop(taskID: AgentBackgroundTaskID) -> Bool {
        guard let index = backgroundTasks.firstIndex(where: { $0.id == taskID }),
            backgroundTasks[index].offersStopAction
        else { return false }
        backgroundTasks[index].stopState = .requested
        publishNow()
        return true
    }

    func finishBackgroundTaskStop(
        taskID: AgentBackgroundTaskID,
        accepted: Bool
    ) {
        guard let index = backgroundTasks.firstIndex(where: { $0.id == taskID }),
            backgroundTasks[index].stopState == .requested,
            backgroundTasks[index].isActive
        else { return }
        backgroundTasks[index].stopState = accepted ? .requested : .failed
        publishNow()
    }
}
