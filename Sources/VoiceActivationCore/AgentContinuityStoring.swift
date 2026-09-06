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
    private var bookmarks: [UUID: AgentSessionBookmark] = [:]
    private var work: [AgentInterruptedWorkKey: AgentInterruptedWorkMarker] = [:]
    private var accessOrdinal: UInt64 = 0

    /// Creates an empty identifier-only store.
    public init() {}

    /// Returns and touches the bookmark owned by one profile.
    public func bookmark(for profileID: UUID) async throws -> AgentSessionBookmark? {
        guard let bookmark = bookmarks[profileID] else { return nil }
        advanceOrdinalIfNeeded()
        accessOrdinal += 1
        let accessed = AgentSessionBookmark(
            profileID: bookmark.profileID,
            sessionID: bookmark.sessionID,
            providerFingerprint: bookmark.providerFingerprint,
            lastAccessOrdinal: accessOrdinal)
        bookmarks[profileID] = accessed
        return accessed
    }

    /// Replaces a profile bookmark and assigns its next local access ordinal.
    public func save(bookmark: AgentSessionBookmark) async throws {
        advanceOrdinalIfNeeded()
        accessOrdinal += 1
        bookmarks[bookmark.profileID] = AgentSessionBookmark(
            profileID: bookmark.profileID,
            sessionID: bookmark.sessionID,
            providerFingerprint: bookmark.providerFingerprint,
            lastAccessOrdinal: accessOrdinal)
    }

    /// Removes all identifier-only records owned by the specified profiles.
    public func remove(profileIDs: Set<UUID>) async throws {
        bookmarks = bookmarks.filter { !profileIDs.contains($0.key) }
        work = work.filter { !profileIDs.contains($0.key.profileID) }
    }

    /// Replaces one exact occurrence with active identifier-only metadata.
    public func markWorkActive(_ marker: AgentInterruptedWorkMarker) async throws {
        work[marker.key] = AgentInterruptedWorkMarker(
            key: marker.key,
            turnID: marker.turnID,
            providerTaskID: marker.providerTaskID,
            state: .active)
    }

    /// Clears only the supplied exact occurrence key.
    public func clearWork(_ key: AgentInterruptedWorkKey) async throws {
        work[key] = nil
    }

    /// Converts every active marker to interrupted and returns the resulting markers.
    public func reconcileInterruptedWork() async throws -> [AgentInterruptedWorkMarker] {
        for (key, marker) in work where marker.state == .active {
            work[key] = AgentInterruptedWorkMarker(
                key: marker.key,
                turnID: marker.turnID,
                providerTaskID: marker.providerTaskID,
                state: .interruptedByProcessExit)
        }
        return work.values.sorted(by: Self.markerOrder)
    }

    /// Removes exact acknowledged keys only when their state is interrupted.
    public func acknowledgeInterruptedWork(_ keys: Set<AgentInterruptedWorkKey>) async throws {
        for key in keys where work[key]?.state == .interruptedByProcessExit {
            work[key] = nil
        }
    }

    private func advanceOrdinalIfNeeded() {
        guard accessOrdinal == .max else { return }
        let ordered = bookmarks.values.sorted {
            if $0.lastAccessOrdinal != $1.lastAccessOrdinal {
                return $0.lastAccessOrdinal < $1.lastAccessOrdinal
            }
            return $0.profileID.uuidString < $1.profileID.uuidString
        }
        bookmarks.removeAll(keepingCapacity: true)
        for (offset, bookmark) in ordered.enumerated() {
            bookmarks[bookmark.profileID] = AgentSessionBookmark(
                profileID: bookmark.profileID,
                sessionID: bookmark.sessionID,
                providerFingerprint: bookmark.providerFingerprint,
                lastAccessOrdinal: UInt64(offset + 1))
        }
        accessOrdinal = UInt64(ordered.count)
    }

    private static func markerOrder(
        _ lhs: AgentInterruptedWorkMarker,
        _ rhs: AgentInterruptedWorkMarker
    ) -> Bool {
        if lhs.key.profileID != rhs.key.profileID {
            return lhs.key.profileID.uuidString < rhs.key.profileID.uuidString
        }
        return lhs.key.occurrenceID.uuidString < rhs.key.occurrenceID.uuidString
    }
}
