// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import YapOpsCore

private actor DeliveryEventRecorder {
    private var events: [AgentRunEvent] = []

    func record(_ event: AgentRunEvent) {
        events.append(event)
    }

    func recordedEvents() -> [AgentRunEvent] {
        events
    }
}

private actor DeliveryHandlerGate {
    private var didEnter = false
    private var isOpen = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        didEnter = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }

        guard !isOpen else {
            return
        }
        await withCheckedContinuation { continuation in
            openWaiters.append(continuation)
        }
    }

    func waitUntilEntered() async {
        guard !didEnter else {
            return
        }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let waiters = openWaiters
        openWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private actor DeliveryCompletionProbe {
    private var didComplete = false

    func complete() {
        didComplete = true
    }

    func completed() -> Bool {
        didComplete
    }
}

private actor DeliveryPriorityRecorder {
    private var priority: TaskPriority?
    private var waiters: [CheckedContinuation<TaskPriority, Never>] = []

    func record(_ priority: TaskPriority) {
        self.priority = priority
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: priority)
        }
    }

    func next() async -> TaskPriority {
        if let priority {
            return priority
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private final class DeliveryRetentionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var delivery: AgentRunEventDelivery?

    func retain(_ delivery: AgentRunEventDelivery) {
        lock.withLock {
            self.delivery = delivery
        }
    }

    func take() -> AgentRunEventDelivery? {
        lock.withLock {
            let delivery = self.delivery
            self.delivery = nil
            return delivery
        }
    }
}

private enum StagedNormalizationOverflowFixture: CaseIterable, Sendable {
    case output
    case diagnostic
    case control

    var event: AgentRunEvent {
        switch self {
        case .output:
            .agentMessageDelta(
                messageID: "message",
                text: String(
                    repeating: "o",
                    count: AgentRunEventDelivery.maximumPendingOutputBytes + 1))
        case .diagnostic:
            .diagnostic(String(
                repeating: "d",
                count: AgentRunEventDelivery.maximumPendingDiagnosticBytes + 1))
        case .control:
            .metadata(
                kind: "",
                summary: String(repeating: "c", count: 64 * 1_024 + 1))
        }
    }
}

@Suite(.serialized)
struct AgentRunEventDeliveryTests {
    @Test func send_WhenConsumerStartsPaused_AdmitsExactlyTheEntryLimit() async {
        let recorder = DeliveryEventRecorder()
        let delivery = AgentRunEventDelivery(
            mode: .staged,
            handler: { event in await recorder.record(event) })

        for index in 0..<AgentRunEventDelivery.maximumPendingEntries {
            #expect(delivery.send(.metadata(kind: "control", summary: "\(index)")) == .accepted)
        }
        let beforeOverflow = delivery.snapshotForTesting
        #expect(beforeOverflow.pendingEntryCount == 256)
        #expect(await recorder.recordedEvents().isEmpty)

        #expect(delivery.send(.metadata(kind: "control", summary: "overflow")) == .capacityExceeded)
        let afterOverflow = delivery.snapshotForTesting
        #expect(afterOverflow.state == .draining)
        #expect(afterOverflow.pendingOutputBytes == beforeOverflow.pendingOutputBytes)
        #expect(afterOverflow.pendingDiagnosticBytes == beforeOverflow.pendingDiagnosticBytes)
        #expect(afterOverflow.pendingControlBytes == beforeOverflow.pendingControlBytes)
        #expect(afterOverflow.pendingEntryCount == beforeOverflow.pendingEntryCount)
        #expect(afterOverflow.discardedOutputBytes == beforeOverflow.discardedOutputBytes)
        #expect(afterOverflow.discardedOutputEntries == beforeOverflow.discardedOutputEntries)
        #expect(afterOverflow.discardedDiagnosticBytes == beforeOverflow.discardedDiagnosticBytes)
        await delivery.finish(.discard)
    }

    @Test func send_WhenConsumerStartsPaused_AdmitsExactlyTheControlByteLimit() async {
        let delivery = AgentRunEventDelivery(mode: .staged) { _ in }
        let chunk = String(repeating: "c", count: 64 * 1_024)

        for _ in 0..<8 {
            #expect(delivery.send(.metadata(kind: "", summary: chunk)) == .accepted)
        }
        let beforeOverflow = delivery.snapshotForTesting
        #expect(beforeOverflow.pendingControlBytes == 512 * 1_024)
        #expect(beforeOverflow.pendingEntryCount == 8)

        #expect(delivery.send(.metadata(kind: "", summary: "x")) == .capacityExceeded)
        let afterOverflow = delivery.snapshotForTesting
        #expect(afterOverflow.pendingControlBytes == beforeOverflow.pendingControlBytes)
        #expect(afterOverflow.pendingEntryCount == beforeOverflow.pendingEntryCount)
        await delivery.finish(.discard)
    }

    @Test func send_WhenConsumerStartsPaused_HoldsExactOutputBoundUntilActivated() async {
        let recorder = DeliveryEventRecorder()
        let delivery = AgentRunEventDelivery(
            mode: .staged,
            handler: { event in await recorder.record(event) })
        let output = String(repeating: "x", count: 512 * 1_024)

        #expect(delivery.send(.agentMessageDelta(messageID: "message", text: output)) == .accepted)
        #expect(delivery.snapshotForTesting.pendingOutputBytes == 512 * 1_024)
        #expect(delivery.snapshotForTesting.pendingEntryCount == 1)
        #expect(await recorder.recordedEvents().isEmpty)

        let beforeOverflow = delivery.snapshotForTesting
        #expect(delivery.send(.agentMessageDelta(messageID: "message", text: "x")) == .capacityExceeded)
        let afterOverflow = delivery.snapshotForTesting
        #expect(afterOverflow.state == .draining)
        #expect(afterOverflow.pendingOutputBytes == beforeOverflow.pendingOutputBytes)
        #expect(afterOverflow.pendingDiagnosticBytes == beforeOverflow.pendingDiagnosticBytes)
        #expect(afterOverflow.pendingControlBytes == beforeOverflow.pendingControlBytes)
        #expect(afterOverflow.pendingEntryCount == beforeOverflow.pendingEntryCount)
        #expect(afterOverflow.discardedOutputBytes == beforeOverflow.discardedOutputBytes)
        #expect(afterOverflow.discardedOutputEntries == beforeOverflow.discardedOutputEntries)
        #expect(afterOverflow.discardedDiagnosticBytes == beforeOverflow.discardedDiagnosticBytes)
        #expect(await recorder.recordedEvents().isEmpty)

        delivery.startConsuming()
        await delivery.finish(.drain)
        #expect(await recorder.recordedEvents() == [
            .agentMessageDelta(messageID: "message", text: output),
        ])
    }

    @Test func send_WhenStagedDiagnosticsCoalesce_AdmitsExactlySixteenKiB() async {
        let recorder = DeliveryEventRecorder()
        let delivery = AgentRunEventDelivery(
            mode: .staged,
            handler: { event in await recorder.record(event) })
        let half = String(repeating: "d", count: 8 * 1_024)

        #expect(delivery.send(.diagnostic(half)) == .accepted)
        #expect(delivery.send(.diagnostic(half)) == .accepted)
        let beforeOverflow = delivery.snapshotForTesting
        #expect(beforeOverflow.pendingDiagnosticBytes == 16 * 1_024)
        #expect(beforeOverflow.pendingEntryCount == 1)
        #expect(await recorder.recordedEvents().isEmpty)

        #expect(delivery.send(.diagnostic("x")) == .capacityExceeded)
        let afterOverflow = delivery.snapshotForTesting
        #expect(afterOverflow.state == .draining)
        #expect(afterOverflow.pendingOutputBytes == beforeOverflow.pendingOutputBytes)
        #expect(afterOverflow.pendingDiagnosticBytes == beforeOverflow.pendingDiagnosticBytes)
        #expect(afterOverflow.pendingControlBytes == beforeOverflow.pendingControlBytes)
        #expect(afterOverflow.pendingEntryCount == beforeOverflow.pendingEntryCount)
        #expect(afterOverflow.discardedOutputBytes == beforeOverflow.discardedOutputBytes)
        #expect(afterOverflow.discardedOutputEntries == beforeOverflow.discardedOutputEntries)
        #expect(afterOverflow.discardedDiagnosticBytes == beforeOverflow.discardedDiagnosticBytes)
        #expect(await recorder.recordedEvents().isEmpty)

        delivery.startConsuming()
        await delivery.finish(.drain)
        #expect(await recorder.recordedEvents() == [
            .diagnostic(half + half),
        ])
    }

    @Test(arguments: StagedNormalizationOverflowFixture.allCases)
    fileprivate func send_WhenStagedNormalizationWouldDiscardPayload_RejectsAtomically(
        fixture: StagedNormalizationOverflowFixture
    ) async {
        let recorder = DeliveryEventRecorder()
        let delivery = AgentRunEventDelivery(
            mode: .staged,
            handler: { delivered in await recorder.record(delivered) })
        let beforeOverflow = delivery.snapshotForTesting

        #expect(delivery.send(fixture.event) == .capacityExceeded)
        let afterOverflow = delivery.snapshotForTesting
        #expect(afterOverflow.state == .draining)
        #expect(afterOverflow.pendingOutputBytes == beforeOverflow.pendingOutputBytes)
        #expect(afterOverflow.pendingDiagnosticBytes == beforeOverflow.pendingDiagnosticBytes)
        #expect(afterOverflow.pendingControlBytes == beforeOverflow.pendingControlBytes)
        #expect(afterOverflow.pendingEntryCount == beforeOverflow.pendingEntryCount)
        #expect(afterOverflow.discardedOutputBytes == beforeOverflow.discardedOutputBytes)
        #expect(afterOverflow.discardedOutputEntries == beforeOverflow.discardedOutputEntries)
        #expect(afterOverflow.discardedDiagnosticBytes == beforeOverflow.discardedDiagnosticBytes)
        delivery.startConsuming()
        await delivery.finish(.drain)
        #expect(await recorder.recordedEvents().isEmpty)
    }

    @Test func send_WhenCreatedFromBackgroundCallback_DeliversAtUserInitiatedPriority() async {
        let recorder = DeliveryPriorityRecorder()
        let retention = DeliveryRetentionBox()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .background).async {
                let delivery = AgentRunEventDelivery { _ in
                    await recorder.record(Task.currentPriority)
                }
                retention.retain(delivery)
                _ = delivery.send(.connected(agentName: "Agent", sessionID: "session"))
                continuation.resume()
            }
        }

        let priority = await recorder.next()
        #expect(priority.rawValue >= TaskPriority.userInitiated.rawValue)

        await retention.take()?.finish(.discard)
    }

    @Test func send_WhenHandlerIsStalled_KeepsTenThousandDeltasWithinEveryBound() async {
        let gate = DeliveryHandlerGate()
        let delivery = AgentRunEventDelivery { _ in await gate.wait() }

        #expect(delivery.send(.connected(agentName: "Agent", sessionID: "session")) == .accepted)
        await gate.waitUntilEntered()
        for _ in 0..<10_000 {
            #expect(delivery.send(.agentMessageDelta(messageID: "message", text: "x")) == .accepted)
            #expect(delivery.send(.agentMessageDelta(messageID: "message", text: "")) == .ignored)
        }

        let snapshot = delivery.snapshotForTesting
        #expect(snapshot.pendingOutputBytes == 10_000)
        #expect(snapshot.pendingDiagnosticBytes == 0)
        #expect(snapshot.pendingControlBytes == "message".utf8.count)
        #expect(snapshot.pendingEntryCount == 1)
        #expect(snapshot.pendingOutputBytes <= AgentRunEventDelivery.maximumPendingOutputBytes)
        #expect(snapshot.pendingDiagnosticBytes <= AgentRunEventDelivery.maximumPendingDiagnosticBytes)
        #expect(snapshot.pendingControlBytes <= AgentRunEventDelivery.maximumPendingControlBytes)
        #expect(snapshot.pendingEntryCount <= AgentRunEventDelivery.maximumPendingEntries)

        await delivery.finish(.discard)
        #expect(delivery.snapshotForTesting.pendingEntryCount == 0)
        await gate.open()
    }

    @Test func send_WhenOneMultibyteDeltaExceedsTheBound_RetainsValidSuffixAfterOneTypedNotice()
        async
    {
        let recorder = DeliveryEventRecorder()
        let delivery = AgentRunEventDelivery { event in await recorder.record(event) }
        let retainedScalarCount = AgentRunEventDelivery.maximumPendingOutputBytes / 4
        let oversized = "prefix" + String(repeating: "🧪", count: retainedScalarCount + 1)

        #expect(delivery.send(.agentMessageDelta(messageID: "message", text: oversized)) == .accepted)
        await delivery.finish(.drain)

        let events = await recorder.recordedEvents()
        #expect(events == [
            .deliveryNotice(AgentRunEventDeliveryNotice(
                kind: .outputTruncated,
                discardedBytes: 10,
                discardedEntries: 0)),
            .agentMessageDelta(
                messageID: "message",
                text: String(repeating: "🧪", count: retainedScalarCount)),
        ])
        guard case let .agentMessageDelta(_, text) = events.last else {
            Issue.record("Expected retained output")
            return
        }
        #expect(String(data: Data(text.utf8), encoding: .utf8) == text)
        #expect(text.utf8.count == AgentRunEventDelivery.maximumPendingOutputBytes)
    }

    @Test func send_WhenDeltaIsExactlyAtTheBound_PreservesItWithoutNotice() async {
        let recorder = DeliveryEventRecorder()
        let delivery = AgentRunEventDelivery { event in await recorder.record(event) }
        let exact = String(
            repeating: "x",
            count: AgentRunEventDelivery.maximumPendingOutputBytes)

        #expect(delivery.send(.thoughtDelta(messageID: nil, text: exact)) == .accepted)
        await delivery.finish(.drain)

        #expect(await recorder.recordedEvents() == [
            .thoughtDelta(messageID: nil, text: exact),
        ])
    }

    @Test func send_WhenCasesAndMessageIdentifiersAlternate_CannotEvadeTheEntryCap() async {
        let gate = DeliveryHandlerGate()
        let delivery = AgentRunEventDelivery { _ in await gate.wait() }
        #expect(delivery.send(.connected(agentName: "Agent", sessionID: "session")) == .accepted)
        await gate.waitUntilEntered()

        for index in 0..<10_000 {
            let event: AgentRunEvent = if index.isMultiple(of: 2) {
                .agentMessageDelta(messageID: "message-\(index)", text: "m")
            } else {
                .thoughtDelta(messageID: "thought-\(index)", text: "t")
            }
            #expect(delivery.send(event) == .accepted)
        }

        let snapshot = delivery.snapshotForTesting
        #expect(snapshot.pendingEntryCount <= AgentRunEventDelivery.maximumPendingEntries)
        #expect(snapshot.pendingOutputBytes <= AgentRunEventDelivery.maximumPendingOutputBytes)
        #expect(snapshot.discardedOutputEntries > 0)
        await delivery.finish(.discard)
        await gate.open()
    }

    @Test func send_WhenControlEventsSeparateMessages_DrainsInExactBarrierOrder() async {
        let recorder = DeliveryEventRecorder()
        let gate = DeliveryHandlerGate()
        let delivery = AgentRunEventDelivery { event in
            await gate.wait()
            await recorder.record(event)
        }
        let turnToken = AgentTurnToken()
        let permission = AgentPermissionRequest(
            turnToken: turnToken,
            requestID: .string("permission"),
            toolCall: AgentToolCallUpdate(id: "tool", title: "Edit"),
            options: [
                AgentPermissionOption(id: "once", label: "Allow once", kind: .allowOnce),
            ])
        let expected: [AgentRunEvent] = [
            .connected(agentName: "Agent", sessionID: "session"),
            .agentMessageDelta(messageID: "first", text: "Hello world"),
            .toolCall(AgentToolCall(id: "tool", title: "Edit")),
            .plan([AgentPlanEntry(content: "Verify", priority: .high, status: .pending)]),
            .permissionRequested(permission),
            .agentMessageDelta(messageID: "second", text: "Done"),
        ]

        #expect(delivery.send(expected[0]) == .accepted)
        await gate.waitUntilEntered()
        #expect(delivery.send(.agentMessageDelta(messageID: "first", text: "Hello")) == .accepted)
        #expect(delivery.send(.agentMessageDelta(messageID: "first", text: " world")) == .accepted)
        for event in expected.dropFirst(2) {
            #expect(delivery.send(event) == .accepted)
        }
        await gate.open()
        await delivery.finish(.drain)

        #expect(await recorder.recordedEvents() == expected)
    }

    @Test func send_WhenToolUpdateContainsArtifact_DeliversStatusThenArtifact() async {
        let recorder = DeliveryEventRecorder()
        let artifact = resultArtifact(index: 1, payloadByteCount: 16)
        let delivery = AgentRunEventDelivery { event in await recorder.record(event) }
        let update = AgentToolCallUpdate(
            id: "render",
            status: .completed,
            content: [.text("Rendered"), .artifact(artifact)])

        #expect(delivery.send(.toolCallUpdate(update)) == .accepted)
        await delivery.finish(.drain)

        #expect(await recorder.recordedEvents() == [
            .toolCallUpdate(AgentToolCallUpdate(
                id: "render",
                status: .completed,
                content: [.text("Rendered")])),
            .artifact(artifact),
        ])
    }

    @Test func send_WhenToolHasThousandsOfTextBlocks_BoundsRenderableEntries() async {
        let recorder = DeliveryEventRecorder()
        let delivery = AgentRunEventDelivery { event in await recorder.record(event) }
        let content = (0..<10_000).map { index in
            AgentToolCallContent.text(index.isMultiple(of: 2) ? "" : "x")
        }

        #expect(delivery.send(.toolCall(AgentToolCall(
            id: "render",
            title: "Render",
            content: content))) == .accepted)
        await delivery.finish(.drain)

        let events = await recorder.recordedEvents()
        guard case let .deliveryNotice(notice) = events.first,
              case let .toolCall(tool) = events.last
        else {
            Issue.record("Expected one bounded tool call and its truncation notice")
            return
        }
        #expect(tool.content.count == 32)
        #expect(tool.content.allSatisfy { $0 == .text("x") })
        #expect(notice.kind == .controlTruncated)
        #expect(notice.discardedEntries == 4_968)
    }

    @Test func send_WhenToolTextBlocksReachByteBudget_BoundsRetainedText() async {
        let recorder = DeliveryEventRecorder()
        let delivery = AgentRunEventDelivery { event in await recorder.record(event) }
        let block = String(repeating: "x", count: 16 * 1_024)

        #expect(delivery.send(.toolCall(AgentToolCall(
            id: "render",
            title: "Render",
            content: Array(repeating: .text(block), count: 40)))) == .accepted)
        await delivery.finish(.drain)

        let events = await recorder.recordedEvents()
        guard case let .toolCall(tool) = events.last else {
            Issue.record("Expected a bounded tool call")
            return
        }
        let retainedBytes = tool.content.reduce(0) { count, item in
            guard case let .text(text) = item else { return count }
            return count + text.utf8.count
        }
        #expect(tool.content.count == 4)
        #expect(retainedBytes == 64 * 1_024)
    }

    @Test func send_WhenArtifactPressureExceedsBound_DiscardsWholeOldestResults() async {
        let recorder = DeliveryEventRecorder()
        let gate = DeliveryHandlerGate()
        let delivery = AgentRunEventDelivery { event in
            await gate.wait()
            await recorder.record(event)
        }
        #expect(delivery.send(.connected(agentName: "Agent", sessionID: "session")) == .accepted)
        await gate.waitUntilEntered()

        for index in 0..<33 {
            #expect(delivery.send(.artifact(resultArtifact(
                index: index,
                payloadByteCount: 160 * 1_024))) == .accepted)
        }

        let snapshot = delivery.snapshotForTesting
        #expect(snapshot.pendingArtifactBytes
            <= AgentRunEventDelivery.maximumPendingArtifactBytes)
        #expect(snapshot.discardedArtifactBytes > 0)
        #expect(snapshot.discardedArtifactEntries > 0)

        await gate.open()
        await delivery.finish(.drain)
        let delivered = await recorder.recordedEvents()
        let artifactNotices = delivered.filter { event in
            guard case let .deliveryNotice(notice) = event else { return false }
            return notice.kind == .artifactTruncated
        }
        let retainedArtifacts = delivered.compactMap { event -> AgentArtifact? in
            guard case let .artifact(artifact) = event else { return nil }
            return artifact
        }
        #expect(artifactNotices.count == 1)
        #expect(retainedArtifacts.count < 33)
        #expect(!retainedArtifacts.contains { $0.uri == "file:///tmp/result-0.png" })
        #expect(retainedArtifacts.allSatisfy { artifact in
            guard case let .image(data, _) = artifact.payload else { return false }
            return data.count == 160 * 1_024
        })
    }

    @Test func send_WhenToolArtifactsAreInterleaved_DoesNotTurnDiscardablePressureFatal()
        async
    {
        let gate = DeliveryHandlerGate()
        let delivery = AgentRunEventDelivery { _ in await gate.wait() }
        #expect(delivery.send(.connected(agentName: "Agent", sessionID: "session")) == .accepted)
        await gate.waitUntilEntered()

        for index in 0..<160 {
            let update = AgentToolCallUpdate(
                id: "tool-\(index)",
                status: .completed,
                content: [.artifact(resultArtifact(index: index, payloadByteCount: 1))])
            #expect(delivery.send(.toolCallUpdate(update)) == .accepted)
        }

        let snapshot = delivery.snapshotForTesting
        #expect(snapshot.state == .open)
        #expect(snapshot.pendingEntryCount <= AgentRunEventDelivery.maximumPendingEntries)
        #expect(snapshot.discardedArtifactEntries > 0)
        await delivery.finish(.discard)
        await gate.open()
    }

    @Test func send_WhenAlternateProducerBuildsOversizedArtifact_RejectsIt() async {
        let delivery = AgentRunEventDelivery { _ in }
        let artifact = resultArtifact(
            index: 1,
            payloadByteCount: AgentArtifactLimits.maximumEmbeddedPayloadBytes + 1)

        #expect(delivery.send(.artifact(artifact)) == .invalid)
        #expect(delivery.snapshotForTesting.pendingArtifactBytes == 0)

        await delivery.finish(.discard)
    }

    @Test func send_WhenControlOnlyReserveFills_FailsExplicitlyAfterAdmittedPrefix() async {
        let recorder = DeliveryEventRecorder()
        let gate = DeliveryHandlerGate()
        let delivery = AgentRunEventDelivery { event in
            await gate.wait()
            await recorder.record(event)
        }
        let first = AgentRunEvent.connected(agentName: "Agent", sessionID: "session")
        #expect(delivery.send(first) == .accepted)
        await gate.waitUntilEntered()

        var admitted: [AgentRunEvent] = [first]
        for index in 0..<AgentRunEventDelivery.maximumPendingEntries {
            let event = AgentRunEvent.metadata(kind: "control", summary: "event-\(index)")
            #expect(delivery.send(event) == .accepted)
            admitted.append(event)
        }
        let beforeOverflow = delivery.snapshotForTesting
        #expect(delivery.send(.metadata(kind: "control", summary: "overflow")) == .capacityExceeded)
        let afterOverflow = delivery.snapshotForTesting
        #expect(afterOverflow.state == .draining)
        #expect(afterOverflow.pendingOutputBytes == beforeOverflow.pendingOutputBytes)
        #expect(afterOverflow.pendingDiagnosticBytes == beforeOverflow.pendingDiagnosticBytes)
        #expect(afterOverflow.pendingControlBytes == beforeOverflow.pendingControlBytes)
        #expect(afterOverflow.pendingEntryCount == beforeOverflow.pendingEntryCount)
        #expect(afterOverflow.discardedOutputBytes == beforeOverflow.discardedOutputBytes)
        #expect(afterOverflow.discardedOutputEntries == beforeOverflow.discardedOutputEntries)
        #expect(afterOverflow.discardedDiagnosticBytes == beforeOverflow.discardedDiagnosticBytes)
        #expect(delivery.send(.metadata(kind: "control", summary: "after")) == .stopped)

        let draining = Task { await delivery.finish(.drain) }
        await gate.open()
        await draining.value
        #expect(await recorder.recordedEvents() == admitted)
    }

    @Test func finish_WhenDraining_WaitsForTheInFlightHandler() async {
        let gate = DeliveryHandlerGate()
        let completion = DeliveryCompletionProbe()
        let delivery = AgentRunEventDelivery { _ in await gate.wait() }
        #expect(delivery.send(.diagnostic("wait")) == .accepted)
        await gate.waitUntilEntered()

        let finishing = Task {
            await delivery.finish(.drain)
            await completion.complete()
        }
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(await completion.completed() == false)

        await gate.open()
        await finishing.value
        #expect(await completion.completed())
    }

    @Test func finish_WhenDiscarding_ClearsPendingAndReturnsWithoutWaitingForHandler() async {
        let gate = DeliveryHandlerGate()
        let completion = DeliveryCompletionProbe()
        let delivery = AgentRunEventDelivery { _ in await gate.wait() }
        #expect(delivery.send(.diagnostic("in flight")) == .accepted)
        await gate.waitUntilEntered()
        #expect(delivery.send(.diagnostic("pending")) == .accepted)

        await delivery.finish(.discard)
        await completion.complete()

        #expect(await completion.completed())
        #expect(delivery.snapshotForTesting.pendingEntryCount == 0)
        #expect(delivery.snapshotForTesting.state == .discarded)
        await gate.open()
    }

    @Test func finish_WhenNextIsSuspended_ResumesTheConsumer() async {
        let delivery = AgentRunEventDelivery { _ in }
        for _ in 0..<20 {
            await Task.yield()
        }

        await delivery.finish(.discard)
        await delivery.waitForConsumerTerminationForTesting()

        #expect(delivery.snapshotForTesting.state == .discarded)
    }

    private func resultArtifact(index: Int, payloadByteCount: Int) -> AgentArtifact {
        AgentArtifact(
            uri: "file:///tmp/result-\(index).png",
            name: "result-\(index).png",
            title: nil,
            descriptiveText: nil,
            mimeType: "image/png",
            declaredSize: UInt64(payloadByteCount),
            payload: .image(
                data: Data(repeating: UInt8(index % 255), count: payloadByteCount),
                mimeType: "image/png"))
    }
}
