// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AppKit
import ApplicationServices
import Darwin
import Foundation
import YapOpsCore

@MainActor
protocol WorkspaceContextReading: Sendable {
    func currentTarget() -> MacContextTarget?
}

@MainActor
struct SystemWorkspaceContextReader: WorkspaceContextReading {
    func currentTarget() -> MacContextTarget? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return MacContextTarget(
            processIdentifier: application.processIdentifier,
            applicationName: application.localizedName ?? "Unknown application",
            bundleIdentifier: application.bundleIdentifier)
    }
}

enum AccessibilityContextReadStatus: Equatable, Sendable {
    case complete
    case notAuthorized
    case targetUnavailable
    case failed
}

struct AccessibilityContextReadResult: Sendable {
    let status: AccessibilityContextReadStatus
    let windowTitle: String?
    let documentURL: String?
    let selectedText: String?
    let resources: [MacContextResource]

    init(
        status: AccessibilityContextReadStatus,
        windowTitle: String? = nil,
        documentURL: String? = nil,
        selectedText: String? = nil,
        resources: [MacContextResource] = []
    ) {
        self.status = status
        self.windowTitle = windowTitle
        self.documentURL = documentURL
        self.selectedText = selectedText
        self.resources = resources
    }
}

protocol AccessibilityContextReading: Sendable {
    func readContext(processIdentifier: Int32) -> AccessibilityContextReadResult
}

protocol MacContextClock: Sendable {
    func sleep(for duration: Duration) async
}

struct ContinuousMacContextClock: MacContextClock {
    func sleep(for duration: Duration) async {
        try? await ContinuousClock().sleep(for: duration)
    }
}

protocol MacContextNow: Sendable {
    func uptimeMilliseconds() -> UInt64
}

struct ContinuousMacContextNow: MacContextNow {
    func uptimeMilliseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds / 1_000_000
    }
}

protocol MacContextExecuting: Sendable {
    func execute(_ operation: @escaping @Sendable () -> Void)
}

// Safety: the queue and its specific key are immutable after initialization, and the serial
// DispatchQueue owns all submitted operation ordering.
final class SerialMacContextExecutor: MacContextExecuting, @unchecked Sendable {
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let queue: DispatchQueue

    init(
        label: String = "com.yapops.mac-context",
        qualityOfService: DispatchQoS = .userInitiated
    ) {
        queue = DispatchQueue(label: label, qos: qualityOfService)
        queue.setSpecific(key: queueKey, value: 1)
    }

    var isExecutingOperation: Bool {
        DispatchQueue.getSpecific(key: queueKey) != nil
    }

    func execute(_ operation: @escaping @Sendable () -> Void) {
        queue.async(execute: operation)
    }
}

@MainActor
final class ConfigurableMacContextCapturer: MacContextCapturing {
    private let capturer: any MacContextCapturing
    private var enabled: Bool

    init(capturer: any MacContextCapturing, enabled: Bool) {
        self.capturer = capturer
        self.enabled = enabled
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }

    func currentTarget() -> MacContextTarget? {
        guard enabled else { return nil }
        return capturer.currentTarget()
    }

    func capture(_ target: MacContextTarget) async -> MacContextSnapshot {
        guard enabled else {
            return MacContextSnapshot.normalized(
                state: .targetUnavailable,
                target: target,
                windowTitle: nil,
                documentURL: nil,
                selectedText: nil,
                resources: [])
        }
        return await capturer.capture(target)
    }
}

@MainActor
final class SystemMacContextSnapshotter: MacContextCapturing {
    private static let captureDeadline = Duration.milliseconds(500)

    private let workspace: any WorkspaceContextReading
    private nonisolated let accessibility: any AccessibilityContextReading
    private nonisolated let executor: any MacContextExecuting
    private nonisolated let clock: any MacContextClock
    private nonisolated let diagnostics: any YapOpsDiagnosticRecording
    private nonisolated let now: any MacContextNow

    init(
        workspace: any WorkspaceContextReading = SystemWorkspaceContextReader(),
        accessibility: any AccessibilityContextReading = SystemAccessibilityContextReader(),
        executor: any MacContextExecuting = SerialMacContextExecutor(),
        clock: any MacContextClock = ContinuousMacContextClock(),
        diagnostics: any YapOpsDiagnosticRecording = YapOpsDiagnostics.shared,
        now: any MacContextNow = ContinuousMacContextNow()
    ) {
        self.workspace = workspace
        self.accessibility = accessibility
        self.executor = executor
        self.clock = clock
        self.diagnostics = diagnostics
        self.now = now
    }

    func currentTarget() -> MacContextTarget? {
        workspace.currentTarget()
    }

    func capture(_ target: MacContextTarget) async -> MacContextSnapshot {
        let captureID = UUID()
        let startedAt = now.uptimeMilliseconds()
        diagnostics.record(category: .app, event: "mac_context.capture_started")
        let timeoutSnapshot = Self.snapshot(
            target: target,
            result: .init(status: .failed),
            overridingState: .timedOut)
        let diagnostics = diagnostics
        let now = now
        let settlement = MacContextCaptureSettlement(
            captureID: captureID,
            cancellationSnapshot: timeoutSnapshot,
            onSettled: { snapshot, terminalState in
                let finishedAt = now.uptimeMilliseconds()
                diagnostics.record(
                    category: .app,
                    event: "mac_context.capture_finished",
                    fields: Self.diagnosticFields(
                        for: snapshot,
                        terminalState: terminalState,
                        startedAt: startedAt,
                        finishedAt: finishedAt))
            })
        let accessibility = accessibility
        let executor = executor
        let clock = clock

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                settlement.install(continuation)

                let deadlineTask = Task {
                    await clock.sleep(for: Self.captureDeadline)
                    settlement.settle(
                        captureID: captureID,
                        snapshot: timeoutSnapshot,
                        terminalState: .timedOut)
                }
                settlement.attachDeadlineTask(deadlineTask)

                executor.execute {
                    guard settlement.isActive(captureID: captureID) else {
                        return
                    }
                    let result = accessibility.readContext(
                        processIdentifier: target.processIdentifier)
                    let snapshot = Self.snapshot(target: target, result: result)
                    settlement.settle(
                        captureID: captureID,
                        snapshot: snapshot,
                        terminalState: snapshot.captureState == .complete ? .completed : .fallback)
                }
            }
        } onCancel: {
            settlement.cancel(captureID: captureID)
        }
    }

    nonisolated private static func snapshot(
        target: MacContextTarget,
        result: AccessibilityContextReadResult,
        overridingState: MacContextCaptureState? = nil
    ) -> MacContextSnapshot {
        if let overridingState {
            return Self.appOnlySnapshot(state: overridingState, target: target)
        }
        switch result.status {
        case .notAuthorized:
            return Self.appOnlySnapshot(state: .accessibilityNotAuthorized, target: target)
        case .targetUnavailable:
            return Self.appOnlySnapshot(state: .targetUnavailable, target: target)
        case .complete:
            return Self.normalizedSnapshot(state: .complete, target: target, result: result)
        case .failed:
            let candidate = Self.normalizedSnapshot(
                state: .accessibilityFailed,
                target: target,
                result: result)
            guard Self.hasUsefulContext(candidate) else {
                return Self.appOnlySnapshot(state: .accessibilityFailed, target: target)
            }
            return Self.normalizedSnapshot(state: .complete, target: target, result: result)
        }
    }

    nonisolated private static func normalizedSnapshot(
        state: MacContextCaptureState,
        target: MacContextTarget,
        result: AccessibilityContextReadResult
    ) -> MacContextSnapshot {
        MacContextSnapshot.normalized(
            state: state,
            target: target,
            windowTitle: result.windowTitle,
            documentURL: result.documentURL,
            selectedText: result.selectedText,
            resources: result.resources)
    }

    nonisolated private static func appOnlySnapshot(
        state: MacContextCaptureState,
        target: MacContextTarget
    ) -> MacContextSnapshot {
        MacContextSnapshot.normalized(
            state: state,
            target: target,
            windowTitle: nil,
            documentURL: nil,
            selectedText: nil,
            resources: [])
    }

    nonisolated private static func hasUsefulContext(_ snapshot: MacContextSnapshot) -> Bool {
        snapshot.windowTitle?.isEmpty == false
            || snapshot.documentURL != nil
            || snapshot.selectedText?.isEmpty == false
            || !snapshot.resources.isEmpty
    }

    nonisolated private static func diagnosticFields(
        for snapshot: MacContextSnapshot,
        terminalState: MacContextCaptureTerminalState,
        startedAt: UInt64,
        finishedAt: UInt64
    ) -> [String: String] {
        [
            "capture_state": snapshot.captureState.rawValue,
            "terminal_state": terminalState.rawValue,
            "duration_ms": String(finishedAt >= startedAt ? finishedAt - startedAt : 0),
            "has_window_title": String(snapshot.windowTitle != nil),
            "has_document_url": String(snapshot.documentURL != nil),
            "has_selection": String(snapshot.selectedText != nil),
            "selection_byte_count": String(snapshot.selectedText?.utf8.count ?? 0),
            "resource_count": String(snapshot.resources.count),
        ]
    }
}

private enum MacContextCaptureTerminalState: String, Sendable {
    case completed
    case fallback
    case timedOut = "timed_out"
    case cancelled
}

// Safety: every mutable field is protected by `lock`; continuations and task cancellation are
// invoked only after releasing it, and the UUID rejects every callback after first settlement.
private final class MacContextCaptureSettlement: @unchecked Sendable {
    private let lock = NSLock()
    private let cancellationSnapshot: MacContextSnapshot
    private let onSettled: @Sendable (MacContextSnapshot, MacContextCaptureTerminalState) -> Void
    private var activeCaptureID: UUID
    private var continuation: CheckedContinuation<MacContextSnapshot, Never>?
    private var pendingSnapshot: MacContextSnapshot?
    private var deadlineTask: Task<Void, Never>?

    init(
        captureID: UUID,
        cancellationSnapshot: MacContextSnapshot,
        onSettled: @escaping @Sendable (MacContextSnapshot, MacContextCaptureTerminalState) -> Void
    ) {
        activeCaptureID = captureID
        self.cancellationSnapshot = cancellationSnapshot
        self.onSettled = onSettled
    }

    func install(_ continuation: CheckedContinuation<MacContextSnapshot, Never>) {
        let pending = lock.withLock { () -> MacContextSnapshot? in
            if let pendingSnapshot {
                self.pendingSnapshot = nil
                return pendingSnapshot
            }
            self.continuation = continuation
            return nil
        }
        if let pending {
            continuation.resume(returning: pending)
        }
    }

    func attachDeadlineTask(_ task: Task<Void, Never>) {
        let shouldCancel = lock.withLock { () -> Bool in
            guard continuation != nil else {
                return true
            }
            deadlineTask = task
            return false
        }
        if shouldCancel {
            task.cancel()
        }
    }

    func isActive(captureID: UUID) -> Bool {
        lock.withLock { activeCaptureID == captureID }
    }

    func settle(
        captureID: UUID,
        snapshot: MacContextSnapshot,
        terminalState: MacContextCaptureTerminalState
    ) {
        let settled = lock.withLock {
            settlement(captureID: captureID, snapshot: snapshot)
        }
        guard settled.didWin else { return }
        settled.deadlineTask?.cancel()
        settled.continuation?.resume(returning: snapshot)
        onSettled(snapshot, terminalState)
    }

    func cancel(captureID: UUID) {
        settle(
            captureID: captureID,
            snapshot: cancellationSnapshot,
            terminalState: .cancelled)
    }

    private func settlement(
        captureID: UUID,
        snapshot: MacContextSnapshot
    ) -> (
        continuation: CheckedContinuation<MacContextSnapshot, Never>?,
        deadlineTask: Task<Void, Never>?,
        didWin: Bool
    ) {
        guard activeCaptureID == captureID else {
            return (nil, nil, false)
        }
        activeCaptureID = UUID()
        let continuation = continuation
        self.continuation = nil
        if continuation == nil {
            pendingSnapshot = snapshot
        }
        let deadlineTask = deadlineTask
        self.deadlineTask = nil
        return (continuation, deadlineTask, true)
    }
}

protocol AccessibilityNativeReading: Sendable {
    func isProcessTrusted() -> Bool
    func processExists(_ processIdentifier: Int32) -> Bool
    func applicationElement(processIdentifier: Int32) -> AXUIElement
    func setMessagingTimeout(_ timeout: Float, for element: AXUIElement) -> AXError
    func copyElementAttribute(_ attribute: CFString, from element: AXUIElement) -> ElementRead
    func copyMultiple(_ attributes: [CFString], from element: AXUIElement) -> MultipleRead
}

struct SystemAccessibilityContextReader: AccessibilityContextReading {
    private static let messagingTimeout: Float = 0.1
    private static let maximumSelectedElements = MacContextSnapshot.maximumResources
    private let native: any AccessibilityNativeReading

    init(native: any AccessibilityNativeReading = SystemAccessibilityNativeReader()) {
        self.native = native
    }

    func readContext(processIdentifier: Int32) -> AccessibilityContextReadResult {
        guard native.isProcessTrusted() else {
            return .init(status: .notAuthorized)
        }
        guard native.processExists(processIdentifier) else {
            return .init(status: .targetUnavailable)
        }

        let application = native.applicationElement(processIdentifier: processIdentifier)
        let timeoutError = native.setMessagingTimeout(Self.messagingTimeout, for: application)
        if timeoutError == .apiDisabled {
            return .init(status: .notAuthorized)
        }
        guard timeoutError == .success else {
            return .init(status: native.processExists(processIdentifier)
                ? .failed
                : .targetUnavailable)
        }

        var hadFailure = false
        let windowRead = native.copyElementAttribute(
            kAXFocusedWindowAttribute as CFString,
            from: application)
        let focusedRead = native.copyElementAttribute(
            kAXFocusedUIElementAttribute as CFString,
            from: application)
        if windowRead.error == .apiDisabled || focusedRead.error == .apiDisabled {
            return .init(status: .notAuthorized)
        }
        hadFailure = hadFailure || windowRead.hadFailure || focusedRead.hadFailure

        var windowTitle: String?
        var windowDocumentURL: String?
        if let window = windowRead.element {
            let read = native.copyMultiple(
                [kAXTitleAttribute as CFString, kAXDocumentAttribute as CFString],
                from: window)
            if read.error == .apiDisabled {
                return .init(status: .notAuthorized)
            }
            hadFailure = hadFailure || read.hadFailure
            windowTitle = Self.string(from: read.values[safe: 0])
            windowDocumentURL = Self.urlString(from: read.values[safe: 1])
        }

        var focusedDocumentURL: String?
        var focusedURL: String?
        var selectedText: String?
        var selectedElements: [AXUIElement] = []
        if let focusedElement = focusedRead.element {
            let read = native.copyMultiple(
                [
                    kAXSelectedTextAttribute as CFString,
                    kAXDocumentAttribute as CFString,
                    kAXURLAttribute as CFString,
                    kAXSelectedChildrenAttribute as CFString,
                    kAXSelectedRowsAttribute as CFString,
                ],
                from: focusedElement)
            if read.error == .apiDisabled {
                return .init(status: .notAuthorized)
            }
            hadFailure = hadFailure || read.hadFailure
            selectedText = Self.string(from: read.values[safe: 0])
            focusedDocumentURL = Self.urlString(from: read.values[safe: 1])
            focusedURL = Self.urlString(from: read.values[safe: 2])
            Self.appendElements(
                from: read.values[safe: 3],
                maximumCount: Self.maximumSelectedElements,
                to: &selectedElements)
            Self.appendElements(
                from: read.values[safe: 4],
                maximumCount: Self.maximumSelectedElements - selectedElements.count,
                to: &selectedElements)
        }

        var resources: [MacContextResource] = []
        for element in selectedElements {
            let read = native.copyMultiple(
                [
                    kAXURLAttribute as CFString,
                    kAXTitleAttribute as CFString,
                    kAXFilenameAttribute as CFString,
                ],
                from: element)
            if read.error == .apiDisabled {
                return .init(status: .notAuthorized)
            }
            hadFailure = hadFailure || read.hadFailure
            guard let uri = Self.urlString(from: read.values[safe: 0]) else {
                continue
            }
            let name = Self.string(from: read.values[safe: 1])
                ?? Self.string(from: read.values[safe: 2])
                ?? URL(string: uri)?.lastPathComponent
                ?? ""
            resources.append(.init(uri: uri, name: name))
        }

        let result = AccessibilityContextReadResult(
            status: hadFailure ? .failed : .complete,
            windowTitle: windowTitle,
            documentURL: focusedDocumentURL ?? focusedURL ?? windowDocumentURL,
            selectedText: selectedText,
            resources: resources)
        if hadFailure, !native.processExists(processIdentifier) {
            return .init(status: .targetUnavailable)
        }
        return result
    }

    private static func string(from value: AnyObject?) -> String? {
        guard let value, !(value is NSNull) else {
            return nil
        }
        return value as? String
    }

    private static func urlString(from value: AnyObject?) -> String? {
        guard let value, !(value is NSNull) else {
            return nil
        }
        if let url = value as? URL {
            return url.absoluteString
        }
        return value as? String
    }

    private static func appendElements(
        from value: AnyObject?,
        maximumCount: Int,
        to elements: inout [AXUIElement]
    ) {
        guard maximumCount > 0, let values = value as? NSArray else {
            return
        }
        for index in 0..<min(maximumCount, values.count) {
            let value = values[index]
            guard CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() else {
                continue
            }
            elements.append(unsafeDowncast(value as AnyObject, to: AXUIElement.self))
        }
    }
}

struct SystemAccessibilityNativeReader: AccessibilityNativeReading {
    func isProcessTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func processExists(_ processIdentifier: Int32) -> Bool {
        guard processIdentifier > 0 else {
            return false
        }
        if Darwin.kill(processIdentifier, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    func applicationElement(processIdentifier: Int32) -> AXUIElement {
        AXUIElementCreateApplication(processIdentifier)
    }

    func setMessagingTimeout(_ timeout: Float, for element: AXUIElement) -> AXError {
        AXUIElementSetMessagingTimeout(element, timeout)
    }

    func copyElementAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> ElementRead {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        if error == .success,
           let value,
           CFGetTypeID(value) == AXUIElementGetTypeID()
        {
            return ElementRead(
                element: unsafeDowncast(value as AnyObject, to: AXUIElement.self),
                error: .success)
        }
        return ElementRead(element: nil, error: error)
    }

    func copyMultiple(
        _ attributes: [CFString],
        from element: AXUIElement
    ) -> MultipleRead {
        var copiedValues: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(
            element,
            attributes as CFArray,
            AXCopyMultipleAttributeOptions(rawValue: 0),
            &copiedValues)
        guard error == .success, let values = copiedValues as? [Any] else {
            return MultipleRead(values: [], error: error, containsValueFailure: false)
        }
        return MultipleRead(
            values: values.map { $0 as AnyObject },
            error: error,
            containsValueFailure: values.contains(where: Self.isFailureValue))
    }

    private static func isFailureValue(_ value: Any) -> Bool {
        guard CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else {
            return false
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .axError else {
            return false
        }
        var error = AXError.success
        guard AXValueGetValue(axValue, .axError, &error) else {
            return true
        }
        return error != .attributeUnsupported && error != .noValue
    }
}

struct ElementRead {
    let element: AXUIElement?
    let error: AXError

    var hadFailure: Bool {
        error != .success && error != .attributeUnsupported && error != .noValue
    }
}

struct MultipleRead {
    let values: [AnyObject]
    let error: AXError
    let containsValueFailure: Bool

    var hadFailure: Bool {
        (error != .success && error != .attributeUnsupported && error != .noValue)
            || containsValueFailure
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
