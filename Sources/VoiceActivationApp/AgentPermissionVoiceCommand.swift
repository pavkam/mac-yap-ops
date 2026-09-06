// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import VoiceActivationCore

enum AgentPermissionVoiceDecision: Equatable {
    case select(optionID: String)
    case cancel
}

enum AgentPermissionVoiceCommand {
    private static let allowOncePhrases: Set<String> = [
        "allow", "allow once", "approve", "approve once", "yes",
    ]
    private static let allowAlwaysPhrases: Set<String> = [
        "allow all", "allow always", "always allow", "approve all", "always approve",
    ]
    private static let rejectOncePhrases: Set<String> = [
        "deny", "deny once", "no", "reject", "reject once",
    ]
    private static let rejectAlwaysPhrases: Set<String> = [
        "always deny", "always reject", "deny all", "deny always", "never allow",
        "reject all", "reject always",
    ]

    static func match(
        _ transcript: String,
        options: [AgentPermissionOption]) -> AgentPermissionVoiceDecision?
    {
        let phrase = normalized(transcript)
        guard !phrase.isEmpty else { return nil }

        let exact = options.filter { normalized($0.label) == phrase }
        if exact.count == 1, let option = exact.first {
            return .select(optionID: option.id)
        }
        if exact.count > 1 {
            return nil
        }
        if allowAlwaysPhrases.contains(phrase) {
            return selectionResult(
                preferred: .allowAlways,
                fallback: .allowOnce,
                options: options).decision
        }
        if allowOncePhrases.contains(phrase) {
            return selectionResult(
                preferred: .allowOnce,
                fallback: .allowAlways,
                options: options).decision
        }
        if rejectAlwaysPhrases.contains(phrase) {
            let result = selectionResult(
                preferred: .rejectAlways,
                fallback: .rejectOnce,
                options: options)
            return result.isUnavailable ? .cancel : result.decision
        }
        if rejectOncePhrases.contains(phrase) {
            let result = selectionResult(
                preferred: .rejectOnce,
                fallback: .rejectAlways,
                options: options)
            return result.isUnavailable ? .cancel : result.decision
        }
        return nil
    }

    private struct SelectionResult {
        let decision: AgentPermissionVoiceDecision?
        let isUnavailable: Bool
    }

    private static func selectionResult(
        preferred: AgentPermissionOptionKind,
        fallback: AgentPermissionOptionKind,
        options: [AgentPermissionOption]
    ) -> SelectionResult
    {
        let preferredOptions = options.filter { $0.kind == preferred }
        if preferredOptions.count == 1, let option = preferredOptions.first {
            return SelectionResult(
                decision: .select(optionID: option.id),
                isUnavailable: false)
        }
        guard preferredOptions.isEmpty else {
            return SelectionResult(decision: nil, isUnavailable: false)
        }
        let fallbackOptions = options.filter { $0.kind == fallback }
        if fallbackOptions.count == 1, let option = fallbackOptions.first {
            return SelectionResult(
                decision: .select(optionID: option.id),
                isUnavailable: false)
        }
        return SelectionResult(
            decision: nil,
            isUnavailable: fallbackOptions.isEmpty)
    }

    private static func normalized(_ value: String) -> String {
        value
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map {
                String($0).folding(
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: Locale(identifier: "en_US_POSIX"))
            }
            .joined(separator: " ")
    }
}
