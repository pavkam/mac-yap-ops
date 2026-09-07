// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import ApplicationServices
import Foundation
import Testing
import YapOpsCore

@testable import YapOpsApp

@Suite(.serialized)
struct SystemMacContextSnapshotterTests {
    @MainActor @Test
    func capture_WhenSelectedItemHasOnlyAbsoluteFilename_PreservesAgentPromptLink() async throws {
        let native = NativeAccessibilityFake(
            processExists: [true],
            selectedChildCount: 1,
            resourceAttributes: [NSNull(), NSNull(), "/tmp/Project Notes.md" as NSString])

        let subject = SystemMacContextSnapshotter(
            workspace: WorkspaceReaderStub(target: .editor),
            accessibility: SystemAccessibilityContextReader(native: native))
        let result = await subject.capture(.editor)

        #expect(result.resources == [
            MacContextResource(uri: "file:///tmp/Project%20Notes.md", name: "Project Notes.md"),
        ])
        let prompt = try MacContextPromptEncoder.content(
            for: AgentPrompt(request: "Summarize this file", context: result),
            systemInstruction: "Use the supplied context.")
        #expect(prompt.contains(.resourceLink(
            role: .macResource,
            uri: "file:///tmp/Project%20Notes.md",
            name: "Project Notes.md")))
    }

    @Test(arguments: ["notes.md", "~/notes.md", "", "https://example.test/file", "/tmp/a\0b"])
    func nativeRead_WhenFilenameCannotIdentifyAbsoluteFile_OmitsResource(filename: String) {
        let native = NativeAccessibilityFake(
            processExists: [true],
            selectedChildCount: 1,
            resourceAttributes: [NSNull(), NSNull(), filename as NSString])

        let result = SystemAccessibilityContextReader(native: native)
            .readContext(processIdentifier: 42)

        #expect(result.resources.isEmpty)
    }

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

    @MainActor @Test func capture_WhenAXFailureContainsOnlyUnsafeURLs_RemainsFailed()
        async
    {
        let target = MacContextTarget.editor
        let subject = SystemMacContextSnapshotter(
            workspace: WorkspaceReaderStub(target: target),
            accessibility: AccessibilityReaderStub(result: .init(
                status: .failed,
                documentURL: "javascript:private()",
                resources: [
                    .init(uri: "relative/private.txt", name: "private.txt"),
                ])))

        let snapshot = await subject.capture(target)

        #expect(snapshot.captureState == .accessibilityFailed)
        #expect(snapshot.documentURL == nil)
        #expect(snapshot.resources.isEmpty)
    }

    @MainActor @Test func capture_WhenAXFailureContainsOneValidField_PreservesNormalizedPartial()
        async
    {
        let target = MacContextTarget.editor
        let subject = SystemMacContextSnapshotter(
            workspace: WorkspaceReaderStub(target: target),
            accessibility: AccessibilityReaderStub(result: .init(
                status: .failed,
                documentURL: "javascript:private()",
                resources: [
                    .init(uri: "file:///tmp/useful.txt", name: "useful.txt"),
                ])))

        let snapshot = await subject.capture(target)

        #expect(snapshot.captureState == .complete)
        #expect(snapshot.documentURL == nil)
        #expect(snapshot.resources.map(\.uri) == ["file:///tmp/useful.txt"])
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
        let accessibility = CountingAccessibilityReader()
        let executor = ControlledMacContextExecutor()
        let subject = SystemMacContextSnapshotter(
            workspace: WorkspaceReaderStub(target: target),
            accessibility: accessibility,
            executor: executor,
            clock: ImmediateMacContextClock())

        let snapshot = await subject.capture(target)
        executor.runNext()

        #expect(snapshot.captureState == .timedOut)
        #expect(snapshot.applicationName == "Editor")
        #expect(snapshot.bundleIdentifier == "com.example.Editor")
        #expect(snapshot.selectedText == nil)
        #expect(accessibility.readCount == 0)
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

    @Test(.timeLimit(.minutes(1))) func deadlineClock_WhenFiredBeforeSleep_ResumesNextSleep()
        async
    {
        let clock = SwitchableMacContextClock()

        await clock.fireDeadline()
        await clock.sleep(for: .milliseconds(500))
    }

    @MainActor @Test func capture_WhenCancelledBeforeWorkerStarts_NeverReadsAccessibility()
        async
    {
        let accessibility = CountingAccessibilityReader()
        let executor = ControlledMacContextExecutor()
        let subject = SystemMacContextSnapshotter(
            workspace: WorkspaceReaderStub(target: .editor),
            accessibility: accessibility,
            executor: executor)

        let capture = Task { await subject.capture(.editor) }
        await executor.waitForOperationCount(1)
        capture.cancel()
        let snapshot = await capture.value
        executor.runNext()

        #expect(snapshot.captureState == .timedOut)
        #expect(accessibility.readCount == 0)
    }

    @Test func executor_WhenOperationsRun_UsesOneDedicatedSerialQueue() async {
        let executor = SerialMacContextExecutor(
            label: "dev.alex.yapops.tests.mac-context")
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

    @Test func accessibilityReader_WhenMessagingTimeoutFails_AbortsBeforeAttributeIPC() {
        let native = NativeAccessibilityFake(
            processExists: [true, true],
            timeoutError: .cannotComplete)
        let subject = SystemAccessibilityContextReader(native: native)

        let result = subject.readContext(processIdentifier: 42)

        #expect(result.status == .failed)
        #expect(native.attributeReadCount == 0)
    }

    @Test func accessibilityReader_WhenTimeoutFailsAfterTargetExits_ReturnsUnavailable() {
        let native = NativeAccessibilityFake(
            processExists: [true, false],
            timeoutError: .invalidUIElement)
        let subject = SystemAccessibilityContextReader(native: native)

        let result = subject.readContext(processIdentifier: 42)

        #expect(result.status == .targetUnavailable)
        #expect(native.attributeReadCount == 0)
    }

    @Test func accessibilityReader_WhenTimeoutReportsAPIDisabled_ReturnsNotAuthorized() {
        let native = NativeAccessibilityFake(
            processExists: [true],
            timeoutError: .apiDisabled)
        let subject = SystemAccessibilityContextReader(native: native)

        let result = subject.readContext(processIdentifier: 42)

        #expect(result.status == .notAuthorized)
        #expect(native.attributeReadCount == 0)
    }

    @Test func accessibilityReader_WhenSelectionIsLarge_ReadsChildrenThenOnlyEnoughRows() {
        let native = NativeAccessibilityFake(
            processExists: [true],
            selectedChildCount: 3,
            selectedRowCount: 64)
        let subject = SystemAccessibilityContextReader(native: native)

        let result = subject.readContext(processIdentifier: 42)

        let expected = (0..<3).map { "child-\($0)" } + (0..<5).map { "row-\($0)" }
        #expect(result.resources.map(\.name) == expected)
        #expect(native.resourceReadOrder == expected)
        #expect(native.resourceReadCount == 8)
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

private final class CountingAccessibilityReader: AccessibilityContextReading, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var readCount: Int {
        lock.withLock { count }
    }

    func readContext(processIdentifier: Int32) -> AccessibilityContextReadResult {
        lock.withLock { count += 1 }
        return .init(status: .complete)
    }
}

private final class ControlledMacContextExecutor: MacContextExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private var operations: [@Sendable () -> Void] = []
    private var countWaiters: [CheckedContinuation<Void, Never>] = []

    func execute(_ operation: @escaping @Sendable () -> Void) {
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            operations.append(operation)
            let waiters = countWaiters
            countWaiters.removeAll()
            return waiters
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitForOperationCount(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock { () -> Bool in
                guard operations.count < count else {
                    return true
                }
                countWaiters.append(continuation)
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    func runNext() {
        let operation = lock.withLock { operations.isEmpty ? nil : operations.removeFirst() }
        operation?()
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
    private var hasFiredDeadline = false
    private var shouldWait = true

    func sleep(for duration: Duration) async {
        guard shouldWait else {
            try? await ContinuousClock().sleep(for: duration)
            return
        }
        await withCheckedContinuation { continuation in
            if hasFiredDeadline {
                hasFiredDeadline = false
                continuation.resume()
            } else {
                deadlineContinuation = continuation
            }
        }
    }

    func fireDeadline() {
        if let continuation = deadlineContinuation {
            deadlineContinuation = nil
            continuation.resume()
        } else {
            hasFiredDeadline = true
        }
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

private final class NativeAccessibilityFake: AccessibilityNativeReading, @unchecked Sendable {
    private let lock = NSLock()
    private let application = AXUIElementCreateApplication(9_001)
    private let window = AXUIElementCreateApplication(9_002)
    private let focusedElement = AXUIElementCreateApplication(9_003)
    private let timeoutError: AXError
    private let resourceAttributes: [AnyObject]?
    private var processExistence: [Bool]
    private var resourceNamesByElement: [ObjectIdentifier: String] = [:]
    private var selectedChildren: [AXUIElement] = []
    private var selectedRows: [AXUIElement] = []
    private var attributeReads = 0
    private var recordedResourceReadOrder: [String] = []

    init(
        processExists: [Bool],
        timeoutError: AXError = .success,
        selectedChildCount: Int = 0,
        selectedRowCount: Int = 0,
        resourceAttributes: [AnyObject]? = nil
    ) {
        processExistence = processExists
        self.timeoutError = timeoutError
        self.resourceAttributes = resourceAttributes
        for index in 0..<selectedChildCount {
            let element = AXUIElementCreateApplication(Int32(10_000 + index))
            selectedChildren.append(element)
            resourceNamesByElement[ObjectIdentifier(element)] = "child-\(index)"
        }
        for index in 0..<selectedRowCount {
            let element = AXUIElementCreateApplication(Int32(20_000 + index))
            selectedRows.append(element)
            resourceNamesByElement[ObjectIdentifier(element)] = "row-\(index)"
        }
    }

    var attributeReadCount: Int {
        lock.withLock { attributeReads }
    }

    var resourceReadOrder: [String] {
        lock.withLock { recordedResourceReadOrder }
    }

    var resourceReadCount: Int {
        resourceReadOrder.count
    }

    func isProcessTrusted() -> Bool {
        true
    }

    func processExists(_ processIdentifier: Int32) -> Bool {
        lock.withLock {
            guard !processExistence.isEmpty else {
                return true
            }
            return processExistence.removeFirst()
        }
    }

    func applicationElement(processIdentifier: Int32) -> AXUIElement {
        application
    }

    func setMessagingTimeout(_ timeout: Float, for element: AXUIElement) -> AXError {
        timeoutError
    }

    func copyElementAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> ElementRead {
        lock.withLock { attributeReads += 1 }
        if attribute as String == kAXFocusedWindowAttribute {
            return ElementRead(element: window, error: .success)
        }
        if attribute as String == kAXFocusedUIElementAttribute {
            return ElementRead(element: focusedElement, error: .success)
        }
        return ElementRead(element: nil, error: .attributeUnsupported)
    }

    func copyMultiple(
        _ attributes: [CFString],
        from element: AXUIElement
    ) -> MultipleRead {
        lock.withLock { attributeReads += 1 }
        if element === window {
            return MultipleRead(
                values: [NSNull(), NSNull()],
                error: .success,
                containsValueFailure: false)
        }
        if element === focusedElement {
            return MultipleRead(
                values: [
                    NSNull(),
                    NSNull(),
                    NSNull(),
                    selectedChildren as NSArray,
                    selectedRows as NSArray,
                ],
                error: .success,
                containsValueFailure: false)
        }
        guard let name = resourceNamesByElement[ObjectIdentifier(element)] else {
            return MultipleRead(values: [], error: .invalidUIElement, containsValueFailure: false)
        }
        lock.withLock { recordedResourceReadOrder.append(name) }
        return MultipleRead(
            values: resourceAttributes ?? [
                "file:///tmp/\(name).txt" as NSString,
                name as NSString,
                NSNull(),
            ],
            error: .success,
            containsValueFailure: false)
    }
}
