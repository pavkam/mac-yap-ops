// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import YapOpsCore

actor UserDefaultsAgentContinuityStore: AgentContinuityStoring {
    static let key = "yapOps.agentContinuity.v1"
    static let maximumEncodedBytes = 512 * 1_024

    private enum StoreError: Error {
        case encodedSize
        case malformedData

        var category: String {
            switch self {
            case .encodedSize: "encoded_size"
            case .malformedData: "malformed_data"
            }
        }
    }

    private let defaults: UserDefaults
    private let diagnostics: any YapOpsDiagnosticRecording
    private let encoder: JSONEncoder
    private var cachedEnvelope: AgentContinuityEnvelope?
    private var isQuarantined = false

    init(
        defaults: UserDefaults,
        diagnostics: any YapOpsDiagnosticRecording = YapOpsDiagnostics.shared
    ) {
        self.defaults = defaults
        self.diagnostics = diagnostics
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
    }

    func bookmark(for profileID: UUID) async throws -> AgentSessionBookmark? {
        var envelope = loadEnvelope()
        do {
            let bookmark = try AgentContinuityStorePolicy.bookmark(
                for: profileID,
                in: &envelope)
            if bookmark != nil {
                try replace(envelope)
            }
            return bookmark
        } catch {
            recordSaveFailure(error, envelope: envelope)
            throw error
        }
    }

    func save(bookmark: AgentSessionBookmark) async throws {
        var envelope = loadEnvelope()
        do {
            try AgentContinuityStorePolicy.save(bookmark, in: &envelope)
            try replace(envelope)
        } catch {
            recordSaveFailure(error, envelope: envelope)
            throw error
        }
    }

    func remove(profileIDs: Set<UUID>) async throws {
        var envelope = loadEnvelope()
        do {
            let changed = try AgentContinuityStorePolicy.remove(
                profileIDs: profileIDs,
                in: &envelope)
            if isQuarantined || changed {
                try replace(envelope)
            }
        } catch {
            recordSaveFailure(error, envelope: envelope)
            throw error
        }
    }

    func markWorkActive(_ marker: AgentInterruptedWorkMarker) async throws {
        var envelope = loadEnvelope()
        do {
            try AgentContinuityStorePolicy.markWorkActive(marker, in: &envelope)
            try replace(envelope)
        } catch {
            recordSaveFailure(error, envelope: envelope)
            throw error
        }
    }

    func clearWork(_ key: AgentInterruptedWorkKey) async throws {
        var envelope = loadEnvelope()
        do {
            let changed = try AgentContinuityStorePolicy.clearWork(key, in: &envelope)
            if isQuarantined || changed {
                try replace(envelope)
            }
        } catch {
            recordSaveFailure(error, envelope: envelope)
            throw error
        }
    }

    func reconcileInterruptedWork() async throws -> [AgentInterruptedWorkMarker] {
        var envelope = loadEnvelope()
        let original = envelope
        do {
            let interrupted = try AgentContinuityStorePolicy.reconcileInterruptedWork(
                in: &envelope)
            if envelope != original {
                try replace(envelope)
            }
            return interrupted
        } catch {
            recordSaveFailure(error, envelope: envelope)
            throw error
        }
    }

    func acknowledgeInterruptedWork(_ keys: Set<AgentInterruptedWorkKey>) async throws {
        var envelope = loadEnvelope()
        do {
            let changed = try AgentContinuityStorePolicy.acknowledgeInterruptedWork(
                keys,
                in: &envelope)
            if isQuarantined || changed {
                try replace(envelope)
            }
        } catch {
            recordSaveFailure(error, envelope: envelope)
            throw error
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
            let envelope: AgentContinuityEnvelope
            do {
                envelope = try JSONDecoder().decode(AgentContinuityEnvelope.self, from: data)
            } catch {
                throw StoreError.malformedData
            }
            try AgentContinuityStorePolicy.validate(envelope)
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
        AgentContinuityStorePolicy.emptyEnvelope()
    }

    private func replace(_ envelope: AgentContinuityEnvelope) throws {
        try AgentContinuityStorePolicy.validate(envelope)
        let data = try encoder.encode(envelope)
        guard data.count <= Self.maximumEncodedBytes else { throw StoreError.encodedSize }
        defaults.set(data, forKey: Self.key)
        cachedEnvelope = envelope
        isQuarantined = false
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
        if let error = error as? StoreError { return error.category }
        guard let error = error as? AgentContinuityStoreError else {
            return "encoding_failure"
        }
        switch error {
        case .invalidSchema:
            return "invalid_schema"
        case .recordLimitExceeded:
            return "record_limit"
        case .duplicateRecord:
            return "malformed_data"
        case .invalidIdentifier:
            return "invalid_identifier"
        case .invalidFingerprint:
            return "invalid_fingerprint"
        }
    }
}
