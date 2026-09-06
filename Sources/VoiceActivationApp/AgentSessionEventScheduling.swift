// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import VoiceActivationCore

protocol AgentSessionEventScheduling: Sendable {
    func schedule(_ operation: @escaping @MainActor @Sendable () -> Void)
}

struct MainRunLoopAgentSessionEventScheduler: AgentSessionEventScheduling {
    func schedule(_ operation: @escaping @MainActor @Sendable () -> Void) {
        MainRunLoopScheduler.shared.schedule(operation)
    }
}
