// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

/// Failures while independently owned client-capability fragments are composed.
public enum ACPClientCapabilitiesError: Error, Equatable, LocalizedError, Sendable {
    /// A contribution was not a JSON object.
    case contributionMustBeObject
    /// Two contributions supplied incompatible values for the same object path.
    case conflictingValues(path: String)

    /// A concise description that names only the JSON path, never contributed data.
    public var errorDescription: String? {
        switch self {
        case .contributionMustBeObject:
            "ACP client capabilities must be JSON objects."
        case .conflictingValues(let path):
            "ACP client capability contributions conflict at \(path)."
        }
    }
}

/// Additively composes independent JSON-object fragments for ACP `clientCapabilities`.
public enum ACPClientCapabilities {
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
            composed = try merge(composed, with: object, path: [])
        }

        return .object(composed)
    }

    private static func merge(
        _ existing: [String: ACPJSONValue],
        with contribution: [String: ACPJSONValue],
        path: [String]
    ) throws -> [String: ACPJSONValue] {
        var result = existing

        for (key, contributionValue) in contribution {
            guard let existingValue = result[key] else {
                result[key] = contributionValue
                continue
            }

            let valuePath = path + [key]
            switch (existingValue, contributionValue) {
            case (.object(let existingObject), .object(let contributionObject)):
                result[key] = .object(try merge(
                    existingObject,
                    with: contributionObject,
                    path: valuePath))
            case (.object, _), (_, .object):
                throw ACPClientCapabilitiesError.conflictingValues(
                    path: valuePath.joined(separator: "."))
            case _ where existingValue == contributionValue:
                continue
            default:
                throw ACPClientCapabilitiesError.conflictingValues(
                    path: valuePath.joined(separator: "."))
            }
        }

        return result
    }
}
