// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import CryptoKit
import Foundation

/// Builds a versioned compatibility fingerprint for an ACP provider session namespace.
public enum AgentProviderFingerprint {
    private static let versionMarker = "voice-activation.agent-provider-fingerprint.v1"

    /// Hashes only the provider configuration fields that define reusable session context.
    ///
    /// Every UTF-8 field is length-prefixed with an unsigned 64-bit big-endian byte count.
    /// Arguments additionally include their count and preserve order and empty values.
    /// Display and permission preferences are deliberately excluded.
    /// - Parameter configuration: The validated provider launch and context configuration.
    /// - Returns: A lowercase 64-character SHA-256 digest.
    public static func make(configuration: AgentHarnessConfiguration) -> String {
        var canonical = Data()
        append(Self.versionMarker, to: &canonical)
        append(configuration.preset.rawValue, to: &canonical)
        append(configuration.executablePath, to: &canonical)
        append(UInt64(configuration.arguments.count), to: &canonical)
        for argument in configuration.arguments {
            append(argument, to: &canonical)
        }
        append(configuration.workingDirectory, to: &canonical)
        append(configuration.systemPrompt, to: &canonical)

        return SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    }

    private static func append(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        append(UInt64(bytes.count), to: &data)
        data.append(bytes)
    }

    private static func append(_ value: UInt64, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }
}
