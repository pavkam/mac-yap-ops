// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
@testable import YapOpsCore

actor RecordingAgentContinuityStore: AgentContinuityStoring {
    enum Operation: String, Hashable, Sendable {
        case read
        case save
        case remove
        case mark
        case clear
        case reconcile
        case acknowledge
    }

    enum Call: Equatable, Sendable {
        case read(UUID)
        case save(UUID, String)
        case remove(Set<UUID>)
        case mark(AgentInterruptedWorkKey)
        case clear(AgentInterruptedWorkKey)
        case reconcile
        case acknowledge(Set<AgentInterruptedWorkKey>)
    }

    enum Failure: Error {
        case requested
    }

    private var envelope: AgentContinuityEnvelope
    private var calls: [Call] = []
    private var failures: Set<Operation>
    private let markGate: RunnerEventGate?
    private let acknowledgeGate: RunnerEventGate?

    init(
        bookmarks: [AgentSessionBookmark] = [],
        markers: [AgentInterruptedWorkMarker] = [],
        failures: Set<Operation> = [],
        markGate: RunnerEventGate? = nil,
        acknowledgeGate: RunnerEventGate? = nil
    ) {
        envelope = AgentContinuityEnvelope(
            schemaVersion: AgentContinuityStorePolicy.schemaVersion,
            bookmarks: bookmarks,
            interruptedWork: markers)
        self.failures = failures
        self.markGate = markGate
        self.acknowledgeGate = acknowledgeGate
    }

    func bookmark(for profileID: UUID) async throws -> AgentSessionBookmark? {
        calls.append(.read(profileID))
        try failIfRequested(.read)
        return try AgentContinuityStorePolicy.bookmark(for: profileID, in: &envelope)
    }

    func save(bookmark: AgentSessionBookmark) async throws {
        calls.append(.save(bookmark.profileID, bookmark.sessionID))
        try failIfRequested(.save)
        try AgentContinuityStorePolicy.save(bookmark, in: &envelope)
    }

    func remove(profileIDs: Set<UUID>) async throws {
        calls.append(.remove(profileIDs))
        try failIfRequested(.remove)
        try AgentContinuityStorePolicy.remove(profileIDs: profileIDs, in: &envelope)
    }

    func markWorkActive(_ marker: AgentInterruptedWorkMarker) async throws {
        calls.append(.mark(marker.key))
        if let markGate { await markGate.wait() }
        try failIfRequested(.mark)
        try AgentContinuityStorePolicy.markWorkActive(marker, in: &envelope)
    }

    func clearWork(_ key: AgentInterruptedWorkKey) async throws {
        calls.append(.clear(key))
        try failIfRequested(.clear)
        try AgentContinuityStorePolicy.clearWork(key, in: &envelope)
    }

    func reconcileInterruptedWork() async throws -> [AgentInterruptedWorkMarker] {
        calls.append(.reconcile)
        try failIfRequested(.reconcile)
        return try AgentContinuityStorePolicy.reconcileInterruptedWork(in: &envelope)
    }

    func acknowledgeInterruptedWork(_ keys: Set<AgentInterruptedWorkKey>) async throws {
        calls.append(.acknowledge(keys))
        if let acknowledgeGate { await acknowledgeGate.wait() }
        try failIfRequested(.acknowledge)
        try AgentContinuityStorePolicy.acknowledgeInterruptedWork(keys, in: &envelope)
    }

    func recordedCalls() -> [Call] {
        calls
    }

    func snapshot() -> AgentContinuityEnvelope {
        envelope
    }

    func setFailures(_ failures: Set<Operation>) {
        self.failures = failures
    }

    private func failIfRequested(_ operation: Operation) throws {
        if failures.contains(operation) { throw Failure.requested }
    }
}

actor RunnerContinuityAcknowledgementRecorder {
    private var acknowledgements: [Set<AgentInterruptedWorkKey>] = []

    func record(_ keys: Set<AgentInterruptedWorkKey>) {
        acknowledgements.append(keys)
    }

    func snapshot() -> [Set<AgentInterruptedWorkKey>] {
        acknowledgements
    }
}

extension ACPAgentRunnerContinuityTests {
    func matchingBookmark(
        profileID: UUID,
        configuration: AgentHarnessConfiguration,
        sessionID: String = "saved-session"
    ) -> AgentSessionBookmark {
        AgentSessionBookmark(
            profileID: profileID,
            sessionID: sessionID,
            providerFingerprint: AgentProviderFingerprint.make(configuration: configuration),
            lastAccessOrdinal: 1)
    }

    func sessionUnavailableResponse(id: Int64) -> ACPMessage {
        .errorResponse(
            id: .integer(id),
            error: ACPJSONRPCError(
                code: -32_002,
                message: "missing",
                data: .object([
                    "resourceType": .string("session"),
                    "resourceId": .string("saved-session"),
                ])))
    }
}
