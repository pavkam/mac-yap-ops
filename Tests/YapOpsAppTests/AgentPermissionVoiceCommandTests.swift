// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Testing
@testable import YapOpsApp
import YapOpsCore

struct AgentPermissionVoiceCommandTests {
    private let options = [
        AgentPermissionOption(id: "allow-once", label: "Allow once", kind: .allowOnce),
        AgentPermissionOption(id: "allow-always", label: "Allow always", kind: .allowAlways),
        AgentPermissionOption(id: "deny-once", label: "Deny", kind: .rejectOnce),
        AgentPermissionOption(id: "deny-always", label: "Never allow", kind: .rejectAlways),
    ]

    @Test func match_WhenSpokenChoiceNamesPermission_SelectsMatchingScope() {
        #expect(AgentPermissionVoiceCommand.match("allow", options: options)
            == .select(optionID: "allow-once"))
        #expect(AgentPermissionVoiceCommand.match("allow all", options: options)
            == .select(optionID: "allow-always"))
        #expect(AgentPermissionVoiceCommand.match("deny", options: options)
            == .select(optionID: "deny-once"))
        #expect(AgentPermissionVoiceCommand.match("deny all", options: options)
            == .select(optionID: "deny-always"))
    }

    @Test func match_WhenSpokenChoiceUsesAgentLabel_SelectsExactOption() {
        #expect(AgentPermissionVoiceCommand.match("Never allow!", options: options)
            == .select(optionID: "deny-always"))
    }

    @Test func match_WhenPhraseIsNormalFollowUp_DoesNotConsumeIt() {
        #expect(AgentPermissionVoiceCommand.match(
            "allow the tests to finish and summarize them",
            options: options) == nil)
    }

    @Test func match_WhenDenyOptionIsMissing_ReturnsNoDecision() {
        let allowOnly = [
            AgentPermissionOption(id: "allow-once", label: "Allow", kind: .allowOnce),
        ]

        #expect(AgentPermissionVoiceCommand.match("deny", options: allowOnly) == nil)
    }

    @Test func match_WhenNormalizedLabelsAreDuplicated_ReturnsNoDecision() {
        let duplicated = [
            AgentPermissionOption(id: "first", label: "Allow once", kind: .allowOnce),
            AgentPermissionOption(id: "second", label: "allow-once", kind: .allowOnce),
        ]

        #expect(AgentPermissionVoiceCommand.match("ALLOW ONCE!", options: duplicated) == nil)
    }

    @Test func match_WhenSemanticChoiceIsAmbiguous_ReturnsNoDecision() {
        let duplicated = [
            AgentPermissionOption(id: "first", label: "Approve this", kind: .allowOnce),
            AgentPermissionOption(id: "second", label: "Proceed", kind: .allowOnce),
        ]

        #expect(AgentPermissionVoiceCommand.match("allow", options: duplicated) == nil)
    }
}
