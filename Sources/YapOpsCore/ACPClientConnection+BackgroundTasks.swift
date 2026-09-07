// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

extension ACPClientConnection {
    func retireCancelledPromptPreservingSession() async -> Bool {
        guard isPromptCancelling,
              activeTurnToken != nil,
              let requestID = activePromptRequestID,
              var pending = pendingRequests[requestID]
        else { return false }
        promptResponseWasReceived = true
        activeEventDelivery?.stopAdmission()
        await cancelPendingPermissions()
        retiredPromptRequestID = requestID
        let result = PendingClientRequest.Result.success(.object([
            "stopReason": .string(AgentStopReason.cancelled.rawValue),
        ]))
        if let continuation = pending.continuation {
            pendingRequests.removeValue(forKey: requestID)
            resume(continuation, with: result)
        } else {
            pending.bufferedResult = result
            pendingRequests[requestID] = pending
        }
        return true
    }

    func waitForInputAndEventCompletion() async {
        _ = await receiveTask?.result
        // EOF can arrive before the decoded-event consumers have finished.
        // Keep the runner's record alive until those callbacks reach it.
        let promptDelivery = activeEventDelivery
        let sessionDelivery = sessionEventDelivery
        await promptDelivery?.finish(.drain)
        await sessionDelivery?.finish(.drain)
    }

    /// Replaces the bounded observer for negotiated events that arrive between prompts.
    ///
    /// The connection owns and releases the handler. Passing `nil` invalidates the
    /// current observer before its queued events are discarded.
    public func setSessionEventHandler(
        _ handler: (@Sendable (AgentRunEvent) async -> Void)?
    ) async {
        let previous = sessionEventDelivery
        sessionEventDelivery = nil
        await previous?.finish(.discard)
        guard let handler, sessionID != nil, terminalError == nil, !isClosing else {
            return
        }
        sessionEventDelivery = AgentRunEventDelivery(handler: handler)
    }

    /// Requests that the pinned Claude AIR adapter stop one exact background task.
    ///
    /// The returned Boolean is only the adapter's acknowledgement. Terminal task
    /// state remains owned by a later typed provider update.
    /// - Parameter taskID: The exact opaque task identity from a typed task event.
    /// - Returns: The strict `stopped` acknowledgement, or `false` when unsupported.
    /// - Throws: ``ACPClientError`` for a malformed response or closed connection.
    public func stopBackgroundTask(taskID: AgentBackgroundTaskID) async throws -> Bool {
        guard capabilities?.supportsAIRAsyncTasks == true else { return false }
        guard !taskID.rawValue.isEmpty,
              taskID.rawValue.utf8.count <= AgentBackgroundTaskLimits.maximumIdentifierBytes,
              let ownedSessionID = sessionID
        else { return false }
        guard inFlightBackgroundTaskStops.insert(taskID).inserted else { return false }
        defer { inFlightBackgroundTaskStops.remove(taskID) }

        // Nonstandard compatibility contract pinned to Claude Agent ACP 0.73.0:
        // https://github.com/agentclientprotocol/claude-agent-acp/blob/v0.73.0/src/acp-agent.ts
        let result = try await sendRequest(
            method: "_session/async_task/stop",
            params: .object([
                "sessionId": .string(ownedSessionID),
                "asyncTaskId": .string(taskID.rawValue),
            ]))
        guard sessionID == ownedSessionID,
              capabilities?.supportsAIRAsyncTasks == true
        else { throw ACPClientError.connectionClosed }
        let object = try requiredObject(result, named: "async task stop result")
        guard case let .bool(stopped) = object["stopped"] else {
            throw ACPClientError.malformedResponse("Invalid async task stop result.")
        }
        return stopped
    }

    func eventDeliverySnapshotForTesting() -> AgentRunEventDeliverySnapshot? {
        activeEventDelivery?.snapshotForTesting
    }

    func sessionEventDeliverySnapshotForTesting() -> AgentRunEventDeliverySnapshot? {
        sessionEventDelivery?.snapshotForTesting
    }
}
