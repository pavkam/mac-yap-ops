// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

extension YapOpsCoordinator {
    /// Stops work and microphone capture until the user explicitly resumes.
    public func cancelAgentRun() {
        guard
            case .agent = executingAction,
            let runID = activeAgentRunID,
            !isConversationListeningPaused,
            agentCancellationTask == nil
        else {
            diagnostics.record(
                category: .agent,
                event: "coordinator.agent_cancel_ignored",
                fields: ["reason": "no_cancellable_turn"])
            return
        }

        diagnostics.record(
            category: .agent,
            event: "coordinator.agent_cancel_requested",
            fields: ["run_id": runID.uuidString])

        isConversationListeningPaused = true
        let hadActiveTurn = executionTask != nil
        executionGeneration &+= 1
        let cancelledInputs = pendingAgentPrompts.map(\.id)
        cancelAllAgentInputs()
        stopActiveSession()
        conversationUtterance = ""
        currentTranscript = ""
        capturedCommand = ""
        pushToTalkActive = false
        pushToTalkContinuesConversation = false
        executionTask?.cancel()
        executionTask = nil
        if hadActiveTurn { beginAgentCancellation(runID: runID) }
        onAgentRunEvent?(.turnCancellationStarted(runID: runID))
        for inputID in cancelledInputs {
            onAgentRunEvent?(.followUpDispositionChanged(
                runID: runID, inputID: inputID, disposition: .cancelled))
        }
        if !hadActiveTurn {
            onAgentRunEvent?(.turnCompleted(runID: runID, result: .init(stopReason: .cancelled)))
        }
    }

    /// Resumes hands-free capture for the retained conversation after Stop.
    /// - Returns: Whether the paused conversation accepted the resume action.
    @discardableResult
    public func resumeAgentConversationListening() -> Bool {
        guard isAgentConversationActive, isConversationListeningPaused,
            agentCancellationTask == nil else { return false }
        isConversationListeningPaused = false
        startConversationListening()
        return true
    }
}
