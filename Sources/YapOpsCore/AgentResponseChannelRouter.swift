// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

/// Routes streamed agent text into explicit spoken and display response channels.
///
/// The router recognizes the marker contract only at the start of legacy agent
/// messages. Provider-typed channel events bypass marker parsing. One router owns
/// one ordered stream and retains only bounded marker lookahead and narration text.
public struct AgentResponseChannelRouter: Sendable {
    /// The exact prefix that opts a legacy agent message into spoken routing.
    public static let spokenMarker = "[[yapops:spoken:v1]]\n"
    /// The optional delimiter that switches a marker-routed message to display text.
    public static let displayMarker = "\n[[yapops:display:v1]]\n"

    private static let maximumNarrationCharacters = 20_000

    private enum StreamOrigin: Equatable, Sendable {
        case marker
        case typed
    }

    private struct PendingMessage: Sendable {
        let messageID: String?
        var text: String
    }

    private struct SpokenMessage: Sendable {
        let messageID: String?
        let origin: StreamOrigin
        var possibleDisplayMarker: String
        var narration: String
        var suppression: AgentSpokenSuppressionReason?
    }

    private struct DisplayMessage: Sendable {
        let messageID: String?
        let origin: StreamOrigin
    }

    private enum State: Sendable {
        case idle
        case undecided(PendingMessage)
        case legacy(messageID: String?)
        case spoken(SpokenMessage)
        case display(DisplayMessage)
    }

    private var state: State = .idle

    /// Creates an empty response-channel router.
    public init() {}

    /// Routes one ordered event, flushing a prior message before a semantic boundary.
    ///
    /// - Parameter event: The next event from the same ordered ACP stream.
    /// - Returns: Zero or more events in their required delivery order.
    public mutating func route(_ event: AgentRunEvent) -> [AgentRunEvent] {
        switch event {
        case let .agentMessageDelta(messageID, text):
            return routeLegacy(messageID: messageID, text: text)
        case let .agentSpokenMessageDelta(messageID, text):
            return routeTypedSpoken(messageID: messageID, text: text)
        case let .agentDisplayMessageDelta(messageID, text):
            return routeTypedDisplay(messageID: messageID, text: text)
        default:
            var events = finishMessage()
            events.append(event)
            return events
        }
    }

    /// Finishes the current message and emits any safe buffered output.
    ///
    /// A partial start marker falls back to legacy text. A spoken response emits
    /// exactly one complete narration unit or one content-free suppression event.
    public mutating func finishMessage() -> [AgentRunEvent] {
        let current = state
        state = .idle

        switch current {
        case .idle, .legacy, .display:
            return []
        case let .undecided(message):
            guard !message.text.isEmpty else { return [] }
            return [.agentMessageDelta(messageID: message.messageID, text: message.text)]
        case var .spoken(message):
            var events: [AgentRunEvent] = []
            if !message.possibleDisplayMarker.isEmpty {
                let text = message.possibleDisplayMarker
                message.possibleDisplayMarker = ""
                admitNarration(text, into: &message)
                events.append(.agentSpokenMessageDelta(
                    messageID: message.messageID,
                    text: text))
            }
            events.append(contentsOf: narrationConclusion(for: message))
            return events
        }
    }

    /// Drops all buffered state without emitting it.
    public mutating func reset() {
        state = .idle
    }

    private mutating func routeLegacy(messageID: String?, text: String) -> [AgentRunEvent] {
        switch state {
        case .idle:
            state = .undecided(PendingMessage(messageID: messageID, text: text))
            return resolveUndecided()
        case var .undecided(message) where message.messageID == messageID:
            message.text.append(text)
            state = .undecided(message)
            return resolveUndecided()
        case .legacy(let currentID) where currentID == messageID:
            return [.agentMessageDelta(messageID: messageID, text: text)]
        case var .spoken(message)
            where message.messageID == messageID && message.origin == .marker:
            return routeMarkerSpoken(text, message: &message)
        case let .display(message)
            where message.messageID == messageID && message.origin == .marker:
            return [.agentDisplayMessageDelta(messageID: messageID, text: text)]
        default:
            var events = finishMessage()
            events.append(contentsOf: routeLegacy(messageID: messageID, text: text))
            return events
        }
    }

    private mutating func resolveUndecided() -> [AgentRunEvent] {
        guard case let .undecided(message) = state else { return [] }
        let marker = Self.spokenMarker

        if marker.hasPrefix(message.text) && message.text != marker {
            return []
        }
        guard message.text.hasPrefix(marker) else {
            state = .legacy(messageID: message.messageID)
            guard !message.text.isEmpty else { return [] }
            return [.agentMessageDelta(messageID: message.messageID, text: message.text)]
        }

        let remainder = String(message.text.dropFirst(marker.count))
        var spoken = SpokenMessage(
            messageID: message.messageID,
            origin: .marker,
            possibleDisplayMarker: "",
            narration: "",
            suppression: nil)
        state = .spoken(spoken)
        return routeMarkerSpoken(remainder, message: &spoken)
    }

    private mutating func routeMarkerSpoken(
        _ text: String,
        message: inout SpokenMessage
    ) -> [AgentRunEvent] {
        let combined = message.possibleDisplayMarker + text
        message.possibleDisplayMarker = ""

        if let markerRange = combined.range(of: Self.displayMarker) {
            let spokenText = String(combined[..<markerRange.lowerBound])
            let displayText = String(combined[markerRange.upperBound...])
            var events: [AgentRunEvent] = []
            if !spokenText.isEmpty {
                admitNarration(spokenText, into: &message)
                events.append(.agentSpokenMessageDelta(
                    messageID: message.messageID,
                    text: spokenText))
            }
            events.append(contentsOf: narrationConclusion(for: message))
            state = .display(DisplayMessage(messageID: message.messageID, origin: .marker))
            if !displayText.isEmpty {
                events.append(.agentDisplayMessageDelta(
                    messageID: message.messageID,
                    text: displayText))
            }
            return events
        }

        let suffixLength = possibleMarkerSuffixLength(in: combined)
        let suffixStart = combined.index(combined.endIndex, offsetBy: -suffixLength)
        let admittedText = String(combined[..<suffixStart])
        message.possibleDisplayMarker = String(combined[suffixStart...])
        if !admittedText.isEmpty {
            admitNarration(admittedText, into: &message)
        }
        state = .spoken(message)
        guard !admittedText.isEmpty else { return [] }
        return [.agentSpokenMessageDelta(messageID: message.messageID, text: admittedText)]
    }

    private mutating func routeTypedSpoken(
        messageID: String?,
        text: String
    ) -> [AgentRunEvent] {
        var events: [AgentRunEvent] = []
        var message: SpokenMessage
        if case let .spoken(current) = state,
           current.messageID == messageID,
           current.origin == .typed
        {
            message = current
        } else {
            events = finishMessage()
            message = SpokenMessage(
                messageID: messageID,
                origin: .typed,
                possibleDisplayMarker: "",
                narration: "",
                suppression: nil)
        }
        admitNarration(text, into: &message)
        state = .spoken(message)
        events.append(.agentSpokenMessageDelta(messageID: messageID, text: text))
        return events
    }

    private mutating func routeTypedDisplay(
        messageID: String?,
        text: String
    ) -> [AgentRunEvent] {
        var events: [AgentRunEvent] = []
        if case let .display(current) = state,
           current.messageID == messageID,
           current.origin == .typed
        {
            // Continue the provider-typed display stream literally.
        } else {
            events = finishMessage()
        }
        state = .display(DisplayMessage(messageID: messageID, origin: .typed))
        events.append(.agentDisplayMessageDelta(messageID: messageID, text: text))
        return events
    }

    private func possibleMarkerSuffixLength(in text: String) -> Int {
        let marker = Self.displayMarker
        let maximum = min(text.count, marker.count - 1)
        guard maximum > 0 else { return 0 }
        for length in stride(from: maximum, through: 1, by: -1) {
            if text.suffix(length) == marker.prefix(length) {
                return length
            }
        }
        return 0
    }

    private func admitNarration(_ text: String, into message: inout SpokenMessage) {
        guard message.suppression == nil else { return }
        guard message.narration.count + text.count <= Self.maximumNarrationCharacters else {
            message.narration = ""
            message.suppression = .oversized
            return
        }
        message.narration.append(text)
    }

    private func narrationConclusion(for message: SpokenMessage) -> [AgentRunEvent] {
        if let suppression = message.suppression {
            return [.agentSpokenNarrationSuppressed(
                messageID: message.messageID,
                reason: suppression)]
        }
        guard !message.narration.isEmpty else { return [] }
        return [.agentSpokenNarrationReady(
            messageID: message.messageID,
            text: message.narration)]
    }
}
