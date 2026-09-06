// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

extension VoiceActivationCoordinator {
    func publishAgentStreamEvent(
        _ streamEvent: AgentRunStreamEvent,
        runID: UUID,
        generation: Int,
        receivedAtUptime: UInt64
    ) {
        switch streamEvent {
        case .live(let event):
            publishAgentEvent(
                event,
                runID: runID,
                generation: generation,
                receivedAtUptime: receivedAtUptime)
        case .restorationStarted(let token, let sessionID):
            guard acceptsRestorationEvent(
                runID: runID,
                generation: generation,
                token: token,
                startsAttempt: true)
            else { return }
            activeAgentRestorationToken = token
            onAgentRunEvent?(.historyRestorationStarted(
                runID: runID,
                token: token,
                sessionID: sessionID))
        case .restored(let token, let event):
            guard acceptsRestorationEvent(
                runID: runID,
                generation: generation,
                token: token)
            else { return }
            onAgentRunEvent?(.historyEvent(
                runID: runID,
                token: token,
                event: event))
        case .restorationCompleted(let token, let activation):
            guard acceptsRestorationEvent(
                runID: runID,
                generation: generation,
                token: token)
            else { return }
            onAgentRunEvent?(.historyRestorationCompleted(
                runID: runID,
                token: token,
                activation: activation))
            activeAgentRestorationToken = nil
        case .restorationAborted(let token):
            guard acceptsRestorationEvent(
                runID: runID,
                generation: generation,
                token: token)
            else { return }
            onAgentRunEvent?(.historyRestorationAborted(
                runID: runID,
                token: token))
            activeAgentRestorationToken = nil
        }
    }

    private func acceptsRestorationEvent(
        runID: UUID,
        generation: Int,
        token: AgentRestorationToken,
        startsAttempt: Bool = false
    ) -> Bool {
        guard executionGeneration == generation, activeAgentRunID == runID else {
            return false
        }
        if startsAttempt {
            return activeAgentRestorationToken == nil || activeAgentRestorationToken == token
        }
        return activeAgentRestorationToken == token
    }
}
