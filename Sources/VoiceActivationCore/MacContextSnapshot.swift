// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

/// An immutable identity for the application that received an explicit voice activation.
public struct MacContextTarget: Equatable, Sendable {
    /// The process identifier frozen when the voice activation was admitted.
    public let processIdentifier: Int32
    /// The user-visible application name frozen when the voice activation was admitted.
    public let applicationName: String
    /// The application's bundle identifier, when the operating system provides one.
    public let bundleIdentifier: String?

    /// Creates an immutable foreground-application identity without retaining framework objects.
    ///
    /// - Parameters:
    ///   - processIdentifier: The frozen process identifier.
    ///   - applicationName: The frozen user-visible application name.
    ///   - bundleIdentifier: The optional frozen bundle identifier.
    public init(
        processIdentifier: Int32,
        applicationName: String,
        bundleIdentifier: String?
    ) {
        self.processIdentifier = processIdentifier
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
    }
}

/// The outcome of one bounded native Mac-context capture.
public enum MacContextCaptureState: String, Codable, Equatable, Sendable {
    /// The native capture completed without an Accessibility failure.
    case complete
    /// Accessibility access was not authorized when capture began.
    case accessibilityNotAuthorized = "accessibility_not_authorized"
    /// The frozen target no longer existed when native capture began.
    case targetUnavailable = "target_unavailable"
    /// Native capture did not complete before its admission deadline.
    case timedOut = "timed_out"
    /// Accessibility could not complete a capture after it began.
    case accessibilityFailed = "accessibility_failed"
}

/// One selected native resource safe to describe to an ACP agent.
public struct MacContextResource: Codable, Equatable, Sendable {
    /// The allow-listed, absolute resource URI.
    public let uri: String
    /// The bounded user-visible resource name.
    public let name: String

    /// Creates a resource value before its URI and name are normalized into a snapshot.
    ///
    /// - Parameters:
    ///   - uri: An untrusted resource URI.
    ///   - name: An untrusted resource name.
    public init(uri: String, name: String) {
        self.uri = uri
        self.name = name
    }
}

/// A bounded, privacy-safe description of the foreground Mac context for one voice turn.
public struct MacContextSnapshot: Codable, Equatable, Sendable {
    /// The maximum UTF-8 size retained for selected text.
    public static let maximumSelectedTextBytes = 12 * 1_024
    /// The maximum UTF-8 size permitted for the later encoded context JSON payload.
    public static let maximumEncodedBytes = 16 * 1_024
    /// The maximum number of unique selected resources retained in Accessibility order.
    public static let maximumResources = 8

    private static let maximumApplicationNameBytes = 256
    private static let maximumBundleIdentifierBytes = 256
    private static let maximumWindowTitleBytes = 512
    private static let maximumURIBytes = 2_048
    private static let maximumResourceNameBytes = 256

    /// The result of the bounded native capture.
    public let captureState: MacContextCaptureState
    /// The bounded user-visible application name from the frozen target.
    public let applicationName: String
    /// The bounded bundle identifier from the frozen target, when available.
    public let bundleIdentifier: String?
    /// The bounded focused-window title, when available.
    public let windowTitle: String?
    /// The allow-listed, bounded focused-document URI, when available.
    public let documentURL: String?
    /// The bounded selected text, when available.
    public let selectedText: String?
    /// The first bounded unique resources in Accessibility order.
    public let resources: [MacContextResource]
    /// Field names changed or omitted because a configured bound was exceeded.
    public let truncatedFields: [String]

    /// Normalizes untrusted native capture values into a deterministic bounded snapshot.
    ///
    /// Strings are truncated only at Unicode-scalar boundaries. Document and resource URIs
    /// must be absolute `file`, `http`, or `https` URLs; invalid or unsafe URIs are omitted.
    /// Resources retain their first-seen Accessibility order and de-duplicate by normalized URI.
    ///
    /// - Parameters:
    ///   - state: The outcome of the native capture.
    ///   - target: The primitive application identity frozen at voice-turn admission.
    ///   - windowTitle: An untrusted focused-window title.
    ///   - documentURL: An untrusted focused-document URI.
    ///   - selectedText: Untrusted selected text.
    ///   - resources: Untrusted selected resources in Accessibility order.
    /// - Returns: A snapshot constrained to the Core privacy and size contract.
    public static func normalized(
        state: MacContextCaptureState,
        target: MacContextTarget,
        windowTitle: String?,
        documentURL: String?,
        selectedText: String?,
        resources: [MacContextResource]
    ) -> Self {
        var truncatedFields: [String] = []
        let applicationName = boundedValue(
            target.applicationName,
            maximumBytes: maximumApplicationNameBytes,
            field: "application.name",
            truncatedFields: &truncatedFields)
        let bundleIdentifier = target.bundleIdentifier.map {
            boundedValue(
                $0,
                maximumBytes: maximumBundleIdentifierBytes,
                field: "application.bundleIdentifier",
                truncatedFields: &truncatedFields)
        }
        let windowTitle = windowTitle.map {
            boundedValue(
                $0,
                maximumBytes: maximumWindowTitleBytes,
                field: "windowTitle",
                truncatedFields: &truncatedFields)
        }
        let documentURL = normalizedURI(
            documentURL,
            field: "documentURL",
            truncatedFields: &truncatedFields)
        let selectedText = selectedText.map {
            boundedValue(
                $0,
                maximumBytes: maximumSelectedTextBytes,
                field: "selectedText",
                truncatedFields: &truncatedFields)
        }

        var normalizedResources: [MacContextResource] = []
        var seenURIs = Set<String>()
        for resource in resources {
            guard let uri = normalizedURI(
                resource.uri,
                field: "resources",
                truncatedFields: &truncatedFields),
                seenURIs.insert(uri).inserted
            else {
                continue
            }
            guard normalizedResources.count < maximumResources else {
                recordTruncation("resources", in: &truncatedFields)
                continue
            }
            let name = boundedValue(
                resource.name,
                maximumBytes: maximumResourceNameBytes,
                field: "resources",
                truncatedFields: &truncatedFields)
            normalizedResources.append(.init(uri: uri, name: name))
        }

        return Self(
            captureState: state,
            applicationName: applicationName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            documentURL: documentURL,
            selectedText: selectedText,
            resources: normalizedResources,
            truncatedFields: truncatedFields)
    }

    private static func boundedValue(
        _ value: String,
        maximumBytes: Int,
        field: String,
        truncatedFields: inout [String]
    ) -> String {
        let bounded = boundedUTF8(value, maximumBytes: maximumBytes)
        if bounded != value {
            recordTruncation(field, in: &truncatedFields)
        }
        return bounded
    }

    private static func normalizedURI(
        _ value: String?,
        field: String,
        truncatedFields: inout [String]
    ) -> String? {
        guard let value else {
            return nil
        }
        guard value.utf8.count <= maximumURIBytes else {
            recordTruncation(field, in: &truncatedFields)
            return nil
        }
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else {
            return nil
        }

        let normalizedURL: URL
        switch scheme {
        case "file" where url.path.hasPrefix("/"):
            normalizedURL = url.standardizedFileURL
        case "http", "https":
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let host = components.host
            else {
                return nil
            }
            components.scheme = scheme
            components.host = host.lowercased()
            guard let canonicalURL = components.url else {
                return nil
            }
            normalizedURL = canonicalURL.standardized
        default:
            return nil
        }

        let normalized = normalizedURL.absoluteString
        guard normalized.utf8.count <= maximumURIBytes else {
            recordTruncation(field, in: &truncatedFields)
            return nil
        }
        return normalized
    }

    private static func recordTruncation(_ field: String, in fields: inout [String]) {
        if !fields.contains(field) {
            fields.append(field)
        }
    }
}

func boundedUTF8(_ value: String, maximumBytes: Int) -> String {
    guard value.utf8.count > maximumBytes else {
        return value
    }

    var result = String.UnicodeScalarView()
    var byteCount = 0
    for scalar in value.unicodeScalars {
        let scalarBytes = String(scalar).utf8.count
        guard byteCount + scalarBytes <= maximumBytes else {
            break
        }
        result.append(scalar)
        byteCount += scalarBytes
    }
    return String(result)
}
