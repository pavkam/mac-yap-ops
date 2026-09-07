// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

extension ACPAgentRunner {
    static let maximumActiveBackgroundTasksPerSession = 32

    func preserveBackgroundSessionAfterPromptCancellation(
        _ turnToken: UUID,
        _ profileID: UUID,
        _ recordID: UUID?
    ) async -> Bool {
        guard let recordID,
              let record = records[profileID],
              record.id == recordID,
              !record.activeBackgroundTaskIDs.isEmpty,
              let connection = record.connection,
              await connection.retireCancelledPromptPreservingSession()
        else { return false }
        diagnostics.record(
            category: .agent,
            event: "acp_runner.cancel_preserved_background_session",
            fields: ["turn_id": turnToken.uuidString])
        return true
    }

    /// Installs the single downstream sink for live between-turn session events.
    public func setSessionEventHandler(
        _ handler: (@Sendable (AgentSessionEventEnvelope) async -> Void)?
    ) {
        sessionEventHandler = isShutDown ? nil : handler
    }

    /// Sends one typed stop request through the exact live cached session.
    public func stopBackgroundTask(
        profileID: UUID,
        sessionID: String,
        taskID: AgentBackgroundTaskID
    ) async throws -> Bool {
        guard !isShutDown,
              let record = records[profileID],
              record.sessionID == sessionID,
              record.exitStatus == nil,
              record.activeBackgroundTaskIDs.contains(taskID),
              record.stoppableBackgroundTaskIDs.contains(taskID),
              let connection = record.connection,
              record.pendingBackgroundTaskStopIDs.insert(taskID).inserted
        else {
            throw ACPAgentRunnerError.backgroundTaskUnavailable
        }

        do {
            let stopped = try await connection.stopBackgroundTask(taskID: taskID)
            guard records[profileID]?.id == record.id,
                  record.sessionID == sessionID,
                  record.exitStatus == nil,
                  record.activeBackgroundTaskIDs.contains(taskID)
            else {
                throw ACPAgentRunnerError.backgroundTaskUnavailable
            }
            record.pendingBackgroundTaskStopIDs.remove(taskID)
            return stopped
        } catch {
            if records[profileID]?.id == record.id {
                record.pendingBackgroundTaskStopIDs.remove(taskID)
            }
            throw error
        }
    }

    func receiveSessionEvent(
        _ streamEvent: AgentRunStreamEvent,
        profileID: UUID,
        sessionID: String,
        recordID: UUID
    ) async {
        guard case .live(let event) = streamEvent,
              let record = records[profileID],
              record.id == recordID,
              record.sessionID == sessionID,
              record.exitStatus == nil
        else {
            diagnostics.record(
                category: .agent,
                event: "acp_runner.session_event_ignored",
                level: .debug,
                fields: ["reason": "stale_identity_or_source"])
            return
        }
        guard await prepareBackgroundTaskEvent(
            event,
            profileID: profileID,
            sessionID: sessionID,
            recordID: recordID)
        else { return }
        guard let handler = sessionEventHandler else { return }
        await handler(AgentSessionEventEnvelope(
            profileID: profileID,
            sessionID: sessionID,
            streamEvent: streamEvent))
    }

    func prepareBackgroundTaskEvent(
        _ event: AgentRunEvent,
        profileID: UUID,
        sessionID: String?,
        recordID: UUID
    ) async -> Bool {
        guard case .backgroundTask(let update) = event else { return true }
        guard let sessionID,
              let record = records[profileID],
              record.id == recordID,
              record.sessionID == sessionID,
              record.exitStatus == nil
        else { return false }

        switch update {
        case .spawned(let taskID, _, _, _, _, let canStop, _, _):
            if record.pendingBackgroundTaskMarkerIDs.contains(taskID) {
                return false
            }
            if record.backgroundTaskWorkKeys[taskID] != nil {
                record.activeBackgroundTaskIDs.insert(taskID)
                updateStopCapability(canStop, taskID: taskID, record: record)
                return true
            }
            guard record.activeBackgroundTaskIDs.contains(taskID)
                    || record.activeBackgroundTaskIDs.count
                        < Self.maximumActiveBackgroundTasksPerSession
            else {
                recordBackgroundTaskOverflow()
                return false
            }
            let key = AgentInterruptedWorkKey(
                profileID: profileID,
                sessionID: sessionID,
                occurrenceID: UUID())
            record.activeBackgroundTaskIDs.insert(taskID)
            record.pendingBackgroundTaskMarkerIDs.insert(taskID)
            record.backgroundTaskWorkKeys[taskID] = key
            updateStopCapability(canStop, taskID: taskID, record: record)
            do {
                try await continuityStore.markWorkActive(AgentInterruptedWorkMarker(
                    key: key,
                    providerTaskID: taskID.rawValue,
                    state: .active))
            } catch {
                rollbackProvisionalTask(taskID, key: key, record: record)
                recordContinuityStoreFailure(operation: "task_spawn")
                return false
            }
            guard records[profileID]?.id == recordID,
                  record.sessionID == sessionID,
                  record.exitStatus == nil,
                  record.backgroundTaskWorkKeys[taskID] == key,
                  record.pendingBackgroundTaskMarkerIDs.remove(taskID) != nil
            else {
                await clearWork(key, operation: "stale_task_spawn")
                return false
            }
            return true

        case .progress(let taskID, _, _, _, _, _, _):
            return await admitActiveTask(
                taskID,
                profileID: profileID,
                sessionID: sessionID,
                recordID: recordID,
                record: record)

        case .stateChanged(let taskID, let state, _, _, _):
            if state.isTerminal {
                record.activeBackgroundTaskIDs.remove(taskID)
                record.stoppableBackgroundTaskIDs.remove(taskID)
                record.pendingBackgroundTaskStopIDs.remove(taskID)
                record.pendingBackgroundTaskMarkerIDs.remove(taskID)
                if let key = record.backgroundTaskWorkKeys.removeValue(forKey: taskID) {
                    await clearWork(key, operation: "task_terminal")
                }
                return true
            }
            return await admitActiveTask(
                taskID,
                profileID: profileID,
                sessionID: sessionID,
                recordID: recordID,
                record: record)
        }
    }

    private func admitActiveTask(
        _ taskID: AgentBackgroundTaskID,
        profileID: UUID,
        sessionID: String,
        recordID: UUID,
        record: ACPAgentConnectionRecord
    ) async -> Bool {
        if record.backgroundTaskWorkKeys[taskID] != nil {
            record.activeBackgroundTaskIDs.insert(taskID)
            return true
        }
        if record.pendingBackgroundTaskMarkerIDs.contains(taskID) {
            return false
        }
        guard record.activeBackgroundTaskIDs.contains(taskID)
                || record.activeBackgroundTaskIDs.count
                    < Self.maximumActiveBackgroundTasksPerSession
        else {
            recordBackgroundTaskOverflow()
            return false
        }
        let key = AgentInterruptedWorkKey(
            profileID: profileID,
            sessionID: sessionID,
            occurrenceID: UUID())
        record.activeBackgroundTaskIDs.insert(taskID)
        record.pendingBackgroundTaskMarkerIDs.insert(taskID)
        record.backgroundTaskWorkKeys[taskID] = key
        do {
            try await continuityStore.markWorkActive(AgentInterruptedWorkMarker(
                key: key,
                providerTaskID: taskID.rawValue,
                state: .active))
        } catch {
            rollbackProvisionalTask(taskID, key: key, record: record)
            recordContinuityStoreFailure(operation: "task_progress")
            return false
        }
        guard records[profileID]?.id == recordID,
              record.sessionID == sessionID,
              record.exitStatus == nil,
              record.backgroundTaskWorkKeys[taskID] == key,
              record.pendingBackgroundTaskMarkerIDs.remove(taskID) != nil
        else {
            await clearWork(key, operation: "stale_task_progress")
            return false
        }
        return true
    }

    private func updateStopCapability(
        _ canStop: Bool,
        taskID: AgentBackgroundTaskID,
        record: ACPAgentConnectionRecord
    ) {
        if canStop {
            record.stoppableBackgroundTaskIDs.insert(taskID)
        } else {
            record.stoppableBackgroundTaskIDs.remove(taskID)
        }
    }

    private func rollbackProvisionalTask(
        _ taskID: AgentBackgroundTaskID,
        key: AgentInterruptedWorkKey,
        record: ACPAgentConnectionRecord
    ) {
        guard record.backgroundTaskWorkKeys[taskID] == key else { return }
        record.activeBackgroundTaskIDs.remove(taskID)
        record.stoppableBackgroundTaskIDs.remove(taskID)
        record.pendingBackgroundTaskMarkerIDs.remove(taskID)
        record.backgroundTaskWorkKeys.removeValue(forKey: taskID)
    }

    private func recordBackgroundTaskOverflow() {
        diagnostics.record(
            category: .agent,
            event: "acp_runner.background_task_ignored",
            level: .warning,
            fields: ["reason": "active_task_limit"])
    }
}

private extension AgentBackgroundTaskState {
    var isTerminal: Bool {
        switch self {
        case .running, .paused: false
        case .completed, .failed, .stopped: true
        }
    }
}
