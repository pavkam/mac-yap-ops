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
                restorationState.hasVisibleHistory = upsertRestoredTool(
                    tool,
                    restorationState: &restorationState)
                    || restorationState.hasVisibleHistory
                self.restorationState = restorationState
            case .toolCallUpdate(let tool):
                restorationState.hasVisibleHistory = updateRestoredTool(
                    tool,
                    restorationState: &restorationState)
                    || restorationState.hasVisibleHistory
                self.restorationState = restorationState
            case .plan(let entries):
                restorationState.hasVisibleHistory = restorationState.hasVisibleHistory
                    || !entries.isEmpty
                restorationState.plan = Array(entries.prefix(Self.maximumPlanEntries))
                self.restorationState = restorationState
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
            var completedRestoration = restorationState
            interruptRestoredWork(restorationState: &completedRestoration)
            historicalTools = completedRestoration.tools
            if let restoredPlan = completedRestoration.plan {
                historicalPlan = restoredPlan
            }
            evictedToolCount = saturatingAdd(
                evictedToolCount,
                completedRestoration.evictedToolCount)
            ignoredToolUpdateCount = saturatingAdd(
                ignoredToolUpdateCount,
                completedRestoration.ignoredToolUpdateCount)
            settleActiveThinkingGroup()
            if restorationState.hasVisibleHistory {
                timeline.append(.historyBoundary)
                _ = activeThinkingGroup()
                enforceTimelineBounds()
            }
            needsResponseSeparator = !outputBuffer.value.isEmpty
        case .resumed:
            self.restorationState = nil
            discardRestorationPreservingCurrentSources(restorationState.checkpoint)
            appendNotice(
                "Previous history is available to the agent but this provider cannot replay it.")
        case .freshBecauseRestorationUnsupported:
            self.restorationState = nil
            discardRestorationPreservingCurrentSources(restorationState.checkpoint)
            appendNotice(
                "This provider cannot restore previous history, so a fresh conversation was started.")
        case .new, .freshAfterUnavailableBookmark:
            self.restorationState = nil
            discardRestorationPreservingCurrentSources(restorationState.checkpoint)
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
        self.restorationState = nil
        discardRestorationPreservingCurrentSources(restorationState.checkpoint)
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

    private func interruptRestoredWork(
        restorationState: inout AgentRunPresentationRestorationState
    ) {
        for index in restorationState.tools.indices {
            switch restorationState.tools[index].status {
            case .completed, .failed, .interrupted:
                continue
            case .pending, .inProgress, nil:
                restorationState.tools[index].status = .interrupted
                restorationState.tools[index].isSettled = true
                updateTimelineTool(restorationState.tools[index])
            }
        }
        restorationState.plan = restorationState.plan?.map { entry in
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
            historicalPlan: historicalPlan,
            historicalTools: historicalTools,
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
        historicalPlan = checkpoint.historicalPlan
        historicalTools = checkpoint.historicalTools
        timeline = checkpoint.timeline
        timelineHasOmittedActivity = checkpoint.timelineHasOmittedActivity
        permissions = checkpoint.permissions
        notices = checkpoint.notices
        evictedToolCount = checkpoint.evictedToolCount
        ignoredToolUpdateCount = checkpoint.ignoredToolUpdateCount
    }

    private func discardRestorationPreservingCurrentSources(
        _ checkpoint: AgentRunPresentationRestorationCheckpoint
    ) {
        let currentPlan = plan
        let currentTools = tools
        let currentHistoricalPlan = historicalPlan
        let currentHistoricalTools = historicalTools
        let currentEvictedToolCount = evictedToolCount
        let currentIgnoredToolUpdateCount = ignoredToolUpdateCount
        restore(checkpoint)
        plan = currentPlan
        tools = currentTools
        historicalPlan = currentHistoricalPlan
        historicalTools = currentHistoricalTools
        evictedToolCount = currentEvictedToolCount
        ignoredToolUpdateCount = currentIgnoredToolUpdateCount

        let retainedTools = historicalTools + tools
        let retainedIDs = Set(retainedTools.lazy.map(\.presentationID))
        for checkpointTool in checkpoint.historicalTools + checkpoint.tools
        where !retainedIDs.contains(checkpointTool.presentationID) {
            if removeTimelineTool(id: checkpointTool.presentationID) {
                markTimelineOmitted()
            }
        }
        let checkpointIDs = Set(
            (checkpoint.historicalTools + checkpoint.tools).lazy.map(\.presentationID))
        for tool in retainedTools {
            if checkpointIDs.contains(tool.presentationID) {
                updateTimelineTool(tool)
            } else {
                appendThinkingDetail(.tool(tool))
            }
        }
        enforceTimelineBounds()
    }

    private func upsertRestoredTool(
        _ tool: AgentToolCall,
        restorationState: inout AgentRunPresentationRestorationState
    ) -> Bool {
        let presentation = AgentToolPresentation(
            id: tool.id,
            source: .restored(restorationState.token),
            title: tool.title,
            kind: tool.kind,
            status: tool.status)
        if let index = restorationState.tools.firstIndex(where: { $0.id == tool.id }) {
            restorationState.tools[index] = presentation
            updateTimelineTool(presentation)
            return true
        }

        let capacity = max(
            0,
            Self.maximumTools - tools.count - historicalTools.count)
        guard capacity > 0 else { return false }
        while restorationState.tools.count >= capacity {
            let removed = restorationState.tools.removeFirst()
            if removeTimelineTool(id: removed.presentationID) {
                markTimelineOmitted()
            }
            restorationState.evictedToolCount = saturatingIncrement(
                restorationState.evictedToolCount)
        }
        restorationState.tools.append(presentation)
        appendThinkingDetail(.tool(presentation))
        enforceTimelineBounds()
        return true
    }

    private func updateRestoredTool(
        _ update: AgentToolCallUpdate,
        restorationState: inout AgentRunPresentationRestorationState
    ) -> Bool {
        guard let index = restorationState.tools.firstIndex(where: { $0.id == update.id }) else {
            restorationState.ignoredToolUpdateCount = saturatingIncrement(
                restorationState.ignoredToolUpdateCount)
            return false
        }
        if let title = update.title {
            restorationState.tools[index].title = title
        }
        if let kind = update.kind {
            restorationState.tools[index].kind = kind
        }
        if let status = update.status {
            restorationState.tools[index].status = status
        }
        updateTimelineTool(restorationState.tools[index])
        return true
    }

    var sourceQualifiedPlan: [AgentPlanEntry] {
        let livePlan = Array(plan.suffix(Self.maximumPlanEntries))
        let restorationPlan = restorationState?.plan ?? []
        let history = historicalPlan + restorationPlan
        let availableHistoryCount = max(0, Self.maximumPlanEntries - livePlan.count)
        return Array(history.suffix(availableHistoryCount)) + livePlan
    }

    var sourceQualifiedTools: [AgentToolPresentation] {
        let history = historicalTools + (restorationState?.tools ?? [])
        let availableHistoryCount = max(0, Self.maximumTools - tools.count)
        return Array(history.suffix(availableHistoryCount)) + tools
    }

    var sourceQualifiedEvictedToolCount: UInt64 {
        saturatingAdd(evictedToolCount, restorationState?.evictedToolCount ?? 0)
    }

    var sourceQualifiedIgnoredToolUpdateCount: UInt64 {
        saturatingAdd(ignoredToolUpdateCount, restorationState?.ignoredToolUpdateCount ?? 0)
    }

    func enforceSourceQualifiedToolBounds() {
        let historyCapacity = max(0, Self.maximumTools - tools.count)
        var restorationState = restorationState
        while historicalTools.count + (restorationState?.tools.count ?? 0) > historyCapacity {
            let removed: AgentToolPresentation
            if !historicalTools.isEmpty {
                removed = historicalTools.removeFirst()
                evictedToolCount = saturatingIncrement(evictedToolCount)
            } else if var currentRestoration = restorationState,
                !currentRestoration.tools.isEmpty
            {
                removed = currentRestoration.tools.removeFirst()
                currentRestoration.evictedToolCount = saturatingIncrement(
                    currentRestoration.evictedToolCount)
                restorationState = currentRestoration
            } else {
                break
            }
            if removeTimelineTool(id: removed.presentationID) {
                markTimelineOmitted()
            }
        }
        self.restorationState = restorationState
    }
}

struct AgentRunPresentationRestorationState {
    let token: AgentRestorationToken
    let checkpoint: AgentRunPresentationRestorationCheckpoint
    var plan: [AgentPlanEntry]? = nil
    var tools: [AgentToolPresentation] = []
    var hasVisibleHistory = false
    var evictedToolCount: UInt64 = 0
    var ignoredToolUpdateCount: UInt64 = 0
}

struct AgentRunPresentationRestorationCheckpoint {
    let providerName: String?
    let needsResponseSeparator: Bool
    let outputBuffer: AgentRunBoundedTextBuffer
    let diagnosticBuffer: AgentRunBoundedTextBuffer
    let plan: [AgentPlanEntry]
    let tools: [AgentToolPresentation]
    let historicalPlan: [AgentPlanEntry]
    let historicalTools: [AgentToolPresentation]
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
