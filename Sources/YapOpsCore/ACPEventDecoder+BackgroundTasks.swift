// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

extension ACPEventDecoder {
    func backgroundTaskUpdate(
        discriminator: String,
        update: [String: ACPJSONValue]
    ) throws -> AgentBackgroundTaskUpdate {
        let id = AgentBackgroundTaskID(rawValue: try boundedRequiredString(
            update["asyncTaskId"], named: "asyncTaskId",
            maximumBytes: AgentBackgroundTaskLimits.maximumIdentifierBytes,
            nonempty: true))
        switch discriminator {
        case "async_task_spawned":
            return .spawned(
                id: id,
                name: try boundedRequiredString(
                    update["name"], named: "name",
                    maximumBytes: AgentBackgroundTaskLimits.maximumShortTextBytes),
                taskType: try boundedRequiredString(
                    update["taskType"], named: "taskType",
                    maximumBytes: AgentBackgroundTaskLimits.maximumShortTextBytes),
                description: try boundedRequiredString(
                    update["description"], named: "description",
                    maximumBytes: AgentBackgroundTaskLimits.maximumDetailBytes),
                showInTranscript: try bool(
                    update["showInTranscript"], named: "showInTranscript"),
                canStop: try bool(update["canStop"], named: "canStop"),
                outputFilePath: try droppingOversizedOptionalString(
                    update["outputFilePath"], named: "outputFilePath",
                    maximumBytes: AgentBackgroundTaskLimits.maximumDetailBytes),
                toolCallID: try droppingOversizedOptionalString(
                    update["toolCallId"], named: "toolCallId",
                    maximumBytes: AgentBackgroundTaskLimits.maximumIdentifierBytes))
        case "async_task_progress":
            return .progress(
                id: id,
                description: try droppingOversizedOptionalString(
                    update["description"], named: "description",
                    maximumBytes: AgentBackgroundTaskLimits.maximumDetailBytes),
                summary: try droppingOversizedOptionalString(
                    update["summary"], named: "summary",
                    maximumBytes: AgentBackgroundTaskLimits.maximumDetailBytes),
                lastToolName: try droppingOversizedOptionalString(
                    update["lastToolName"], named: "lastToolName",
                    maximumBytes: AgentBackgroundTaskLimits.maximumShortTextBytes),
                usage: try backgroundTaskUsage(update["usage"]),
                outputFilePath: try droppingOversizedOptionalString(
                    update["outputFilePath"], named: "outputFilePath",
                    maximumBytes: AgentBackgroundTaskLimits.maximumDetailBytes),
                toolCallID: try droppingOversizedOptionalString(
                    update["toolCallId"], named: "toolCallId",
                    maximumBytes: AgentBackgroundTaskLimits.maximumIdentifierBytes))
        case "async_task_state_update":
            return .stateChanged(
                id: id,
                state: try backgroundTaskState(update["state"]),
                summary: try droppingOversizedOptionalString(
                    update["summary"], named: "summary",
                    maximumBytes: AgentBackgroundTaskLimits.maximumDetailBytes),
                outputFilePath: try droppingOversizedOptionalString(
                    update["outputFilePath"], named: "outputFilePath",
                    maximumBytes: AgentBackgroundTaskLimits.maximumDetailBytes),
                toolCallID: try droppingOversizedOptionalString(
                    update["toolCallId"], named: "toolCallId",
                    maximumBytes: AgentBackgroundTaskLimits.maximumIdentifierBytes))
        default:
            throw malformed("async task discriminator")
        }
    }

    private func backgroundTaskState(
        _ value: ACPJSONValue?
    ) throws -> AgentBackgroundTaskState {
        switch try string(value, named: "state") {
        case "pending", "running": .running
        case "paused": .paused
        case "completed": .completed
        case "failed": .failed
        case "killed", "cancelled", "stopped": .stopped
        default: throw malformed("state")
        }
    }

    private func backgroundTaskUsage(
        _ value: ACPJSONValue?
    ) throws -> AgentBackgroundTaskUsage? {
        guard let value, value != .null else { return nil }
        let usage = try object(value, named: "usage")
        return AgentBackgroundTaskUsage(
            totalTokens: try optionalClampedNonnegativeInteger(
                usage["totalTokens"], named: "usage.totalTokens"),
            toolUses: try optionalClampedNonnegativeInteger(
                usage["toolUses"], named: "usage.toolUses"),
            durationMilliseconds: try optionalClampedNonnegativeInteger(
                usage["durationMs"], named: "usage.durationMs"))
    }

    private func optionalClampedNonnegativeInteger(
        _ value: ACPJSONValue?,
        named name: String
    ) throws -> Int? {
        guard let value, value != .null else { return nil }
        let unsigned = try unsignedInteger(value, named: name)
        return unsigned > UInt64(Int.max) ? Int.max : Int(unsigned)
    }

    private func boundedRequiredString(
        _ value: ACPJSONValue?,
        named name: String,
        maximumBytes: Int,
        nonempty: Bool = false
    ) throws -> String {
        let value = try string(value, named: name)
        guard (!nonempty || !value.isEmpty), value.utf8.count <= maximumBytes else {
            throw malformed(name)
        }
        return value
    }

    private func droppingOversizedOptionalString(
        _ value: ACPJSONValue?,
        named name: String,
        maximumBytes: Int
    ) throws -> String? {
        guard let value, value != .null else { return nil }
        let string = try string(value, named: name)
        return string.utf8.count <= maximumBytes ? string : nil
    }

    private func bool(_ value: ACPJSONValue?, named name: String) throws -> Bool {
        guard case let .bool(value) = value else { throw malformed(name) }
        return value
    }
}
