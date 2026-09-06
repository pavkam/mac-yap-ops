// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import VoiceActivationCore

@MainActor
struct AgentRunPresentationRestorationStage {
    let token: AgentRestorationToken
    var providerName: String?
    var outputBuffer = AgentRunBoundedTextBuffer(
        maximumBytes: AgentRunPresentation.maximumOutputBytes,
        marker: "… earlier output omitted …\n")
    var diagnosticBuffer = AgentRunBoundedTextBuffer(
        maximumBytes: AgentRunPresentation.maximumDiagnosticBytes,
        marker: "… earlier diagnostics omitted …\n")
    var plan: [AgentPlanEntry]?
    var tools: [AgentToolPresentation] = []
    var timeline: [AgentRunTimelineItem] = []
    var timelineHasOmittedActivity = false
    var notices: [String] = []
    var hasVisibleHistory = false
    var evictedToolCount: UInt64 = 0
    var ignoredToolUpdateCount: UInt64 = 0

    mutating func receive(
        _ event: AgentRunEvent,
        maximumToolCount: Int,
        noticeDescription: (AgentRunEventDeliveryNotice) -> String
    ) {
        switch event {
        case .connected(let agentName, _):
            providerName = agentName
        case .userMessageDelta(let messageID, let text):
            hasVisibleHistory = !text.isEmpty || hasVisibleHistory
            appendUserMessage(text, messageID: messageID)
        case .agentMessageDelta(let messageID, let text):
            hasVisibleHistory = !text.isEmpty || hasVisibleHistory
            outputBuffer.append(text)
            settleActiveThinkingGroup()
            appendResponseMessage(text, messageID: messageID)
        case .thoughtDelta(let messageID, let text):
            hasVisibleHistory = !text.isEmpty || hasVisibleHistory
            appendThinkingMessage(text, messageID: messageID)
        case .toolCall(let tool):
            hasVisibleHistory = upsertTool(tool, maximumCount: maximumToolCount)
                || hasVisibleHistory
        case .toolCallUpdate(let update):
            hasVisibleHistory = updateTool(update) || hasVisibleHistory
        case .plan(let entries):
            plan = Array(entries.prefix(AgentRunPresentation.maximumPlanEntries))
            hasVisibleHistory = !entries.isEmpty || hasVisibleHistory
        case .metadata(let kind, let summary):
            if kind == AgentRunMetadataKind.sessionRecovered {
                appendNotice(summary)
            } else {
                diagnosticBuffer.append("[\(kind)] \(summary)\n")
            }
        case .diagnostic(let message):
            diagnosticBuffer.append(message)
            if !message.hasSuffix("\n") {
                diagnosticBuffer.append("\n")
            }
        case .unknown(let discriminator, let summary):
            diagnosticBuffer.append("[\(discriminator)] \(summary)\n")
        case .deliveryNotice(let notice):
            appendNotice(noticeDescription(notice))
        case .permissionRequested:
            preconditionFailure("Historical permissions must not enter the restoration stage.")
        }
    }

    mutating func settleHistoricalWork() {
        for index in tools.indices {
            switch tools[index].status {
            case .completed, .failed, .interrupted:
                continue
            case .pending, .inProgress, nil:
                tools[index].status = .interrupted
                tools[index].isSettled = true
                updateTimelineTool(tools[index])
            }
        }
        plan = plan?.map { entry in
            guard entry.status == .inProgress else { return entry }
            return AgentPlanEntry(
                content: entry.content,
                priority: entry.priority,
                status: .interrupted)
        }
        settleActiveThinkingGroup()
    }

    mutating func evictOldestTool() -> AgentToolPresentation? {
        guard !tools.isEmpty else { return nil }
        let removed = tools.removeFirst()
        if removeTimelineTool(id: removed.presentationID) {
            timelineHasOmittedActivity = true
            enforceTimelineBounds()
        }
        evictedToolCount = saturatingIncrement(evictedToolCount)
        return removed
    }

    private mutating func appendUserMessage(_ text: String, messageID: String?) {
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
        enforceTimelineBounds()
    }

    private mutating func appendResponseMessage(_ text: String, messageID: String?) {
        guard !text.isEmpty else { return }
        if case .message(var message) = timeline.last,
            message.kind == .response,
            message.messageID == messageID
        {
            message.text.append(text)
            timeline[timeline.index(before: timeline.endIndex)] = .message(message)
        } else {
            timeline.append(.message(AgentMessagePresentation(
                id: UUID(),
                messageID: messageID,
                kind: .response,
                text: text)))
        }
        enforceTimelineBounds()
    }

    private mutating func appendThinkingMessage(_ text: String, messageID: String?) {
        guard !text.isEmpty else { return }
        var thinking = activeThinkingGroup()
        if case .thought(var message) = thinking.details.last,
            message.messageID == messageID
        {
            message.text.append(text)
            thinking.details[thinking.details.index(before: thinking.details.endIndex)] =
                .thought(message)
            replaceActiveThinkingGroup(with: thinking)
        } else {
            appendThinkingDetail(.thought(AgentMessagePresentation(
                id: UUID(),
                messageID: messageID,
                kind: .thought,
                text: text)))
        }
        enforceTimelineBounds()
    }

    private mutating func upsertTool(_ tool: AgentToolCall, maximumCount: Int) -> Bool {
        let presentation = AgentToolPresentation(
            id: tool.id,
            source: .restored(token),
            title: tool.title,
            kind: tool.kind,
            status: tool.status)
        if let index = tools.firstIndex(where: { $0.id == tool.id }) {
            tools[index] = presentation
            updateTimelineTool(presentation)
            return true
        }
        guard maximumCount > 0 else { return false }
        while tools.count >= maximumCount {
            _ = evictOldestTool()
        }
        tools.append(presentation)
        appendThinkingDetail(.tool(presentation))
        enforceTimelineBounds()
        return true
    }

    private mutating func updateTool(_ update: AgentToolCallUpdate) -> Bool {
        guard let index = tools.firstIndex(where: { $0.id == update.id }) else {
            ignoredToolUpdateCount = saturatingIncrement(ignoredToolUpdateCount)
            return false
        }
        if let title = update.title {
            tools[index].title = title
        }
        if let kind = update.kind {
            tools[index].kind = kind
        }
        if let status = update.status {
            tools[index].status = status
        }
        updateTimelineTool(tools[index])
        return true
    }

    private mutating func appendNotice(_ message: String) {
        guard notices.last != message else { return }
        notices.append(message)
        if notices.count > AgentRunPresentation.maximumNotices {
            notices.removeFirst()
        }
    }

    private mutating func appendThinkingDetail(_ detail: AgentThinkingDetail) {
        var thinking = activeThinkingGroup()
        if thinking.details.count == AgentRunPresentation.maximumThinkingDetailsPerGroup {
            thinking.details.removeFirst()
            thinking.omittedDetailCount = saturatingIncrement(thinking.omittedDetailCount)
        }
        thinking.details.append(detail)
        replaceActiveThinkingGroup(with: thinking)
    }

    private mutating func activeThinkingGroup() -> AgentThinkingPresentation {
        if case .thinking(let thinking) = timeline.last, !thinking.isSettled {
            return thinking
        }
        let thinking = AgentThinkingPresentation(id: UUID(), details: [])
        timeline.append(.thinking(thinking))
        return thinking
    }

    private mutating func replaceActiveThinkingGroup(with thinking: AgentThinkingPresentation) {
        guard case .thinking = timeline.last else {
            preconditionFailure("The restoration thinking group must be last.")
        }
        timeline[timeline.index(before: timeline.endIndex)] = .thinking(thinking)
    }

    private mutating func settleActiveThinkingGroup() {
        guard case .thinking(var thinking) = timeline.last, !thinking.isSettled else { return }
        guard !thinking.details.isEmpty else {
            timeline.removeLast()
            return
        }
        thinking.isSettled = true
        timeline[timeline.index(before: timeline.endIndex)] = .thinking(thinking)
    }

    private mutating func updateTimelineTool(_ tool: AgentToolPresentation) {
        for timelineIndex in timeline.indices {
            guard case .thinking(var thinking) = timeline[timelineIndex],
                let detailIndex = thinking.details.firstIndex(where: { detail in
                    guard case .tool(let candidate) = detail else { return false }
                    return candidate.presentationID == tool.presentationID
                })
            else { continue }
            thinking.details[detailIndex] = .tool(tool)
            timeline[timelineIndex] = .thinking(thinking)
            return
        }
    }

    @discardableResult
    private mutating func removeTimelineTool(id: AgentToolPresentationID) -> Bool {
        for timelineIndex in timeline.indices {
            guard case .thinking(var thinking) = timeline[timelineIndex],
                let detailIndex = thinking.details.firstIndex(where: { detail in
                    guard case .tool(let tool) = detail else { return false }
                    return tool.presentationID == id
                })
            else { continue }
            thinking.details.remove(at: detailIndex)
            thinking.omittedDetailCount = saturatingIncrement(thinking.omittedDetailCount)
            timeline[timelineIndex] = .thinking(thinking)
            return true
        }
        return false
    }

    private mutating func enforceTimelineBounds() {
        enforceAgentRunTimelineBounds(
            &timeline,
            hasOmittedActivity: &timelineHasOmittedActivity,
            maximumTextBytes: AgentRunPresentation.maximumTimelineTextBytes,
            maximumItems: AgentRunPresentation.maximumTimelineItems)
    }
}
