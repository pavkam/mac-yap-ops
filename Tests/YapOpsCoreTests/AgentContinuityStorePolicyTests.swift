// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import YapOpsCore

@Suite struct AgentContinuityStorePolicyTests {
    @Test func save_WhenMaximumOrdinalIsReached_RebasesWithStableUUIDTiebreak() throws {
        let lowID = profileID(0)
        let highID = profileID(1)
        var envelope = AgentContinuityEnvelope(
            schemaVersion: 1,
            bookmarks: [
                bookmark(profileID: highID, sessionID: "high", ordinal: .max),
                bookmark(profileID: lowID, sessionID: "low", ordinal: .max),
            ],
            interruptedWork: [])

        try AgentContinuityStorePolicy.save(
            bookmark(profileID: profileID(2), sessionID: "new", ordinal: 0),
            in: &envelope)

        let ordinals = Dictionary(uniqueKeysWithValues: envelope.bookmarks.map {
            ($0.profileID, $0.lastAccessOrdinal)
        })
        #expect(ordinals[lowID] == 1)
        #expect(ordinals[highID] == 2)
        #expect(ordinals[profileID(2)] == 3)
    }

    @Test func save_WhenLRUOrdinalsTie_EvictsLexicallyLowestProfileUUID() throws {
        var envelope = AgentContinuityEnvelope(
            schemaVersion: 1,
            bookmarks: (0..<64).reversed().map {
                bookmark(profileID: profileID($0), sessionID: "session-\($0)", ordinal: 1)
            },
            interruptedWork: [])

        try AgentContinuityStorePolicy.save(
            bookmark(profileID: profileID(64), sessionID: "new", ordinal: 0),
            in: &envelope)

        #expect(envelope.bookmarks.count == 64)
        #expect(!envelope.bookmarks.contains { $0.profileID == profileID(0) })
        #expect(envelope.bookmarks.contains { $0.profileID == profileID(1) })
        #expect(envelope.bookmarks.contains { $0.profileID == profileID(64) })
    }

    @Test func validate_WhenRecordsDuplicate_ThrowsContentFreeError() {
        let duplicate = bookmark(profileID: profileID(0), sessionID: "session", ordinal: 1)
        let envelope = AgentContinuityEnvelope(
            schemaVersion: 1,
            bookmarks: [duplicate, duplicate],
            interruptedWork: [])

        #expect(throws: AgentContinuityStoreError.duplicateRecord) {
            try AgentContinuityStorePolicy.validate(envelope)
        }
    }

    private let fingerprint = String(repeating: "a", count: 64)

    private func bookmark(
        profileID: UUID,
        sessionID: String,
        ordinal: UInt64
    ) -> AgentSessionBookmark {
        AgentSessionBookmark(
            profileID: profileID,
            sessionID: sessionID,
            providerFingerprint: fingerprint,
            lastAccessOrdinal: ordinal)
    }

    private func profileID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
    }
}
