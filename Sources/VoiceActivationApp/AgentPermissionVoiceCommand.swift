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
            return selection(
                preferred: .allowAlways,
                fallback: .allowOnce,
                options: options)
        }
        if allowOncePhrases.contains(phrase) {
            return selection(
                preferred: .allowOnce,
                fallback: .allowAlways,
                options: options)
        }
        if rejectAlwaysPhrases.contains(phrase) {
            return selection(
                preferred: .rejectAlways,
                fallback: .rejectOnce,
                options: options)
        }
        if rejectOncePhrases.contains(phrase) {
            return selection(
                preferred: .rejectOnce,
                fallback: .rejectAlways,
                options: options)
        }
        return nil
    }

    private static func selection(
        preferred: AgentPermissionOptionKind,
        fallback: AgentPermissionOptionKind,
        options: [AgentPermissionOption]
    ) -> AgentPermissionVoiceDecision?
    {
        let preferredOptions = options.filter { $0.kind == preferred }
        if preferredOptions.count == 1, let option = preferredOptions.first {
            return .select(optionID: option.id)
        }
        guard preferredOptions.isEmpty else {
            return nil
        }
        let fallbackOptions = options.filter { $0.kind == fallback }
        if fallbackOptions.count == 1, let option = fallbackOptions.first {
            return .select(optionID: option.id)
        }
        return nil
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
