// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import YapOpsApp

@MainActor
@Suite struct SettingsAutosaveTests {
    /// A burst of keystrokes must produce exactly one write. Saving per
    /// keystroke would validate a half-typed wake phrase and report an error at
    /// someone mid-word.
    @Test func consecutiveEditsCollapseIntoOneSave() async {
        let autosave = SettingsAutosave(debounce: .zero)
        let saves = Counter()

        for _ in 0..<5 {
            autosave.edited(save: { await saves.increment(); return true }, errorMessage: { nil })
        }
        await autosave.settle()

        #expect(await saves.count == 1)
        #expect(autosave.status == .saved)
    }

    @Test func successfulSaveReportsTheReceipt() async {
        let autosave = SettingsAutosave(debounce: .zero)

        autosave.edited(save: { true }, errorMessage: { nil })
        await autosave.settle()

        #expect(autosave.status == .saved)
    }

    /// A rejected save surfaces the real validation message, not a generic one.
    @Test func rejectedSaveReportsTheValidationMessage() async {
        let autosave = SettingsAutosave(debounce: .zero)

        autosave.edited(save: { false }, errorMessage: { "Trigger phrase is required." })
        await autosave.settle()

        #expect(autosave.status == .failed("Trigger phrase is required."))
    }

    /// The model can reject without setting a message; the receipt must still
    /// say something truthful rather than rendering an empty error.
    @Test func rejectedSaveWithoutAMessageStillReports() async {
        let autosave = SettingsAutosave(debounce: .zero)

        autosave.edited(save: { false }, errorMessage: { nil })
        await autosave.settle()

        #expect(autosave.status == .failed("Settings could not be saved."))
    }

    /// Closing the window inside the debounce window must write, not discard.
    /// This is the failure autosave exists to remove.
    @Test func flushWritesAPendingEdit() async {
        let autosave = SettingsAutosave(debounce: .seconds(60))
        let saves = Counter()

        autosave.edited(save: { await saves.increment(); return true }, errorMessage: { nil })
        await autosave.flush(
            save: { await saves.increment(); return true },
            errorMessage: { nil })

        #expect(await saves.count == 1)
        #expect(autosave.status == .saved)
    }

    /// With nothing pending, closing the window must not write.
    @Test func flushWithoutAPendingEditDoesNothing() async {
        let autosave = SettingsAutosave(debounce: .zero)
        let saves = Counter()

        await autosave.flush(save: { await saves.increment(); return true }, errorMessage: { nil })

        #expect(await saves.count == 0)
        #expect(autosave.status == .idle)
    }

    /// A cancelled autosave cannot later report a receipt for state that no
    /// longer exists.
    @Test func cancelDropsThePendingSave() async {
        let autosave = SettingsAutosave(debounce: .seconds(60))
        let saves = Counter()

        autosave.edited(save: { await saves.increment(); return true }, errorMessage: { nil })
        autosave.cancel()
        await autosave.settle()

        #expect(await saves.count == 0)
        #expect(autosave.status == .idle)
    }

    @Test func anEditImmediatelyShowsSaving() {
        let autosave = SettingsAutosave(debounce: .seconds(60))

        autosave.edited(save: { true }, errorMessage: { nil })

        #expect(autosave.status == .saving)
    }
}

private actor Counter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}
