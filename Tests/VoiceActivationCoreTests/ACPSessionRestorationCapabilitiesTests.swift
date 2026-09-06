// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationCore

@Suite struct ACPSessionRestorationCapabilitiesTests {
    @Test func decode_WhenRootIsNil_TreatsCapabilitiesAsUnsupported() throws {
        let capabilities = try ACPSessionRestorationCapabilities.decode(from: nil)

        #expect(capabilities == .init(loadSession: false, resumeSession: false))
    }

    @Test func decode_WhenRootIsNull_TreatsCapabilitiesAsUnsupported() throws {
        let capabilities = try ACPSessionRestorationCapabilities.decode(from: .null)

        #expect(capabilities == .init(loadSession: false, resumeSession: false))
    }

    @Test(arguments: [
        ACPJSONValue.bool(true),
        .string("not-capabilities"),
        .array([]),
    ])
    func decode_WhenRootIsNotAnObject_ThrowsExactMalformedResponse(value: ACPJSONValue) {
        do {
            _ = try ACPSessionRestorationCapabilities.decode(from: value)
            Issue.record("Expected malformed capabilities response")
        } catch let error as ACPClientError {
            #expect(error == .malformedResponse("Invalid agentCapabilities."))
        } catch {
            Issue.record("Expected ACPClientError")
        }
    }

    @Test func coding_WhenEnvelopeRoundTrips_PreservesBookmarksAndInterruptedWork() throws {
        let bookmark = AgentSessionBookmark(
            profileID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sessionID: "session-1",
            providerFingerprint: String(repeating: "a", count: 64),
            lastAccessOrdinal: 4)
        let marker = AgentInterruptedWorkMarker(
            key: AgentInterruptedWorkKey(
                profileID: bookmark.profileID,
                sessionID: bookmark.sessionID,
                occurrenceID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!),
            turnID: "turn-1",
            providerTaskID: "task-1",
            state: .interruptedByProcessExit)
        let envelope = AgentContinuityEnvelope(
            schemaVersion: 1,
            bookmarks: [bookmark],
            interruptedWork: [marker])

        let decoded = try JSONDecoder().decode(
            AgentContinuityEnvelope.self,
            from: JSONEncoder().encode(envelope))

        #expect(decoded == envelope)
    }

    @Test func mutation_WhenEnvelopeCollectionsChange_RetainsSchemaAndNewCollections() {
        var envelope = AgentContinuityEnvelope(
            schemaVersion: 1,
            bookmarks: [],
            interruptedWork: [])
        let bookmark = AgentSessionBookmark(
            profileID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            sessionID: "session-2",
            providerFingerprint: String(repeating: "b", count: 64),
            lastAccessOrdinal: 7)
        let marker = AgentInterruptedWorkMarker(
            key: AgentInterruptedWorkKey(
                profileID: bookmark.profileID,
                sessionID: bookmark.sessionID,
                occurrenceID: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!),
            state: .active)

        envelope.bookmarks.append(bookmark)
        envelope.interruptedWork.append(marker)

        #expect(envelope.schemaVersion == 1)
        #expect(envelope.bookmarks == [bookmark])
        #expect(envelope.interruptedWork == [marker])
    }

    @Test func decode_WhenCapabilitiesAreOmitted_TreatsOptionalMethodsAsUnsupported() throws {
        let capabilities = try ACPSessionRestorationCapabilities.decode(from: .object([:]))

        #expect(capabilities == .init(loadSession: false, resumeSession: false))
    }

    @Test func decode_WhenOptionalCapabilitiesAreNull_TreatsOptionalMethodsAsUnsupported() throws {
        let capabilities = try ACPSessionRestorationCapabilities.decode(from: .object([
            "loadSession": .null,
            "sessionCapabilities": .null,
        ]))

        #expect(capabilities == .init(loadSession: false, resumeSession: false))
    }

    @Test func decode_WhenLoadSessionIsBoolean_UsesAdvertisedValue() throws {
        let capabilities = try ACPSessionRestorationCapabilities.decode(from: .object([
            "loadSession": .bool(true),
        ]))

        #expect(capabilities == .init(loadSession: true, resumeSession: false))
    }

    @Test(arguments: [
        ACPJSONValue.string("yes"),
        .integer(1),
        .array([]),
        .object([:]),
    ])
    func decode_WhenLoadSessionIsNotBoolean_ThrowsMalformedResponse(
        value: ACPJSONValue
    ) {
        #expect(throws: ACPClientError.malformedResponse(
            "Invalid agentCapabilities.loadSession.")) {
            try ACPSessionRestorationCapabilities.decode(from: .object(["loadSession": value]))
        }
    }

    @Test(arguments: [
        ACPJSONValue.bool(true),
        .string("unsupported"),
        .array([]),
    ])
    func decode_WhenSessionCapabilitiesIsNotAnObject_ThrowsMalformedResponse(
        value: ACPJSONValue
    ) {
        #expect(throws: ACPClientError.malformedResponse(
            "Invalid agentCapabilities.sessionCapabilities.")) {
            try ACPSessionRestorationCapabilities.decode(from: .object([
                "sessionCapabilities": value,
            ]))
        }
    }

    @Test func decode_WhenResumeObjectIsPresent_TreatsResumeAsSupported() throws {
        let capabilities = try ACPSessionRestorationCapabilities.decode(from: .object([
            "sessionCapabilities": .object(["resume": .object([:])]),
        ]))

        #expect(capabilities.resumeSession)
    }

    @Test func decode_WhenResumeIsAbsentOrNull_TreatsResumeAsUnsupported() throws {
        let absent = try ACPSessionRestorationCapabilities.decode(from: .object([
            "sessionCapabilities": .object([:]),
        ]))
        let null = try ACPSessionRestorationCapabilities.decode(from: .object([
            "sessionCapabilities": .object(["resume": .null]),
        ]))

        #expect(!absent.resumeSession)
        #expect(!null.resumeSession)
    }

    @Test(arguments: [
        ACPJSONValue.bool(true),
        .string("supported"),
        .array([]),
    ])
    func decode_WhenResumeIsNotAnObject_ThrowsMalformedResponse(value: ACPJSONValue) {
        #expect(throws: ACPClientError.malformedResponse(
            "Invalid agentCapabilities.sessionCapabilities.resume.")) {
            try ACPSessionRestorationCapabilities.decode(from: .object([
                "sessionCapabilities": .object(["resume": value]),
            ]))
        }
    }
}
