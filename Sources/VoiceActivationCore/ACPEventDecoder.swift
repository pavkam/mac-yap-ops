// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

/// Converts validated ACP session-update notifications into bounded app events.
public struct ACPEventDecoder: Sendable {
    /// The maximum retained UTF-8 size for generated metadata summaries.
    public static let maximumSummaryBytes = 256
    /// The maximum retained UTF-8 size for opaque remote identifiers.
    public static let maximumOpaqueIdentifierBytes = AgentRunEventDelivery.maximumOpaqueIdentifierBytes

    /// Errors raised when a session update does not match its declared shape.
    public enum EventError: Error, Equatable, Sendable {
        /// A required field was missing, invalid, or outside its accepted bound.
        case malformedSessionUpdate(String)
    }

    private static let maximumDiscriminatorBytes = 128

    /// Creates a stateless ACP event decoder.
    public init() {}

    /// Decodes a `session/update` notification and ignores unrelated messages.
    ///
    /// - Parameter message: A validated JSON-RPC message.
    /// - Returns: A bounded app event, or `nil` for a non-session notification.
    /// - Throws: ``EventError`` when the declared session-update payload is malformed.
    public func event(from message: ACPMessage) throws -> AgentRunEvent? {
        guard case let .notification(method, params) = message, method == "session/update" else {
            return nil
        }

        let parameters = try object(params, named: "params")
        _ = try opaqueString(parameters["sessionId"], named: "sessionId")
        let update = try object(parameters["update"], named: "update")
        let discriminator = try string(update["sessionUpdate"], named: "sessionUpdate")

        switch discriminator {
        case "user_message_chunk":
            let chunk = try contentChunk(update)
            guard chunk.isUserRequest,
                  case let .text(text) = chunk.content
            else {
                return nil
            }
            return .userMessageDelta(messageID: chunk.messageID, text: text)
        case "agent_message_chunk":
            let chunk = try contentChunk(update)
            switch chunk.content {
            case let .text(text):
                return switch chunk.responseChannel {
                case .spoken:
                    .agentSpokenMessageDelta(messageID: chunk.messageID, text: text)
                case .display:
                    .agentDisplayMessageDelta(messageID: chunk.messageID, text: text)
                case nil:
                    .agentMessageDelta(messageID: chunk.messageID, text: text)
                }
            case let .artifact(artifact):
                return .artifact(artifact)
            case .unsupported:
                return .metadata(
                    kind: discriminator,
                    summary: bounded("Agent sent \(chunk.contentType) content"))
            }
        case "agent_thought_chunk":
            let chunk = try contentChunk(update)
            guard case let .text(text) = chunk.content else {
                return .metadata(
                    kind: discriminator,
                    summary: bounded("Agent sent \(chunk.contentType) thought content"))
            }
            return .thoughtDelta(messageID: chunk.messageID, text: text)
        case "tool_call":
            return .toolCall(try toolCall(update))
        case "tool_call_update":
            return .toolCallUpdate(try toolCallUpdate(update))
        case "plan":
            return .plan(try plan(update))
        case "available_commands_update":
            return .metadata(kind: discriminator, summary: try availableCommandsSummary(update))
        case "current_mode_update":
            let mode = try string(update["currentModeId"], named: "currentModeId")
            return .metadata(kind: discriminator, summary: bounded("Current mode: \(mode)"))
        case "config_option_update":
            return .metadata(kind: discriminator, summary: try configOptionsSummary(update))
        case "session_info_update":
            return .metadata(kind: discriminator, summary: try sessionInfoSummary(update))
        case "usage_update":
            return .metadata(kind: discriminator, summary: try usageSummary(update))
        case "async_task_spawned", "async_task_progress", "async_task_state_update":
            do {
                return .backgroundTask(try backgroundTaskUpdate(
                    discriminator: discriminator,
                    update: update))
            } catch {
                return AgentBackgroundTaskLimits.invalidUpdate
            }
        default:
            let retainedDiscriminator = bounded(
                discriminator,
                maximumBytes: Self.maximumDiscriminatorBytes)
            return .unknown(
                discriminator: retainedDiscriminator,
                summary: bounded("Unsupported ACP session update: \(retainedDiscriminator)"))
        }
    }

    func sessionUpdateDiscriminator(from message: ACPMessage) throws -> String {
        guard case let .notification(method, params) = message, method == "session/update" else {
            throw malformed("session/update notification")
        }
        let parameters = try object(params, named: "params")
        _ = try opaqueString(parameters["sessionId"], named: "sessionId")
        let update = try object(parameters["update"], named: "update")
        return try string(update["sessionUpdate"], named: "sessionUpdate")
    }

    private func contentChunk(_ update: [String: ACPJSONValue]) throws -> ContentChunk {
        let content = try object(update["content"], named: "content")
        let contentType = try string(content["type"], named: "content.type")
        let messageID = try optionalOpaqueString(update["messageId"], named: "messageId")
        let isUserRequest = promptBlockRoleIsRequest(content["_meta"])

        return ContentChunk(
            contentType: contentType,
            messageID: messageID,
            content: try decodedContentBlock(content),
            isUserRequest: isUserRequest,
            responseChannel: responseChannel(from: content["_meta"]))
    }

    private func decodedContentBlock(
        _ content: [String: ACPJSONValue]) throws -> DecodedContentBlock
    {
        let contentType = try string(content["type"], named: "content.type")

        switch contentType {
        case "text":
            return .text(try string(content["text"], named: "content.text"))
        case "image":
            let mimeType = try boundedString(
                content["mimeType"],
                named: "content.mimeType",
                maximumBytes: AgentArtifactLimits.maximumMIMETypeBytes)
            let data = try embeddedData(content["data"], named: "content.data")
            let uri = try optionalBoundedString(
                content["uri"],
                named: "content.uri",
                maximumBytes: AgentArtifactLimits.maximumURIBytes)
            return .artifact(AgentArtifact(
                uri: uri,
                name: artifactName(uri: uri, fallback: "Image"),
                title: nil,
                descriptiveText: nil,
                mimeType: mimeType,
                declaredSize: nil,
                payload: .image(data: data, mimeType: mimeType)))
        case "audio":
            _ = try embeddedData(content["data"], named: "content.data")
            _ = try boundedString(
                content["mimeType"],
                named: "content.mimeType",
                maximumBytes: AgentArtifactLimits.maximumMIMETypeBytes)
            return .unsupported(contentType)
        case "resource_link":
            let uri = try boundedString(
                content["uri"],
                named: "content.uri",
                maximumBytes: AgentArtifactLimits.maximumURIBytes)
            return .artifact(AgentArtifact(
                uri: uri,
                name: try boundedString(
                    content["name"],
                    named: "content.name",
                    maximumBytes: AgentArtifactLimits.maximumDisplayTextBytes),
                title: try optionalBoundedString(
                    content["title"],
                    named: "content.title",
                    maximumBytes: AgentArtifactLimits.maximumDisplayTextBytes),
                descriptiveText: try optionalBoundedString(
                    content["description"],
                    named: "content.description",
                    maximumBytes: AgentArtifactLimits.maximumDisplayTextBytes),
                mimeType: try optionalBoundedString(
                    content["mimeType"],
                    named: "content.mimeType",
                    maximumBytes: AgentArtifactLimits.maximumMIMETypeBytes),
                declaredSize: try optionalUnsignedInteger(content["size"], named: "content.size"),
                payload: .linked))
        case "resource":
            return .artifact(try embeddedResource(content))
        default:
            throw malformed("content.type")
        }
    }

    private func promptBlockRoleIsRequest(_ value: ACPJSONValue?) -> Bool {
        guard case let .object(metadata) = value,
              case let .object(namespace) = metadata["ciobanu.org.voiceActivation"],
              case .string("request") = namespace["promptBlockRole"]
        else {
            return false
        }
        return true
    }

    private func responseChannel(from value: ACPJSONValue?) -> ResponseChannel? {
        guard case let .object(metadata) = value,
              case let .object(namespace) = metadata["ciobanu.org.voiceActivation"],
              case let .object(extensionValue) = namespace["responseChannel"],
              case .integer(1) = extensionValue["version"],
              case let .string(channel) = extensionValue["channel"]
        else {
            return nil
        }
        return ResponseChannel(rawValue: channel)
    }

    private func embeddedResource(_ content: [String: ACPJSONValue]) throws -> AgentArtifact {
        let resource = try object(content["resource"], named: "content.resource")
        let uri = try boundedString(
            resource["uri"],
            named: "content.resource.uri",
            maximumBytes: AgentArtifactLimits.maximumURIBytes)
        let mimeType = try optionalBoundedString(
            resource["mimeType"],
            named: "content.resource.mimeType",
            maximumBytes: AgentArtifactLimits.maximumMIMETypeBytes)
        let payload: AgentArtifactPayload

        if let text = try optionalString(resource["text"], named: "content.resource.text") {
            guard text.utf8.count <= AgentArtifactLimits.maximumEmbeddedPayloadBytes else {
                throw malformed("content.resource.text")
            }
            payload = .embeddedText(text)
        } else if resource.keys.contains("blob") {
            payload = .embeddedBlob(try embeddedData(
                resource["blob"],
                named: "content.resource.blob"))
        } else {
            throw malformed("content.resource.text or content.resource.blob")
        }

        return AgentArtifact(
            uri: uri,
            name: artifactName(uri: uri, fallback: "Resource"),
            title: nil,
            descriptiveText: nil,
            mimeType: mimeType,
            declaredSize: nil,
            payload: payload)
    }

    private func toolCall(_ update: [String: ACPJSONValue]) throws -> AgentToolCall {
        AgentToolCall(
            id: try opaqueString(update["toolCallId"], named: "toolCallId"),
            title: try string(update["title"], named: "title"),
            kind: try optionalRawValue(update["kind"], named: "kind"),
            status: try optionalRawValue(update["status"], named: "status"),
            content: try toolContent(update["content"]))
    }

    private func toolCallUpdate(_ update: [String: ACPJSONValue]) throws -> AgentToolCallUpdate {
        AgentToolCallUpdate(
            id: try opaqueString(update["toolCallId"], named: "toolCallId"),
            title: try optionalString(update["title"], named: "title"),
            kind: try optionalRawValue(update["kind"], named: "kind"),
            status: try optionalRawValue(update["status"], named: "status"),
            content: try toolContent(update["content"]))
    }

    private func toolContent(_ value: ACPJSONValue?) throws -> [AgentToolCallContent] {
        guard let value else {
            return []
        }

        return try array(value, named: "content").compactMap { wrapperValue in
            let wrapper = try object(wrapperValue, named: "tool content")
            switch try string(wrapper["type"], named: "tool content.type") {
            case "content":
                let content = try object(wrapper["content"], named: "tool content.content")
                switch try decodedContentBlock(content) {
                case let .text(text):
                    return .text(text)
                case let .artifact(artifact):
                    return .artifact(artifact)
                case .unsupported:
                    return nil
                }
            case "diff":
                _ = try string(wrapper["path"], named: "tool content.path")
                _ = try string(wrapper["newText"], named: "tool content.newText")
                return nil
            case "terminal":
                _ = try opaqueString(
                    wrapper["terminalId"],
                    named: "tool content.terminalId")
                return nil
            default:
                throw malformed("tool content.type")
            }
        }
    }

    private func plan(_ update: [String: ACPJSONValue]) throws -> [AgentPlanEntry] {
        try array(update["entries"], named: "entries").enumerated().map { index, value in
            let entry = try object(value, named: "entries[\(index)]")
            return AgentPlanEntry(
                content: try string(entry["content"], named: "entries[\(index)].content"),
                priority: try rawValue(
                    entry["priority"],
                    named: "entries[\(index)].priority"),
                status: try rawValue(
                    entry["status"],
                    named: "entries[\(index)].status"))
        }
    }

    private func availableCommandsSummary(_ update: [String: ACPJSONValue]) throws -> String {
        let commands = try array(update["availableCommands"], named: "availableCommands")
        let names = try commands.enumerated().map { index, value in
            let command = try object(value, named: "availableCommands[\(index)]")
            let name = try string(command["name"], named: "availableCommands[\(index)].name")
            _ = try string(
                command["description"],
                named: "availableCommands[\(index)].description")
            return name
        }
        let noun = names.count == 1 ? "command" : "commands"
        let listedNames = names.prefix(8).joined(separator: ", ")
        return bounded("\(names.count) \(noun) available: \(listedNames)")
    }

    private func configOptionsSummary(_ update: [String: ACPJSONValue]) throws -> String {
        let values = try array(update["configOptions"], named: "configOptions")
        let identifiers = try values.enumerated().map { index, value in
            let option = try object(value, named: "configOptions[\(index)]")
            let identifier = try string(option["id"], named: "configOptions[\(index)].id")
            _ = try string(option["name"], named: "configOptions[\(index)].name")
            let type = try string(option["type"], named: "configOptions[\(index)].type")

            switch type {
            case "select":
                _ = try string(
                    option["currentValue"],
                    named: "configOptions[\(index)].currentValue")
                let choices = try array(
                    option["options"],
                    named: "configOptions[\(index)].options")
                try validateConfigSelectOptions(choices, optionIndex: index)
            case "boolean":
                guard case .bool = option["currentValue"] else {
                    throw malformed("configOptions[\(index)].currentValue")
                }
            default:
                throw malformed("configOptions[\(index)].type")
            }

            return identifier
        }
        let noun = identifiers.count == 1 ? "option" : "options"
        let listedIdentifiers = identifiers.prefix(8).joined(separator: ", ")
        return bounded("\(identifiers.count) configuration \(noun) available: \(listedIdentifiers)")
    }

    private func validateConfigSelectOptions(
        _ choices: [ACPJSONValue],
        optionIndex: Int) throws
    {
        guard let firstChoice = choices.first else {
            return
        }
        let firstObject = try object(
            firstChoice,
            named: "configOptions[\(optionIndex)].options[0]")

        if firstObject.keys.contains("group") {
            for (groupIndex, groupValue) in choices.enumerated() {
                let group = try object(
                    groupValue,
                    named: "configOptions[\(optionIndex)].options[\(groupIndex)]")
                _ = try string(group["group"], named: "config option group")
                _ = try string(group["name"], named: "config option group name")
                let groupChoices = try array(
                    group["options"],
                    named: "config option group choices")
                try validateFlatConfigSelectOptions(groupChoices)
            }
        } else {
            try validateFlatConfigSelectOptions(choices)
        }
    }

    private func validateFlatConfigSelectOptions(_ choices: [ACPJSONValue]) throws {
        for choiceValue in choices {
            let choice = try object(choiceValue, named: "config option choice")
            _ = try string(choice["value"], named: "config option value")
            _ = try string(choice["name"], named: "config option name")
        }
    }

    private func sessionInfoSummary(_ update: [String: ACPJSONValue]) throws -> String {
        let title = try optionalString(update["title"], named: "title")
        let updatedAt = try optionalString(update["updatedAt"], named: "updatedAt")
        var parts: [String] = []

        if let title {
            parts.append("Session title: \(title)")
        } else if update.keys.contains("title") {
            parts.append("Session title cleared")
        }
        if let updatedAt {
            parts.append("updated: \(updatedAt)")
        } else if update.keys.contains("updatedAt") {
            parts.append("update time cleared")
        }

        return bounded(parts.isEmpty ? "Session information changed" : parts.joined(separator: "; "))
    }

    private func usageSummary(_ update: [String: ACPJSONValue]) throws -> String {
        let used = try unsignedInteger(update["used"], named: "used")
        let size = try unsignedInteger(update["size"], named: "size")
        var summary = "Context usage: \(used) of \(size) tokens"

        if let costValue = update["cost"], costValue != .null {
            let cost = try object(costValue, named: "cost")
            let amount = try number(cost["amount"], named: "cost.amount")
            let currency = try string(cost["currency"], named: "cost.currency")
            summary += "; cost: \(amount) \(currency)"
        }

        return bounded(summary)
    }

    func object(
        _ value: ACPJSONValue?,
        named name: String) throws -> [String: ACPJSONValue]
    {
        guard case let .object(object) = value else {
            throw malformed(name)
        }
        return object
    }

    private func array(_ value: ACPJSONValue?, named name: String) throws -> [ACPJSONValue] {
        guard case let .array(array) = value else {
            throw malformed(name)
        }
        return array
    }

    func string(_ value: ACPJSONValue?, named name: String) throws -> String {
        guard case let .string(string) = value else {
            throw malformed(name)
        }
        return string
    }

    private func optionalString(_ value: ACPJSONValue?, named name: String) throws -> String? {
        guard let value, value != .null else {
            return nil
        }
        return try string(value, named: name)
    }

    private func boundedString(
        _ value: ACPJSONValue?,
        named name: String,
        maximumBytes: Int) throws -> String
    {
        let result = try string(value, named: name)
        guard result.utf8.count <= maximumBytes else {
            throw malformed(name)
        }
        return result
    }

    private func optionalBoundedString(
        _ value: ACPJSONValue?,
        named name: String,
        maximumBytes: Int) throws -> String?
    {
        guard let value, value != .null else {
            return nil
        }
        return try boundedString(value, named: name, maximumBytes: maximumBytes)
    }

    private func embeddedData(_ value: ACPJSONValue?, named name: String) throws -> Data {
        let encoded = try string(value, named: name)
        guard let data = Data(base64Encoded: encoded),
              data.count <= AgentArtifactLimits.maximumEmbeddedPayloadBytes
        else {
            throw malformed(name)
        }
        return data
    }

    private func artifactName(uri: String?, fallback: String) -> String {
        guard let uri,
              let candidate = URL(string: uri)?.lastPathComponent.removingPercentEncoding,
              !candidate.isEmpty
        else {
            return fallback
        }
        return candidate
    }

    private func opaqueString(_ value: ACPJSONValue?, named name: String) throws -> String {
        let identifier = try string(value, named: name)
        guard !identifier.isEmpty,
              identifier.utf8.count <= Self.maximumOpaqueIdentifierBytes
        else {
            throw malformed(name)
        }
        return identifier
    }

    private func optionalOpaqueString(
        _ value: ACPJSONValue?,
        named name: String) throws -> String?
    {
        guard let value, value != .null else {
            return nil
        }
        return try opaqueString(value, named: name)
    }

    private func rawValue<Value>(
        _ value: ACPJSONValue?,
        named name: String) throws -> Value
    where Value: RawRepresentable, Value.RawValue == String {
        let encoded = try string(value, named: name)
        guard let decoded = Value(rawValue: encoded) else {
            throw malformed(name)
        }
        return decoded
    }

    private func optionalRawValue<Value>(
        _ value: ACPJSONValue?,
        named name: String) throws -> Value?
    where Value: RawRepresentable, Value.RawValue == String {
        guard let value, value != .null else {
            return nil
        }
        return try rawValue(value, named: name)
    }

    func unsignedInteger(_ value: ACPJSONValue?, named name: String) throws -> UInt64 {
        switch value {
        case let .integer(integer) where integer >= 0:
            return UInt64(integer)
        case let .unsignedInteger(integer):
            return integer
        default:
            throw malformed(name)
        }
    }

    private func optionalUnsignedInteger(
        _ value: ACPJSONValue?,
        named name: String) throws -> UInt64?
    {
        guard let value, value != .null else {
            return nil
        }
        return try unsignedInteger(value, named: name)
    }

    private func number(_ value: ACPJSONValue?, named name: String) throws -> String {
        switch value {
        case let .integer(number):
            return String(number)
        case let .unsignedInteger(number):
            return String(number)
        case let .number(number):
            return String(number)
        default:
            throw malformed(name)
        }
    }

    func malformed(_ field: String) -> EventError {
        .malformedSessionUpdate("Invalid or missing \(field).")
    }

    private func bounded(
        _ value: String,
        maximumBytes: Int = Self.maximumSummaryBytes) -> String
    {
        guard value.utf8.count > maximumBytes else {
            return value
        }

        var result = ""
        var byteCount = 0
        for character in value {
            let characterBytes = String(character).utf8.count
            guard byteCount + characterBytes <= maximumBytes else {
                break
            }
            result.append(character)
            byteCount += characterBytes
        }
        return result
    }
}

private struct ContentChunk: Sendable {
    let contentType: String
    let messageID: String?
    let content: DecodedContentBlock
    let isUserRequest: Bool
    let responseChannel: ResponseChannel?
}

private enum ResponseChannel: String, Sendable {
    case spoken
    case display
}

private enum DecodedContentBlock: Sendable {
    case text(String)
    case artifact(AgentArtifact)
    case unsupported(String)
}
