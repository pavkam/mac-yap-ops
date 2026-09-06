// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Testing
@testable import VoiceActivationCore

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

    @Test func compose_WhenAContributionIsNotAnObject_ThrowsConflict() {
        #expect(throws: ACPClientCapabilitiesError.self) {
            try ACPClientCapabilities.compose([.bool(true)])
        }
    }
}
