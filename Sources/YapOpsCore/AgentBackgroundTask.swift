// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

/// An opaque provider-owned task identifier scoped to one ACP session.
public struct AgentBackgroundTaskID: Hashable, Sendable {
    /// The exact opaque identifier supplied by the provider.
    public let rawValue: String

    /// Creates an identifier whose wire validity is checked before use.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// The normalized lifecycle state of a provider-owned background task.
public enum AgentBackgroundTaskState: String, Equatable, Sendable {
    /// The task is currently running.
    case running
    /// The task is paused but remains active.
    case paused
    /// The task completed successfully.
    case completed
    /// The task terminated unsuccessfully.
    case failed
    /// The provider reported that the task stopped.
    case stopped
}

/// Bounded cumulative usage reported for a provider-owned background task.
public struct AgentBackgroundTaskUsage: Equatable, Sendable {
    /// Total tokens used, when supplied.
    public let totalTokens: Int?
    /// Total tool invocations, when supplied.
    public let toolUses: Int?
    /// Total elapsed provider time in milliseconds, when supplied.
    public let durationMilliseconds: Int?

    /// Creates a usage snapshot from nonnegative, bounded counters.
    public init(totalTokens: Int?, toolUses: Int?, durationMilliseconds: Int?) {
        self.totalTokens = totalTokens
        self.toolUses = toolUses
        self.durationMilliseconds = durationMilliseconds
    }
}

/// A typed lifecycle update from the pinned Claude Agent ACP AIR extension.
public enum AgentBackgroundTaskUpdate: Equatable, Sendable {
    /// Announces a provider-owned background task.
    case spawned(
        id: AgentBackgroundTaskID,
        name: String,
        taskType: String,
        description: String,
        showInTranscript: Bool,
        canStop: Bool,
        outputFilePath: String?,
        toolCallID: String?)
    /// Reports nonterminal progress for an existing task.
    case progress(
        id: AgentBackgroundTaskID,
        description: String?,
        summary: String?,
        lastToolName: String?,
        usage: AgentBackgroundTaskUsage?,
        outputFilePath: String?,
        toolCallID: String?)
    /// Reports a normalized lifecycle-state change.
    case stateChanged(
        id: AgentBackgroundTaskID,
        state: AgentBackgroundTaskState,
        summary: String?,
        outputFilePath: String?,
        toolCallID: String?)
}

enum AgentBackgroundTaskLimits {
    static let maximumIdentifierBytes = 256
    static let maximumShortTextBytes = 256
    static let maximumDetailBytes = 4 * 1_024
    static let invalidUpdate = AgentRunEvent.unknown(
        discriminator: "async_task_update",
        summary: "Invalid ACP async task update.")
}
