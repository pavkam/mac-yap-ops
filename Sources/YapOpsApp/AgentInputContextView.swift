// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import YapOpsCore

struct AgentInputContextPresentation {
    let summary: AgentInputContextSummary

    var isLimited: Bool {
        summary.captureState != nil && (summary.captureState != .complete || summary.isTruncated)
    }
    var symbol: String { isLimited ? "exclamationmark.circle" : "macwindow" }

    var title: String {
        guard let app = summary.applicationName else { return "No Mac context" }
        return "Context from \(app)"
    }

    var detail: String {
        var captured: [String] = []
        if summary.hasWindow { captured.append("Window") }
        if summary.hasDocument { captured.append("Document link") }
        if summary.hasSelectedText { captured.append("Selected text") }
        if summary.resourceCount > 0 {
            captured.append(summary.resourceCount == 1
                ? "1 selected item" : "\(summary.resourceCount) selected items")
        }
        switch summary.captureState {
        case nil:
            return "Context is off or no focused app was available."
        case .accessibilityNotAuthorized:
            return "App name only. Enable Accessibility in YapOps Settings for selections."
        case .targetUnavailable:
            return "App name only. The focused app was no longer available."
        case .timedOut:
            return "App name only. The focused app did not respond in time."
        case .accessibilityFailed:
            captured.append("Some context was unavailable")
        case .complete:
            if !summary.hasSelectedText && summary.resourceCount == 0 {
                captured.append("No selection")
            }
        }
        if summary.isTruncated { captured.append("Some context was shortened or omitted") }
        return captured.joined(separator: " · ")
    }
}

/// Describes a request's captured context without displaying the selection itself.
struct AgentInputContextView: View {
    let summary: AgentInputContextSummary

    private var presentation: AgentInputContextPresentation {
        AgentInputContextPresentation(summary: summary)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: presentation.symbol)
                .foregroundStyle(presentation.isLimited ? Color.orange : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .fontWeight(.medium)
                    .lineLimit(2)
                Text(presentation.detail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mac context")
        .accessibilityValue(presentation.title + ". " + presentation.detail)
    }
}
