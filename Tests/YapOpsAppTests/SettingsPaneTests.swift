// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AppKit
import Testing
@testable import YapOpsApp

struct SettingsPaneTests {
    @Test(arguments: SettingsPane.allCases)
    func image_WhenUsedBySettingsTab_Resolves(pane: SettingsPane) {
        let image = NSImage(
            systemSymbolName: pane.symbol,
            accessibilityDescription: nil)

        #expect(image != nil)
    }
}
