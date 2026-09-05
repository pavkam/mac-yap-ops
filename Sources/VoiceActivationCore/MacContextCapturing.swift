// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

/// Captures a bounded native context for a foreground application frozen at voice-turn admission.
@MainActor
public protocol MacContextCapturing: Sendable {
    /// Returns the current foreground application identity without retaining framework objects.
    func currentTarget() -> MacContextTarget?

    /// Captures one bounded context for the supplied frozen application identity.
    ///
    /// - Parameter target: The application identity captured at voice-turn admission.
    /// - Returns: A bounded snapshot whose state explains unavailable native context.
    func capture(_ target: MacContextTarget) async -> MacContextSnapshot
}

/// A no-op capturer for configurations where native Mac context is unavailable.
@MainActor
public struct EmptyMacContextCapturer: MacContextCapturing {
    /// Creates a capturer that never exposes a foreground target.
    public init() {}

    /// Returns no target because this fallback never performs native application reads.
    public func currentTarget() -> MacContextTarget? {
        nil
    }

    /// Returns an application-only unavailable snapshot if capture is invoked directly.
    ///
    /// - Parameter target: The already-frozen target to preserve in the fallback result.
    /// - Returns: A normalized snapshot with ``MacContextCaptureState/targetUnavailable``.
    public func capture(_ target: MacContextTarget) async -> MacContextSnapshot {
        MacContextSnapshot.normalized(
            state: .targetUnavailable,
            target: target,
            windowTitle: nil,
            documentURL: nil,
            selectedText: nil,
            resources: [])
    }
}
