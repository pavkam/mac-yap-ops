// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import YapOpsCore

extension YapOpsCoordinatorTests {
    @MainActor @Test
    func newConversation_RequestsFreshSession_AndOnlyFollowUpsRestoreContext() async throws {
        let fixture = try Fixture(profiles: [try makeAgentProfile()])
        defer { fixture.coordinator.stop() }
        fixture.coordinator.setPassiveEnabled(true)
        fixture.speech.emit("agent first", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 1 }
        let firstRunID = try #require(fixture.coordinator.activeAgentRunID)
        await fixture.agentRunner.complete(runIndex: 0)
        await waitUntil { fixture.coordinator.executionTask == nil }
        fixture.speech.emit("follow up", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 2 }
        #expect(fixture.coordinator.activeAgentRunID == firstRunID)
        await fixture.agentRunner.complete(runIndex: 1)
        await waitUntil { fixture.coordinator.executionTask == nil }

        fixture.coordinator.endAgentConversation()
        await waitUntil { fixture.speech.mode == .passiveWake }
        fixture.speech.emit("agent start again", isFinal: true)
        await waitUntil { await fixture.agentRunner.recordedInvocations().count == 3 }

        #expect(fixture.coordinator.activeAgentRunID != firstRunID)
        #expect(await fixture.agentRunner.recordedInvocations().map(\.restorationNeed)
            == [.fresh, .visibleHistory, .fresh])
        await fixture.agentRunner.complete(runIndex: 2)
    }
}
