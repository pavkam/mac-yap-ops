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

struct MenuWindowShadowRefreshView: NSViewRepresentable {
    let layoutIdentity: MenuContentLayoutIdentity

    func makeNSView(context: Context) -> MenuWindowShadowRefreshNSView {
        let view = MenuWindowShadowRefreshNSView()
        view.update(layoutIdentity: layoutIdentity)
        return view
    }

    func updateNSView(_ nsView: MenuWindowShadowRefreshNSView, context: Context) {
        nsView.update(layoutIdentity: layoutIdentity)
    }
}

@MainActor
final class MenuWindowShadowRefreshNSView: NSView {
    private var layoutIdentity: MenuContentLayoutIdentity?
    private var refreshTask: Task<Void, Never>?

    func update(layoutIdentity: MenuContentLayoutIdentity) {
        guard self.layoutIdentity != layoutIdentity else { return }
        self.layoutIdentity = layoutIdentity
        scheduleRefresh()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            window?.invalidateShadow()
            refreshTask = nil
        }
    }
}
