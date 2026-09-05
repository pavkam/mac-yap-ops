// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import VoiceActivationCore

extension AgentRunPanelView {
    func requestCard(_ snapshot: AgentRunSnapshot) -> some View {
        userBubble(snapshot.prompt, label: "Request")
    }

    @ViewBuilder
    func timeline(_ snapshot: AgentRunSnapshot) -> some View {
        if snapshot.timeline.isEmpty,
           snapshot.phase == .running || snapshot.phase == .cancelling
        {
            HStack(spacing: 10) {
                AgentRunWorkingGlyph(tint: accent, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.phase == .cancelling ? "Wrapping up" : "Starting")
                        .font(.callout.weight(.semibold))
                    Text(snapshot.phase == .cancelling
                        ? "Waiting for the agent to stop safely"
                        : "Connecting to \(snapshot.providerName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            ForEach(snapshot.timeline) { item in
                switch item {
                case .omitted:
                    Label("Earlier activity omitted", systemImage: "ellipsis.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case let .message(message):
                    messageBlock(message)
                case let .userMessage(message):
                    userMessageBlock(message)
                case let .thinking(thinking):
                    thinkingCard(thinking)
                }
            }
        }
    }

    func messageBlock(_ message: AgentMessagePresentation) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionLabel(
                message.kind == .thought
                    ? "Thinking"
                    : model.snapshot?.providerName ?? "Agent",
                symbol: message.kind == .thought ? "brain.head.profile" : "sparkles")
            AgentMarkdownView(markdown: message.text)
                .font(.body)
                .foregroundStyle(message.kind == .thought ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .tint(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, message.kind == .thought ? 12 : 0)
    }

    func userMessageBlock(_ message: AgentUserMessagePresentation) -> some View {
        userBubble(message.text, label: "Follow-up")
    }

    @ViewBuilder
    func noticeCards(_ snapshot: AgentRunSnapshot) -> some View {
        ForEach(Array(snapshot.notices.enumerated()), id: \.offset) { _, notice in
            Label {
                Text(notice)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(10)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    @ViewBuilder
    func failureCard(_ snapshot: AgentRunSnapshot) -> some View {
        if case let .failed(message) = snapshot.phase {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Agent stopped")
                        .font(.callout.weight(.semibold))
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.red.opacity(0.45), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
