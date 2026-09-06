// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

extension ACPAgentRunner {
    func establishRestoration(
        _ token: AgentRestorationToken?,
        recordID: UUID,
        turnToken: UUID
    ) {
        guard var turn = activeTurn, turn.token == turnToken else { return }
        turn.restorationToken = token
        turn.restorationRecordID = token == nil ? nil : recordID
        turn.connectionAttemptUsedRestoration = token != nil
        activeTurn = turn
    }

    func ensureRestorationCurrent(
        token: AgentRestorationToken,
        recordID: UUID,
        turnToken: UUID
    ) throws {
        guard let turn = activeTurn,
              turn.token == turnToken,
              turn.recordID == recordID,
              turn.restorationToken == token,
              turn.restorationRecordID == recordID,
              !turn.isCancelling,
              records[turn.profileID]?.id == recordID
        else { throw ACPAgentRunnerError.cancelled }
    }

    func forwardRestored(
        token: AgentRestorationToken,
        event: AgentRunEvent,
        recordID: UUID,
        turnToken: UUID,
        onEvent: @escaping @Sendable (AgentRunStreamEvent) async -> Void
    ) async {
        guard (try? ensureRestorationCurrent(
            token: token,
            recordID: recordID,
            turnToken: turnToken)) != nil
        else { return }
        await onEvent(.restored(token: token, event: event))
        guard (try? ensureRestorationCurrent(
            token: token,
            recordID: recordID,
            turnToken: turnToken)) != nil
        else { return }
    }

    func completeRestoration(
        token: AgentRestorationToken,
        recordID: UUID,
        turnToken: UUID,
        activation: AgentSessionActivation,
        onEvent: @escaping @Sendable (AgentRunStreamEvent) async -> Void
    ) async throws {
        try ensureRestorationCurrent(
            token: token,
            recordID: recordID,
            turnToken: turnToken)
        guard var turn = activeTurn, turn.token == turnToken else {
            throw ACPAgentRunnerError.cancelled
        }
        turn.restorationToken = nil
        turn.restorationRecordID = nil
        activeTurn = turn
        await onEvent(.restorationCompleted(token: token, activation: activation))
        try ensureActiveTurn(token: turnToken)
    }

    func abortRestorationIfCurrent(
        token: AgentRestorationToken,
        recordID: UUID,
        turnToken: UUID,
        onEvent: @escaping @Sendable (AgentRunStreamEvent) async -> Void
    ) async {
        guard var turn = activeTurn,
              turn.token == turnToken,
              turn.restorationToken == token,
              turn.restorationRecordID == recordID
        else { return }
        turn.restorationToken = nil
        turn.restorationRecordID = nil
        activeTurn = turn
        await onEvent(.restorationAborted(token: token))
    }

    func saveBookmark(
        profileID: UUID,
        activation: AgentSessionActivation,
        providerFingerprint: String
    ) async {
        await saveBookmark(
            profileID: profileID,
            sessionID: activation.sessionID,
            providerFingerprint: providerFingerprint)
    }

    func saveBookmark(
        profileID: UUID,
        sessionID: String,
        providerFingerprint: String
    ) async {
        do {
            try await continuityStore.save(bookmark: AgentSessionBookmark(
                profileID: profileID,
                sessionID: sessionID,
                providerFingerprint: providerFingerprint,
                lastAccessOrdinal: 0))
        } catch {
            recordContinuityStoreFailure(operation: "save")
        }
    }

    func removeContinuityRecords(profileIDs: Set<UUID>) async {
        do {
            try await continuityStore.remove(profileIDs: profileIDs)
        } catch {
            recordContinuityStoreFailure(operation: "remove")
        }
    }

    func recordContinuityStoreFailure(operation: String) {
        let event = operation == "read"
            ? "continuity_store.read_failed"
            : "continuity_store.save_failed"
        diagnostics.record(
            category: .agent,
            event: event,
            level: .error,
            fields: ["failure_category": operation])
    }
}
