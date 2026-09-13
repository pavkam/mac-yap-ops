// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI
import YapOpsCore

/// Opens and closes the first-run window.
///
/// SwiftUI's `openWindow`/`dismissWindow` actions only exist inside a view's
/// environment, and the app's own state (`AppPreferences`) lives in
/// `YapOpsApp`. This is the seam between the two, mirroring
/// `SettingsWindowPresenter`: activation is explicit because YapOps otherwise
/// never takes foreground, and a first-run window that opens behind every
/// other app is not a first-run flow.
@MainActor
enum FirstRunPresenter {
    static let windowID = "first-run"

    static func present(with openWindow: OpenWindowAction) {
        YapOpsDiagnostics.shared.record(
            category: .ui,
            event: "first_run.window_open_requested")
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: windowID)
    }

    /// Closes the first-run window by title, since the presenter has no
    /// `dismissWindow` action of its own — `FirstRunView`'s environment does,
    /// but threading a second action through its `onFinish` closure for one
    /// call is more indirection than the window lookup below.
    static func dismiss() {
        YapOpsDiagnostics.shared.record(
            category: .ui,
            event: "first_run.window_dismissed")
        NSApplication.shared.windows
            .first { $0.identifier?.rawValue == windowID }?
            .close()
    }
}
