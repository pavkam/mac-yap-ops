// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
import VoiceActivationCore

@testable import VoiceActivationApp

@Suite(.serialized)
struct SystemMacContextSnapshotterDiagnosticsTests {
    @MainActor @Test func capture_WhenComplete_RecordsSafePairedMetadataWithDuration()
        async
    {
        let diagnostics = AppDiagnosticRecorderSpy()
        let now = MacContextNowStub(values: [100, 145])
        let selectedValue = "diagnostic selection sentinel"
        let titleValue = "diagnostic title sentinel"
        let uriValue = "file:///diagnostic-sentinel"
        let subject = SystemMacContextSnapshotter(
            workspace: MacContextWorkspaceStub(target: .editor),
            accessibility: MacContextAccessibilityStub(result: .init(
                status: .complete,
                windowTitle: titleValue,
                documentURL: uriValue,
                selectedText: selectedValue,
                resources: [.init(uri: uriValue, name: "diagnostic-name-sentinel")])),
            diagnostics: diagnostics,
            now: now)

        _ = await subject.capture(.editor)

        let entries = diagnostics.snapshot()
        #expect(entries.count == 2)
        #expect(entries[0].event == "mac_context.capture_started")
        #expect(entries[0].fields.isEmpty)
        #expect(entries[1].event == "mac_context.capture_finished")
        #expect(entries[1].fields == [
            "capture_state": "complete",
            "terminal_state": "completed",
            "duration_ms": "45",
            "has_window_title": "true",
            "has_document_url": "true",
            "has_selection": "true",
            "selection_byte_count": "29",
            "resource_count": "1",
        ])
        #expect(!entries.flatMap(\.fields.values).contains(selectedValue))
        #expect(!entries.flatMap(\.fields.values).contains(titleValue))
        #expect(!entries.flatMap(\.fields.values).contains(uriValue))
        #expect(!entries.flatMap(\.fields.values).contains("diagnostic-name-sentinel"))
    }

    @MainActor @Test func capture_WhenNativeFallbackOccurs_RecordsFallbackStateOnce() async {
        for fixture in [
            (AccessibilityContextReadStatus.notAuthorized,
             MacContextCaptureState.accessibilityNotAuthorized.rawValue),
            (AccessibilityContextReadStatus.targetUnavailable,
             MacContextCaptureState.targetUnavailable.rawValue),
            (AccessibilityContextReadStatus.failed,
             MacContextCaptureState.accessibilityFailed.rawValue),
        ] {
            let diagnostics = AppDiagnosticRecorderSpy()
            let subject = SystemMacContextSnapshotter(
                workspace: MacContextWorkspaceStub(target: .editor),
                accessibility: MacContextAccessibilityStub(result: .init(status: fixture.0)),
                diagnostics: diagnostics,
                now: MacContextNowStub(values: [20, 23]))

            _ = await subject.capture(.editor)

            let entries = diagnostics.snapshot()
            #expect(entries.count == 2)
            #expect(entries[1].fields["capture_state"] == fixture.1)
            #expect(entries[1].fields["terminal_state"] == "fallback")
            #expect(entries[1].fields["duration_ms"] == "3")
        }
    }

    @MainActor @Test func capture_WhenDeadlineWins_RecordsTimedOutMetadataAndSuppressesLateWorker()
        async
    {
        let diagnostics = AppDiagnosticRecorderSpy()
        let executor = QueuedMacContextExecutor()
        let subject = SystemMacContextSnapshotter(
            workspace: MacContextWorkspaceStub(target: .editor),
            accessibility: MacContextAccessibilityStub(result: .init(
                status: .complete,
                selectedText: "late diagnostic sentinel")),
            executor: executor,
            clock: ImmediateDiagnosticClock(),
            diagnostics: diagnostics,
            now: MacContextNowStub(values: [30, 38, 50]))

        _ = await subject.capture(.editor)
        executor.runNext()

        let entries = diagnostics.snapshot()
        #expect(entries.count == 2)
        #expect(entries[1].fields["capture_state"] == "timed_out")
        #expect(entries[1].fields["terminal_state"] == "timed_out")
        #expect(entries[1].fields["duration_ms"] == "8")
        #expect(!entries.flatMap(\.fields.values).contains("late diagnostic sentinel"))
    }

    @MainActor @Test func capture_WhenCancelledBeforeWorkerStarts_RecordsCancelledMetadataOnce()
        async
    {
        let diagnostics = AppDiagnosticRecorderSpy()
        let executor = QueuedMacContextExecutor()
        let subject = SystemMacContextSnapshotter(
            workspace: MacContextWorkspaceStub(target: .editor),
            accessibility: MacContextAccessibilityStub(result: .init(status: .complete)),
            executor: executor,
            clock: WaitingDiagnosticClock(),
            diagnostics: diagnostics,
            now: MacContextNowStub(values: [60, 67]))
        let capture = Task { await subject.capture(.editor) }

        await executor.waitForOperationCount(1)
        capture.cancel()
        _ = await capture.value
        executor.runNext()

        let entries = diagnostics.snapshot()
        #expect(entries.count == 2)
        #expect(entries[1].fields["capture_state"] == "timed_out")
        #expect(entries[1].fields["terminal_state"] == "cancelled")
        #expect(entries[1].fields["duration_ms"] == "7")
    }

    @MainActor @Test func capture_WhenFlushedToJSONL_PersistsSafeMetadataWithoutSnapshotValues()
        async throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = try JSONLVoiceActivationDiagnosticRecorder(directoryURL: directory)
        let selectedValue = "jsonl selection sentinel"
        let titleValue = "jsonl title sentinel"
        let uriValue = "file:///jsonl-sentinel"
        let resourceName = "jsonl-resource-sentinel"
        let subject = SystemMacContextSnapshotter(
            workspace: MacContextWorkspaceStub(target: .editor),
            accessibility: MacContextAccessibilityStub(result: .init(
                status: .complete,
                windowTitle: titleValue,
                documentURL: uriValue,
                selectedText: selectedValue,
                resources: [.init(uri: uriValue, name: resourceName)])),
            diagnostics: recorder,
            now: MacContextNowStub(values: [1, 2]))

        _ = await subject.capture(.editor)
        recorder.flush()

        let contents = try String(contentsOf: recorder.currentLogURL, encoding: .utf8)
        let records = try contents.split(separator: "\n").map {
            try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
        #expect(records.map { $0["event"] as? String } == [
            "mac_context.capture_started",
            "mac_context.capture_finished",
        ])
        let fields = try #require(records[1]["fields"] as? [String: String])
        #expect(fields == [
            "capture_state": "complete",
            "terminal_state": "completed",
            "duration_ms": "1",
            "has_window_title": "true",
            "has_document_url": "true",
            "has_selection": "true",
            "selection_byte_count": "24",
            "resource_count": "1",
        ])
        #expect(!contents.contains(selectedValue))
        #expect(!contents.contains(titleValue))
        #expect(!contents.contains(uriValue))
        #expect(!contents.contains(resourceName))
        #expect(!contents.contains("diagnostic-app-sentinel"))
        #expect(!contents.contains("diagnostic.bundle.sentinel"))
    }
}

private extension MacContextTarget {
    static let editor = MacContextTarget(
        processIdentifier: 44,
        applicationName: "diagnostic-app-sentinel",
        bundleIdentifier: "diagnostic.bundle.sentinel")
}

@MainActor
private struct MacContextWorkspaceStub: WorkspaceContextReading {
    let target: MacContextTarget?

    func currentTarget() -> MacContextTarget? { target }
}

private struct MacContextAccessibilityStub: AccessibilityContextReading {
    let result: AccessibilityContextReadResult

    func readContext(processIdentifier: Int32) -> AccessibilityContextReadResult { result }
}

private struct ImmediateDiagnosticClock: MacContextClock {
    func sleep(for duration: Duration) async {}
}

private struct WaitingDiagnosticClock: MacContextClock {
    func sleep(for duration: Duration) async {
        try? await ContinuousClock().sleep(for: .seconds(3_600))
    }
}

private final class MacContextNowStub: MacContextNow, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UInt64]

    init(values: [UInt64]) {
        self.values = values
    }

    func uptimeMilliseconds() -> UInt64 {
        lock.withLock { values.removeFirst() }
    }
}

private final class QueuedMacContextExecutor: MacContextExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private var operations: [@Sendable () -> Void] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func execute(_ operation: @escaping @Sendable () -> Void) {
        let pendingWaiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            operations.append(operation)
            let pendingWaiters = waiters
            self.waiters.removeAll()
            return pendingWaiters
        }
        for waiter in pendingWaiters { waiter.resume() }
    }

    func waitForOperationCount(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock { () -> Bool in
                guard operations.count < count else { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func runNext() {
        let operation = lock.withLock { operations.isEmpty ? nil : operations.removeFirst() }
        operation?()
    }
}
