// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

@testable import YapOpsCore

final class AppDiagnosticRecorderSpy: YapOpsDiagnosticRecording,
    @unchecked Sendable
{
    struct Entry: Sendable {
        let category: YapOpsDiagnosticCategory
        let event: String
        let level: YapOpsDiagnosticLevel
        let fields: [String: String]
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    func record(
        category: YapOpsDiagnosticCategory,
        event: String,
        level: YapOpsDiagnosticLevel,
        fields: [String: String]
    ) {
        lock.lock()
        entries.append(
            Entry(
                category: category,
                event: event,
                level: level,
                fields: fields))
        lock.unlock()
    }

    func flush() {}

    func snapshot() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}
