// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

extension YapOpsCoordinator {
    /// Retires coordinator work captured for the specified agent profiles.
    ///
    /// This fence is synchronous: every matching admission and context capture is
    /// invalid before the caller resets durable runner state. Direct commands and
    /// agent work for profiles outside `profileIDs` remain untouched.
    ///
    /// - Parameter profileIDs: Exact profile identifiers whose agent work is stale.
    public func invalidateAgentProfiles(_ profileIDs: Set<UUID>) {
        guard
            let profileID = activeProfile?.id,
            profileIDs.contains(profileID),
            ownsAgentWork
        else { return }

        diagnostics.record(
            category: .agent,
            event: "coordinator.agent_profile_invalidated",
            fields: ["profile_id": profileID.uuidString])

        let runID = activeAgentRunID
        executionGeneration &+= 1
        cancelAllAgentInputs()
        executionTask?.cancel()
        executionTask = nil
        agentCancellationTask?.cancel()
        agentCancellationTask = nil
        agentCancellationToken = nil
        restartTask?.cancel()
        restartTask = nil
        pushToTalkActive = false
        pushToTalkContinuesConversation = false
        agentConversationEndResult = nil
        agentSpeechOutputActive = false
        agentTurnHadActivity = false
        executingAction = nil
        activeAgentRunID = nil
        capturedAction = nil
        capturedLocaleID = nil
        activeProfile = nil
        onAgentSpeechCancellation?()
        stopActiveSession()
        state = .disabled

        if let runID {
            onAgentRunEvent?(
                .completed(
                    runID: runID,
                    result: AgentRunResult(stopReason: .cancelled)))
        }
    }

    private var ownsAgentWork: Bool {
        if case .agent = capturedAction { return true }
        if case .agent = executingAction { return true }
        return activeAgentInput != nil || !pendingAgentPrompts.isEmpty
    }
}
