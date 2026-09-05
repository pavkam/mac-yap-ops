// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
import VoiceActivationCore

@testable import VoiceActivationApp

@Suite(.serialized)
struct SystemMacContextSnapshotterTests {
    @MainActor @Test func capture_WhenAccessibilityIsTrusted_MapsFocusedValuesInOrder()
        async throws
    {
        let target = MacContextTarget.editor
        let accessibility = AccessibilityReaderStub(result: .init(
            status: .complete,
            windowTitle: "notes.md",
            documentURL: "file:///tmp/notes.md",
            selectedText: "one two",
            resources: [
                .init(uri: "file:///tmp/a.md", name: "a.md"),
                .init(uri: "file:///tmp/b.md", name: "b.md"),
            ]))
        let subject = SystemMacContextSnapshotter(
            workspace: WorkspaceReaderStub(target: target),
            accessibility: accessibility)

        let frozenTarget = try #require(subject.currentTarget())
        let snapshot = await subject.capture(frozenTarget)

        #expect(snapshot.captureState == .complete)
        #expect(snapshot.applicationName == "Editor")
        #expect(snapshot.bundleIdentifier == "com.example.Editor")
        #expect(snapshot.windowTitle == "notes.md")
        #expect(snapshot.documentURL == "file:///tmp/notes.md")
        #expect(snapshot.selectedText == "one two")
        #expect(snapshot.resources.map(\.name) == ["a.md", "b.md"])
    }

    @MainActor @Test func capture_WhenAccessibilityIsNotTrusted_ReturnsFrozenAppIdentity()
        async
    {
        let target = MacContextTarget.editor
        let subject = SystemMacContextSnapshotter(
            workspace: WorkspaceReaderStub(target: target),
            accessibility: AccessibilityReaderStub(result: .init(
                status: .notAuthorized,
                windowTitle: "must not escape",
                selectedText: "must not escape",
                resources: [.init(uri: "file:///tmp/private", name: "private")])))

        let snapshot = await subject.capture(target)

        #expect(snapshot.captureState == .accessibilityNotAuthorized)
        #expect(snapshot.applicationName == "Editor")
        #expect(snapshot.bundleIdentifier == "com.example.Editor")
        #expect(snapshot.windowTitle == nil)
        #expect(snapshot.selectedText == nil)
        #expect(snapshot.resources.isEmpty)
    }

    @MainActor @Test func capture_WhenAttributesAreUnsupported_TreatsThemAsAbsent()
        async
    {
        let target = MacContextTarget.editor
        let subject = SystemMacContextSnapshotter(
            workspace: WorkspaceReaderStub(target: target),
            accessibility: AccessibilityReaderStub(result: .init(status: .complete)))

        let snapshot = await subject.capture(target)

        #expect(snapshot.captureState == .complete)
        #expect(snapshot.windowTitle == nil)
        #expect(snapshot.documentURL == nil)
        #expect(snapshot.selectedText == nil)
        #expect(snapshot.resources.isEmpty)
    }

    @MainActor @Test func capture_WhenAXFailsAfterUsefulTitle_PreservesPartialContext()
        async
    {
        let target = MacContextTarget.editor
        let subject = SystemMacContextSnapshotter(
            workspace: WorkspaceReaderStub(target: target),
            accessibility: AccessibilityReaderStub(result: .init(
                status: .failed,
                windowTitle: "Recovered title")))

        let snapshot = await subject.capture(target)

        #expect(snapshot.captureState == .complete)
        #expect(snapshot.windowTitle == "Recovered title")
        #expect(snapshot.selectedText == nil)
    }

    @MainActor @Test func capture_WhenResourceURLsRepeat_KeepsFirstNormalizedOccurrence()
        async
    {
        let target = MacContextTarget.editor
        let subject = SystemMacContextSnapshotter(
            workspace: WorkspaceReaderStub(target: target),
            accessibility: AccessibilityReaderStub(result: .init(
                status: .complete,
                resources: [
                    .init(uri: "file:///tmp/../tmp/a.md", name: "first.md"),
                    .init(uri: "file:///tmp/a.md", name: "duplicate.md"),
                    .init(uri: "file:///tmp/b.md", name: "b.md"),
                ])))

        let snapshot = await subject.capture(target)

        #expect(snapshot.resources.map(\.uri) == [
            "file:///tmp/a.md",
            "file:///tmp/b.md",
        ])
        #expect(snapshot.resources.map(\.name) == ["first.md", "b.md"])
    }

    @MainActor @Test func capture_WhenFrozenPIDNoLongerExists_ReturnsTargetUnavailable()
        async
    {
        let target = MacContextTarget.editor
        let subject = SystemMacContextSnapshotter(
            workspace: WorkspaceReaderStub(target: target),
            accessibility: AccessibilityReaderStub(result: .init(status: .targetUnavailable)))

        let snapshot = await subject.capture(target)

        #expect(snapshot.captureState == .targetUnavailable)
        #expect(snapshot.applicationName == "Editor")
        #expect(snapshot.bundleIdentifier == "com.example.Editor")
    }

    @MainActor @Test func capture_WhenDeadlineWins_ReturnsTimedOutFrozenIdentity()
        async
    {
        let target = MacContextTarget.editor
        let accessibility = ControlledAccessibilityReader(
            result: .init(status: .complete, selectedText: "too late"))
        let subject = SystemMacContextSnapshotter(
            workspace: WorkspaceReaderStub(target: target),
            accessibility: accessibility,
            clock: ImmediateMacContextClock())

        let snapshot = await subject.capture(target)

        #expect(snapshot.captureState == .timedOut)
        #expect(snapshot.applicationName == "Editor")
        #expect(snapshot.bundleIdentifier == "com.example.Editor")
        #expect(snapshot.selectedText == nil)
        await accessibility.waitUntilStarted()
        accessibility.release()
    }

    @MainActor @Test func capture_WhenTimedOutWorkerFinishesLate_DoesNotCrossApplyResult()
        async
    {
        let firstTarget = MacContextTarget.editor
        let secondTarget = MacContextTarget(
            processIdentifier: 43,
            applicationName: "Browser",
            bundleIdentifier: "com.example.Browser")
        let accessibility = ControlledAccessibilityReader(
            result: .init(status: .complete, selectedText: "stale editor selection"),
            followingResults: [
                43: .init(status: .complete, selectedText: "current browser selection"),
            ])
        let clock = SwitchableMacContextClock()
        let subject = SystemMacContextSnapshotter(
            workspace: WorkspaceReaderStub(target: firstTarget),
            accessibility: accessibility,
            clock: clock)

        let firstCapture = Task { await subject.capture(firstTarget) }
        await accessibility.waitUntilStarted()
        await clock.fireDeadline()
        let timedOut = await firstCapture.value
        #expect(timedOut.captureState == .timedOut)
        #expect(timedOut.applicationName == "Editor")

        accessibility.release()
        await clock.disableDeadline()
        let current = await subject.capture(secondTarget)

        #expect(current.captureState == .complete)
        #expect(current.applicationName == "Browser")
        #expect(current.selectedText == "current browser selection")
    }

    @Test func executor_WhenOperationsRun_UsesOneDedicatedSerialQueue() async {
        let executor = SerialMacContextExecutor(
            label: "dev.alex.voice-activation.tests.mac-context")
        let observations = SerialExecutionObservations()

        await withCheckedContinuation { continuation in
            executor.execute {
                observations.record(executor.isExecutingOperation)
                executor.execute {
                    observations.record(executor.isExecutingOperation)
                    continuation.resume()
                }
            }
        }

        #expect(observations.values == [true, true])
    }
}

private extension MacContextTarget {
    static let editor = MacContextTarget(
        processIdentifier: 42,
        applicationName: "Editor",
        bundleIdentifier: "com.example.Editor")
}

@MainActor
private struct WorkspaceReaderStub: WorkspaceContextReading {
    let target: MacContextTarget?

    func currentTarget() -> MacContextTarget? {
        target
    }
}

private struct AccessibilityReaderStub: AccessibilityContextReading {
    let result: AccessibilityContextReadResult

    func readContext(processIdentifier: Int32) -> AccessibilityContextReadResult {
        result
    }
}

private final class ControlledAccessibilityReader: AccessibilityContextReading, @unchecked Sendable {
    private let condition = NSCondition()
    private let firstResult: AccessibilityContextReadResult
    private let followingResults: [Int32: AccessibilityContextReadResult]
    private var isStarted = false
    private var isReleased = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        result: AccessibilityContextReadResult,
        followingResults: [Int32: AccessibilityContextReadResult] = [:]
    ) {
        firstResult = result
        self.followingResults = followingResults
    }

    func readContext(processIdentifier: Int32) -> AccessibilityContextReadResult {
        if let following = followingResults[processIdentifier] {
            return following
        }

        condition.lock()
        isStarted = true
        let waiters = startedWaiters
        startedWaiters.removeAll()
        condition.broadcast()
        condition.unlock()
        for waiter in waiters {
            waiter.resume()
        }

        condition.lock()
        while !isReleased {
            condition.wait()
        }
        condition.unlock()
        return firstResult
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            condition.lock()
            if isStarted {
                condition.unlock()
                continuation.resume()
            } else {
                startedWaiters.append(continuation)
                condition.unlock()
            }
        }
    }

    func release() {
        condition.lock()
        isReleased = true
        condition.broadcast()
        condition.unlock()
    }
}

private struct ImmediateMacContextClock: MacContextClock {
    func sleep(for duration: Duration) async {}
}

private actor SwitchableMacContextClock: MacContextClock {
    private var deadlineContinuation: CheckedContinuation<Void, Never>?
    private var shouldWait = true

    func sleep(for duration: Duration) async {
        guard shouldWait else {
            try? await ContinuousClock().sleep(for: duration)
            return
        }
        await withCheckedContinuation { deadlineContinuation = $0 }
    }

    func fireDeadline() {
        let continuation = deadlineContinuation
        deadlineContinuation = nil
        continuation?.resume()
    }

    func disableDeadline() {
        shouldWait = false
    }
}

private final class SerialExecutionObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Bool] = []

    var values: [Bool] {
        lock.withLock { storage }
    }

    func record(_ value: Bool) {
        lock.withLock { storage.append(value) }
    }
}
