// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

/// A single-use gate that linearizes whether an agent run may begin side effects.
///
/// The owner invalidates a pending admission when its input, run, or generation
/// retires. The runner claims it as its first operation. Once claimed, later
/// invalidation is handled by ordinary active-run cancellation.
public final class AgentRunAdmission: @unchecked Sendable {
    private enum State {
        case standalonePending
        case unbound(inputID: UUID)
        case pending(inputID: UUID, runID: UUID, executionGeneration: Int)
        case claimed
        case invalidated
    }

    // The lock protects coordinator binding and the single admission outcome across actors.
    private let lock = NSLock()
    private var state: State

    /// Creates one pending, single-use run admission.
    public init() {
        state = .standalonePending
    }

    init(inputID: UUID) {
        state = .unbound(inputID: inputID)
    }

    func bind(inputID: UUID, runID: UUID, executionGeneration: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case .unbound(let expectedInputID) = state,
              expectedInputID == inputID
        else { return false }
        state = .pending(
            inputID: inputID,
            runID: runID,
            executionGeneration: executionGeneration)
        return true
    }

    /// Atomically claims this admission before the runner performs any side effect.
    ///
    /// - Returns: `true` only for the first claim while admission is pending.
    @discardableResult
    public func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .standalonePending, .pending:
            break
        case .unbound, .claimed, .invalidated:
            return false
        }
        state = .claimed
        return true
    }

    /// Atomically invalidates this admission if the runner has not claimed it.
    ///
    /// - Returns: `true` when invalidation won the race, or `false` after a
    ///   claim or earlier invalidation already established the outcome.
    @discardableResult
    public func invalidate() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .standalonePending, .unbound, .pending:
            break
        case .claimed, .invalidated:
            return false
        }
        state = .invalidated
        return true
    }
}

/// The ACP stop reason that completed an agent turn.
public enum AgentStopReason: String, Codable, Equatable, Sendable {
    /// The agent deliberately finished the turn.
    case endTurn = "end_turn"
    /// The model reached its token limit.
    case maxTokens = "max_tokens"
    /// The harness reached its per-turn request limit.
    case maxTurnRequests = "max_turn_requests"
    /// The agent refused the request.
    case refusal
    /// The local user cancelled the turn.
    case cancelled
}

/// The terminal result of one agent turn.
public struct AgentRunResult: Equatable, Sendable {
    /// The reason the harness reports for ending the turn.
    public let stopReason: AgentStopReason

    /// Creates an agent result from its terminal stop reason.
    ///
    /// - Parameter stopReason: The reason the turn ended.
    public init(stopReason: AgentStopReason) {
        self.stopReason = stopReason
    }
}

/// Runs ACP turns and manages their cached conversation sessions.
public protocol AgentHarnessRunning: Sendable {
    /// Runs one prompt in the profile's reusable conversation session.
    ///
    /// - Parameters:
    ///   - admission: The single-use gate claimed before any runner side effect.
    ///   - profileID: The wake profile that owns the cached session.
    ///   - configuration: The harness launch and permission configuration.
    ///   - prompt: The typed user request and its optional captured Mac context.
    ///   - onEvent: An asynchronous sink for ordered streaming events.
    /// - Returns: The turn's terminal stop reason.
    /// - Throws: A transport, protocol, launch, or cancellation error.
    func run(
        admission: AgentRunAdmission,
        profileID: UUID,
        configuration: AgentHarnessConfiguration,
        prompt: AgentPrompt,
        onEvent: @escaping @Sendable (AgentRunEvent) async -> Void
    ) async throws -> AgentRunResult

    /// Answers one pending permission request for the active turn.
    ///
    /// - Parameters:
    ///   - turnToken: The turn identity that owns the request.
    ///   - requestID: The ACP request identifier.
    ///   - optionID: The chosen harness option, or `nil` to cancel the request.
    func resolvePermission(
        turnToken: AgentTurnToken,
        requestID: ACPRequestID,
        optionID: String?) async
    /// Cancels the active turn without discarding unrelated cached sessions.
    func cancel() async
    /// Discards cached sessions belonging to the supplied profiles.
    ///
    /// - Parameter profileIDs: Profile identities whose sessions are no longer valid.
    func reset(profileIDs: Set<UUID>) async
    /// Cancels active work and closes every cached harness process.
    func shutdown() async
}

extension AgentHarnessRunning {
    /// Runs one independently admitted prompt outside coordinator ownership.
    ///
    /// This convenience overload creates a fresh single-use admission and is
    /// intended for direct runner clients and tests.
    public func run(
        profileID: UUID,
        configuration: AgentHarnessConfiguration,
        prompt: AgentPrompt,
        onEvent: @escaping @Sendable (AgentRunEvent) async -> Void
    ) async throws -> AgentRunResult {
        try await run(
            admission: AgentRunAdmission(),
            profileID: profileID,
            configuration: configuration,
            prompt: prompt,
            onEvent: onEvent)
    }
}
