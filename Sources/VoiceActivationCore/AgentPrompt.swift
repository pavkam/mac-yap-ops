// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

/// One immutable agent request together with the Mac context captured for that request.
public struct AgentPrompt: Equatable, Sendable {
    /// The untouched recognized request, bounded separately before ACP transport.
    public let request: String
    /// The optional bounded Mac-context snapshot captured when the request was admitted.
    public let context: MacContextSnapshot?
    /// Optional identifier-free continuity metadata composed after session activation.
    public let continuity: AgentContinuityPromptContext?

    /// Creates a typed agent request.
    ///
    /// - Parameters:
    ///   - request: The untouched recognized request.
    ///   - context: The optional context snapshot associated with this request.
    ///   - continuity: Optional fixed-schema session continuity metadata.
    public init(
        request: String,
        context: MacContextSnapshot?,
        continuity: AgentContinuityPromptContext? = nil
    ) {
        self.request = request
        self.context = context
        self.continuity = continuity
    }
}

/// The advisory origin role attached to every outbound ACP prompt block.
public enum AgentPromptBlockRole: String, Equatable, Sendable {
    /// A client or configured system instruction.
    case instruction
    /// Reserved for a future continuity block.
    case continuity
    /// The structured, untrusted Mac-context JSON snapshot.
    case macContext = "mac_context"
    /// A resource link captured from the Mac context snapshot.
    case macResource = "mac_resource"
    /// The untouched recognized request.
    case request
}

/// One typed ACP prompt block before it is serialized to the protocol wire.
public enum AgentPromptContent: Equatable, Sendable {
    /// Text content annotated with its protocol origin role.
    case text(role: AgentPromptBlockRole, value: String)
    /// A resource link annotated with its protocol origin role.
    case resourceLink(role: AgentPromptBlockRole, uri: String, name: String)
}
