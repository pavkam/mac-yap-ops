// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

/// An opaque, provider-owned session reference retained for one wake profile.
///
/// The bookmark deliberately contains identifiers and a compatibility fingerprint
/// only; it never stores conversation content or provider authorization.
public struct AgentSessionBookmark: Codable, Equatable, Sendable {
    /// The wake profile that owns the provider session.
    public let profileID: UUID
    /// The opaque provider session identifier.
    public let sessionID: String
    /// The versioned fingerprint of session-defining provider configuration.
    public let providerFingerprint: String
    /// The monotonic local ordinal used by storage for least-recently-used eviction.
    public let lastAccessOrdinal: UInt64

    /// Creates an opaque session bookmark for a compatible provider configuration.
    public init(
        profileID: UUID,
        sessionID: String,
        providerFingerprint: String,
        lastAccessOrdinal: UInt64
    ) {
        self.profileID = profileID
        self.sessionID = sessionID
        self.providerFingerprint = providerFingerprint
        self.lastAccessOrdinal = lastAccessOrdinal
    }
}

/// The durable local state of work that may have been interrupted by process exit.
public enum AgentInterruptedWorkState: String, Codable, Equatable, Sendable {
    /// The prompt or provider task was active when the local process last persisted it.
    case active
    /// The local process exited before it observed a terminal result.
    case interruptedByProcessExit
}

/// Uniquely identifies one local lifecycle for opaque provider work.
public struct AgentInterruptedWorkKey: Codable, Hashable, Sendable {
    /// The wake profile that owns the work.
    public let profileID: UUID
    /// The opaque provider session identifier.
    public let sessionID: String
    /// A fresh local identity that prevents provider task-ID reuse from merging work.
    public let occurrenceID: UUID

    /// Creates a unique key for one local work lifecycle.
    public init(profileID: UUID, sessionID: String, occurrenceID: UUID) {
        self.profileID = profileID
        self.sessionID = sessionID
        self.occurrenceID = occurrenceID
    }
}

/// Identifier-only durable metadata for one ordinary prompt or provider task.
public struct AgentInterruptedWorkMarker: Codable, Equatable, Sendable {
    /// The exact local lifecycle represented by this marker.
    public let key: AgentInterruptedWorkKey
    /// The opaque provider turn identifier, if the provider supplied one.
    public let turnID: String?
    /// The opaque provider task identifier, if this work is provider-managed.
    public let providerTaskID: String?
    /// The local lifecycle state observed by YapOps.
    public let state: AgentInterruptedWorkState

    /// Creates identifier-only metadata for potentially interrupted work.
    public init(
        key: AgentInterruptedWorkKey,
        turnID: String? = nil,
        providerTaskID: String? = nil,
        state: AgentInterruptedWorkState
    ) {
        self.key = key
        self.turnID = turnID
        self.providerTaskID = providerTaskID
        self.state = state
    }
}

/// The versioned, identifier-only continuity state persisted for all profiles.
///
/// Storage owns validation, bounds, and atomic updates. This value only groups
/// bookmarks and interrupted-work markers without retaining conversation content.
public struct AgentContinuityEnvelope: Codable, Equatable, Sendable {
    /// The persistence schema version used to validate this envelope.
    public let schemaVersion: Int
    /// The persisted bookmarks, mutable only for storage's bounded replacement policy.
    public var bookmarks: [AgentSessionBookmark]
    /// The persisted interrupted-work markers, mutable only for storage reconciliation.
    public var interruptedWork: [AgentInterruptedWorkMarker]

    /// Creates a versioned identifier-only continuity envelope.
    public init(
        schemaVersion: Int,
        bookmarks: [AgentSessionBookmark],
        interruptedWork: [AgentInterruptedWorkMarker]
    ) {
        self.schemaVersion = schemaVersion
        self.bookmarks = bookmarks
        self.interruptedWork = interruptedWork
    }
}

/// The optional restoration methods advertised by an ACP agent at initialization.
public struct ACPSessionRestorationCapabilities: Equatable, Sendable {
    /// Whether the agent supports `session/load` and its visible-history replay.
    public let loadSession: Bool
    /// Whether the agent supports `session/resume` without historical replay.
    public let resumeSession: Bool

    /// Creates a capability value from already validated runtime advertisement fields.
    public init(loadSession: Bool, resumeSession: Bool) {
        self.loadSession = loadSession
        self.resumeSession = resumeSession
    }

    /// Strictly decodes the `initialize` result's optional `agentCapabilities` object.
    ///
    /// An absent or `null` capabilities object, field, or `resume` field is
    /// unsupported. `loadSession` must be Boolean when present. Both
    /// `sessionCapabilities` and its present `resume` member must be JSON objects.
    /// - Parameter value: The optional `agentCapabilities` value from `initialize`.
    /// - Returns: The advertised restoration support, with omitted methods disabled.
    /// - Throws: ``ACPClientError/malformedResponse(_:)`` for malformed shapes.
    public static func decode(from value: ACPJSONValue?) throws -> Self {
        guard let value, value != .null else {
            return Self(loadSession: false, resumeSession: false)
        }
        guard case .object(let capabilities) = value else {
            throw ACPClientError.malformedResponse("Invalid agentCapabilities.")
        }

        let loadSession: Bool
        switch capabilities["loadSession"] {
        case nil, .null:
            loadSession = false
        case .bool(let advertised):
            loadSession = advertised
        default:
            throw ACPClientError.malformedResponse("Invalid agentCapabilities.loadSession.")
        }

        let resumeSession: Bool
        switch capabilities["sessionCapabilities"] {
        case nil, .null:
            resumeSession = false
        case .object(let sessionCapabilities):
            switch sessionCapabilities["resume"] {
            case nil, .null:
                resumeSession = false
            case .object:
                resumeSession = true
            default:
                throw ACPClientError.malformedResponse(
                    "Invalid agentCapabilities.sessionCapabilities.resume.")
            }
        default:
            throw ACPClientError.malformedResponse("Invalid agentCapabilities.sessionCapabilities.")
        }

        return Self(loadSession: loadSession, resumeSession: resumeSession)
    }
}

/// The caller's restoration goal before a new prompt is sent.
public enum AgentSessionRestorationNeed: Equatable, Sendable {
    /// Rebuild the visible conversation panel from provider replay when possible.
    case visibleHistory
    /// Continue provider-owned context without presenting historical replay.
    case contextOnly
}

/// The completed session activation path for a provider session.
public enum AgentSessionActivation: Equatable, Sendable {
    /// A newly created provider session.
    case new(sessionID: String)
    /// An existing provider session loaded with visible replay.
    case loaded(sessionID: String)
    /// An existing provider session resumed without visible replay.
    case resumed(sessionID: String)
    /// A fresh session opened after the saved session was unavailable.
    case freshAfterUnavailableBookmark(sessionID: String)
    /// A fresh session opened because the agent advertised no restoration method.
    case freshBecauseRestorationUnsupported(sessionID: String)
}

/// The deterministic provider operation selected for one restoration attempt.
public enum AgentSessionRestorationOperation: Equatable, Sendable {
    /// Load the session and deliver its bounded replay to visible history.
    case load
    /// Load the session only to retain context, discarding its bounded replay.
    case loadDiscardingReplay
    /// Resume provider-owned context without historical replay.
    case resume
    /// Create a fresh provider session without attempting restoration.
    case new
}

/// The fixed-schema continuity state that may accompany a newly published prompt.
public enum AgentContinuityPromptSessionState: String, Codable, Equatable, Sendable {
    /// The prior session was loaded with visible replay.
    case loaded
    /// The prior session resumed but cannot supply local history.
    case resumedWithoutHistory = "resumed_without_history"
    /// A saved session was unavailable and was replaced before prompt publication.
    case freshAfterUnavailableBookmark = "fresh_after_unavailable_bookmark"
    /// The agent did not advertise any supported restoration method.
    case freshBecauseRestorationUnsupported = "fresh_because_restoration_unsupported"
}

/// Bounded, identifier-free continuity state supplied to a provider with a new prompt.
public struct AgentContinuityPromptContext: Codable, Equatable, Sendable {
    /// The only schema emitted for continuity prompt metadata.
    public static let schemaIdentifier = "yapops.agent-continuity.v1"
    /// The maximum encoded UTF-8 size of one continuity metadata block.
    public static let maximumEncodedBytes = 512

    /// The fixed schema identifier for this compact context block.
    public let schema: String
    /// The session activation state visible to the provider.
    ///
    /// A normal new session has no restoration state, so interruption-only metadata
    /// encodes this field as JSON `null` instead of inventing a semantic state.
    public let sessionState: AgentContinuityPromptSessionState?
    /// Whether the previous locally active turn ended with process exit.
    public let previousTurnInterrupted: Bool

    /// Creates fixed-schema continuity metadata without conversation content.
    public init(
        sessionState: AgentContinuityPromptSessionState,
        previousTurnInterrupted: Bool
    ) {
        self.init(
            validatedSessionState: sessionState,
            previousTurnInterrupted: previousTurnInterrupted)
    }

    /// Creates honest interruption metadata for a normal new or live-cached session.
    ///
    /// This is the only public construction path whose encoded `sessionState` is `null`.
    public static func previousTurnInterruptedInNormalSession() -> Self {
        Self(
            validatedSessionState: nil,
            previousTurnInterrupted: true)
    }

    private init(
        validatedSessionState: AgentContinuityPromptSessionState?,
        previousTurnInterrupted: Bool
    ) {
        schema = Self.schemaIdentifier
        sessionState = validatedSessionState
        self.previousTurnInterrupted = previousTurnInterrupted
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case sessionState
        case previousTurnInterrupted
    }

    /// Encodes all three fixed fields, using `null` for a normal interruption-only state.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(sessionState, forKey: .sessionState)
        try container.encode(previousTurnInterrupted, forKey: .previousTurnInterrupted)
    }

    /// Decodes fixed-schema identifier-free continuity metadata.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchema = try container.decode(String.self, forKey: .schema)
        guard decodedSchema == Self.schemaIdentifier else {
            throw DecodingError.dataCorruptedError(
                forKey: .schema,
                in: container,
                debugDescription: "Unsupported agent continuity prompt schema")
        }
        schema = decodedSchema
        guard container.contains(.sessionState) else {
            throw DecodingError.keyNotFound(
                CodingKeys.sessionState,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Missing agent continuity session state"))
        }
        let decodedSessionState = try container.decodeIfPresent(
            AgentContinuityPromptSessionState.self,
            forKey: .sessionState)
        let decodedPreviousTurnInterrupted = try container.decode(
            Bool.self,
            forKey: .previousTurnInterrupted)
        guard decodedSessionState != nil || decodedPreviousTurnInterrupted else {
            throw DecodingError.dataCorruptedError(
                forKey: .sessionState,
                in: container,
                debugDescription: "A normal session requires interrupted previous work")
        }
        sessionState = decodedSessionState
        previousTurnInterrupted = decodedPreviousTurnInterrupted
    }
}

/// Consume-on-publication interruption metadata supplied by the App lifecycle owner.
///
/// The value carries exact identifier-only markers transiently. Provider-managed task
/// markers are excluded so session prompting cannot acknowledge another feature's work.
public struct AgentRunContinuityRequest: Equatable, Sendable {
    /// Whether the next successfully published prompt should report an interrupted turn.
    public let previousTurnInterrupted: Bool
    /// Exact ordinary-turn keys eligible for acknowledgement after frame publication.
    public let ordinaryInterruptedWorkKeys: Set<AgentInterruptedWorkKey>
    private let onPublishedAcknowledgement:
        (@Sendable (Set<AgentInterruptedWorkKey>) async -> Void)?

    /// Creates a request by accepting only reconciled ordinary-turn markers.
    ///
    /// - Parameters:
    ///   - previousTurnInterrupted: Whether interruption metadata should be emitted.
    ///   - interruptedWork: Reconciled markers owned by the selected profile.
    ///   - onPublishedAcknowledgement: Consumes exact ordinary markers only after the
    ///     runner has published the prompt frame and persisted their acknowledgement.
    public init(
        previousTurnInterrupted: Bool = false,
        interruptedWork: [AgentInterruptedWorkMarker] = [],
        onPublishedAcknowledgement:
            (@Sendable (Set<AgentInterruptedWorkKey>) async -> Void)? = nil
    ) {
        self.previousTurnInterrupted = previousTurnInterrupted
        ordinaryInterruptedWorkKeys = Set(interruptedWork.lazy.filter {
            $0.state == .interruptedByProcessExit && $0.providerTaskID == nil
        }.map(\.key))
        self.onPublishedAcknowledgement = onPublishedAcknowledgement
    }

    /// Confirms the exact eligible markers durably acknowledged after prompt publication.
    ///
    /// Keys not carried by this request are ignored, keeping callbacks profile- and
    /// occurrence-qualified even when a caller is stale.
    public func confirmPublishedAcknowledgement(
        _ keys: Set<AgentInterruptedWorkKey>
    ) async {
        let eligible = keys.intersection(ordinaryInterruptedWorkKeys)
        guard !eligible.isEmpty else { return }
        await onPublishedAcknowledgement?(eligible)
    }

    /// Compares only interruption metadata; acknowledgement callback identity is operational.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.previousTurnInterrupted == rhs.previousTurnInterrupted
            && lhs.ordinaryInterruptedWorkKeys == rhs.ordinaryInterruptedWorkKeys
    }
}

/// A caller-owned identity that prevents stale restoration callbacks from mutating a run.
///
/// Establish the token before connecting, then compare it again after every
/// suspension before applying replay to mutable state.
public struct AgentRestorationToken: Hashable, Sendable {
    /// The unique local restoration identity.
    public let rawValue: UUID

    /// Creates a restoration token from a caller-supplied unique identity.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    /// Creates a fresh restoration token.
    public init() {
        rawValue = UUID()
    }
}

/// An ordered event tagged by whether it belongs to provider history or live work.
public enum AgentRunStreamEvent: Equatable, Sendable {
    /// A compatible restoration attempt began for an opaque provider session.
    case restorationStarted(token: AgentRestorationToken, sessionID: String)
    /// A bounded event replayed from the restoring provider session.
    case restored(token: AgentRestorationToken, event: AgentRunEvent)
    /// A restoration attempt completed with its selected session activation.
    case restorationCompleted(token: AgentRestorationToken, activation: AgentSessionActivation)
    /// A restoration attempt ended before it could complete safely.
    case restorationAborted(token: AgentRestorationToken)
    /// An event emitted by the current live prompt.
    case live(AgentRunEvent)
}
