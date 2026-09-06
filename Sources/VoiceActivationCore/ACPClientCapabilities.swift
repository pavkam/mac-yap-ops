// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

/// Failures while independently owned client-capability fragments are composed.
public enum ACPClientCapabilitiesError: Error, Equatable, LocalizedError, Sendable {
    /// A contribution was not a JSON object.
    case contributionMustBeObject
    /// Two contributions supplied incompatible values at the same object path.
    case conflictingValues

    /// A concise description that never exposes contributed keys, paths, or values.
    public var errorDescription: String? {
        switch self {
        case .contributionMustBeObject:
            "ACP client capabilities must be JSON objects."
        case .conflictingValues:
            "ACP client capability contributions conflict."
        }
    }
}

/// Additively composes independent JSON-object fragments for ACP `clientCapabilities`.
public enum ACPClientCapabilities {
    /// Voice Activation's optional v1 spoken/display response-channel extension.
    public static let voiceResponseChannelsV1: ACPJSONValue = .object([
        "_meta": .object([
            "ciobanu.org.voiceActivation": .object([
                "responseChannels": .object([
                    "version": .integer(1),
                    "channels": .array([.string("spoken"), .string("display")]),
                ]),
            ]),
        ]),
    ])

    /// Deep-merges independently owned JSON-object fragments.
    ///
    /// Object paths merge recursively. An identical non-object leaf may be shared;
    /// incompatible leaves or an object/non-object collision fail rather than letting
    /// one feature silently override another. This type owns no provider policy.
    /// - Parameter fragments: JSON-object fragments contributed by independent clients.
    /// - Returns: One JSON object, or an empty object when no fragments contribute.
    /// - Throws: ``ACPClientCapabilitiesError`` when a fragment or collision is invalid.
    public static func compose(_ fragments: [ACPJSONValue]) throws -> ACPJSONValue {
        var composed: [String: ACPJSONValue] = [:]

        for fragment in fragments {
            guard case .object(let object) = fragment else {
                throw ACPClientCapabilitiesError.contributionMustBeObject
            }
            composed = try merge(composed, with: object)
        }

        return .object(composed)
    }

    private static func merge(
        _ existing: [String: ACPJSONValue],
        with contribution: [String: ACPJSONValue]
    ) throws -> [String: ACPJSONValue] {
        var result = existing

        for key in contribution.keys.sorted() {
            guard let contributionValue = contribution[key] else {
                continue
            }
            guard let existingValue = result[key] else {
                result[key] = contributionValue
                continue
            }

            switch (existingValue, contributionValue) {
            case (.object(let existingObject), .object(let contributionObject)):
                result[key] = .object(try merge(
                    existingObject,
                    with: contributionObject))
            case (.object, _), (_, .object):
                throw ACPClientCapabilitiesError.conflictingValues
            case _ where existingValue == contributionValue:
                continue
            default:
                throw ACPClientCapabilitiesError.conflictingValues
            }
        }

        return result
    }
}
