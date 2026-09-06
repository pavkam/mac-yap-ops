// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import VoiceActivationCore

extension AgentRunEvent {
    var isTokenDelta: Bool {
        switch self {
        case .agentMessageDelta, .thoughtDelta:
            true
        default:
            false
        }
    }

    var presentationDiagnosticName: String {
        switch self {
        case .connected: "connected"
        case .userMessageDelta: "user_message_delta"
        case .agentMessageDelta: "agent_message_delta"
        case .thoughtDelta: "thought_delta"
        case .artifact: "artifact"
        case .toolCall: "tool_call"
        case .toolCallUpdate: "tool_call_update"
        case .plan: "plan"
        case .permissionRequested: "permission_requested"
        case .metadata: "metadata"
        case .diagnostic: "diagnostic"
        case .deliveryNotice: "delivery_notice"
        case .unknown: "unknown"
        }
    }

    var presentationCharacterCount: Int {
        switch self {
        case .agentMessageDelta(_, let text), .thoughtDelta(_, let text):
            text.count
        case .diagnostic(let message):
            message.count
        case .metadata(_, let summary), .unknown(_, let summary):
            summary.count
        case .connected, .userMessageDelta, .artifact, .toolCall, .toolCallUpdate, .plan,
            .permissionRequested,
            .deliveryNotice:
            0
        }
    }

    var presentationArtifactMetrics: (count: Int, bytes: Int) {
        switch self {
        case let .artifact(artifact):
            (1, artifact.embeddedByteCount)
        case let .toolCall(tool):
            tool.content.artifactMetrics
        case let .toolCallUpdate(update):
            update.content.artifactMetrics
        case let .permissionRequested(request):
            request.toolCall.content.artifactMetrics
        case .connected, .userMessageDelta, .agentMessageDelta, .thoughtDelta, .plan, .metadata,
            .diagnostic, .unknown, .deliveryNotice:
            (0, 0)
        }
    }
}

private extension AgentArtifact {
    var embeddedByteCount: Int {
        switch payload {
        case .image(let data, _), .embeddedBlob(let data): data.count
        case .embeddedText(let text): text.utf8.count
        case .linked: 0
        }
    }
}

private extension Array where Element == AgentToolCallContent {
    var artifactMetrics: (count: Int, bytes: Int) {
        reduce(into: (count: 0, bytes: 0)) { result, content in
            guard case let .artifact(artifact) = content else { return }
            result.count += 1
            let bytes = artifact.embeddedByteCount
            result.bytes = result.bytes > Int.max - bytes ? Int.max : result.bytes + bytes
        }
    }
}

struct AgentRunBoundedTextBuffer {
    private let maximumBytes: Int
    private let marker: Data
    private var storage = Data()
    private var head = 0
    private(set) var discardedBytes: UInt64 = 0

    var value: String {
        guard discardedBytes > 0 else {
            return String(decoding: storage[head...], as: UTF8.self)
        }
        var rendered = marker
        rendered.append(storage[head...])
        return String(decoding: rendered, as: UTF8.self)
    }

    init(maximumBytes: Int, marker: String) {
        precondition(maximumBytes > marker.utf8.count)
        self.maximumBytes = maximumBytes
        self.marker = Data(marker.utf8)
    }

    mutating func append(_ text: String) {
        let data = Data(text.utf8)
        guard !data.isEmpty else { return }
        compactIfNeeded(additionalBytes: data.count)
        storage.append(data)
        let payloadLimit = maximumBytes - (discardedBytes > 0 ? marker.count : 0)
        if storage.count - head > payloadLimit {
            discardPrefix(atLeast: storage.count - head - (maximumBytes - marker.count))
        }
    }

    mutating func removeAll(keepingCapacity: Bool = true) {
        storage.removeAll(keepingCapacity: keepingCapacity)
        head = 0
        discardedBytes = 0
    }

    private mutating func discardPrefix(atLeast count: Int) {
        var newHead = min(storage.count, head + max(0, count))
        while newHead < storage.count, storage[newHead] & 0xC0 == 0x80 {
            newHead += 1
        }
        discardedBytes = saturatingAdd(discardedBytes, UInt64(newHead - head))
        head = newHead
        compactIfNeeded(additionalBytes: 0)
    }

    private mutating func compactIfNeeded(additionalBytes: Int) {
        guard head > 0,
            head >= 64 * 1_024 || storage.count + additionalBytes > maximumBytes * 2
        else { return }
        storage.removeSubrange(0..<head)
        head = 0
    }
}

extension AgentRunTimelineItem {
    var containsText: Bool {
        switch self {
        case .message, .userMessage:
            true
        case .thinking(let thinking):
            thinking.details.contains { detail in
                guard case .thought(let message) = detail else { return false }
                return !message.text.isEmpty
            }
        case .historyBoundary, .omitted:
            false
        }
    }

    var text: String {
        switch self {
        case .message(let message):
            message.text
        case .userMessage(let message):
            message.text
        case .thinking(let thinking):
            thinking.details.reduce(into: "") { text, detail in
                guard case .thought(let message) = detail else { return }
                text.append(message.text)
            }
        case .historyBoundary, .omitted:
            ""
        }
    }

    func droppingTextPrefix(
        atLeast byteCount: Int,
        using transform: (String, Int) -> String
    ) -> AgentRunTimelineItem {
        switch self {
        case .message(var message):
            message.text = transform(message.text, byteCount)
            return .message(message)
        case .userMessage(let message):
            return .userMessage(
                AgentUserMessagePresentation(
                    id: message.id,
                    messageID: message.messageID,
                    text: transform(message.text, byteCount),
                    disposition: message.disposition))
        case .thinking(var thinking):
            var remainingBytes = byteCount
            var retainedDetails: [AgentThinkingDetail] = []
            for detail in thinking.details {
                guard case .thought(var message) = detail, remainingBytes > 0 else {
                    retainedDetails.append(detail)
                    continue
                }
                let originalByteCount = message.text.utf8.count
                if originalByteCount <= remainingBytes {
                    remainingBytes -= originalByteCount
                    thinking.omittedDetailCount = saturatingIncrement(
                        thinking.omittedDetailCount)
                    continue
                }
                message.text = transform(message.text, remainingBytes)
                remainingBytes = 0
                retainedDetails.append(.thought(message))
            }
            thinking.details = retainedDetails
            return .thinking(thinking)
        case .historyBoundary, .omitted:
            return self
        }
    }
}

func enforceAgentRunTimelineBounds(
    _ timeline: inout [AgentRunTimelineItem],
    hasOmittedActivity: inout Bool,
    maximumTextBytes: Int,
    maximumItems: Int,
    onOmission: (AgentRunTimelineItem) -> Void = { _ in }
) {
    var retainedTextBytes = timeline.reduce(into: 0) { count, item in
        guard item.containsText else { return }
        let byteCount = item.text.utf8.count
        count = count > Int.max - byteCount ? Int.max : count + byteCount
    }
    while retainedTextBytes > maximumTextBytes,
        let index = timeline.firstIndex(where: \AgentRunTimelineItem.containsText)
    {
        onOmission(timeline[index])
        let originalByteCount = timeline[index].text.utf8.count
        let excessByteCount = retainedTextBytes - maximumTextBytes
        if originalByteCount <= excessByteCount {
            timeline.remove(at: index)
            retainedTextBytes -= originalByteCount
        } else {
            timeline[index] = timeline[index].droppingTextPrefix(
                atLeast: excessByteCount,
                using: droppingAgentRunUTF8Prefix)
            retainedTextBytes -= originalByteCount - timeline[index].text.utf8.count
        }
        hasOmittedActivity = true
    }

    if hasOmittedActivity,
        !timeline.contains(where: { item in
            if case .omitted = item { return true }
            return false
        })
    {
        timeline.insert(.omitted, at: timeline.startIndex)
    }

    while timeline.count > maximumItems,
        let index = timeline.firstIndex(where: { item in
            if case .omitted = item { return false }
            return true
        })
    {
        onOmission(timeline[index])
        timeline.remove(at: index)
        hasOmittedActivity = true
        if !timeline.contains(.omitted) {
            timeline.insert(.omitted, at: timeline.startIndex)
        }
    }
}

func normalizeAgentRunTimelineOmissionMarker(
    _ timeline: inout [AgentRunTimelineItem],
    isRequired: Bool
) {
    timeline.removeAll { $0 == .omitted }
    if isRequired {
        timeline.insert(.omitted, at: timeline.startIndex)
    }
}

private func droppingAgentRunUTF8Prefix(_ text: String, atLeast byteCount: Int) -> String {
    let data = Data(text.utf8)
    var retainedStart = min(max(0, byteCount), data.count)
    while retainedStart < data.count, data[retainedStart] & 0xC0 == 0x80 {
        retainedStart += 1
    }
    return String(decoding: data[retainedStart...], as: UTF8.self)
}

func saturatingIncrement(_ value: UInt64) -> UInt64 {
    value == UInt64.max ? UInt64.max : value + 1
}

func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? UInt64.max : result
}
