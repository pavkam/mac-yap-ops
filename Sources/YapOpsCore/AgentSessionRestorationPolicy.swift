// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

/// Selects the capability-gated ACP operation for one session restoration need.
public enum AgentSessionRestorationPolicy {
    /// Chooses load, resume, or a fresh session from runtime-advertised capabilities.
    ///
    /// Provider presets intentionally do not participate: only the current
    /// `initialize` advertisement is authoritative.
    /// - Parameters:
    ///   - need: Whether to start fresh or restore visible history or provider context.
    ///   - capabilities: The strictly decoded runtime capability advertisement.
    /// - Returns: The one safe operation permitted by the normative capability table.
    public static func operation(
        need: AgentSessionRestorationNeed,
        capabilities: ACPSessionRestorationCapabilities
    ) -> AgentSessionRestorationOperation {
        switch need {
        case .visibleHistory where capabilities.loadSession:
            .load
        case .contextOnly where capabilities.resumeSession:
            .resume
        case .visibleHistory where capabilities.resumeSession:
            .resume
        case .contextOnly where capabilities.loadSession:
            .loadDiscardingReplay
        default:
            .new
        }
    }
}
