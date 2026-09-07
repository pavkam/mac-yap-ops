// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import YapOpsCore

extension AgentRunPresentation {
    /// Attaches capture metadata only to its live, retained local request.
    func receiveContext(runID: UUID, inputID: UUID?, summary: AgentInputContextSummary) {
        guard self.runID == runID, phase == .running || phase == .listening else { return }
        if let inputID {
            guard let index = timeline.firstIndex(where: { item in
                guard case .userMessage(let message) = item else { return false }
                return message.id == inputID && message.disposition != nil
            }), case .userMessage(var message) = timeline[index],
                message.contextSummary != summary
            else { return }
            flushPendingPublication()
            message.contextSummary = summary
            timeline[index] = .userMessage(message)
        } else {
            guard promptContext != summary else { return }
            flushPendingPublication()
            promptContext = summary
        }
        publishNow()
    }
}
