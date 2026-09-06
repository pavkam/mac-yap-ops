// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

/// Describes a coalescing mutation and any bytes discarded to maintain bounds.
struct AgentRunEventCoalescingChange {
    let outputByteDelta: Int
    let diagnosticByteDelta: Int
    let discardedBytes: Int
    let noticeKind: AgentRunEventDeliveryNoticeKind
}

/// The bounded event plus metadata about payload bytes removed during normalization.
struct AgentRunEventNormalization {
    let entries: [AgentRunEventDeliveryEntry]
}

/// Indicates that a required control event cannot fit within its safety bound.
enum AgentRunEventNormalizationError: Error {
    case oversizedOpaqueIdentifier
    case oversizedPermission
    case invalidArtifact
}

/// Applies UTF-8 limits to untrusted ACP event fields before they enter the queue.
enum AgentRunEventNormalizer {
    private static let maximumControlTextBytes = 64 * 1_024
    private static let maximumPlanEntryBytes = 8 * 1_024
    private static let maximumToolTextBytes = 16 * 1_024
    private static let maximumToolTextEntries = 32
    private static let maximumRetainedToolTextBytes = 64 * 1_024

    static func normalize(_ event: AgentRunEvent) throws -> AgentRunEventNormalization {
        switch event {
        case let .userMessageDelta(messageID, text):
            try validate(identifier: messageID)
            return textEntries(kind: .userMessage(messageID), text: text)
        case let .agentMessageDelta(messageID, text):
            try validate(identifier: messageID)
            return textEntries(kind: .agentMessage(messageID), text: text)
        case let .agentSpokenMessageDelta(messageID, text):
            try validate(identifier: messageID)
            return textEntries(kind: .agentSpokenMessage(messageID), text: text)
        case let .agentSpokenNarrationReady(messageID, _):
            try validate(identifier: messageID)
            return controlEntries(event: event, discardedBytes: 0, discardedEntries: 0)
        case let .agentSpokenNarrationSuppressed(messageID, _):
            try validate(identifier: messageID)
            return controlEntries(event: event, discardedBytes: 0, discardedEntries: 0)
        case let .agentDisplayMessageDelta(messageID, text):
            try validate(identifier: messageID)
            return textEntries(kind: .agentDisplayMessage(messageID), text: text)
        case let .thoughtDelta(messageID, text):
            try validate(identifier: messageID)
            return textEntries(kind: .thought(messageID), text: text)
        case let .artifact(artifact):
            try validate(artifact: artifact)
            return AgentRunEventNormalization(entries: [artifactEntry(artifact)])
        case let .diagnostic(text):
            return textEntries(kind: .diagnostic, text: text)
        case let .connected(agentName, sessionID):
            try validate(identifier: sessionID)
            let bounded = boundedPrefix(agentName, maximumBytes: maximumControlTextBytes)
            return controlEntries(
                event: .connected(agentName: bounded.value, sessionID: sessionID),
                discardedBytes: bounded.discardedBytes,
                discardedEntries: 0)
        case let .toolCall(toolCall):
            try validate(identifier: toolCall.id)
            let bounded = boundedPrefix(toolCall.title, maximumBytes: maximumControlTextBytes)
            let normalizedContent = try normalize(toolContent: toolCall.content)
            var entries = controlEntries(
                event: .toolCall(AgentToolCall(
                    id: toolCall.id,
                    title: bounded.value,
                    kind: toolCall.kind,
                    status: toolCall.status,
                    content: normalizedContent.text)),
                discardedBytes: saturatingAdd(
                    bounded.discardedBytes,
                    normalizedContent.discardedBytes),
                discardedEntries: normalizedContent.discardedEntries).entries
            entries.append(contentsOf: normalizedContent.artifacts)
            return AgentRunEventNormalization(entries: entries)
        case let .toolCallUpdate(update):
            try validate(identifier: update.id)
            let bounded = update.title.map {
                boundedPrefix($0, maximumBytes: maximumControlTextBytes)
            }
            let normalizedContent = try normalize(toolContent: update.content)
            var entries = controlEntries(
                event: .toolCallUpdate(AgentToolCallUpdate(
                    id: update.id,
                    title: bounded?.value,
                    kind: update.kind,
                    status: update.status,
                    content: normalizedContent.text)),
                discardedBytes: saturatingAdd(
                    bounded?.discardedBytes ?? 0,
                    normalizedContent.discardedBytes),
                discardedEntries: normalizedContent.discardedEntries).entries
            entries.append(contentsOf: normalizedContent.artifacts)
            return AgentRunEventNormalization(entries: entries)
        case let .plan(plan):
            var discardedBytes = 0
            var discardedEntries = 0
            var retained: [AgentPlanEntry] = []
            retained.reserveCapacity(min(plan.count, AgentRunEventDelivery.maximumPlanEntries))
            for entry in plan.prefix(AgentRunEventDelivery.maximumPlanEntries) {
                let bounded = boundedPrefix(
                    entry.content,
                    maximumBytes: maximumPlanEntryBytes)
                discardedBytes = saturatingAdd(discardedBytes, bounded.discardedBytes)
                retained.append(AgentPlanEntry(
                    content: bounded.value,
                    priority: entry.priority,
                    status: entry.status))
            }
            if plan.count > retained.count {
                discardedEntries = plan.count - retained.count
                for entry in plan.dropFirst(retained.count) {
                    discardedBytes = saturatingAdd(discardedBytes, entry.content.utf8.count)
                }
            }
            return controlEntries(
                event: .plan(retained),
                discardedBytes: discardedBytes,
                discardedEntries: discardedEntries)
        case let .metadata(kind, summary):
            let boundedKind = boundedPrefix(kind, maximumBytes: maximumControlTextBytes)
            let boundedSummary = boundedPrefix(summary, maximumBytes: maximumControlTextBytes)
            return controlEntries(
                event: .metadata(kind: boundedKind.value, summary: boundedSummary.value),
                discardedBytes: saturatingAdd(
                    boundedKind.discardedBytes,
                    boundedSummary.discardedBytes),
                discardedEntries: 0)
        case let .unknown(discriminator, summary):
            let boundedDiscriminator = boundedPrefix(
                discriminator,
                maximumBytes: maximumControlTextBytes)
            let boundedSummary = boundedPrefix(summary, maximumBytes: maximumControlTextBytes)
            return controlEntries(
                event: .unknown(
                    discriminator: boundedDiscriminator.value,
                    summary: boundedSummary.value),
                discardedBytes: saturatingAdd(
                    boundedDiscriminator.discardedBytes,
                    boundedSummary.discardedBytes),
                discardedEntries: 0)
        case let .permissionRequested(request):
            try validate(request: request)
            let boundedTitle = request.toolCall.title.map {
                boundedPrefix($0, maximumBytes: maximumControlTextBytes)
            }
            let normalizedContent = try normalize(toolContent: request.toolCall.content)
            let normalized = AgentPermissionRequest(
                turnToken: request.turnToken,
                requestID: request.requestID,
                toolCall: AgentToolCallUpdate(
                    id: request.toolCall.id,
                    title: boundedTitle?.value,
                    kind: request.toolCall.kind,
                    status: request.toolCall.status,
                    content: normalizedContent.text),
                options: request.options)
            guard AgentRunEventDeliveryEntry.controlByteCount(for: .permissionRequested(normalized))
                    <= AgentRunEventDelivery.maximumPendingControlBytes
            else {
                throw AgentRunEventNormalizationError.oversizedPermission
            }
            var entries = controlEntries(
                event: .permissionRequested(normalized),
                discardedBytes: saturatingAdd(
                    boundedTitle?.discardedBytes ?? 0,
                    normalizedContent.discardedBytes),
                discardedEntries: normalizedContent.discardedEntries).entries
            entries.append(contentsOf: normalizedContent.artifacts)
            return AgentRunEventNormalization(entries: entries)
        case .deliveryNotice:
            return AgentRunEventNormalization(entries: [AgentRunEventDeliveryEntry(event: event)])
        }
    }

    private static func textEntries(
        kind: AgentRunEventDeliveryTextKind,
        text: String) -> AgentRunEventNormalization
    {
        guard !text.isEmpty else {
            return AgentRunEventNormalization(entries: [])
        }
        let maximumBytes = kind == .diagnostic
            ? AgentRunEventDelivery.maximumPendingDiagnosticBytes
            : AgentRunEventDelivery.maximumPendingOutputBytes
        let buffer = AgentRunEventDeliveryTextBuffer(text, maximumBytes: maximumBytes)
        var entries: [AgentRunEventDeliveryEntry] = []
        if buffer.discardedOnInitialization > 0 {
            entries.append(AgentRunEventDeliveryEntry(notice: AgentRunEventDeliveryNotice(
                kind: kind == .diagnostic ? .diagnosticTruncated : .outputTruncated,
                discardedBytes: UInt64(buffer.discardedOnInitialization),
                discardedEntries: 0)))
        }
        entries.append(AgentRunEventDeliveryEntry(textKind: kind, buffer: buffer))
        return AgentRunEventNormalization(entries: entries)
    }

    private static func controlEntries(
        event: AgentRunEvent,
        discardedBytes: Int,
        discardedEntries: Int) -> AgentRunEventNormalization
    {
        var entries: [AgentRunEventDeliveryEntry] = []
        if discardedBytes > 0 || discardedEntries > 0 {
            entries.append(AgentRunEventDeliveryEntry(notice: AgentRunEventDeliveryNotice(
                kind: .controlTruncated,
                discardedBytes: UInt64(discardedBytes),
                discardedEntries: UInt64(discardedEntries))))
        }
        entries.append(AgentRunEventDeliveryEntry(event: event))
        return AgentRunEventNormalization(entries: entries)
    }

    private static func normalize(
        toolContent: [AgentToolCallContent]
    ) throws -> (
        text: [AgentToolCallContent],
        artifacts: [AgentRunEventDeliveryEntry],
        discardedBytes: Int,
        discardedEntries: Int)
    {
        var text: [AgentToolCallContent] = []
        var artifacts: [AgentRunEventDeliveryEntry] = []
        var discardedBytes = 0
        var discardedEntries = 0
        var retainedTextBytes = 0
        text.reserveCapacity(min(toolContent.count, maximumToolTextEntries))

        for content in toolContent {
            switch content {
            case let .text(value):
                guard !value.isEmpty else { continue }
                let availableBytes = maximumRetainedToolTextBytes - retainedTextBytes
                guard text.count < maximumToolTextEntries, availableBytes > 0 else {
                    discardedBytes = saturatingAdd(discardedBytes, value.utf8.count)
                    discardedEntries = saturatingAdd(discardedEntries, 1)
                    continue
                }
                let bounded = boundedPrefix(
                    value,
                    maximumBytes: min(maximumToolTextBytes, availableBytes))
                if !bounded.value.isEmpty {
                    text.append(.text(bounded.value))
                    retainedTextBytes = saturatingAdd(
                        retainedTextBytes,
                        bounded.value.utf8.count)
                } else {
                    discardedEntries = saturatingAdd(discardedEntries, 1)
                }
                discardedBytes = saturatingAdd(discardedBytes, bounded.discardedBytes)
            case let .artifact(artifact):
                try validate(artifact: artifact)
                artifacts.append(artifactEntry(artifact))
            }
        }
        return (text, artifacts, discardedBytes, discardedEntries)
    }

    private static func artifactEntry(_ artifact: AgentArtifact) -> AgentRunEventDeliveryEntry {
        AgentRunEventDeliveryEntry(event: .artifact(artifact))
    }

    private static func validate(artifact: AgentArtifact) throws {
        try validate(
            artifact.name,
            maximumBytes: AgentArtifactLimits.maximumDisplayTextBytes,
            allowsEmpty: false)
        try validate(artifact.uri, maximumBytes: AgentArtifactLimits.maximumURIBytes)
        try validate(artifact.title, maximumBytes: AgentArtifactLimits.maximumDisplayTextBytes)
        try validate(
            artifact.descriptiveText,
            maximumBytes: AgentArtifactLimits.maximumDisplayTextBytes)
        try validate(
            artifact.mimeType,
            maximumBytes: AgentArtifactLimits.maximumMIMETypeBytes)

        switch artifact.payload {
        case let .image(data, mimeType):
            guard data.count <= AgentArtifactLimits.maximumEmbeddedPayloadBytes,
                  artifact.mimeType == mimeType
            else {
                throw AgentRunEventNormalizationError.invalidArtifact
            }
            try validate(
                mimeType,
                maximumBytes: AgentArtifactLimits.maximumMIMETypeBytes,
                allowsEmpty: false)
        case let .embeddedText(text):
            guard artifact.uri != nil,
                  text.utf8.count <= AgentArtifactLimits.maximumEmbeddedPayloadBytes
            else {
                throw AgentRunEventNormalizationError.invalidArtifact
            }
        case let .embeddedBlob(data):
            guard artifact.uri != nil,
                  data.count <= AgentArtifactLimits.maximumEmbeddedPayloadBytes
            else {
                throw AgentRunEventNormalizationError.invalidArtifact
            }
        case .linked:
            guard artifact.uri != nil else {
                throw AgentRunEventNormalizationError.invalidArtifact
            }
        }
    }

    private static func validate(
        _ value: String?,
        maximumBytes: Int,
        allowsEmpty: Bool = true) throws
    {
        guard let value else {
            return
        }
        guard value.utf8.count <= maximumBytes,
              allowsEmpty || !value.isEmpty
        else {
            throw AgentRunEventNormalizationError.invalidArtifact
        }
    }

    private static func validate(request: AgentPermissionRequest) throws {
        try validate(requestID: request.requestID)
        try validate(identifier: request.toolCall.id)
        guard request.options.count <= AgentRunEventDelivery.maximumPermissionOptions else {
            throw AgentRunEventNormalizationError.oversizedPermission
        }
        for option in request.options {
            try validate(identifier: option.id)
        }
    }

    private static func validate(requestID: ACPRequestID) throws {
        if case let .string(identifier) = requestID {
            try validate(identifier: identifier)
        }
    }

    private static func validate(identifier: String?) throws {
        guard let identifier else {
            return
        }
        guard identifier.utf8.count <= AgentRunEventDelivery.maximumOpaqueIdentifierBytes else {
            throw AgentRunEventNormalizationError.oversizedOpaqueIdentifier
        }
    }
}
