// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import VoiceActivationCore

extension AgentRunPresentation {
    /// Begins accepting bounded history for one current restoration attempt.
    func beginHistoryRestoration(
        runID: UUID,
        token: AgentRestorationToken,
        sessionID _: String
    ) {
        guard self.runID == runID, phase?.isTerminal == false else { return }
        guard restorationState == nil else { return }
        flushPendingPublication()
        restorationState = AgentRunPresentationRestorationState(
            token: token,
            checkpoint: restorationCheckpoint())
        diagnosticsRecorder.record(
            category: .ui,
            event: "agent_presentation.history_started",
            fields: ["run_id": runID.uuidString])
    }

    /// Applies one source-qualified history event without creating live permission state.
    func receiveRestored(
        runID: UUID,
        token: AgentRestorationToken,
        event: AgentRunEvent
    ) {
        guard self.runID == runID, var restorationState, restorationState.token == token else {
            return
        }
        guard case .permissionRequested = event else {
            switch event {
            case .userMessageDelta(let messageID, let text):
                restorationState.hasVisibleHistory = restorationState.hasVisibleHistory
                    || !text.isEmpty
                self.restorationState = restorationState
                appendRestoredUserMessage(text, messageID: messageID)
            case .agentMessageDelta(_, let text), .thoughtDelta(_, let text):
                restorationState.hasVisibleHistory = restorationState.hasVisibleHistory
                    || !text.isEmpty
                self.restorationState = restorationState
                apply(event)
            case .toolCall(let tool):
                restorationState.hasVisibleHistory = true
                restorationState.toolIDs.insert(tool.id)
                self.restorationState = restorationState
                apply(event)
            case .toolCallUpdate(let tool):
                restorationState.hasVisibleHistory = true
                restorationState.toolIDs.insert(tool.id)
                self.restorationState = restorationState
                apply(event)
            case .plan(let entries):
                restorationState.hasVisibleHistory = restorationState.hasVisibleHistory
                    || !entries.isEmpty
                restorationState.receivedPlan = true
                self.restorationState = restorationState
                apply(event)
            case .connected, .metadata, .diagnostic, .unknown, .deliveryNotice:
                self.restorationState = restorationState
                apply(event)
            case .permissionRequested:
                preconditionFailure("Historical permissions are handled before event reduction.")
            }

            if event.isRestorationTextDelta {
                publishTokenUpdate(runID: runID)
            } else {
                flushPendingPublication()
                publishNow()
            }
            return
        }

        diagnosticsRecorder.record(
            category: .ui,
            event: "agent_presentation.history_permission_ignored",
            fields: ["run_id": runID.uuidString])
    }

    /// Settles source-qualified history and prepares a distinct current-turn boundary.
    func completeHistoryRestoration(
        runID: UUID,
        token: AgentRestorationToken,
        activation: AgentSessionActivation
    ) {
        guard self.runID == runID,
            let restorationState,
            restorationState.token == token
        else { return }
        flushPendingPublication()

        switch activation {
        case .loaded:
            interruptRestoredWork(
                toolIDs: restorationState.toolIDs,
                interruptsPlan: restorationState.receivedPlan)
            settleActiveThinkingGroup()
            if restorationState.hasVisibleHistory {
                timeline.append(.historyBoundary)
                _ = activeThinkingGroup()
                enforceTimelineBounds()
            }
            needsResponseSeparator = !outputBuffer.value.isEmpty
        case .resumed:
            restore(restorationState.checkpoint)
            appendNotice(
                "Previous history is available to the agent but this provider cannot replay it.")
        case .freshBecauseRestorationUnsupported:
            restore(restorationState.checkpoint)
            appendNotice(
                "This provider cannot restore previous history, so a fresh conversation was started.")
        case .new, .freshAfterUnavailableBookmark:
            restore(restorationState.checkpoint)
        }

        self.restorationState = nil
        diagnosticsRecorder.record(
            category: .ui,
            event: "agent_presentation.history_completed",
            fields: [
                "run_id": runID.uuidString,
                "activation": activation.presentationDiagnosticName,
            ])
        publishNow()
    }

    /// Removes only the partial state owned by a matching restoration attempt.
    func abortHistoryRestoration(runID: UUID, token: AgentRestorationToken) {
        guard self.runID == runID,
            let restorationState,
            restorationState.token == token
        else { return }
        flushPendingPublication()
        restore(restorationState.checkpoint)
        self.restorationState = nil
        diagnosticsRecorder.record(
            category: .ui,
            event: "agent_presentation.history_aborted",
            fields: ["run_id": runID.uuidString])
        publishNow()
    }

    private func appendRestoredUserMessage(_ text: String, messageID: String?) {
        guard !text.isEmpty else { return }
        settleActiveThinkingGroup()
        if case .userMessage(var message) = timeline.last,
            message.messageID == messageID
        {
            message.text.append(text)
            timeline[timeline.index(before: timeline.endIndex)] = .userMessage(message)
        } else {
            timeline.append(.userMessage(AgentUserMessagePresentation(
                id: UUID(),
                messageID: messageID,
                text: text)))
        }
        needsResponseSeparator = !outputBuffer.value.isEmpty
        enforceTimelineBounds()
    }

    private func interruptRestoredWork(toolIDs: Set<String>, interruptsPlan: Bool) {
        for index in tools.indices where toolIDs.contains(tools[index].id) {
            switch tools[index].status {
            case .completed, .failed, .interrupted:
                continue
            case .pending, .inProgress, nil:
                tools[index].status = .interrupted
                tools[index].isSettled = true
                updateTimelineTool(tools[index])
            }
        }
        guard interruptsPlan else { return }
        plan = plan.map { entry in
            guard entry.status == .inProgress else { return entry }
            return AgentPlanEntry(
                content: entry.content,
                priority: entry.priority,
                status: .interrupted)
        }
    }

    private func restorationCheckpoint() -> AgentRunPresentationRestorationCheckpoint {
        AgentRunPresentationRestorationCheckpoint(
            providerName: providerName,
            needsResponseSeparator: needsResponseSeparator,
            outputBuffer: outputBuffer,
            diagnosticBuffer: diagnosticBuffer,
            plan: plan,
            tools: tools,
            timeline: timeline,
            timelineHasOmittedActivity: timelineHasOmittedActivity,
            permissions: permissions,
            notices: notices,
            evictedToolCount: evictedToolCount,
            ignoredToolUpdateCount: ignoredToolUpdateCount)
    }

    private func restore(_ checkpoint: AgentRunPresentationRestorationCheckpoint) {
        providerName = checkpoint.providerName
        needsResponseSeparator = checkpoint.needsResponseSeparator
        outputBuffer = checkpoint.outputBuffer
        diagnosticBuffer = checkpoint.diagnosticBuffer
        plan = checkpoint.plan
        tools = checkpoint.tools
        timeline = checkpoint.timeline
        timelineHasOmittedActivity = checkpoint.timelineHasOmittedActivity
        permissions = checkpoint.permissions
        notices = checkpoint.notices
        evictedToolCount = checkpoint.evictedToolCount
        ignoredToolUpdateCount = checkpoint.ignoredToolUpdateCount
    }
}

struct AgentRunPresentationRestorationState {
    let token: AgentRestorationToken
    let checkpoint: AgentRunPresentationRestorationCheckpoint
    var toolIDs: Set<String> = []
    var hasVisibleHistory = false
    var receivedPlan = false
}

struct AgentRunPresentationRestorationCheckpoint {
    let providerName: String?
    let needsResponseSeparator: Bool
    let outputBuffer: AgentRunBoundedTextBuffer
    let diagnosticBuffer: AgentRunBoundedTextBuffer
    let plan: [AgentPlanEntry]
    let tools: [AgentToolPresentation]
    let timeline: [AgentRunTimelineItem]
    let timelineHasOmittedActivity: Bool
    let permissions: [AgentPermissionPresentation]
    let notices: [String]
    let evictedToolCount: UInt64
    let ignoredToolUpdateCount: UInt64
}

extension AgentRunEvent {
    fileprivate var isRestorationTextDelta: Bool {
        switch self {
        case .userMessageDelta, .agentMessageDelta, .thoughtDelta:
            true
        default:
            false
        }
    }
}

extension AgentSessionActivation {
    fileprivate var presentationDiagnosticName: String {
        switch self {
        case .new: "new"
        case .loaded: "loaded"
        case .resumed: "resumed"
        case .freshAfterUnavailableBookmark: "fresh_after_unavailable_bookmark"
        case .freshBecauseRestorationUnsupported: "fresh_restoration_unsupported"
        }
    }
}
