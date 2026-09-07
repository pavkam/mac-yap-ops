// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Testing
@testable import YapOpsCore

struct RestorationPolicyCase: Sendable {
    let need: AgentSessionRestorationNeed
    let loadSession: Bool
    let resumeSession: Bool
    let expected: AgentSessionRestorationOperation
}

@Suite struct AgentSessionRestorationPolicyTests {
    @Test(arguments: [
        RestorationPolicyCase(need: .visibleHistory, loadSession: false, resumeSession: false, expected: .new),
        RestorationPolicyCase(need: .visibleHistory, loadSession: false, resumeSession: true, expected: .resume),
        RestorationPolicyCase(need: .visibleHistory, loadSession: true, resumeSession: false, expected: .load),
        RestorationPolicyCase(need: .visibleHistory, loadSession: true, resumeSession: true, expected: .load),
        RestorationPolicyCase(need: .contextOnly, loadSession: false, resumeSession: false, expected: .new),
        RestorationPolicyCase(need: .contextOnly, loadSession: false, resumeSession: true, expected: .resume),
        RestorationPolicyCase(need: .contextOnly, loadSession: true, resumeSession: false, expected: .loadDiscardingReplay),
        RestorationPolicyCase(need: .contextOnly, loadSession: true, resumeSession: true, expected: .resume),
    ])
    func operation_ForEveryCapabilityCombination_MatchesNormativeTable(
        fixture: RestorationPolicyCase
    ) {
        let operation = AgentSessionRestorationPolicy.operation(
            need: fixture.need,
            capabilities: .init(
                loadSession: fixture.loadSession,
                resumeSession: fixture.resumeSession))

        #expect(operation == fixture.expected)
    }
}
