// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationCore

final class ConversationStartGate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)

    func wait() {
        semaphore.wait()
    }

    func release() {
        semaphore.signal()
    }
}

@MainActor
final class FakeSpeechSession: SpeechSessionProtocol {
    private(set) var mode: SpeechSessionMode?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var contextualStrings: [String] = []
    private var handler: ((SpeechUpdate) -> Void)?
    private var interruptionHandler: (() -> Void)?
    private var retiredHandlers: [(SpeechUpdate) -> Void] = []
    private var failingMode: SpeechSessionMode?
    private var conversationStartGate: ConversationStartGate?

    func start(
        mode: SpeechSessionMode,
        localeID: String,
        contextualStrings: [String],
        onUpdate: @escaping (SpeechUpdate) -> Void,
        onInterruption: @escaping () -> Void) throws
    {
        if failingMode == mode {
            failingMode = nil
            throw FakeSpeechSessionError.startFailed
        }
        startCount += 1
        self.mode = mode
        self.contextualStrings = contextualStrings
        handler = onUpdate
        interruptionHandler = onInterruption
        if mode == .conversation, let conversationStartGate {
            self.conversationStartGate = nil
            conversationStartGate.wait()
        }
    }

    func stop() {
        stopCount += 1
        mode = nil
        if let handler {
            retiredHandlers.append(handler)
        }
        handler = nil
        interruptionHandler = nil
    }

    func emit(_ transcript: String, isFinal: Bool = false) {
        handler?(SpeechUpdate(transcript: transcript, isFinal: isFinal, errorDescription: nil))
    }

    func emitError(_ description: String) {
        handler?(SpeechUpdate(transcript: "", isFinal: false, errorDescription: description))
    }

    func interrupt() {
        interruptionHandler?()
    }

    func emitFromRetiredSession(_ transcript: String, isFinal: Bool = false) {
        retiredHandlers.last?(
            SpeechUpdate(transcript: transcript, isFinal: isFinal, errorDescription: nil))
    }

    func failNextStart(for mode: SpeechSessionMode) {
        failingMode = mode
    }

    func blockNextConversationStart(using gate: ConversationStartGate) {
        conversationStartGate = gate
    }
}

enum FakeSpeechSessionError: Error {
    case startFailed
}

actor RecordingCommandRunner: CommandRunning {
    private(set) var transcripts: [String] = []
    private(set) var templates: [CommandTemplate] = []

    func run(template: CommandTemplate, transcript: String) async throws -> CommandResult {
        templates.append(template)
        transcripts.append(transcript)
        return CommandResult(terminationStatus: 0)
    }

    func recordedTranscripts() -> [String] {
        transcripts
    }

    func recordedTemplates() -> [CommandTemplate] {
        templates
    }
}

actor ControlledCommandRunner: CommandRunning {
    private var transcripts: [String] = []
    private var continuations: [CheckedContinuation<CommandResult, Never>] = []

    func run(template: CommandTemplate, transcript: String) async throws -> CommandResult {
        transcripts.append(transcript)
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func recordedTranscripts() -> [String] {
        transcripts
    }

    func completeNext() {
        continuations.removeFirst().resume(returning: CommandResult(terminationStatus: 0))
    }
}

actor ControlledAgentRunner: AgentHarnessRunning {
    struct Invocation: Equatable, Sendable {
        let profileID: UUID
        let configuration: AgentHarnessConfiguration
        let prompt: AgentPrompt
        let restorationNeed: AgentSessionRestorationNeed
        let runContinuity: AgentRunContinuityRequest
    }

    struct PermissionResolution: Equatable, Sendable {
        let turnToken: AgentTurnToken
        let requestID: ACPRequestID
        let optionID: String?
    }

    private(set) var cancelCount = 0
    private(set) var shutdownCount = 0
    private var runAttempts = 0
    private var invocations: [Invocation] = []
    private var permissionResolutions: [PermissionResolution] = []
    private var eventHandlers: [@Sendable (AgentRunStreamEvent) async -> Void] = []
    private var completions: [CheckedContinuation<AgentRunResult, any Error>?] = []
    private var invocationWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var activeRunIndex: Int?
    private var delaysCancellation = false
    private var completesImmediately = false
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
    private var preClaimGate: AgentRunnerPreClaimGate?
    private var postClaimBarrier: AgentRunnerActorBarrier?

    func run(
        admission: AgentRunAdmission,
        profileID: UUID,
        configuration: AgentHarnessConfiguration,
        prompt: AgentPrompt,
        restorationNeed: AgentSessionRestorationNeed,
        runContinuity: AgentRunContinuityRequest,
        onEvent: @escaping @Sendable (AgentRunStreamEvent) async -> Void
    ) async throws -> AgentRunResult {
        if let preClaimGate {
            self.preClaimGate = nil
            await preClaimGate.waitBeforeClaim()
        }
        guard admission.claim() else { throw CancellationError() }
        if let postClaimBarrier {
            postClaimBarrier.block()
            self.postClaimBarrier = nil
        }
        runAttempts += 1
        guard activeRunIndex == nil else {
            throw ControlledAgentRunnerError.turnAlreadyActive
        }

        let runIndex = invocations.count
        invocations.append(Invocation(
            profileID: profileID,
            configuration: configuration,
            prompt: prompt,
            restorationNeed: restorationNeed,
            runContinuity: runContinuity))
        resumeInvocationWaiters()
        eventHandlers.append(onEvent)
        activeRunIndex = runIndex
        if completesImmediately {
            activeRunIndex = nil
            return AgentRunResult(stopReason: .endTurn)
        }
        return try await withCheckedThrowingContinuation { continuation in
            completions.append(continuation)
        }
    }

    func resolvePermission(
        turnToken: AgentTurnToken,
        requestID: ACPRequestID,
        optionID: String?) async
    {
        permissionResolutions.append(PermissionResolution(
            turnToken: turnToken,
            requestID: requestID,
            optionID: optionID))
    }

    func cancel() async {
        cancelCount += 1
        if delaysCancellation {
            await withCheckedContinuation { continuation in
                cancellationWaiters.append(continuation)
            }
        }
        activeRunIndex = nil
    }

    func reset(profileIDs: Set<UUID>) async {}

    func shutdown() async {
        shutdownCount += 1
        activeRunIndex = nil
    }

    func recordedInvocations() -> [Invocation] {
        invocations
    }

    func waitForInvocationCount(_ count: Int) async {
        guard invocations.count < count else { return }
        await withCheckedContinuation { continuation in
            invocationWaiters.append((count, continuation))
        }
    }

    func recordedRunAttemptCount() -> Int {
        runAttempts
    }

    func recordedPermissionResolutions() -> [PermissionResolution] {
        permissionResolutions
    }

    func delayCancellation() {
        delaysCancellation = true
    }

    func completeRunsImmediately() {
        completesImmediately = true
    }

    func blockBeforeAdmissionClaim(using gate: AgentRunnerPreClaimGate) {
        preClaimGate = gate
    }

    func blockAfterAdmissionClaim(using barrier: AgentRunnerActorBarrier) {
        postClaimBarrier = barrier
    }

    func releaseCancellation() {
        delaysCancellation = false
        let waiters = cancellationWaiters
        cancellationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func emit(_ event: AgentRunEvent, from runIndex: Int) async {
        await eventHandlers[runIndex](.live(event))
    }

    func emitStream(_ event: AgentRunStreamEvent, from runIndex: Int) async {
        await eventHandlers[runIndex](event)
    }

    private func resumeInvocationWaiters() {
        var remaining: [(Int, CheckedContinuation<Void, Never>)] = []
        for (count, continuation) in invocationWaiters {
            if invocations.count >= count {
                continuation.resume()
            } else {
                remaining.append((count, continuation))
            }
        }
        invocationWaiters = remaining
    }

    func complete(
        runIndex: Int,
        stopReason: AgentStopReason = .endTurn)
    {
        let continuation = completions[runIndex]
        completions[runIndex] = nil
        if activeRunIndex == runIndex {
            activeRunIndex = nil
        }
        continuation?.resume(returning: AgentRunResult(stopReason: stopReason))
    }

    func fail(runIndex: Int, error: any Error) {
        let continuation = completions[runIndex]
        completions[runIndex] = nil
        if activeRunIndex == runIndex {
            activeRunIndex = nil
        }
        continuation?.resume(throwing: error)
    }
}

enum ControlledAgentRunnerError: Error, LocalizedError {
    case turnAlreadyActive
    case runFailed

    var errorDescription: String? {
        switch self {
        case .turnAlreadyActive:
            "Another fake agent turn is already active."
        case .runFailed:
            "The fake agent run failed."
        }
    }
}

@MainActor
final class ControlledMacContextCapturer: MacContextCapturing {
    private struct SuspendedCapture {
        let snapshot: MacContextSnapshot
        let continuation: CheckedContinuation<MacContextSnapshot, Never>
    }

    var target: MacContextTarget?
    var nextSnapshot: MacContextSnapshot?
    var suspendsCaptures = false
    var resolvesCancellation = true
    var onCaptureCancellation: (@Sendable (Int) -> Void)?
    private(set) var currentTargetCallCount = 0
    private(set) var capturedTargets: [MacContextTarget] = []
    private(set) var cancelledCaptureIndices: [Int] = []
    private var suspendedCaptures: [Int: SuspendedCapture] = [:]

    init(target: MacContextTarget? = nil, snapshot: MacContextSnapshot? = nil) {
        self.target = target
        nextSnapshot = snapshot
    }

    func currentTarget() -> MacContextTarget? {
        currentTargetCallCount += 1
        return target
    }

    func capture(_ target: MacContextTarget) async -> MacContextSnapshot {
        let captureIndex = capturedTargets.count
        capturedTargets.append(target)
        let frozenSnapshot = nextSnapshot ?? makeMacContextSnapshot(
            target: target,
            state: .targetUnavailable)
        let onCaptureCancellation = onCaptureCancellation
        guard suspendsCaptures else { return frozenSnapshot }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                suspendedCaptures[captureIndex] = SuspendedCapture(
                    snapshot: frozenSnapshot,
                    continuation: continuation)
            }
        } onCancel: {
            onCaptureCancellation?(captureIndex)
            Task { @MainActor [weak self] in
                self?.cancelCapture(at: captureIndex)
            }
        }
    }

    func completeCapture(at index: Int, with snapshot: MacContextSnapshot? = nil) {
        guard let capture = suspendedCaptures.removeValue(forKey: index) else { return }
        capture.continuation.resume(returning: snapshot ?? capture.snapshot)
    }

    private func cancelCapture(at index: Int) {
        cancelledCaptureIndices.append(index)
        guard resolvesCancellation else { return }
        completeCapture(at: index)
    }
}

actor AgentRunnerPreClaimGate {
    private var didReachPreClaim = false
    private var isOpen = false
    private var reachObservers: [CheckedContinuation<Void, Never>] = []
    private var claimWaiters: [CheckedContinuation<Void, Never>] = []

    func waitBeforeClaim() async {
        didReachPreClaim = true
        let observers = reachObservers
        reachObservers.removeAll()
        for observer in observers {
            observer.resume()
        }
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            claimWaiters.append(continuation)
        }
    }

    func waitUntilRunReachedPreClaim() async {
        guard !didReachPreClaim else { return }
        await withCheckedContinuation { continuation in
            reachObservers.append(continuation)
        }
    }

    func releaseClaim() {
        isOpen = true
        let waiters = claimWaiters
        claimWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

final class AgentRunnerActorBarrier: @unchecked Sendable {
    private let condition = NSCondition()
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private var entered = false

    func block() {
        condition.lock()
        entered = true
        condition.broadcast()
        condition.unlock()
        releaseSemaphore.wait()
    }

    func isEntered() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        return entered
    }

    func release() {
        releaseSemaphore.signal()
    }
}

final class ContextCancellationOwnershipProbe: @unchecked Sendable {
    struct Observation: Equatable {
        let captureIndex: Int
        let hasActiveInput: Bool
        let pendingInputCount: Int
        let executionGeneration: Int
    }

    private let lock = NSLock()
    private var values: [Observation] = []

    func append(_ observation: Observation) {
        lock.lock()
        values.append(observation)
        lock.unlock()
    }

    func observations() -> [Observation] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

func makeMacContextSnapshot(
    target: MacContextTarget,
    state: MacContextCaptureState = .complete,
    selectedText: String? = nil
) -> MacContextSnapshot {
    MacContextSnapshot.normalized(
        state: state,
        target: target,
        windowTitle: nil,
        documentURL: nil,
        selectedText: selectedText,
        resources: [])
}

func makeAgentConfiguration(
    displayName: String = "Codex",
    workingDirectory: String = "/tmp") throws -> AgentHarnessConfiguration
{
    try AgentHarnessConfiguration(
        preset: .codex,
        displayName: displayName,
        executablePath: "/usr/bin/env",
        arguments: ["agent"],
        workingDirectory: workingDirectory,
        permissionPolicy: .ask)
}

func makeAgentProfile(
    id: UUID = UUID(),
    wakePhrase: String = "agent",
    displayName: String = "Codex",
    accent: WakeProfileAccent = .purple) throws -> WakeProfile
{
    try WakeProfile(
        id: id,
        wakePhrase: wakePhrase,
        action: .agent(try makeAgentConfiguration(displayName: displayName)),
        accent: accent)
}

@Suite(.serialized)
struct VoiceActivationCoordinatorTests {
}
