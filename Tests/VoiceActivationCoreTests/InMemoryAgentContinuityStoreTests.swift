// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationCore

@Suite struct InMemoryAgentContinuityStoreTests {
    @Test func save_WhenIdentifierIsEmpty_ThrowsWithoutReplacingBookmark() async throws {
        let store = InMemoryAgentContinuityStore()
        try await store.save(bookmark: bookmark(index: 0, sessionID: "valid"))

        await #expect(throws: AgentContinuityStoreError.invalidIdentifier) {
            try await store.save(bookmark: bookmark(index: 0, sessionID: ""))
        }

        #expect(try await store.bookmark(for: profileID(0))?.sessionID == "valid")
    }

    @Test func identifiers_WhenMultibyteValueCrossesBound_RejectsOnlyOversizedValue()
        async throws
    {
        let store = InMemoryAgentContinuityStore()
        let exact = String(repeating: "🦊", count: 1_024)
        try await store.save(bookmark: bookmark(index: 0, sessionID: exact))
        try await store.markWorkActive(marker(
            index: 0,
            sessionID: exact,
            turnID: exact,
            providerTaskID: exact))

        await #expect(throws: AgentContinuityStoreError.invalidIdentifier) {
            try await store.save(bookmark: bookmark(index: 1, sessionID: exact + "a"))
        }
        await #expect(throws: AgentContinuityStoreError.invalidIdentifier) {
            try await store.markWorkActive(marker(index: 1, turnID: exact + "a"))
        }
        await #expect(throws: AgentContinuityStoreError.invalidIdentifier) {
            try await store.markWorkActive(marker(index: 2, providerTaskID: exact + "a"))
        }

        #expect(try await store.bookmark(for: profileID(0))?.sessionID == exact)
        #expect(try await store.bookmark(for: profileID(1)) == nil)
    }

    @Test func save_WhenFingerprintIsNotLowercaseSHA256_ThrowsAtomically() async throws {
        let store = InMemoryAgentContinuityStore()
        try await store.save(bookmark: bookmark(index: 0))

        await #expect(throws: AgentContinuityStoreError.invalidFingerprint) {
            try await store.save(bookmark: bookmark(
                index: 0,
                fingerprint: String(repeating: "A", count: 64)))
        }

        #expect(try await store.bookmark(for: profileID(0))?.providerFingerprint == fingerprint)
    }

    @Test func save_WhenSixtyFifthProfileArrives_EvictsTouchedLRUBookmark() async throws {
        let store = InMemoryAgentContinuityStore()
        for index in 0..<64 {
            try await store.save(bookmark: bookmark(index: index))
        }
        _ = try await store.bookmark(for: profileID(0))

        try await store.save(bookmark: bookmark(index: 64))

        #expect(try await store.bookmark(for: profileID(0)) != nil)
        #expect(try await store.bookmark(for: profileID(1)) == nil)
        #expect(try await store.bookmark(for: profileID(64)) != nil)
    }

    @Test func markWorkActive_WhenSixtyFifthExactKeyArrives_ThrowsAtomically() async throws {
        let store = InMemoryAgentContinuityStore()
        for index in 0..<64 {
            try await store.markWorkActive(marker(index: index))
        }

        await #expect(throws: AgentContinuityStoreError.recordLimitExceeded) {
            try await store.markWorkActive(marker(index: 64))
        }

        #expect(try await store.reconcileInterruptedWork().count == 64)
    }

    @Test func saveAndMark_WhenIdentityRepeats_ReplacesAndNormalizesState() async throws {
        let store = InMemoryAgentContinuityStore()
        try await store.save(bookmark: bookmark(index: 0, sessionID: "old"))
        try await store.save(bookmark: bookmark(index: 0, sessionID: "new"))
        let key = workKey(index: 0)
        try await store.markWorkActive(AgentInterruptedWorkMarker(
            key: key,
            turnID: "old-turn",
            state: .active))
        try await store.markWorkActive(AgentInterruptedWorkMarker(
            key: key,
            turnID: "new-turn",
            state: .interruptedByProcessExit))

        let bookmark = try #require(try await store.bookmark(for: profileID(0)))
        let interrupted = try await store.reconcileInterruptedWork()
        #expect(bookmark.sessionID == "new")
        #expect(interrupted.count == 1)
        #expect(interrupted.first?.turnID == "new-turn")
        #expect(interrupted.first?.state == .interruptedByProcessExit)
    }

    @Test func workOperations_WhenOccurrencesAndProfilesDiffer_MutateOnlyExactOwners()
        async throws
    {
        let store = InMemoryAgentContinuityStore()
        try await store.save(bookmark: bookmark(index: 0))
        try await store.save(bookmark: bookmark(index: 1))
        let first = marker(index: 0, profileIndex: 0, providerTaskID: "reused")
        let second = marker(index: 1, profileIndex: 0, providerTaskID: "reused")
        let unrelated = marker(index: 2, profileIndex: 1)
        try await store.markWorkActive(first)
        try await store.markWorkActive(second)
        try await store.markWorkActive(unrelated)

        try await store.clearWork(first.key)
        let interrupted = try await store.reconcileInterruptedWork()
        try await store.acknowledgeInterruptedWork([second.key])
        try await store.remove(profileIDs: [profileID(0)])

        #expect(interrupted.map(\.key).contains(second.key))
        #expect(interrupted.map(\.key).contains(unrelated.key))
        #expect(try await store.bookmark(for: profileID(0)) == nil)
        #expect(try await store.bookmark(for: profileID(1)) != nil)
        #expect(try await store.reconcileInterruptedWork() == [
            AgentInterruptedWorkMarker(
                key: unrelated.key,
                turnID: unrelated.turnID,
                providerTaskID: unrelated.providerTaskID,
                state: .interruptedByProcessExit),
        ])
    }

    private let fingerprint = String(repeating: "a", count: 64)

    private func bookmark(
        index: Int,
        sessionID: String? = nil,
        fingerprint: String? = nil
    ) -> AgentSessionBookmark {
        AgentSessionBookmark(
            profileID: profileID(index),
            sessionID: sessionID ?? "session-\(index)",
            providerFingerprint: fingerprint ?? self.fingerprint,
            lastAccessOrdinal: 9_999)
    }

    private func marker(
        index: Int,
        profileIndex: Int? = nil,
        sessionID: String? = nil,
        turnID: String? = nil,
        providerTaskID: String? = nil
    ) -> AgentInterruptedWorkMarker {
        AgentInterruptedWorkMarker(
            key: AgentInterruptedWorkKey(
                profileID: profileID(profileIndex ?? index),
                sessionID: sessionID ?? "session-\(profileIndex ?? index)",
                occurrenceID: occurrenceID(index)),
            turnID: turnID,
            providerTaskID: providerTaskID,
            state: .active)
    }

    private func workKey(index: Int) -> AgentInterruptedWorkKey {
        AgentInterruptedWorkKey(
            profileID: profileID(index),
            sessionID: "session-\(index)",
            occurrenceID: occurrenceID(index))
    }

    private func profileID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
    }

    private func occurrenceID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", index + 1))!
    }

}
