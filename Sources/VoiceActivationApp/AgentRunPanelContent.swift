// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import VoiceActivationCore

extension AgentRunPanelView {
    func requestCard(_ snapshot: AgentRunSnapshot) -> some View {
        userBubble(snapshot.prompt, label: "Request")
    }

    func miniAgentMark(_ snapshot: AgentRunSnapshot) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [accent, accent.opacity(0.68)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing))
            Circle().stroke(.white.opacity(0.28), lineWidth: 0.7)
            ProfileIconGlyph(icon: snapshot.profileIcon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 27, height: 27)
        .shadow(color: accent.opacity(0.18), radius: 5, y: 2)
        .accessibilityHidden(true)
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
                case .historyBoundary:
                    Label("Previous provider history", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case let .message(message):
                    messageBlock(message, snapshot: snapshot)
                case let .userMessage(message):
                    userMessageBlock(message)
                case let .thinking(thinking):
                    thinkingCard(thinking)
                }
            }
        }
    }

    func messageBlock(
        _ message: AgentMessagePresentation,
        snapshot: AgentRunSnapshot
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if message.kind == .response {
                miniAgentMark(snapshot)
            }

            VStack(alignment: .leading, spacing: 8) {
                if message.kind == .thought {
                    sectionLabel("Thinking", symbol: "brain.head.profile")
                } else {
                    Label {
                        Text(snapshot.profileName)
                    } icon: {
                        ProfileIconGlyph(icon: snapshot.profileIcon)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                AgentMarkdownView(
                    markdown: message.text,
                    accent: accent,
                    style: message.kind == .thought ? .detail : .response)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.white.opacity(message.kind == .thought ? 0.035 : 0.055))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, message.kind == .thought ? 12 : 0)
    }

    func userMessageBlock(_ message: AgentUserMessagePresentation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            userBubble(message.text, label: "Follow-up")
            if let transport = message.transportPresentation {
                Text(transport.caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                    .accessibilityLabel(transport.accessibilityValue)
                    .accessibilityValue(transport.accessibilityValue)
                    .accessibilityHint(transport.accessibilityValue)
            }
        }
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
