// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

struct MenuContentLayoutIdentity: Equatable {
    let showsLastCommand: Bool
    let agentControls: AgentControls
    let profileCount: Int
    let showsCaptureCancellation: Bool

    enum AgentControls: Equatable {
        case active
        case terminal
        case hidden
    }
}

struct MenuWindowConfigurationView: NSViewRepresentable {
    let layoutIdentity: MenuContentLayoutIdentity

    func makeNSView(context: Context) -> MenuWindowConfigurationNSView {
        let view = MenuWindowConfigurationNSView()
        view.update(layoutIdentity: layoutIdentity)
        return view
    }

    func updateNSView(_ nsView: MenuWindowConfigurationNSView, context: Context) {
        nsView.update(layoutIdentity: layoutIdentity)
    }
}

@MainActor
final class MenuWindowConfigurationNSView: NSView {
    private var layoutIdentity: MenuContentLayoutIdentity?
    private var configurationTask: Task<Void, Never>?

    func update(layoutIdentity: MenuContentLayoutIdentity) {
        guard self.layoutIdentity != layoutIdentity else { return }
        self.layoutIdentity = layoutIdentity
        configureWindow()
        scheduleConfiguration()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        configureWindow()
        scheduleConfiguration()
    }

    private func scheduleConfiguration() {
        configurationTask?.cancel()
        configurationTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            configureWindow()
            configurationTask = nil
        }
    }

    private func configureWindow() {
        guard let window, window.hasShadow else { return }
        window.hasShadow = false
    }
}
