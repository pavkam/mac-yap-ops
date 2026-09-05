// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

/// The semantic operation represented by an ACP tool call.
public enum AgentToolKind: String, Codable, Equatable, Sendable {
    /// Reads data without modifying it.
    case read
    /// Modifies existing content.
    case edit
    /// Removes content or resources.
    case delete
    /// Moves or renames content.
    case move
    /// Searches local or remote data.
    case search
    /// Executes a command or program.
    case execute
    /// Performs agent reasoning without an external operation.
    case think
    /// Retrieves a remote resource.
    case fetch
    /// Changes the harness operating mode.
    case switchMode = "switch_mode"
    /// Represents an operation not covered by the known ACP kinds.
    case other
}

/// The lifecycle state reported for an ACP tool call.
public enum AgentToolCallStatus: String, Codable, Equatable, Sendable {
    /// The call has been proposed but has not started.
    case pending
    /// The call is currently executing.
    case inProgress = "in_progress"
    /// The call finished successfully.
    case completed
    /// The call finished unsuccessfully.
    case failed
}

/// The retained body of a result artifact produced by an ACP agent.
public enum AgentArtifactPayload: Equatable, Sendable {
    /// Inline image bytes with their required media type.
    case image(data: Data, mimeType: String)
    /// Inline UTF-8 resource text.
    case embeddedText(String)
    /// Inline binary resource bytes.
    case embeddedBlob(Data)
    /// A resource referenced only by its URI.
    case linked
}

/// A bounded file, image, or document result produced by an ACP agent.
public struct AgentArtifact: Equatable, Sendable {
    /// The provider-supplied resource URI, when one exists.
    public let uri: String?
    /// The bounded display and materialization name.
    public let name: String
    /// An optional bounded user-facing title.
    public let title: String?
    /// Optional bounded descriptive text supplied for the result.
    public let descriptiveText: String?
    /// The declared media type, when supplied.
    public let mimeType: String?
    /// The provider-declared byte size, when supplied.
    public let declaredSize: UInt64?
    /// The retained inline or linked payload.
    public let payload: AgentArtifactPayload

    /// Creates a bounded agent result artifact.
    ///
    /// - Parameters:
    ///   - uri: The optional provider-supplied URI.
    ///   - name: The display and materialization name.
    ///   - title: An optional user-facing title.
    ///   - descriptiveText: Optional descriptive text.
    ///   - mimeType: The optional declared media type.
    ///   - declaredSize: The optional provider-declared size.
    ///   - payload: The retained inline or linked payload.
    public init(
        uri: String?,
        name: String,
        title: String?,
        descriptiveText: String?,
        mimeType: String?,
        declaredSize: UInt64?,
        payload: AgentArtifactPayload)
    {
        self.uri = uri
        self.name = name
        self.title = title
        self.descriptiveText = descriptiveText
        self.mimeType = mimeType
        self.declaredSize = declaredSize
        self.payload = payload
    }
}

/// User-presentable content attached to an ACP tool call.
public enum AgentToolCallContent: Equatable, Sendable {
    /// A regular text result.
    case text(String)
    /// A file, image, or document result.
    case artifact(AgentArtifact)
}

enum AgentArtifactLimits {
    static let maximumURIBytes = 4 * 1_024
    static let maximumMIMETypeBytes = 256
    static let maximumDisplayTextBytes = 8 * 1_024
    static let maximumEmbeddedPayloadBytes = 768 * 1_024
}

/// The initial description of an ACP tool call.
public struct AgentToolCall: Equatable, Sendable {
    /// The bounded opaque identifier used to correlate updates.
    public let id: String
    /// The short human-readable operation title.
    public let title: String
    /// The semantic operation kind, when supplied by the harness.
    public let kind: AgentToolKind?
    /// The initial lifecycle state, when supplied by the harness.
    public let status: AgentToolCallStatus?
    /// Ordered user-presentable results supplied with the call.
    public let content: [AgentToolCallContent]

    /// Creates an initial tool-call description.
    ///
    /// - Parameters:
    ///   - id: The opaque correlation identifier.
    ///   - title: The human-readable operation title.
    ///   - kind: The semantic operation kind.
    ///   - status: The initial lifecycle state.
    ///   - content: Ordered user-presentable results supplied with the call.
    public init(
        id: String,
        title: String,
        kind: AgentToolKind? = nil,
        status: AgentToolCallStatus? = nil,
        content: [AgentToolCallContent] = [])
    {
        self.id = id
        self.title = title
        self.kind = kind
        self.status = status
        self.content = content
    }
}

/// A partial lifecycle update for an existing ACP tool call.
public struct AgentToolCallUpdate: Equatable, Sendable {
    /// The bounded opaque identifier of the existing call.
    public let id: String
    /// A replacement title, when the harness changed it.
    public let title: String?
    /// A replacement semantic kind, when supplied.
    public let kind: AgentToolKind?
    /// A replacement lifecycle state, when supplied.
    public let status: AgentToolCallStatus?
    /// Ordered user-presentable results supplied with the update.
    public let content: [AgentToolCallContent]

    /// Creates a partial tool-call update.
    ///
    /// - Parameters:
    ///   - id: The opaque correlation identifier.
    ///   - title: An optional replacement title.
    ///   - kind: An optional replacement semantic kind.
    ///   - status: An optional replacement lifecycle state.
    ///   - content: Ordered user-presentable results supplied with the update.
    public init(
        id: String,
        title: String? = nil,
        kind: AgentToolKind? = nil,
        status: AgentToolCallStatus? = nil,
        content: [AgentToolCallContent] = [])
    {
        self.id = id
        self.title = title
        self.kind = kind
        self.status = status
        self.content = content
    }
}

/// The relative importance assigned to an ACP plan entry.
public enum AgentPlanPriority: String, Codable, Equatable, Sendable {
    /// Work that should be handled first.
    case high
    /// Normally ordered work.
    case medium
    /// Deferrable or lower-impact work.
    case low
}

/// The lifecycle state of one ACP plan entry.
public enum AgentPlanStatus: String, Codable, Equatable, Sendable {
    /// The plan item has not started.
    case pending
    /// The plan item is currently active.
    case inProgress = "in_progress"
    /// The plan item finished.
    case completed
}

/// One user-presentable entry in the agent's current plan.
public struct AgentPlanEntry: Equatable, Sendable {
    /// The concise action described by the agent.
    public let content: String
    /// The entry's relative priority.
    public let priority: AgentPlanPriority
    /// The entry's current lifecycle state.
    public let status: AgentPlanStatus

    /// Creates a plan entry.
    ///
    /// - Parameters:
    ///   - content: The concise planned action.
    ///   - priority: The relative importance of the action.
    ///   - status: The current lifecycle state.
    public init(content: String, priority: AgentPlanPriority, status: AgentPlanStatus) {
        self.content = content
        self.priority = priority
        self.status = status
    }
}

/// The semantic effect of an option in an ACP permission request.
public enum AgentPermissionOptionKind: String, Codable, Equatable, Sendable {
    /// Allows only the current operation.
    case allowOnce = "allow_once"
    /// Allows this and matching future operations.
    case allowAlways = "allow_always"
    /// Rejects only the current operation.
    case rejectOnce = "reject_once"
    /// Rejects this and matching future operations.
    case rejectAlways = "reject_always"
}

/// One selectable response offered by an ACP permission request.
public struct AgentPermissionOption: Equatable, Sendable {
    /// The opaque option identifier returned to the harness.
    public let id: String
    /// The user-visible option label.
    public let label: String
    /// The semantic effect used for automatic and spoken selection.
    public let kind: AgentPermissionOptionKind

    /// Creates a permission option.
    ///
    /// - Parameters:
    ///   - id: The opaque identifier returned to the harness.
    ///   - label: The user-visible label.
    ///   - kind: The semantic permission effect.
    public init(id: String, label: String, kind: AgentPermissionOptionKind) {
        self.id = id
        self.label = label
        self.kind = kind
    }
}

/// A permission decision requested by the harness during an active turn.
public struct AgentPermissionRequest: Equatable, Sendable {
    /// The local turn identity that prevents stale responses crossing turns.
    public let turnToken: AgentTurnToken
    /// The JSON-RPC request identifier used for the response.
    public let requestID: ACPRequestID
    /// The operation for which permission is requested.
    public let toolCall: AgentToolCallUpdate
    /// The nonempty choices accepted by the harness.
    public let options: [AgentPermissionOption]

    /// Creates a permission request bound to one local turn.
    ///
    /// - Parameters:
    ///   - turnToken: The local turn identity.
    ///   - requestID: The JSON-RPC request identifier.
    ///   - toolCall: The operation awaiting permission.
    ///   - options: The choices accepted by the harness.
    public init(
        turnToken: AgentTurnToken,
        requestID: ACPRequestID,
        toolCall: AgentToolCallUpdate,
        options: [AgentPermissionOption])
    {
        self.turnToken = turnToken
        self.requestID = requestID
        self.toolCall = toolCall
        self.options = options
    }
}

/// The bounded event channel whose data was discarded under backpressure.
public enum AgentRunEventDeliveryNoticeKind: Equatable, Sendable {
    /// User-visible agent output was truncated.
    case outputTruncated
    /// File, image, or document results were discarded under pressure.
    case artifactTruncated
    /// Diagnostic-only output was truncated.
    case diagnosticTruncated
    /// Control events were truncated and the turn can no longer proceed safely.
    case controlTruncated
}

/// A synthesized event describing bounded event-delivery loss.
public struct AgentRunEventDeliveryNotice: Equatable, Sendable {
    /// The channel whose data was discarded.
    public let kind: AgentRunEventDeliveryNoticeKind
    /// The total UTF-8 payload bytes discarded.
    public let discardedBytes: UInt64
    /// The total event entries discarded.
    public let discardedEntries: UInt64

    /// Creates a delivery-loss notice.
    ///
    /// - Parameters:
    ///   - kind: The affected event channel.
    ///   - discardedBytes: The number of discarded UTF-8 bytes.
    ///   - discardedEntries: The number of discarded event entries.
    public init(
        kind: AgentRunEventDeliveryNoticeKind,
        discardedBytes: UInt64,
        discardedEntries: UInt64)
    {
        self.kind = kind
        self.discardedBytes = discardedBytes
        self.discardedEntries = discardedEntries
    }
}

/// Stable metadata discriminators synthesized by the local runner.
public enum AgentRunMetadataKind {
    /// Indicates that an unavailable remote session was replaced transparently.
    public static let sessionRecovered = "session_recovered"
}

/// An ordered, bounded event emitted while an ACP turn runs.
public enum AgentRunEvent: Equatable, Sendable {
    /// The ACP connection completed initialization and opened a session.
    case connected(agentName: String, sessionID: String)
    /// A streaming fragment of user-visible Markdown from the agent.
    case agentMessageDelta(messageID: String?, text: String)
    /// A streaming fragment of agent reasoning that may be collapsed in the UI.
    case thoughtDelta(messageID: String?, text: String)
    /// A file, image, or document result produced by the agent.
    case artifact(AgentArtifact)
    /// A newly announced tool call.
    case toolCall(AgentToolCall)
    /// A partial update for an existing tool call.
    case toolCallUpdate(AgentToolCallUpdate)
    /// The latest complete plan snapshot.
    case plan([AgentPlanEntry])
    /// Concise protocol or runner metadata.
    case metadata(kind: String, summary: String)
    /// Bounded diagnostic text suitable for an expandable detail view.
    case diagnostic(String)
    /// A permission request that blocks the current agent operation.
    case permissionRequested(AgentPermissionRequest)
    /// A valid but unsupported ACP update retained as a bounded summary.
    case unknown(discriminator: String, summary: String)
    /// A synthesized warning that event delivery discarded bounded data.
    case deliveryNotice(AgentRunEventDeliveryNotice)
}
