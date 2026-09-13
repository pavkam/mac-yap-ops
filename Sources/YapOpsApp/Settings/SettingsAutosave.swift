// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import YapOpsCore

/// Debounces Settings edits into saves, and owns the receipt the user sees.
///
/// An explicit "Save Settings" button applied all three tabs at once, which left
/// it unclear what was pending: you could change a wake phrase on Profiles, a
/// voice on Speech, and have no indication that either was unsaved. Autosave
/// removes the question — but autosave without a visible receipt is worse than
/// an explicit save, because now nothing tells you the write happened. The
/// receipt is not decoration; it is the half of this change that makes it safe.
///
/// Edits are debounced because a save validates every profile: saving on each
/// keystroke would spend the window reporting "Trigger phrase is required" at
/// someone in the middle of typing one.
@MainActor
@Observable
final class SettingsAutosave {
    /// What the receipt shows.
    enum Status: Equatable {
        /// No edit since the last settled state.
        case idle
        /// An edit landed and is waiting out the debounce, or is being written.
        case saving
        /// The last write succeeded.
        case saved
        /// The last write was rejected. Carries the validation message.
        case failed(String)
    }

    private(set) var status: Status = .idle

    /// How long to wait after the last edit. Long enough to type a wake phrase
    /// through, short enough that the receipt still feels like a response.
    private let debounce: Duration
    private let clock: any Clock<Duration>
    private var pendingSave: Task<Void, Never>?
    private var receiptReset: Task<Void, Never>?

    init(
        debounce: Duration = .milliseconds(900),
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.debounce = debounce
        self.clock = clock
    }

    /// Records an edit and schedules a save once edits stop.
    ///
    /// Each call supersedes the one before it: the previous timer is cancelled
    /// so a burst of keystrokes produces exactly one write, and a save that has
    /// been superseded cannot report a receipt for state that no longer exists.
    func edited(save: @escaping () async -> Bool, errorMessage: @escaping () -> String?) {
        pendingSave?.cancel()
        receiptReset?.cancel()
        status = .saving

        pendingSave = Task { [debounce, clock] in
            do {
                try await clock.sleep(for: debounce)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            let succeeded = await save()
            guard !Task.isCancelled else { return }

            if succeeded {
                status = .saved
                scheduleReceiptReset()
            } else {
                status = .failed(errorMessage() ?? "Settings could not be saved.")
            }
        }
    }

    /// Writes any pending edit immediately, for window close.
    ///
    /// Without this, closing Settings inside the debounce window silently
    /// discards the last edit — the exact failure autosave is supposed to remove.
    func flush(save: @escaping () async -> Bool, errorMessage: @escaping () -> String?) async {
        guard pendingSave != nil else { return }
        pendingSave?.cancel()
        pendingSave = nil

        status = .saving
        let succeeded = await save()
        status = succeeded ? .saved : .failed(errorMessage() ?? "Settings could not be saved.")
    }

    /// Awaits the in-flight debounce and save, for deterministic tests.
    ///
    /// Production never needs this: the receipt is the observable outcome.
    func settle() async {
        await pendingSave?.value
    }

    /// Drops a pending save without writing it.
    func cancel() {
        pendingSave?.cancel()
        pendingSave = nil
        receiptReset?.cancel()
        receiptReset = nil
        status = .idle
    }

    /// The receipt settles back to idle so a stale "Saved" does not imply the
    /// current state was just written.
    private func scheduleReceiptReset() {
        receiptReset = Task { [clock] in
            do {
                try await clock.sleep(for: .seconds(3))
            } catch {
                return
            }
            guard !Task.isCancelled, status == .saved else { return }
            status = .idle
        }
    }
}
