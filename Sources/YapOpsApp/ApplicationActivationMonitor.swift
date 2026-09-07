// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AppKit
import Foundation

@MainActor
final class ApplicationActivationMonitor {
    private let notificationCenter: NotificationCenter
    private var observer: NSObjectProtocol?

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    func start(model: AppModel) {
        stop()
        observer = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main)
        { [weak model] _ in
            MainActor.assumeIsolated {
                model?.applicationDidBecomeActive()
            }
        }
    }

    func stop() {
        guard let observer else { return }
        notificationCenter.removeObserver(observer)
        self.observer = nil
    }
}
