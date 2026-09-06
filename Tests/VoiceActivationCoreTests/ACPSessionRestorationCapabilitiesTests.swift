// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Testing
@testable import VoiceActivationCore

@Suite struct ACPSessionRestorationCapabilitiesTests {
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
        #expect(throws: ACPClientError.self) {
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
        #expect(throws: ACPClientError.self) {
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
        #expect(throws: ACPClientError.self) {
            try ACPSessionRestorationCapabilities.decode(from: .object([
                "sessionCapabilities": .object(["resume": value]),
            ]))
        }
    }
}
