// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

/// Stores bounded, identifier-only ACP session continuity state.
public protocol AgentContinuityStoring: Sendable {
    /// Returns the bookmark owned by one profile, recording it as recently accessed.
    func bookmark(for profileID: UUID) async throws -> AgentSessionBookmark?
    /// Replaces the bookmark owned by its profile.
    func save(bookmark: AgentSessionBookmark) async throws
    /// Removes bookmarks and work markers owned by the specified profiles.
    func remove(profileIDs: Set<UUID>) async throws
    /// Stores one exact local work occurrence as active.
    func markWorkActive(_ marker: AgentInterruptedWorkMarker) async throws
    /// Removes one exact local work occurrence regardless of its state.
    func clearWork(_ key: AgentInterruptedWorkKey) async throws
    /// Converts active occurrences to interrupted state and returns all interrupted work.
    func reconcileInterruptedWork() async throws -> [AgentInterruptedWorkMarker]
    /// Removes only exact matching occurrences already marked as interrupted.
    func acknowledgeInterruptedWork(_ keys: Set<AgentInterruptedWorkKey>) async throws
}

/// An actor-isolated continuity store for tests and non-durable default composition.
public actor InMemoryAgentContinuityStore: AgentContinuityStoring {
    private var envelope: AgentContinuityEnvelope

    /// Creates an empty identifier-only store.
    public init() {
        envelope = AgentContinuityStorePolicy.emptyEnvelope()
    }

    /// Returns and touches the bookmark owned by one profile.
    public func bookmark(for profileID: UUID) async throws -> AgentSessionBookmark? {
        try AgentContinuityStorePolicy.bookmark(for: profileID, in: &envelope)
    }

    /// Replaces a profile bookmark and assigns its next local access ordinal.
    public func save(bookmark: AgentSessionBookmark) async throws {
        try AgentContinuityStorePolicy.save(bookmark, in: &envelope)
    }

    /// Removes all identifier-only records owned by the specified profiles.
    public func remove(profileIDs: Set<UUID>) async throws {
        try AgentContinuityStorePolicy.remove(profileIDs: profileIDs, in: &envelope)
    }

    /// Replaces one exact occurrence with active identifier-only metadata.
    public func markWorkActive(_ marker: AgentInterruptedWorkMarker) async throws {
        try AgentContinuityStorePolicy.markWorkActive(marker, in: &envelope)
    }

    /// Clears only the supplied exact occurrence key.
    public func clearWork(_ key: AgentInterruptedWorkKey) async throws {
        try AgentContinuityStorePolicy.clearWork(key, in: &envelope)
    }

    /// Converts every active marker to interrupted and returns the resulting markers.
    public func reconcileInterruptedWork() async throws -> [AgentInterruptedWorkMarker] {
        try AgentContinuityStorePolicy.reconcileInterruptedWork(in: &envelope)
    }

    /// Removes exact acknowledged keys only when their state is interrupted.
    public func acknowledgeInterruptedWork(_ keys: Set<AgentInterruptedWorkKey>) async throws {
        try AgentContinuityStorePolicy.acknowledgeInterruptedWork(keys, in: &envelope)
    }
}
