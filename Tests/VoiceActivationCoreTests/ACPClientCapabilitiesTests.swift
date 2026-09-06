// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Testing
@testable import VoiceActivationCore

struct CapabilityLeafCase: Sendable {
    let value: ACPJSONValue
}

struct CapabilityConflictCase: Sendable {
    let existing: ACPJSONValue
    let contribution: ACPJSONValue
}

@Suite struct ACPClientCapabilitiesTests {
    @Test func compose_WhenThereAreNoContributions_ReturnsEmptyObject() throws {
        let capabilities = try ACPClientCapabilities.compose([])

        #expect(capabilities == .object([:]))
    }

    @Test func compose_WhenObjectFragmentsUseDistinctPaths_DeepMergesThem() throws {
        let capabilities = try ACPClientCapabilities.compose([
            .object(["filesystem": .object(["read": .bool(true)])]),
            .object(["filesystem": .object(["write": .bool(true)])]),
            .object(["terminal": .object(["execute": .object([:])])]),
        ])

        #expect(capabilities == .object([
            "filesystem": .object([
                "read": .bool(true),
                "write": .bool(true),
            ]),
            "terminal": .object(["execute": .object([:])]),
        ]))
    }

    @Test func compose_WhenFragmentsRepeatAnIdenticalScalarLeaf_PreservesTheLeaf() throws {
        let capabilities = try ACPClientCapabilities.compose([
            .object(["terminal": .object(["enabled": .bool(true)])]),
            .object(["terminal": .object(["enabled": .bool(true)])]),
        ])

        #expect(capabilities == .object([
            "terminal": .object(["enabled": .bool(true)]),
        ]))
    }

    @Test(arguments: [
        CapabilityLeafCase(value: .array([.string("item")])),
        CapabilityLeafCase(value: .integer(-7)),
        CapabilityLeafCase(value: .unsignedInteger(UInt64.max)),
        CapabilityLeafCase(value: .number(3.5)),
        CapabilityLeafCase(value: .string("enabled")),
        CapabilityLeafCase(value: .null),
    ])
    func compose_WhenFragmentsRepeatAnIdenticalJSONLeaf_PreservesConcreteValue(
        fixture: CapabilityLeafCase
    ) throws {
        let capabilities = try ACPClientCapabilities.compose([
            .object(["nested": .object(["leaf": fixture.value])]),
            .object(["nested": .object(["leaf": fixture.value])]),
        ])

        #expect(capabilities == .object([
            "nested": .object(["leaf": fixture.value]),
        ]))
    }

    @Test func compose_WhenNestedObjectsHaveDistinctLeaves_DeepMergesEveryLevel() throws {
        let capabilities = try ACPClientCapabilities.compose([
            .object(["root": .object(["nested": .object(["first": .null])])]),
            .object(["root": .object(["nested": .object(["second": .string("value")])])]),
        ])

        #expect(capabilities == .object([
            "root": .object([
                "nested": .object([
                    "first": .null,
                    "second": .string("value"),
                ]),
            ]),
        ]))
    }

    @Test func compose_WhenAPathCollidesBetweenScalarAndObject_ThrowsConflict() {
        #expect(throws: ACPClientCapabilitiesError.self) {
            try ACPClientCapabilities.compose([
                .object(["terminal": .bool(true)]),
                .object(["terminal": .object(["execute": .object([:])])]),
            ])
        }
    }

    @Test func compose_WhenAPathCollidesBetweenUnequalScalars_ThrowsConflict() {
        #expect(throws: ACPClientCapabilitiesError.self) {
            try ACPClientCapabilities.compose([
                .object(["terminal": .object(["enabled": .bool(true)])]),
                .object(["terminal": .object(["enabled": .bool(false)])]),
            ])
        }
    }

    @Test func compose_WhenArraysDiffer_ThrowsConflict() {
        #expect(throws: ACPClientCapabilitiesError.self) {
            try ACPClientCapabilities.compose([
                .object(["terminal": .object(["modes": .array([.string("read")])])]),
                .object(["terminal": .object(["modes": .array([.string("write")])])]),
            ])
        }
    }

    @Test func compose_WhenNumberKindsDiffer_ThrowsConflict() {
        #expect(throws: ACPClientCapabilitiesError.self) {
            try ACPClientCapabilities.compose([
                .object(["terminal": .object(["limit": .integer(1)])]),
                .object(["terminal": .object(["limit": .unsignedInteger(1)])]),
            ])
        }
    }

    @Test(arguments: [
        CapabilityConflictCase(existing: .string("first"), contribution: .string("second")),
        CapabilityConflictCase(existing: .number(1.5), contribution: .number(2.5)),
        CapabilityConflictCase(existing: .null, contribution: .bool(true)),
    ])
    func compose_WhenNonObjectLeafValuesDiffer_ThrowsConflict(
        fixture: CapabilityConflictCase
    ) {
        #expect(throws: ACPClientCapabilitiesError.self) {
            try ACPClientCapabilities.compose([
                .object(["terminal": .object(["value": fixture.existing])]),
                .object(["terminal": .object(["value": fixture.contribution])]),
            ])
        }
    }

    @Test func compose_WhenManyConflictsUseUntrustedKeys_ReturnsOneFixedPrivateError() {
        let untrustedKey = "authorization\\nplaceholder-token"
        let fragments: [ACPJSONValue] = [
            .object([
                "alpha": .bool(true),
                untrustedKey: .string("placeholder-secret"),
            ]),
            .object([
                "alpha": .object(["nested": .object([:])]),
                untrustedKey: .string("different-placeholder-secret"),
            ]),
        ]
        var descriptions: [String] = []

        for _ in 0..<8 {
            do {
                _ = try ACPClientCapabilities.compose(fragments)
                Issue.record("Expected conflicting capability contributions")
            } catch let error as ACPClientCapabilitiesError {
                descriptions.append(error.errorDescription ?? "")
                #expect(String(describing: error) == "conflictingValues")
            } catch {
                Issue.record("Expected ACPClientCapabilitiesError")
            }
        }

        #expect(descriptions == Array(
            repeating: "ACP client capability contributions conflict.",
            count: 8))
        #expect(!descriptions.joined().contains("authorization"))
        #expect(!descriptions.joined().contains("placeholder"))
    }

    @Test func compose_WhenAContributionIsNotAnObject_ThrowsConflict() {
        #expect(throws: ACPClientCapabilitiesError.self) {
            try ACPClientCapabilities.compose([.bool(true)])
        }
    }
}
