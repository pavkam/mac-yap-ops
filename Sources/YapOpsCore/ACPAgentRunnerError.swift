// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

/// Local lifecycle failures produced while managing reusable ACP sessions.
public enum ACPAgentRunnerError: Error, Equatable, LocalizedError, Sendable {
    /// The user cancelled the active turn.
    case cancelled
    /// The runner has permanently shut down.
    case shutDown
    /// A second prompt arrived before the active prompt completed.
    case turnAlreadyActive
    /// Required control events exceeded the bounded delivery queue.
    case eventDeliveryOverflow
    /// ACP initialization did not complete before the startup deadline.
    case startupTimedOut
    /// All cached sessions are pinned by active provider-owned tasks.
    case sessionCapacityReached
    /// A fresh conversation would interrupt tasks owned by the previous session.
    case backgroundTasksActive
    /// The requested provider-owned task is stale, stopped, or not stoppable.
    case backgroundTaskUnavailable

    /// A user-presentable explanation of the runner failure.
    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "The agent run was cancelled."
        case .shutDown:
            "The agent runner has shut down."
        case .turnAlreadyActive:
            "Another agent prompt is already active."
        case .eventDeliveryOverflow:
            "The agent produced more control events than can be delivered safely."
        case .startupTimedOut:
            "The agent did not finish starting within 12 seconds."
        case .sessionCapacityReached:
            "Four agent sessions already have active background tasks."
        case .backgroundTasksActive:
            "Finish or stop this profile’s background tasks before starting a new conversation."
        case .backgroundTaskUnavailable:
            "The background task is no longer available to stop."
        }
    }
}

