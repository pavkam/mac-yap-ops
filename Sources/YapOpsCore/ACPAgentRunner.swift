// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

/// A replaceable asynchronous delay source used by runner deadlines and tests.
public protocol ACPAgentRunnerClock: Sendable {
    /// Suspends for the supplied logical duration.
    ///
    /// - Parameter duration: The amount of time to wait.
    func sleep(for duration: Duration) async
}

/// The production runner clock backed by Swift's monotonic continuous clock.
public struct ContinuousACPAgentRunnerClock: ACPAgentRunnerClock, Sendable {
    /// Creates a monotonic runner clock.
    public init() {}

    /// Suspends for the requested duration unless the surrounding task ends first.
    ///
    /// - Parameter duration: The amount of time to wait.
    public func sleep(for duration: Duration) async {
        try? await ContinuousClock().sleep(for: duration)
    }
}

struct ACPAgentRunnerTestingHooks: Sendable {
    let beforeCancelledExitWaitReturns: @Sendable () async -> Void
    let afterPromptResponseBeforeDeliveryDrain: @Sendable () async -> Void
    let beforeSuccessIsPublished: @Sendable () async -> Void
    let beforeMidTurnOfferCompletion: @Sendable () async -> Void

    init(
        beforeCancelledExitWaitReturns: @escaping @Sendable () async -> Void = {},
        afterPromptResponseBeforeDeliveryDrain: @escaping @Sendable () async -> Void = {},
        beforeSuccessIsPublished: @escaping @Sendable () async -> Void = {},
        beforeMidTurnOfferCompletion: @escaping @Sendable () async -> Void = {}
    ) {
        self.beforeCancelledExitWaitReturns = beforeCancelledExitWaitReturns
        self.afterPromptResponseBeforeDeliveryDrain = afterPromptResponseBeforeDeliveryDrain
        self.beforeSuccessIsPublished = beforeSuccessIsPublished
        self.beforeMidTurnOfferCompletion = beforeMidTurnOfferCompletion
    }
}

/// Owns bounded reusable ACP processes and serializes their active turns.
public actor ACPAgentRunner: AgentHarnessRunning {
    /// The maximum retained standard-error tail for failed harness diagnostics.
    public static let maximumStandardErrorBytes = 16 * 1_024
    /// The maximum number of idle profile sessions retained simultaneously.
    public static let maximumCachedSessions = 4

    static let maximumTrackedSessionEvictions = 64
    static let sessionRecoveryNotice =
        "The previous agent session was unavailable, so a fresh session was started."
    static let sessionEvictionNotice =
        "This profile's previous agent session was released to keep resource use bounded, "
        + "so a fresh session was started."
    static let startupRecoveryNotice =
        "Agent startup stalled, so a fresh connection was started."

    static let connectionStartupTimeout = Duration.seconds(12)
    static let cancellationGracePeriod = Duration.seconds(2)
    static let exitDrainGracePeriod = Duration.milliseconds(500)
    static let promptSettlePeriod = Duration.milliseconds(25)

    let transportFactory: any ACPTransportCreating
    let continuityStore: any AgentContinuityStoring
    let clock: any ACPAgentRunnerClock
    let startupClock: any ACPAgentRunnerClock
    let drainClock: any ACPAgentRunnerClock
    let settleClock: any ACPAgentRunnerClock
    let testingHooks: ACPAgentRunnerTestingHooks
    let diagnostics: any YapOpsDiagnosticRecording
    var records: [UUID: ACPAgentConnectionRecord] = [:]
    var activeTurn: ACPAgentActiveTurn?
    var isShutDown = false
    var latestAccessOrdinal: UInt64 = 0
    var evictedProfileIDs: [UUID] = []
    var sessionEventHandler:
        (@Sendable (AgentSessionEventEnvelope) async -> Void)?

    /// Creates an ACP runner with replaceable transport, timing, and diagnostics boundaries.
    ///
    /// - Parameters:
    ///   - transportFactory: Creates one process transport per fresh session.
    ///   - continuityStore: Retains bounded identifier-only session continuity.
    ///   - clock: Controls cancellation deadlines.
    ///   - drainClock: Controls post-exit stream draining.
    ///   - settleClock: Controls the short successful-prompt process-settlement window.
    ///   - diagnostics: Records privacy-safe lifecycle metadata.
    public init(
        transportFactory: any ACPTransportCreating = ACPProcessTransportFactory(),
        continuityStore: any AgentContinuityStoring = InMemoryAgentContinuityStore(),
        clock: any ACPAgentRunnerClock = ContinuousACPAgentRunnerClock(),
        drainClock: any ACPAgentRunnerClock = ContinuousACPAgentRunnerClock(),
        settleClock: any ACPAgentRunnerClock = ContinuousACPAgentRunnerClock(),
        diagnostics: any YapOpsDiagnosticRecording = YapOpsDiagnostics.shared
    ) {
        self.transportFactory = transportFactory
        self.continuityStore = continuityStore
        self.clock = clock
        startupClock = ContinuousACPAgentRunnerClock()
        self.drainClock = drainClock
        self.settleClock = settleClock
        testingHooks = ACPAgentRunnerTestingHooks()
        self.diagnostics = diagnostics
    }

    init(
        transportFactory: any ACPTransportCreating = ACPProcessTransportFactory(),
        continuityStore: any AgentContinuityStoring = InMemoryAgentContinuityStore(),
        clock: any ACPAgentRunnerClock = ContinuousACPAgentRunnerClock(),
        startupClock: any ACPAgentRunnerClock = ContinuousACPAgentRunnerClock(),
        drainClock: any ACPAgentRunnerClock = ContinuousACPAgentRunnerClock(),
        settleClock: any ACPAgentRunnerClock = ContinuousACPAgentRunnerClock(),
        testingHooks: ACPAgentRunnerTestingHooks,
        diagnostics: any YapOpsDiagnosticRecording = YapOpsDiagnostics.shared
    ) {
        self.transportFactory = transportFactory
        self.continuityStore = continuityStore
        self.clock = clock
        self.startupClock = startupClock
        self.drainClock = drainClock
        self.settleClock = settleClock
        self.testingHooks = testingHooks
        self.diagnostics = diagnostics
    }

    /// Runs a prompt in a fresh or retained profile session, recovering stale sessions once.
    ///
    /// - Parameters:
    ///   - admission: The single-use gate claimed before any runner side effect.
    ///   - profileID: The owner of the reusable ACP session.
    ///   - configuration: The validated process and permission configuration.
    ///   - prompt: The typed request and optional Mac context sent to the harness.
    ///   - restorationNeed: Whether to start fresh or restore provider context and history.
    ///   - runContinuity: Consume-on-publication interrupted-work metadata.
    ///   - onEvent: Receives ordered source-qualified stream events.
    /// - Returns: The terminal result reported by the harness.
    /// - Throws: ``ACPAgentRunnerError`` or an underlying transport/protocol error.
    public func run(
        admission: AgentRunAdmission,
        profileID: UUID,
        configuration: AgentHarnessConfiguration,
        prompt: AgentPrompt,
        restorationNeed: AgentSessionRestorationNeed,
        runContinuity: AgentRunContinuityRequest,
        onEvent: @escaping @Sendable (AgentRunStreamEvent) async -> Void
    ) async throws
        -> AgentRunResult
    {
        guard admission.claim() else { throw CancellationError() }
        guard !isShutDown else {
            diagnostics.record(
                category: .agent,
                event: "acp_runner.run_rejected",
                fields: ["reason": "shut_down"])
            throw ACPAgentRunnerError.shutDown
        }
        guard activeTurn == nil else {
            diagnostics.record(
                category: .agent,
                event: "acp_runner.run_rejected",
                fields: ["reason": "turn_already_active"])
            throw ACPAgentRunnerError.turnAlreadyActive
        }

        let token = UUID()
        let startedAtUptime = DispatchTime.now().uptimeNanoseconds
        diagnostics.record(
            category: .agent,
            event: "acp_runner.run_started",
            fields: [
                "turn_id": token.uuidString,
                "profile_id": profileID.uuidString,
                "request_byte_count": String(prompt.request.utf8.count),
                "cached_session_count": String(records.count),
                "task_priority": String(Task.currentPriority.rawValue),
            ])
        let completion = ACPAgentRunCompletionLatch()
        let delivery = AgentRunEventDelivery { [diagnostics] event in
            let deliveryStartedAtUptime = DispatchTime.now().uptimeNanoseconds
            diagnostics.record(
                category: .agent,
                event: "acp_runner.delivery_handler_started",
                level: .debug,
                fields: [
                    "turn_id": token.uuidString,
                    "event_kind": event.runnerDiagnosticName,
                    "task_priority": String(Task.currentPriority.rawValue),
                ])
            await onEvent(.live(event))
            diagnostics.record(
                category: .agent,
                event: "acp_runner.delivery_handler_finished",
                level: .debug,
                fields: [
                    "turn_id": token.uuidString,
                    "event_kind": event.runnerDiagnosticName,
                    "duration_ms": String(
                        Self.elapsedMilliseconds(since: deliveryStartedAtUptime)),
                    "task_priority": String(Task.currentPriority.rawValue),
                ])
        }
        activeTurn = ACPAgentActiveTurn(
            token: token,
            profileID: profileID,
            recordID: nil,
            connection: nil,
            completion: completion,
            delivery: delivery,
            streamEventHandler: onEvent,
            isCancelling: false,
            deliveryOverflowed: false,
            restorationToken: nil,
            restorationRecordID: nil,
            connectionAttemptUsedRestoration: false)

        var runRecord: ACPAgentConnectionRecord?
        var didAttemptSessionRecovery = false
        var didAttemptStartupRecovery = false
        var shouldPublishSessionRecoveryNotice = false
        var shouldPublishStartupRecoveryNotice = false
        var skipBookmarkForNextConnection = false
        var freshAfterUnavailableBookmark = false
        do {
            while true {
                let acquisition: ACPAgentConnectionAcquisition
                do {
                    acquisition = try await connectionRecord(
                        profileID: profileID,
                        configuration: configuration,
                        restorationNeed: restorationNeed,
                        turnToken: token,
                        skipBookmark: skipBookmarkForNextConnection,
                        freshAfterUnavailableBookmark: freshAfterUnavailableBookmark,
                        onEvent: onEvent)
                    skipBookmarkForNextConnection = false
                    freshAfterUnavailableBookmark = false
                } catch let error as ACPClientError {
                    let usedRestoration = activeTurn?.token == token
                        && activeTurn?.connectionAttemptUsedRestoration == true
                    let permitsFreshFallback = error.isSessionUnavailable
                        || error == .eventDeliveryOverflow
                    guard usedRestoration,
                          permitsFreshFallback,
                          !didAttemptSessionRecovery,
                          !skipBookmarkForNextConnection,
                          ownsActiveTurn(token),
                          !isActiveTurnCancelling(token)
                    else { throw error }
                    didAttemptSessionRecovery = true
                    await removeContinuityRecords(profileIDs: [profileID])
                    try ensureActiveTurn(token: token)
                    skipBookmarkForNextConnection = true
                    freshAfterUnavailableBookmark = true
                    shouldPublishSessionRecoveryNotice = true
                    continue
                } catch let error as ACPAgentRunnerError {
                    guard error == .startupTimedOut,
                        !didAttemptStartupRecovery,
                        ownsActiveTurn(token),
                        !isActiveTurnCancelling(token)
                    else {
                        throw error
                    }
                    didAttemptStartupRecovery = true
                    let restorationTimedOut = activeTurn?.token == token
                        && activeTurn?.connectionAttemptUsedRestoration == true
                    if restorationTimedOut {
                        await removeContinuityRecords(profileIDs: [profileID])
                        try ensureActiveTurn(token: token)
                        skipBookmarkForNextConnection = true
                        freshAfterUnavailableBookmark = true
                    }
                    shouldPublishStartupRecoveryNotice = true
                    diagnostics.record(
                        category: .agent,
                        event: "acp_runner.startup_recovery_started",
                        level: .warning,
                        fields: [
                            "turn_id": token.uuidString,
                            "profile_id": profileID.uuidString,
                        ])
                    continue
                }
                let record = acquisition.record
                runRecord = record
                guard ownsActiveTurn(token),
                    !isActiveTurnCancelling(token),
                    activeTurn?.deliveryOverflowed == false
                else {
                    if activeTurn?.token == token, activeTurn?.deliveryOverflowed == true {
                        throw ACPAgentRunnerError.eventDeliveryOverflow
                    }
                    throw ACPAgentRunnerError.cancelled
                }
                guard let connection = record.connection else {
                    throw ACPClientError.connectionClosed
                }
                updateActiveTurn(token: token, record: record, connection: connection)
                let recordID = record.id
                if shouldPublishStartupRecoveryNotice {
                    try publishSessionNotice(
                        Self.startupRecoveryNotice,
                        turnToken: token)
                    shouldPublishStartupRecoveryNotice = false
                } else if shouldPublishSessionRecoveryNotice {
                    try publishSessionNotice(
                        Self.sessionRecoveryNotice,
                        turnToken: token)
                    shouldPublishSessionRecoveryNotice = false
                } else if evictedProfileIDs.contains(profileID) {
                    try publishSessionNotice(
                        Self.sessionEvictionNotice,
                        turnToken: token)
                    evictedProfileIDs.removeAll { $0 == profileID }
                }

                let continuity = continuityContext(
                    activation: acquisition.activation,
                    previousTurnInterrupted: runContinuity.previousTurnInterrupted)
                let composedPrompt = AgentPrompt(
                    request: prompt.request,
                    context: prompt.context,
                    continuity: continuity)
                guard let activatedSessionID = record.sessionID else {
                    throw ACPClientError.malformedResponse("The session is not initialized.")
                }
                let workKey = AgentInterruptedWorkKey(
                    profileID: profileID,
                    sessionID: activatedSessionID,
                    occurrenceID: UUID())
                let publicationState = ACPAgentPromptPublicationState()
                let publicationHooks = ACPClientPromptPublicationHooks(
                    beforePublication: { [weak self] in
                        guard let self else { throw ACPAgentRunnerError.cancelled }
                        try await self.preparePromptPublication(
                            key: workKey,
                            turnToken: token,
                            profileID: profileID,
                            recordID: recordID)
                        publicationState.markMarkerWritten()
                    },
                    afterPublication: { [weak self] in
                        publicationState.markFramePublished()
                        let acknowledged = await self?.confirmPromptPublication(
                            turnToken: token,
                            profileID: profileID,
                            recordID: recordID,
                            acknowledgementKeys: runContinuity.ordinaryInterruptedWorkKeys) ?? []
                        await runContinuity.confirmPublishedAcknowledgement(acknowledged)
                    })

                let result: AgentRunResult
                do {
                    result = try await connection.prompt(
                        composedPrompt,
                        publicationHooks: publicationHooks
                    ) { [weak self] event in
                        await self?.forward(
                            event: event,
                            turnToken: token,
                            profileID: profileID,
                            recordID: recordID)
                    }
                } catch let error as ACPClientError {
                    await clearWorkIfPromptWasNotPublished(
                        key: workKey,
                        state: publicationState)
                    guard !didAttemptSessionRecovery,
                        !publicationState.snapshot().frameWasPublished,
                        error.isSessionUnavailable,
                        ownsActiveTurn(token),
                        !isActiveTurnCancelling(token)
                    else {
                        throw error
                    }

                    didAttemptSessionRecovery = true
                    diagnostics.record(
                        category: .agent,
                        event: "acp_runner.session_recovery_started",
                        level: .warning,
                        fields: [
                            "turn_id": token.uuidString,
                            "profile_id": profileID.uuidString,
                            "record_id": recordID.uuidString,
                        ])
                    await discardRecord(
                        profileID: profileID,
                        recordID: recordID,
                        fallbackRecord: record)
                    await removeContinuityRecords(profileIDs: [profileID])
                    runRecord = nil
                    clearActiveTurnConnection(token: token)
                    try ensureActiveTurn(token: token)
                    skipBookmarkForNextConnection = true
                    freshAfterUnavailableBookmark = true
                    shouldPublishSessionRecoveryNotice = true
                    continue
                }
                if isActiveTurnCancelling(token), result.stopReason != .cancelled {
                    throw ACPClientError.malformedResponse(
                        "A cancelled prompt returned a non-cancelled stopReason.")
                }

                await testingHooks.afterPromptResponseBeforeDeliveryDrain()

                if await processExitWasObservedDuringPromptSettlement(record: record) {
                    _ = await record.exitTask?.result
                }

                await delivery.finish(.drain)
                guard activeTurn?.token == token else {
                    throw ACPAgentRunnerError.cancelled
                }
                guard activeTurn?.deliveryOverflowed == false else {
                    throw ACPAgentRunnerError.eventDeliveryOverflow
                }
                await testingHooks.beforeSuccessIsPublished()
                guard activeTurn?.token == token else {
                    throw ACPAgentRunnerError.cancelled
                }
                guard activeTurn?.deliveryOverflowed == false else {
                    throw ACPAgentRunnerError.eventDeliveryOverflow
                }
                if isActiveTurnCancelling(token), result.stopReason != .cancelled {
                    throw ACPAgentRunnerError.cancelled
                }
                await clearSettledWork(workKey)
                guard activeTurn?.token == token else {
                    throw ACPAgentRunnerError.cancelled
                }
                if isActiveTurnCancelling(token), result.stopReason != .cancelled {
                    throw ACPAgentRunnerError.cancelled
                }
                clearActiveTurn(token: token)
                await completion.resolve(.success(result))
                diagnostics.record(
                    category: .agent,
                    event: "acp_runner.run_finished",
                    fields: [
                        "turn_id": token.uuidString,
                        "profile_id": profileID.uuidString,
                        "stop_reason": result.stopReason.rawValue,
                        "duration_ms": String(
                            Self.elapsedMilliseconds(
                                since: startedAtUptime)),
                    ])
                return result
            }
        } catch {
            let reportedError: any Error =
                activeTurn?.token == token
                    && activeTurn?.deliveryOverflowed == true
                ? ACPAgentRunnerError.eventDeliveryOverflow
                : error
            if let runRecord, runRecord.exitStatus != nil {
                _ = await runRecord.exitTask?.result
            }
            await delivery.finish(.drain)
            await completion.resolve(.failure)
            if let runRecord {
                await discardRecord(
                    profileID: profileID,
                    recordID: runRecord.id,
                    fallbackRecord: runRecord)
            }
            clearActiveTurn(token: token)
            diagnostics.record(
                category: .agent,
                event: "acp_runner.run_failed",
                level: reportedError is CancellationError ? .info : .error,
                fields: [
                    "turn_id": token.uuidString,
                    "profile_id": profileID.uuidString,
                    "duration_ms": String(Self.elapsedMilliseconds(since: startedAtUptime)),
                    "error_type": String(describing: type(of: reportedError)),
                ])
            throw reportedError
        }
    }

    /// Answers a permission request only when it belongs to the active turn.
    ///
    /// - Parameters:
    ///   - turnToken: The local identity of the requesting turn.
    ///   - requestID: The JSON-RPC request identifier.
    ///   - optionID: The selected option, or `nil` to cancel the request.
    public func resolvePermission(
        turnToken: AgentTurnToken,
        requestID: ACPRequestID,
        optionID: String?
    ) async {
        guard let connection = activeTurn?.connection else {
            diagnostics.record(
                category: .agent,
                event: "acp_runner.permission_ignored",
                fields: ["reason": "no_connection"])
            return
        }
        diagnostics.record(
            category: .agent,
            event: "acp_runner.permission_resolving",
            fields: ["has_option": String(optionID != nil)])
        await connection.resolvePermission(
            turnToken: turnToken,
            requestID: requestID,
            optionID: optionID)
    }

    /// Requests cooperative cancellation, then evicts an unresponsive process after a deadline.
    public func cancel() async {
        guard var turn = activeTurn, !turn.isCancelling else {
            diagnostics.record(
                category: .agent,
                event: "acp_runner.cancel_ignored",
                fields: ["reason": "no_turn_or_already_cancelling"])
            return
        }
        diagnostics.record(
            category: .agent,
            event: "acp_runner.cancel_started",
            fields: [
                "turn_id": turn.token.uuidString,
                "profile_id": turn.profileID.uuidString,
                "has_connection": String(turn.connection != nil),
            ])
        turn.isCancelling = true
        let restorationToken = turn.restorationToken
        turn.restorationToken = nil
        turn.restorationRecordID = nil
        activeTurn = turn
        if let restorationToken {
            await turn.streamEventHandler(.restorationAborted(token: restorationToken))
        }

        let token = turn.token
        let profileID = turn.profileID
        let capturedRecordID = turn.recordID
        let completion = turn.completion
        if let connection = turn.connection {
            Task {
                await connection.cancel()
            }
        }

        var outcome = await raceCancellation(completion: completion)
        if case .deadline = outcome, let completed = await completion.completedValue() {
            outcome = .completion(completed)
        }

        if case .completion(.success(let result)) = outcome,
            result.stopReason == .cancelled
        {
            diagnostics.record(
                category: .agent,
                event: "acp_runner.cancel_finished",
                fields: [
                    "turn_id": token.uuidString,
                    "outcome": "cooperative",
                ])
            return
        }

        if await preserveBackgroundSessionAfterPromptCancellation(
            token, profileID, capturedRecordID) { return }

        diagnostics.record(
            category: .agent,
            event: "acp_runner.cancel_forcing_eviction",
            level: .warning,
            fields: ["turn_id": token.uuidString])
        await forceEvictActiveRecord(
            turnToken: token,
            profileID: profileID,
            capturedRecordID: capturedRecordID)
    }

    /// Discards cached sessions whose profile configuration changed or was removed.
    ///
    /// - Parameter profileIDs: The profile identities to invalidate.
    public func reset(profileIDs: Set<UUID>) async {
        diagnostics.record(
            category: .agent,
            event: "acp_runner.reset_started",
            fields: ["profile_count": String(profileIDs.count)])
        var removed: [ACPAgentConnectionRecord] = []
        var discardedDelivery: AgentRunEventDelivery?
        var abortedRestoration: (
            AgentRestorationToken,
            @Sendable (AgentRunStreamEvent) async -> Void)?
        if let turn = activeTurn, profileIDs.contains(turn.profileID) {
            discardedDelivery = turn.delivery
            if let token = turn.restorationToken {
                abortedRestoration = (token, turn.streamEventHandler)
            }
            activeTurn = nil
        }
        for profileID in profileIDs {
            guard let record = records.removeValue(forKey: profileID) else {
                continue
            }
            removed.append(record)
        }
        evictedProfileIDs.removeAll { profileIDs.contains($0) }

        if let (token, handler) = abortedRestoration {
            await handler(.restorationAborted(token: token))
        }
        await discardedDelivery?.finish(.discard)

        for record in removed {
            await dispose(record)
        }
        await removeContinuityRecords(profileIDs: profileIDs)
        diagnostics.record(
            category: .agent,
            event: "acp_runner.reset_finished",
            fields: ["disposed_session_count": String(removed.count)])
    }

    /// Permanently stops the runner and disposes every active or cached process.
    public func shutdown() async {
        guard !isShutDown else {
            diagnostics.record(category: .agent, event: "acp_runner.shutdown_ignored")
            return
        }
        diagnostics.record(
            category: .agent,
            event: "acp_runner.shutdown_started",
            fields: ["cached_session_count": String(records.count)])
        isShutDown = true
        sessionEventHandler = nil

        if let turn = activeTurn {
            activeTurn = nil
            if let token = turn.restorationToken {
                await turn.streamEventHandler(.restorationAborted(token: token))
            }
            await turn.delivery.finish(.discard)
            if let connection = turn.connection {
                Task {
                    await connection.cancel()
                }
            }
        }

        let cachedRecords = Array(records.values)
        records.removeAll()
        evictedProfileIDs.removeAll()
        for record in cachedRecords {
            await dispose(record)
        }
        diagnostics.record(
            category: .agent,
            event: "acp_runner.shutdown_finished",
            fields: ["disposed_session_count": String(cachedRecords.count)])
    }
}
