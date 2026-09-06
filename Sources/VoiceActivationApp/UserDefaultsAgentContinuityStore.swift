// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import VoiceActivationCore

actor UserDefaultsAgentContinuityStore: AgentContinuityStoring {
    static let key = "voiceActivation.agentContinuity.v1"
    static let maximumRecords = 64
    static let maximumEncodedBytes = 512 * 1_024

    private enum StoreError: Error {
        case invalidIdentifier
        case invalidFingerprint
        case recordLimit
        case encodedSize
        case invalidSchema
        case malformedData

        var category: String {
            switch self {
            case .invalidIdentifier: "invalid_identifier"
            case .invalidFingerprint: "invalid_fingerprint"
            case .recordLimit: "record_limit"
            case .encodedSize: "encoded_size"
            case .invalidSchema: "invalid_schema"
            case .malformedData: "malformed_data"
            }
        }
    }

    private let defaults: UserDefaults
    private let diagnostics: any VoiceActivationDiagnosticRecording
    private let encoder: JSONEncoder
    private var cachedEnvelope: AgentContinuityEnvelope?
    private var isQuarantined = false

    init(
        defaults: UserDefaults,
        diagnostics: any VoiceActivationDiagnosticRecording = VoiceActivationDiagnostics.shared
    ) {
        self.defaults = defaults
        self.diagnostics = diagnostics
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
    }

    func bookmark(for profileID: UUID) async throws -> AgentSessionBookmark? {
        var envelope = loadEnvelope()
        guard let index = envelope.bookmarks.firstIndex(where: { $0.profileID == profileID }) else {
            return nil
        }
        let ordinal = nextAccessOrdinal(bookmarks: &envelope.bookmarks)
        let existing = envelope.bookmarks[index]
        let accessed = AgentSessionBookmark(
            profileID: existing.profileID,
            sessionID: existing.sessionID,
            providerFingerprint: existing.providerFingerprint,
            lastAccessOrdinal: ordinal)
        envelope.bookmarks[index] = accessed
        try replaceReportingFailure(envelope)
        return accessed
    }

    func save(bookmark: AgentSessionBookmark) async throws {
        var envelope = loadEnvelope()
        do {
            try validate(bookmark)
            let ordinal = nextAccessOrdinal(bookmarks: &envelope.bookmarks)
            let replacement = AgentSessionBookmark(
                profileID: bookmark.profileID,
                sessionID: bookmark.sessionID,
                providerFingerprint: bookmark.providerFingerprint,
                lastAccessOrdinal: ordinal)
            envelope.bookmarks.removeAll { $0.profileID == bookmark.profileID }
            envelope.bookmarks.append(replacement)
            if envelope.bookmarks.count > Self.maximumRecords {
                envelope.bookmarks.remove(at: leastRecentlyUsedIndex(in: envelope.bookmarks))
            }
            try replace(envelope)
        } catch {
            recordSaveFailure(error, envelope: envelope)
            throw error
        }
    }

    func remove(profileIDs: Set<UUID>) async throws {
        var envelope = loadEnvelope()
        let oldBookmarkCount = envelope.bookmarks.count
        let oldWorkCount = envelope.interruptedWork.count
        envelope.bookmarks.removeAll { profileIDs.contains($0.profileID) }
        envelope.interruptedWork.removeAll { profileIDs.contains($0.key.profileID) }
        if isQuarantined || oldBookmarkCount != envelope.bookmarks.count
            || oldWorkCount != envelope.interruptedWork.count
        {
            try replaceReportingFailure(envelope)
        }
    }

    func markWorkActive(_ marker: AgentInterruptedWorkMarker) async throws {
        var envelope = loadEnvelope()
        do {
            try validate(marker)
            let active = AgentInterruptedWorkMarker(
                key: marker.key,
                turnID: marker.turnID,
                providerTaskID: marker.providerTaskID,
                state: .active)
            envelope.interruptedWork.removeAll { $0.key == marker.key }
            envelope.interruptedWork.append(active)
            guard envelope.interruptedWork.count <= Self.maximumRecords else {
                throw StoreError.recordLimit
            }
            try replace(envelope)
        } catch {
            recordSaveFailure(error, envelope: envelope)
            throw error
        }
    }

    func clearWork(_ key: AgentInterruptedWorkKey) async throws {
        var envelope = loadEnvelope()
        let oldCount = envelope.interruptedWork.count
        envelope.interruptedWork.removeAll { $0.key == key }
        if isQuarantined || oldCount != envelope.interruptedWork.count {
            try replaceReportingFailure(envelope)
        }
    }

    func reconcileInterruptedWork() async throws -> [AgentInterruptedWorkMarker] {
        var envelope = loadEnvelope()
        var changed = false
        envelope.interruptedWork = envelope.interruptedWork.map { marker in
            guard marker.state == .active else { return marker }
            changed = true
            return AgentInterruptedWorkMarker(
                key: marker.key,
                turnID: marker.turnID,
                providerTaskID: marker.providerTaskID,
                state: .interruptedByProcessExit)
        }
        if changed {
            try replaceReportingFailure(envelope)
        }
        return envelope.interruptedWork.filter { $0.state == .interruptedByProcessExit }
    }

    func acknowledgeInterruptedWork(_ keys: Set<AgentInterruptedWorkKey>) async throws {
        var envelope = loadEnvelope()
        let oldCount = envelope.interruptedWork.count
        envelope.interruptedWork.removeAll {
            $0.state == .interruptedByProcessExit && keys.contains($0.key)
        }
        if isQuarantined || oldCount != envelope.interruptedWork.count {
            try replaceReportingFailure(envelope)
        }
    }

    private func loadEnvelope() -> AgentContinuityEnvelope {
        if let cachedEnvelope { return cachedEnvelope }
        guard let stored = defaults.object(forKey: Self.key) else {
            let empty = emptyEnvelope()
            cachedEnvelope = empty
            return empty
        }
        guard let data = stored as? Data else {
            return quarantine(category: StoreError.malformedData.category)
        }
        do {
            guard data.count <= Self.maximumEncodedBytes else { throw StoreError.encodedSize }
            try validateSchemaShape(data)
            let envelope = try JSONDecoder().decode(AgentContinuityEnvelope.self, from: data)
            try validate(envelope)
            cachedEnvelope = envelope
            return envelope
        } catch {
            return quarantine(category: failureCategory(error))
        }
    }

    private func quarantine(category: String) -> AgentContinuityEnvelope {
        let empty = emptyEnvelope()
        cachedEnvelope = empty
        isQuarantined = true
        diagnostics.record(
            category: .settings,
            event: "continuity_store.load_quarantined",
            level: .warning,
            fields: ["failure_category": category])
        return empty
    }

    private func emptyEnvelope() -> AgentContinuityEnvelope {
        AgentContinuityEnvelope(schemaVersion: 1, bookmarks: [], interruptedWork: [])
    }

    private func replaceReportingFailure(_ envelope: AgentContinuityEnvelope) throws {
        do {
            try replace(envelope)
        } catch {
            recordSaveFailure(error, envelope: envelope)
            throw error
        }
    }

    private func replace(_ envelope: AgentContinuityEnvelope) throws {
        try validate(envelope)
        let data = try encoder.encode(envelope)
        guard data.count <= Self.maximumEncodedBytes else { throw StoreError.encodedSize }
        defaults.set(data, forKey: Self.key)
        cachedEnvelope = envelope
        isQuarantined = false
    }

    private func validate(_ envelope: AgentContinuityEnvelope) throws {
        guard envelope.schemaVersion == 1 else { throw StoreError.invalidSchema }
        guard envelope.bookmarks.count <= Self.maximumRecords,
            envelope.interruptedWork.count <= Self.maximumRecords
        else { throw StoreError.recordLimit }
        guard Set(envelope.bookmarks.map(\.profileID)).count == envelope.bookmarks.count,
            Set(envelope.interruptedWork.map(\.key)).count == envelope.interruptedWork.count
        else { throw StoreError.malformedData }
        for bookmark in envelope.bookmarks { try validate(bookmark) }
        for marker in envelope.interruptedWork { try validate(marker) }
    }

    private func validateSchemaShape(_ data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw StoreError.malformedData
        }
        guard let root = object as? [String: Any],
            Set(root.keys) == ["schemaVersion", "bookmarks", "interruptedWork"],
            let bookmarks = root["bookmarks"] as? [[String: Any]],
            let work = root["interruptedWork"] as? [[String: Any]]
        else { throw StoreError.malformedData }
        let bookmarkKeys: Set<String> = [
            "profileID", "sessionID", "providerFingerprint", "lastAccessOrdinal",
        ]
        guard bookmarks.allSatisfy({ Set($0.keys) == bookmarkKeys }) else {
            throw StoreError.malformedData
        }
        let markerKeys: Set<String> = ["key", "turnID", "providerTaskID", "state"]
        let requiredMarkerKeys: Set<String> = ["key", "state"]
        let workKeyKeys: Set<String> = ["profileID", "sessionID", "occurrenceID"]
        for marker in work {
            let keys = Set(marker.keys)
            guard keys.isSubset(of: markerKeys), requiredMarkerKeys.isSubset(of: keys),
                let key = marker["key"] as? [String: Any], Set(key.keys) == workKeyKeys
            else { throw StoreError.malformedData }
        }
    }

    private func validate(_ bookmark: AgentSessionBookmark) throws {
        try validateIdentifier(bookmark.sessionID)
        guard bookmark.providerFingerprint.utf8.count == 64,
            bookmark.providerFingerprint.utf8.allSatisfy({
                (48...57).contains($0) || (97...102).contains($0)
            })
        else { throw StoreError.invalidFingerprint }
    }

    private func validate(_ marker: AgentInterruptedWorkMarker) throws {
        try validateIdentifier(marker.key.sessionID)
        if let turnID = marker.turnID { try validateIdentifier(turnID) }
        if let providerTaskID = marker.providerTaskID { try validateIdentifier(providerTaskID) }
    }

    private func validateIdentifier(_ identifier: String) throws {
        guard !identifier.isEmpty,
            identifier.utf8.count <= ACPEventDecoder.maximumOpaqueIdentifierBytes
        else { throw StoreError.invalidIdentifier }
    }

    private func nextAccessOrdinal(bookmarks: inout [AgentSessionBookmark]) -> UInt64 {
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

    private func leastRecentlyUsedIndex(in bookmarks: [AgentSessionBookmark]) -> Int {
        bookmarks.indices.min {
            let lhs = bookmarks[$0]
            let rhs = bookmarks[$1]
            if lhs.lastAccessOrdinal != rhs.lastAccessOrdinal {
                return lhs.lastAccessOrdinal < rhs.lastAccessOrdinal
            }
            return lhs.profileID.uuidString < rhs.profileID.uuidString
        } ?? 0
    }

    private func recordSaveFailure(_ error: Error, envelope: AgentContinuityEnvelope) {
        diagnostics.record(
            category: .settings,
            event: "continuity_store.save_failed",
            level: .error,
            fields: [
                "failure_category": failureCategory(error),
                "bookmark_count": String(envelope.bookmarks.count),
                "work_marker_count": String(envelope.interruptedWork.count),
            ])
    }

    private func failureCategory(_ error: Error) -> String {
        (error as? StoreError)?.category ?? "encoding_failure"
    }
}
