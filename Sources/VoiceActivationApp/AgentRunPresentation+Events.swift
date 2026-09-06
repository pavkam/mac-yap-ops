// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import VoiceActivationCore

extension AgentRunPresentation {
    func apply(_ event: AgentRunEvent) {
        switch event {
        case .connected(let agentName, _):
            providerName = agentName
        case .userMessageDelta:
            break
        case .agentMessageDelta(let messageID, let text),
            .agentDisplayMessageDelta(let messageID, let text):
            if needsResponseSeparator, !text.isEmpty {
                outputBuffer.append("\n\n")
                needsResponseSeparator = false
            }
            outputBuffer.append(text)
            settleActiveThinkingGroup()
            appendResponseMessage(text, messageID: messageID, kind: .response)
        case .agentSpokenMessageDelta(let messageID, let text):
            spokenOutputBuffer.append(text)
            settleActiveThinkingGroup()
            appendResponseMessage(text, messageID: messageID, kind: .spokenResponse)
        case .agentSpokenNarrationReady, .agentSpokenNarrationSuppressed:
            break
        case .thoughtDelta(let messageID, let text):
            appendThinkingMessage(text, messageID: messageID)
        case .artifact(let artifact):
            upsertArtifact(artifact)
        case .toolCall(let tool):
            upsertTool(
                AgentToolPresentation(
                    id: tool.id,
                    title: tool.title,
                    kind: tool.kind,
                    status: tool.status,
                    content: toolTextContent(tool.content)))
            upsertArtifacts(from: tool.content)
        case .toolCallUpdate(let update):
            updateTool(update)
            upsertArtifacts(from: update.content)
        case .plan(let entries):
            plan = entries
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
        case .permissionRequested(let request):
            let key = AgentPermissionKey(
                turnToken: request.turnToken,
                requestID: request.requestID)
            guard !permissions.contains(where: { $0.key == key }) else { return }
            permissions.append(
                AgentPermissionPresentation(
                    key: key,
                    toolTitle: request.toolCall.title ?? "Agent action",
                    options: request.options,
                    isResolving: false))
        case .unknown(let discriminator, let summary):
            diagnosticBuffer.append("[\(discriminator)] \(summary)\n")
        case .deliveryNotice(let notice):
            if notice.kind == .artifactTruncated {
                omittedArtifactCount = saturatingAdd(
                    omittedArtifactCount,
                    notice.discardedEntries)
            }
            appendNotice(noticeDescription(notice))
        }
    }

    func appendNotice(_ message: String) {
        guard notices.last != message else { return }
        notices.append(message)
        if notices.count > Self.maximumNotices {
            notices.remove(at: notices.startIndex)
        }
    }

    func upsertTool(_ tool: AgentToolPresentation) {
        if let index = tools.firstIndex(where: { $0.presentationID == tool.presentationID }) {
            tools[index] = tool
            updateTimelineTool(tool)
            return
        }
        if tools.count == Self.maximumTools {
            let removedTool = tools.remove(at: tools.startIndex)
            if removeTimelineTool(id: removedTool.presentationID) {
                markLiveTimelineOmitted()
            }
            evictedToolCount = saturatingIncrement(evictedToolCount)
        }
        tools.append(tool)
        appendThinkingDetail(.tool(tool))
        enforceSourceQualifiedToolBounds()
        enforceTimelineBounds()
    }

    func updateTool(_ update: AgentToolCallUpdate) {
        guard let index = tools.firstIndex(where: {
            $0.source == .live && $0.id == update.id
        }) else {
            ignoredToolUpdateCount = saturatingIncrement(ignoredToolUpdateCount)
            return
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
    }

    func toolTextContent(_ content: [AgentToolCallContent]) -> [String] {
        content.compactMap { item in
            guard case let .text(text) = item else { return nil }
            return text
        }
    }

    func upsertArtifacts(from content: [AgentToolCallContent]) {
        for item in content {
            guard case let .artifact(artifact) = item else { continue }
            upsertArtifact(artifact)
        }
    }

    func upsertArtifact(_ artifact: AgentArtifact) {
        let newByteCount = AgentArtifactPresentation(id: UUID(), artifact: artifact)
            .embeddedByteCount
        guard newByteCount <= Self.maximumArtifactBytes else {
            recordArtifactOmission()
            return
        }

        if let key = canonicalURIKey(artifact.uri),
            var index = artifacts.firstIndex(where: {
                canonicalURIKey($0.artifact.uri) == key
            })
        {
            let id = artifacts[index].id
            retainedArtifactBytes -= artifacts[index].embeddedByteCount
            artifacts[index] = AgentArtifactPresentation(id: id, artifact: artifact)
            retainedArtifactBytes += newByteCount

            while retainedArtifactBytes > Self.maximumArtifactBytes, artifacts.count > 1 {
                let removalIndex = index == artifacts.startIndex
                    ? artifacts.index(after: artifacts.startIndex)
                    : artifacts.startIndex
                retainedArtifactBytes -= artifacts[removalIndex].embeddedByteCount
                artifacts.remove(at: removalIndex)
                if removalIndex < index {
                    index -= 1
                }
                recordArtifactOmission()
            }
            return
        }

        while artifacts.count >= Self.maximumArtifacts
            || retainedArtifactBytes > Self.maximumArtifactBytes - newByteCount
        {
            guard !artifacts.isEmpty else { break }
            retainedArtifactBytes -= artifacts.removeFirst().embeddedByteCount
            recordArtifactOmission()
        }
        artifacts.append(AgentArtifactPresentation(id: UUID(), artifact: artifact))
        retainedArtifactBytes += newByteCount
    }

    func canonicalURIKey(_ uri: String?) -> String? {
        guard let uri else { return nil }
        guard var components = URLComponents(string: uri) else { return uri }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        return components.string ?? uri
    }

    func recordArtifactOmission() {
        omittedArtifactCount = saturatingIncrement(omittedArtifactCount)
        guard omittedArtifactCount == 1 else { return }
        appendNotice("Earlier generated results were omitted to keep this conversation responsive.")
    }

    func settleTools() {
        for index in tools.indices where tools[index].isWorking {
            tools[index].isSettled = true
            updateTimelineTool(tools[index])
        }
        settleActiveThinkingGroup()
    }

    func appendResponseMessage(
        _ text: String,
        messageID: String?,
        kind: AgentMessagePresentationKind
    ) {
        guard !text.isEmpty else { return }
        if case .message(var message) = timeline.last,
            message.kind == kind,
            message.messageID == messageID
        {
            message.text.append(text)
            timeline[timeline.index(before: timeline.endIndex)] = .message(message)
            enforceTimelineBounds()
            return
        }

        timeline.append(
            .message(
                AgentMessagePresentation(
                    id: UUID(),
                    messageID: messageID,
                    kind: kind,
                    text: text)))
        enforceTimelineBounds()
    }

    func appendThinkingMessage(_ text: String, messageID: String?) {
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
            appendThinkingDetail(
                .thought(
                    AgentMessagePresentation(
                        id: UUID(),
                        messageID: messageID,
                        kind: .thought,
                        text: text)))
        }
        enforceTimelineBounds()
    }

    func appendThinkingDetail(_ detail: AgentThinkingDetail) {
        var thinking = activeThinkingGroup()
        if thinking.details.count == Self.maximumThinkingDetailsPerGroup {
            thinking.details.removeFirst()
            thinking.omittedDetailCount = saturatingIncrement(thinking.omittedDetailCount)
        }
        thinking.details.append(detail)
        replaceActiveThinkingGroup(with: thinking)
    }

    func activeThinkingGroup() -> AgentThinkingPresentation {
        if case .thinking(let thinking) = timeline.last, !thinking.isSettled {
            return thinking
        }
        let thinking = AgentThinkingPresentation(id: UUID(), details: [])
        timeline.append(.thinking(thinking))
        return thinking
    }

    func replaceActiveThinkingGroup(with thinking: AgentThinkingPresentation) {
        guard case .thinking = timeline.last else {
            preconditionFailure("The active thinking group must be the final timeline item.")
        }
        timeline[timeline.index(before: timeline.endIndex)] = .thinking(thinking)
    }

    func settleActiveThinkingGroup() {
        guard case .thinking(var thinking) = timeline.last, !thinking.isSettled else { return }
        guard !thinking.details.isEmpty else {
            timeline.removeLast()
            return
        }
        thinking.isSettled = true
        timeline[timeline.index(before: timeline.endIndex)] = .thinking(thinking)
    }

    func updateTimelineTool(_ tool: AgentToolPresentation) {
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
    func removeTimelineTool(id: AgentToolPresentationID) -> Bool {
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

    func enforceTimelineBounds() {
        let historicalIDs: Set<AgentRunTimelineItemID>
        if let boundaryIndex = timeline.lastIndex(of: .historyBoundary) {
            historicalIDs = Set(timeline[..<boundaryIndex].map(\.id))
        } else {
            historicalIDs = []
        }
        var historicalHasOmissions = historicalTimelineHasOmittedActivity
        var liveHasOmissions = liveTimelineHasOmittedActivity
        var hasOmissions = historicalHasOmissions || liveHasOmissions
        enforceAgentRunTimelineBounds(
            &timeline,
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
        historicalTimelineHasOmittedActivity = historicalHasOmissions
        liveTimelineHasOmittedActivity = liveHasOmissions
        normalizeAgentRunTimelineOmissionMarker(
            &timeline,
            isRequired: historicalHasOmissions || liveHasOmissions)
    }

    func markLiveTimelineOmitted() {
        liveTimelineHasOmittedActivity = true
        ensureTimelineOmissionMarker()
    }

    func markHistoricalTimelineOmitted() {
        historicalTimelineHasOmittedActivity = true
        ensureTimelineOmissionMarker()
    }

    private func ensureTimelineOmissionMarker() {
        guard
            !timeline.contains(where: { item in
                if case .omitted = item { return true }
                return false
            })
        else { return }
        timeline.insert(.omitted, at: timeline.startIndex)
    }

}
