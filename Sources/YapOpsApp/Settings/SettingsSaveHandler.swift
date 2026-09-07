// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import YapOpsCore

@MainActor
enum SettingsSaveHandler {
    @discardableResult
    static func perform(save: () async -> Bool, close: () -> Void) async -> Bool {
        YapOpsDiagnostics.shared.record(
            category: .ui,
            event: "settings.save_button_clicked")
        let saved = await save()
        if saved {
            close()
            YapOpsDiagnostics.shared.record(
                category: .ui,
                event: "settings.window_close_after_save")
        }
        return saved
    }
}
