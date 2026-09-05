// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import SwiftUI
import VoiceActivationCore

extension AgentRunPanelView {
    @ViewBuilder
    func plan(_ snapshot: AgentRunSnapshot) -> some View {
        if !snapshot.plan.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                sectionLabel("Plan", symbol: "list.bullet.clipboard")
                ForEach(Array(snapshot.plan.enumerated()), id: \.offset) { _, entry in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Image(systemName: planSymbol(entry.status))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(entry.status == .inProgress ? accent : .secondary)
                            .accessibilityHidden(true)
                        Text(entry.content)
                            .font(.callout)
                            .foregroundStyle(
                                entry.status == .completed ? .secondary : .primary)
                    }
                }
            }
        }
    }

    func thinkingCard(_ thinking: AgentThinkingPresentation) -> some View {
        let isExpanded = model.isThinkingExpanded(thinkingID: thinking.id)
        let detailCount = thinking.details.count
        let detailCountLabel = thinking.omittedDetailCount > 0
            ? "\(detailCount)+ steps"
            : "\(detailCount) \(detailCount == 1 ? "step" : "steps")"
        let detailSummary = thinking.isWorking && detailCount == 0
            ? "Starting the agent"
            : "\(detailCountLabel) · \(isExpanded ? "Hide" : "Show") details"

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.22)) {
                    model.toggleThinkingDetails(thinkingID: thinking.id)
                }
            } label: {
                HStack(spacing: 10) {
                    thinkingActivityIcon(thinking)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(thinking.isWorking ? "Thinking…" : "Thinking")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(thinking.hasFailedTool ? .red : .primary)
                        Text(detailSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    panelSeparator
                    if thinking.omittedDetailCount > 0 {
                        Label(
                            "\(thinking.omittedDetailCount) earlier steps omitted",
                            systemImage: "ellipsis.circle")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(thinking.details) { detail in
                        thinkingDetail(detail)
                    }
                }
                .padding(.top, 10)
                .padding(.leading, 30)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(11)
        .background(.quaternary.opacity(thinking.isWorking ? 0.45 : 0.25),
                    in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    func thinkingActivityIcon(_ thinking: AgentThinkingPresentation) -> some View {
        if thinking.isWorking {
            AgentRunWorkingGlyph(tint: accent, size: 24)
        } else {
            Image(systemName: thinking.hasFailedTool
                ? "exclamationmark.circle.fill"
                : "checkmark.circle")
                .font(.body)
                .foregroundStyle(thinking.hasFailedTool ? .red : .secondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    func thinkingDetail(_ detail: AgentThinkingDetail) -> some View {
        switch detail {
        case let .thought(message):
            VStack(alignment: .leading, spacing: 5) {
                sectionLabel("Reasoning", symbol: "brain.head.profile")
                AgentMarkdownView(markdown: message.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        case let .tool(tool):
            HStack(alignment: .top, spacing: 8) {
                toolActivityIcon(tool)
                VStack(alignment: .leading, spacing: 2) {
                    Text(toolSummary(tool))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tool.status == .failed ? .red : .secondary)
                    Text(tool.title)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    func toolActivityIcon(_ tool: AgentToolPresentation) -> some View {
        if tool.isWorking {
            AgentRunWorkingGlyph(tint: accent, size: 18)
        } else {
            Image(systemName: toolSymbol(tool))
                .font(.caption.weight(.semibold))
                .foregroundStyle(tool.status == .failed ? .red : .secondary)
                .frame(width: 18, height: 18, alignment: .topLeading)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    func permissions(_ snapshot: AgentRunSnapshot) -> some View {
        ForEach(snapshot.permissions) { permission in
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Permission requested")
                            .font(.callout.weight(.semibold))
                        Text(permission.toolTitle)
                            .font(.body)
                        Text("Say “allow”, “allow all”, “deny”, or “deny all”.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(accent)
                }

                HStack {
                    ForEach(permission.options, id: \.id) { option in
                        permissionButton(option, permission: permission)
                    }
                }
                .controlSize(.small)
            }
            .padding(12)
            .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(accent.opacity(0.5), lineWidth: 1)
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.2),
            value: snapshot.permissions.map(\.id))
    }

    @ViewBuilder
    private func permissionButton(
        _ option: AgentPermissionOption,
        permission: AgentPermissionPresentation
    ) -> some View {
        let isAllow = option.kind == .allowOnce || option.kind == .allowAlways
        let button = Button(option.label) {
            model.selectPermission(permission, optionID: option.id)
        }
        .disabled(permission.isResolving || model.resolvingPermissions.contains(permission.key))

        if isAllow {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}
