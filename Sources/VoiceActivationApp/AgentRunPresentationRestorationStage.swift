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
    var artifacts: [AgentArtifactPresentation] = []
    var retainedArtifactBytes = 0
    var omittedArtifactCount: UInt64 = 0
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
        case .agentMessageDelta(let messageID, let text),
            .agentSpokenMessageDelta(let messageID, let text),
            .agentDisplayMessageDelta(let messageID, let text):
            hasVisibleHistory = !text.isEmpty || hasVisibleHistory
            outputBuffer.append(text)
            settleActiveThinkingGroup()
            appendResponseMessage(text, messageID: messageID)
        case .agentSpokenNarrationReady, .agentSpokenNarrationSuppressed:
            break
        case .thoughtDelta(let messageID, let text):
            hasVisibleHistory = !text.isEmpty || hasVisibleHistory
            appendThinkingMessage(text, messageID: messageID)
        case .artifact(let artifact):
            hasVisibleHistory = upsertArtifact(artifact) || hasVisibleHistory
        case .toolCall(let tool):
            hasVisibleHistory = upsertTool(tool, maximumCount: maximumToolCount)
                || hasVisibleHistory
            hasVisibleHistory = upsertArtifacts(from: tool.content) || hasVisibleHistory
        case .toolCallUpdate(let update):
            hasVisibleHistory = updateTool(update) || hasVisibleHistory
            hasVisibleHistory = upsertArtifacts(from: update.content) || hasVisibleHistory
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
            if notice.kind == .artifactTruncated {
                omittedArtifactCount = saturatingAdd(
                    omittedArtifactCount,
                    notice.discardedEntries)
            }
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
            status: tool.status,
            content: toolTextContent(tool.content))
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
        let textContent = toolTextContent(update.content)
        if !textContent.isEmpty {
            tools[index].content = textContent
        }
        updateTimelineTool(tools[index])
        return true
    }

    private func toolTextContent(_ content: [AgentToolCallContent]) -> [String] {
        content.compactMap { item in
            guard case let .text(text) = item else { return nil }
            return text
        }
    }

    private mutating func upsertArtifacts(from content: [AgentToolCallContent]) -> Bool {
        var changed = false
        for item in content {
            guard case let .artifact(artifact) = item else { continue }
            changed = upsertArtifact(artifact) || changed
        }
        return changed
    }

    private mutating func upsertArtifact(_ artifact: AgentArtifact) -> Bool {
        let presentation = AgentArtifactPresentation(id: UUID(), artifact: artifact)
        let newByteCount = presentation.embeddedByteCount
        guard newByteCount <= AgentRunPresentation.maximumArtifactBytes else {
            omittedArtifactCount = saturatingIncrement(omittedArtifactCount)
            return false
        }
        if let key = canonicalURIKey(artifact.uri),
            let index = artifacts.firstIndex(where: {
                canonicalURIKey($0.artifact.uri) == key
            })
        {
            let id = artifacts[index].id
            retainedArtifactBytes -= artifacts[index].embeddedByteCount
            artifacts[index] = AgentArtifactPresentation(id: id, artifact: artifact)
            retainedArtifactBytes += newByteCount
            trimArtifacts(protecting: index)
            return true
        }
        while artifacts.count >= AgentRunPresentation.maximumArtifacts
            || retainedArtifactBytes > AgentRunPresentation.maximumArtifactBytes - newByteCount
        {
            retainedArtifactBytes -= artifacts.removeFirst().embeddedByteCount
            omittedArtifactCount = saturatingIncrement(omittedArtifactCount)
        }
        artifacts.append(presentation)
        retainedArtifactBytes += newByteCount
        return true
    }

    private mutating func trimArtifacts(protecting protectedIndex: Int) {
        var index = protectedIndex
        while retainedArtifactBytes > AgentRunPresentation.maximumArtifactBytes,
            artifacts.count > 1
        {
            let removalIndex = index == artifacts.startIndex
                ? artifacts.index(after: artifacts.startIndex)
                : artifacts.startIndex
            retainedArtifactBytes -= artifacts[removalIndex].embeddedByteCount
            artifacts.remove(at: removalIndex)
            if removalIndex < index { index -= 1 }
            omittedArtifactCount = saturatingIncrement(omittedArtifactCount)
        }
    }

    private func canonicalURIKey(_ uri: String?) -> String? {
        guard let uri, var components = URLComponents(string: uri) else { return uri }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        return components.string ?? uri
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
