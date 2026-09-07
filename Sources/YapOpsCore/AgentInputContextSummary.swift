// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

/// A bounded, in-memory description of captured context without selection contents or paths.
public struct AgentInputContextSummary: Equatable, Sendable {
    /// The capture outcome, or nil when no context capture was requested or available.
    public let captureState: MacContextCaptureState?
    /// The bounded name of the application captured for this input.
    public let applicationName: String?
    /// Whether a nonempty window title was captured.
    public let hasWindow: Bool
    /// Whether a document link was captured.
    public let hasDocument: Bool
    /// Whether nonblank selected text was captured.
    public let hasSelectedText: Bool
    /// The bounded number of selected resource links captured.
    public let resourceCount: Int
    /// Whether the capture omitted or shortened values to meet its bounds.
    public let isTruncated: Bool

    /// Projects a request's snapshot into display metadata without retaining private content.
    /// - Parameter context: The exact captured snapshot associated with the request.
    public init(context: MacContextSnapshot?) {
        captureState = context?.captureState
        applicationName = context.map { boundedUTF8($0.applicationName, maximumBytes: 256) }
        hasWindow = context?.windowTitle?.isEmpty == false
        hasDocument = context?.documentURL != nil
        hasSelectedText = context?.selectedText?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        resourceCount = min(context?.resources.count ?? 0, MacContextSnapshot.maximumResources)
        isTruncated = context?.truncatedFields.isEmpty == false
    }
}
