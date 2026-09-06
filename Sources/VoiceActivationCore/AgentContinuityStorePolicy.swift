// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

/// Content-free failures raised by the shared continuity storage policy.
public enum AgentContinuityStoreError: Error, Equatable, Sendable {
    /// The envelope does not use the supported schema version.
    case invalidSchema
    /// A bookmark or work-marker collection exceeds its bounded record count.
    case recordLimitExceeded
    /// A supposedly unique profile or exact work key occurs more than once.
    case duplicateRecord
    /// An opaque session, turn, or task identifier is empty or oversized.
    case invalidIdentifier
    /// A provider fingerprint is not exactly 64 lowercase hexadecimal characters.
    case invalidFingerprint
}

/// Shared structural and mutation policy for identifier-only continuity stores.
///
/// Both durable and in-memory adapters delegate here so validation, bounds,
/// replacement, access ordinals, and exact-key lifecycle semantics cannot drift.
public enum AgentContinuityStorePolicy {
    /// The only continuity envelope schema currently accepted.
    public static let schemaVersion = 1
    /// The maximum unique bookmarks and maximum unique work markers retained.
    public static let maximumRecords = 64
    /// The ACP-wide UTF-8 byte bound for every persisted opaque identifier.
    public static let maximumIdentifierBytes = ACPEventDecoder.maximumOpaqueIdentifierBytes
    /// The exact lowercase hexadecimal character count of a SHA-256 fingerprint.
    public static let fingerprintCharacterCount = 64

    /// Creates a valid empty continuity envelope.
    public static func emptyEnvelope() -> AgentContinuityEnvelope {
        AgentContinuityEnvelope(
            schemaVersion: schemaVersion,
            bookmarks: [],
            interruptedWork: [])
    }

    /// Validates schema, uniqueness, record counts, identifiers, and fingerprints.
    /// - Parameter envelope: The complete identifier-only state to validate.
    /// - Throws: A content-free ``AgentContinuityStoreError``.
    public static func validate(_ envelope: AgentContinuityEnvelope) throws {
        guard envelope.schemaVersion == schemaVersion else {
            throw AgentContinuityStoreError.invalidSchema
        }
        guard envelope.bookmarks.count <= maximumRecords,
            envelope.interruptedWork.count <= maximumRecords
        else { throw AgentContinuityStoreError.recordLimitExceeded }
        guard Set(envelope.bookmarks.map(\.profileID)).count == envelope.bookmarks.count,
            Set(envelope.interruptedWork.map(\.key)).count == envelope.interruptedWork.count
        else { throw AgentContinuityStoreError.duplicateRecord }
        for bookmark in envelope.bookmarks { try validate(bookmark) }
        for marker in envelope.interruptedWork { try validate(marker) }
    }

    /// Returns and touches one profile bookmark using a managed access ordinal.
    /// - Parameters:
    ///   - profileID: The exact profile owner to retrieve.
    ///   - envelope: The complete state, updated atomically when the bookmark exists.
    /// - Returns: The touched bookmark, or `nil` when the profile has none.
    /// - Throws: A content-free ``AgentContinuityStoreError`` for invalid state.
    public static func bookmark(
        for profileID: UUID,
        in envelope: inout AgentContinuityEnvelope
    ) throws -> AgentSessionBookmark? {
        try validate(envelope)
        guard let index = envelope.bookmarks.firstIndex(where: { $0.profileID == profileID }) else {
            return nil
        }
        var candidate = envelope
        let ordinal = nextAccessOrdinal(bookmarks: &candidate.bookmarks)
        let existing = candidate.bookmarks[index]
        let accessed = AgentSessionBookmark(
            profileID: existing.profileID,
            sessionID: existing.sessionID,
            providerFingerprint: existing.providerFingerprint,
            lastAccessOrdinal: ordinal)
        candidate.bookmarks[index] = accessed
        try validate(candidate)
        envelope = candidate
        return accessed
    }

    /// Replaces a profile bookmark, manages its ordinal, and evicts one stable LRU.
    /// - Parameters:
    ///   - bookmark: The untrusted identifier-only bookmark to save.
    ///   - envelope: The complete state, replaced only after validation succeeds.
    /// - Throws: A content-free ``AgentContinuityStoreError``.
    public static func save(
        _ bookmark: AgentSessionBookmark,
        in envelope: inout AgentContinuityEnvelope
    ) throws {
        try validate(envelope)
        try validate(bookmark)
        var candidate = envelope
        let ordinal = nextAccessOrdinal(bookmarks: &candidate.bookmarks)
        candidate.bookmarks.removeAll { $0.profileID == bookmark.profileID }
        candidate.bookmarks.append(AgentSessionBookmark(
            profileID: bookmark.profileID,
            sessionID: bookmark.sessionID,
            providerFingerprint: bookmark.providerFingerprint,
            lastAccessOrdinal: ordinal))
        if candidate.bookmarks.count > maximumRecords {
            candidate.bookmarks.remove(at: leastRecentlyUsedIndex(in: candidate.bookmarks))
        }
        try validate(candidate)
        envelope = candidate
    }

    /// Removes records owned by the specified profiles only.
    /// - Parameters:
    ///   - profileIDs: The exact profile owners to remove.
    ///   - envelope: The complete state, replaced only after validation succeeds.
    /// - Returns: Whether any record was removed.
    /// - Throws: A content-free ``AgentContinuityStoreError`` for invalid state.
    @discardableResult
    public static func remove(
        profileIDs: Set<UUID>,
        in envelope: inout AgentContinuityEnvelope
    ) throws -> Bool {
        try validate(envelope)
        var candidate = envelope
        candidate.bookmarks.removeAll { profileIDs.contains($0.profileID) }
        candidate.interruptedWork.removeAll { profileIDs.contains($0.key.profileID) }
        let changed = candidate != envelope
        envelope = candidate
        return changed
    }

    /// Replaces one exact work key with validated active identifier metadata.
    /// - Parameters:
    ///   - marker: The untrusted marker whose lifecycle state is normalized to active.
    ///   - envelope: The complete state, replaced only after validation succeeds.
    /// - Throws: A content-free ``AgentContinuityStoreError``.
    public static func markWorkActive(
        _ marker: AgentInterruptedWorkMarker,
        in envelope: inout AgentContinuityEnvelope
    ) throws {
        try validate(envelope)
        try validate(marker)
        var candidate = envelope
        candidate.interruptedWork.removeAll { $0.key == marker.key }
        candidate.interruptedWork.append(AgentInterruptedWorkMarker(
            key: marker.key,
            turnID: marker.turnID,
            providerTaskID: marker.providerTaskID,
            state: .active))
        try validate(candidate)
        envelope = candidate
    }

    /// Clears one exact work occurrence without matching provider identifiers loosely.
    /// - Parameters:
    ///   - key: The complete local occurrence key to clear.
    ///   - envelope: The complete state, replaced only after validation succeeds.
    /// - Returns: Whether the exact key existed.
    /// - Throws: A content-free ``AgentContinuityStoreError`` for invalid state.
    @discardableResult
    public static func clearWork(
        _ key: AgentInterruptedWorkKey,
        in envelope: inout AgentContinuityEnvelope
    ) throws -> Bool {
        try validate(envelope)
        var candidate = envelope
        candidate.interruptedWork.removeAll { $0.key == key }
        let changed = candidate != envelope
        envelope = candidate
        return changed
    }

    /// Converts all active work to interrupted state and returns every interrupted marker.
    /// - Parameter envelope: The complete state, atomically reconciled after validation.
    /// - Returns: All resulting markers in interrupted state, preserving storage order.
    /// - Throws: A content-free ``AgentContinuityStoreError`` for invalid state.
    public static func reconcileInterruptedWork(
        in envelope: inout AgentContinuityEnvelope
    ) throws -> [AgentInterruptedWorkMarker] {
        try validate(envelope)
        var candidate = envelope
        candidate.interruptedWork = candidate.interruptedWork.map { marker in
            guard marker.state == .active else { return marker }
            return AgentInterruptedWorkMarker(
                key: marker.key,
                turnID: marker.turnID,
                providerTaskID: marker.providerTaskID,
                state: .interruptedByProcessExit)
        }
        envelope = candidate
        return candidate.interruptedWork.filter { $0.state == .interruptedByProcessExit }
    }

    /// Removes only exact acknowledged keys whose current state is interrupted.
    /// - Parameters:
    ///   - keys: Complete local occurrence keys accepted by the caller.
    ///   - envelope: The complete state, replaced only after validation succeeds.
    /// - Returns: Whether an interrupted marker was removed.
    /// - Throws: A content-free ``AgentContinuityStoreError`` for invalid state.
    @discardableResult
    public static func acknowledgeInterruptedWork(
        _ keys: Set<AgentInterruptedWorkKey>,
        in envelope: inout AgentContinuityEnvelope
    ) throws -> Bool {
        try validate(envelope)
        var candidate = envelope
        candidate.interruptedWork.removeAll {
            $0.state == .interruptedByProcessExit && keys.contains($0.key)
        }
        let changed = candidate != envelope
        envelope = candidate
        return changed
    }

    private static func validate(_ bookmark: AgentSessionBookmark) throws {
        try validateIdentifier(bookmark.sessionID)
        guard bookmark.providerFingerprint.utf8.count == fingerprintCharacterCount,
            bookmark.providerFingerprint.utf8.allSatisfy({
                (48...57).contains($0) || (97...102).contains($0)
            })
        else { throw AgentContinuityStoreError.invalidFingerprint }
    }

    private static func validate(_ marker: AgentInterruptedWorkMarker) throws {
        try validateIdentifier(marker.key.sessionID)
        if let turnID = marker.turnID { try validateIdentifier(turnID) }
        if let providerTaskID = marker.providerTaskID { try validateIdentifier(providerTaskID) }
    }

    private static func validateIdentifier(_ identifier: String) throws {
        guard !identifier.isEmpty, identifier.utf8.count <= maximumIdentifierBytes else {
            throw AgentContinuityStoreError.invalidIdentifier
        }
    }

    private static func nextAccessOrdinal(bookmarks: inout [AgentSessionBookmark]) -> UInt64 {
        let maximum = bookmarks.map(\.lastAccessOrdinal).max() ?? 0
        guard maximum == .max else { return maximum + 1 }
        let order = bookmarks.indices.sorted {
            let lhs = bookmarks[$0]
            let rhs = bookmarks[$1]
            if lhs.lastAccessOrdinal != rhs.lastAccessOrdinal {
                return lhs.lastAccessOrdinal < rhs.lastAccessOrdinal
            }
            return lhs.profileID.uuidString < rhs.profileID.uuidString
        }
        for (offset, index) in order.enumerated() {
            let bookmark = bookmarks[index]
            bookmarks[index] = AgentSessionBookmark(
                profileID: bookmark.profileID,
                sessionID: bookmark.sessionID,
                providerFingerprint: bookmark.providerFingerprint,
                lastAccessOrdinal: UInt64(offset + 1))
        }
        return UInt64(bookmarks.count + 1)
    }

    private static func leastRecentlyUsedIndex(in bookmarks: [AgentSessionBookmark]) -> Int {
        bookmarks.indices.min {
            let lhs = bookmarks[$0]
            let rhs = bookmarks[$1]
            if lhs.lastAccessOrdinal != rhs.lastAccessOrdinal {
                return lhs.lastAccessOrdinal < rhs.lastAccessOrdinal
            }
            return lhs.profileID.uuidString < rhs.profileID.uuidString
        } ?? 0
    }
}
