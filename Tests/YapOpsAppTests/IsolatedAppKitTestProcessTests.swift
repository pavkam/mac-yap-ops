// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing

struct IsolatedAppKitTestProcessTests {
    @MainActor @Test(.timeLimit(.minutes(1)))
    func run_WhenWaitingForChild_AllowsParentMainActorProgress() async throws {
        let childKey = "YAPOPS_ISOLATED_PROCESS_RESPONSIVENESS_CHILD"
        guard ProcessInfo.processInfo.environment[childKey] != "1" else {
            try await Task.sleep(for: .milliseconds(50))
            return
        }

        var mainActorAdvanced = false
        let heartbeat = Task { @MainActor in mainActorAdvanced = true }

        try await IsolatedAppKitTestProcess.run(
            environmentKey: childKey,
            testFilter: "run_WhenWaitingForChild_AllowsParentMainActorProgress")

        #expect(mainActorAdvanced)
        await heartbeat.value
    }
}
