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
            stage: AgentRunPresentationRestorationStage(token: token))
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
            let maximumToolCount = max(
                0,
                Self.maximumTools - tools.count - historicalTools.count)
            restorationState.stage.receive(
                event,
                maximumToolCount: maximumToolCount,
                noticeDescription: noticeDescription)
            self.restorationState = restorationState

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
            var restorationState,
            restorationState.token == token
        else { return }
        flushPendingPublication()
        self.restorationState = nil

        switch activation {
        case .loaded:
            restorationState.stage.settleHistoricalWork()
            mergeLoadedRestoration(
                restorationState.stage,
                hasLiveProviderUpdate: restorationState.hasLiveProviderUpdate)
        case .resumed:
            appendNotice(
                "Previous history is available to the agent but this provider cannot replay it.")
        case .freshBecauseRestorationUnsupported:
            appendNotice(
                "This provider cannot restore previous history, so a fresh conversation was started.")
        case .new, .freshAfterUnavailableBookmark:
            break
        }

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
        diagnosticsRecorder.record(
            category: .ui,
            event: "agent_presentation.history_aborted",
            fields: ["run_id": runID.uuidString])
        publishNow()
    }

    private func mergeLoadedRestoration(
        _ stage: AgentRunPresentationRestorationStage,
        hasLiveProviderUpdate: Bool
    ) {
        let liveOutputWasEmpty = outputBuffer.value.isEmpty
        outputBuffer = mergedTextBuffer(
            historical: stage.outputBuffer,
            live: outputBuffer,
            maximumBytes: Self.maximumOutputBytes,
            marker: "… earlier output omitted …\n",
            separator: "\n\n")
        diagnosticBuffer = mergedTextBuffer(
            historical: stage.diagnosticBuffer,
            live: diagnosticBuffer,
            maximumBytes: Self.maximumDiagnosticBytes,
            marker: "… earlier diagnostics omitted …\n")
        if !hasLiveProviderUpdate, let restoredProviderName = stage.providerName {
            providerName = restoredProviderName
        }
        notices = boundedNotices(stage.notices + notices)

        historicalTools = stage.tools
        historicalArtifacts = stage.artifacts
        omittedArtifactCount = saturatingAdd(
            omittedArtifactCount,
            stage.omittedArtifactCount)
        if let restoredPlan = stage.plan {
            historicalPlan = restoredPlan
        }
        evictedToolCount = saturatingAdd(evictedToolCount, stage.evictedToolCount)
        ignoredToolUpdateCount = saturatingAdd(
            ignoredToolUpdateCount,
            stage.ignoredToolUpdateCount)

        var historicalHasOmissions = stage.timelineHasOmittedActivity
        var liveHasOmissions = liveTimelineHasOmittedActivity
        timeline = mergedTimeline(
            historical: stage.timeline,
            historicalHasOmissions: &historicalHasOmissions,
            liveHasOmissions: &liveHasOmissions,
            includesHistoryBoundary: stage.hasVisibleHistory,
            replacesExistingHistory: true)
        historicalTimelineHasOmittedActivity = historicalHasOmissions
        liveTimelineHasOmittedActivity = liveHasOmissions
        if liveOutputWasEmpty {
            needsResponseSeparator = !stage.outputBuffer.value.isEmpty
        }
    }

    var sourceQualifiedProviderName: String? {
        guard let restorationState,
            !restorationState.hasLiveProviderUpdate,
            let restoredProviderName = restorationState.stage.providerName
        else { return providerName }
        return restoredProviderName
    }

    var sourceQualifiedOutput: String {
        guard let stage = restorationState?.stage else { return outputBuffer.value }
        return mergedTextBuffer(
            historical: stage.outputBuffer,
            live: outputBuffer,
            maximumBytes: Self.maximumOutputBytes,
            marker: "… earlier output omitted …\n",
            separator: "\n\n").value
    }

    var sourceQualifiedDiagnostics: String {
        guard let stage = restorationState?.stage else { return diagnosticBuffer.value }
        return mergedTextBuffer(
            historical: stage.diagnosticBuffer,
            live: diagnosticBuffer,
            maximumBytes: Self.maximumDiagnosticBytes,
            marker: "… earlier diagnostics omitted …\n").value
    }

    var sourceQualifiedTimeline: [AgentRunTimelineItem] {
        guard let stage = restorationState?.stage else { return timeline }
        var historicalHasOmissions = historicalTimelineHasOmittedActivity
            || stage.timelineHasOmittedActivity
        var liveHasOmissions = liveTimelineHasOmittedActivity
        return mergedTimeline(
            historical: stage.timeline,
            historicalHasOmissions: &historicalHasOmissions,
            liveHasOmissions: &liveHasOmissions,
            includesHistoryBoundary: false,
            replacesExistingHistory: false)
    }

    var sourceQualifiedNotices: [String] {
        guard let stage = restorationState?.stage else { return notices }
        return boundedNotices(stage.notices + notices)
    }

    var sourceQualifiedPlan: [AgentPlanEntry] {
        let livePlan = Array(plan.suffix(Self.maximumPlanEntries))
        let restorationPlan = restorationState?.stage.plan ?? []
        let history = historicalPlan + restorationPlan
        let availableHistoryCount = max(0, Self.maximumPlanEntries - livePlan.count)
        return Array(history.suffix(availableHistoryCount)) + livePlan
    }

    var sourceQualifiedTools: [AgentToolPresentation] {
        let history = historicalTools + (restorationState?.stage.tools ?? [])
        let availableHistoryCount = max(0, Self.maximumTools - tools.count)
        return Array(history.suffix(availableHistoryCount)) + tools
    }

    var sourceQualifiedEvictedToolCount: UInt64 {
        saturatingAdd(evictedToolCount, restorationState?.stage.evictedToolCount ?? 0)
    }

    var sourceQualifiedIgnoredToolUpdateCount: UInt64 {
        saturatingAdd(
            ignoredToolUpdateCount,
            restorationState?.stage.ignoredToolUpdateCount ?? 0)
    }

    var sourceQualifiedArtifactProjection: (
        artifacts: [AgentArtifactPresentation],
        omittedCount: UInt64
    ) {
        let stagedArtifacts = restorationState?.stage.artifacts ?? []
        var combined = historicalArtifacts + stagedArtifacts + artifacts
        var seenURIs: Set<String> = []
        combined = combined.reversed().filter { artifact in
            guard let key = canonicalURIKey(artifact.artifact.uri) else { return true }
            return seenURIs.insert(key).inserted
        }.reversed()

        var retainedBytes = combined.reduce(0) { $0 + $1.embeddedByteCount }
        var additionalOmissions: UInt64 = 0
        while combined.count > Self.maximumArtifacts
            || retainedBytes > Self.maximumArtifactBytes
        {
            retainedBytes -= combined.removeFirst().embeddedByteCount
            additionalOmissions = saturatingIncrement(additionalOmissions)
        }
        let stagedOmissions = restorationState?.stage.omittedArtifactCount ?? 0
        return (
            combined,
            saturatingAdd(
                saturatingAdd(omittedArtifactCount, stagedOmissions),
                additionalOmissions))
    }

    func enforceSourceQualifiedToolBounds() {
        let historyCapacity = max(0, Self.maximumTools - tools.count)
        var restorationState = restorationState
        while historicalTools.count + (restorationState?.stage.tools.count ?? 0)
            > historyCapacity
        {
            if !historicalTools.isEmpty {
                let removed = historicalTools.removeFirst()
                evictedToolCount = saturatingIncrement(evictedToolCount)
                if removeTimelineTool(id: removed.presentationID) {
                    markHistoricalTimelineOmitted()
                }
            } else if restorationState?.stage.evictOldestTool() == nil {
                break
            }
        }
        self.restorationState = restorationState
    }

    private func mergedTextBuffer(
        historical: AgentRunBoundedTextBuffer,
        live: AgentRunBoundedTextBuffer,
        maximumBytes: Int,
        marker: String,
        separator: String = ""
    ) -> AgentRunBoundedTextBuffer {
        var result = AgentRunBoundedTextBuffer(maximumBytes: maximumBytes, marker: marker)
        let historicalValue = historical.value
        let liveValue = live.value
        result.append(historicalValue)
        if !historicalValue.isEmpty, !liveValue.isEmpty {
            result.append(separator)
        }
        result.append(liveValue)
        return result
    }

    private func mergedTimeline(
        historical: [AgentRunTimelineItem],
        historicalHasOmissions: inout Bool,
        liveHasOmissions: inout Bool,
        includesHistoryBoundary: Bool,
        replacesExistingHistory: Bool
    ) -> [AgentRunTimelineItem] {
        let isSentinel: (AgentRunTimelineItem) -> Bool = { item in
            switch item {
            case .omitted, .historyBoundary:
                true
            case .message, .userMessage, .thinking:
                false
            }
        }
        let existingBoundaryIndex = timeline.lastIndex(of: .historyBoundary)
        let priorHistory: [AgentRunTimelineItem]
        let retainedLiveSlice: ArraySlice<AgentRunTimelineItem>
        let live: [AgentRunTimelineItem]
        if let existingBoundaryIndex {
            priorHistory = replacesExistingHistory
                ? []
                : timeline[..<existingBoundaryIndex].filter { !isSentinel($0) }
            let liveStartIndex = timeline.index(after: existingBoundaryIndex)
            retainedLiveSlice = timeline[liveStartIndex...]
            live = retainedLiveSlice.filter { !isSentinel($0) }
        } else {
            priorHistory = []
            retainedLiveSlice = timeline[...]
            live = retainedLiveSlice.filter { !isSentinel($0) }
        }

        historicalHasOmissions = historicalHasOmissions || historical.contains(.omitted)
        let retainedHistory = historical.filter { !isSentinel($0) } + priorHistory
        var result = retainedHistory
        if includesHistoryBoundary
            || historical.contains(.historyBoundary)
            || (existingBoundaryIndex != nil && !replacesExistingHistory)
        {
            result.append(.historyBoundary)
        }
        result.append(contentsOf: live)
        let historicalIDs = Set(retainedHistory.map(\.id))
        var hasOmissions = historicalHasOmissions || liveHasOmissions
        enforceAgentRunTimelineBounds(
            &result,
            hasOmittedActivity: &hasOmissions,
            maximumTextBytes: Self.maximumTimelineTextBytes,
            maximumItems: Self.maximumTimelineItems,
            onOmission: { item in
                switch item {
                case .omitted, .historyBoundary:
                    break
                case .message, .userMessage, .thinking:
                    if historicalIDs.contains(item.id) {
                        historicalHasOmissions = true
                    } else {
                        liveHasOmissions = true
                    }
                }
            })
        normalizeAgentRunTimelineOmissionMarker(
            &result,
            isRequired: historicalHasOmissions || liveHasOmissions)
        return result
    }

    private func boundedNotices(_ values: [String]) -> [String] {
        Array(values.suffix(Self.maximumNotices))
    }
}

struct AgentRunPresentationRestorationState {
    var stage: AgentRunPresentationRestorationStage
    var hasLiveProviderUpdate = false

    var token: AgentRestorationToken { stage.token }
    var tools: [AgentToolPresentation] { stage.tools }
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
