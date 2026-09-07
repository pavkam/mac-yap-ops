// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI
import YapOpsCore

/// Renders the movable expanded conversation panel and its compact notification form.
struct AgentRunPanelView: View {
    @Bindable var model: AgentRunPanelModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let cornerRadius: CGFloat = model.isMinimized ? 18 : 22
        ZStack {
            AgentRunPanelBackdrop()
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    Color(nsColor: .separatorColor),
                    lineWidth: contrast == .increased ? 1.5 : 0.5)
                .accessibilityHidden(true)
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .tint(accent)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .snappy(duration: AgentRunPanelLayout.transitionDuration),
            value: model.isMinimized)
    }

    @ViewBuilder
    var content: some View {
        if let snapshot = model.snapshot {
            if model.isMinimized {
                compactContent(snapshot)
                    .transition(presentationTransition)
            } else {
                expandedContent(snapshot)
                    .transition(presentationTransition)
            }
        }
    }

    func expandedContent(_ snapshot: AgentRunSnapshot) -> some View {
        VStack(spacing: 0) {
            header(snapshot)
            panelSeparator
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        requestCard(snapshot)
                        AgentRunArtifactShelf(snapshot: snapshot, model: model)
                        backgroundTasks(snapshot)
                        timeline(snapshot)
                        plan(snapshot)
                        noticeCards(snapshot)
                        failureCard(snapshot)
                        permissions(snapshot)
                        Color.clear.frame(height: 1).id("agent-run-bottom")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 16)
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(
                        0,
                        geometry.contentSize.height
                            - geometry.contentOffset.y
                            - geometry.containerSize.height)
                } action: { _, distanceFromBottom in
                    model.updateScrollGeometry(distanceFromBottom: distanceFromBottom)
                }
                .onScrollPhaseChange { oldPhase, newPhase, context in
                    let wasUserScrolling = oldPhase == .interacting
                        || oldPhase == .decelerating
                    let isUserScrolling = newPhase == .interacting
                        || newPhase == .decelerating
                    guard wasUserScrolling || isUserScrolling else { return }
                    let geometry = context.geometry
                    let distance = max(
                        0,
                        geometry.contentSize.height
                            - geometry.contentOffset.y
                            - geometry.containerSize.height)
                    if isUserScrolling {
                        model.beginUserScrolling(distanceFromBottom: distance)
                    } else {
                        model.endUserScrolling(distanceFromBottom: distance)
                    }
                }
                .onChange(of: snapshot.artifacts) { followBottom(proxy) }
                .onChange(of: snapshot.backgroundTasks) { followBottom(proxy) }
                .onChange(of: snapshot.timeline) { followBottom(proxy) }
                .onChange(of: snapshot.promptContext) { followBottom(proxy) }
                .onChange(of: snapshot.notices) { followBottom(proxy) }
                .onChange(of: snapshot.plan) { followBottom(proxy) }
                .onChange(of: snapshot.permissions) { followBottom(proxy) }
                .onChange(of: snapshot.phase) { followBottom(proxy) }
            }
            actionDock(snapshot)
        }
    }

    func followBottom(_ proxy: ScrollViewProxy) {
        guard model.isAutoFollowing else { return }
        proxy.scrollTo("agent-run-bottom", anchor: .bottom)
    }

    func header(_ snapshot: AgentRunSnapshot) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                ProfileIconGlyph(icon: snapshot.profileIcon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.profileName)
                        .font(.headline)
                    Text(panelPhaseLabel(snapshot))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay { AgentRunPanelDragSurface() }

            AgentRunElapsedTimeView(
                phase: snapshot.phase,
                elapsedSeconds: snapshot.elapsedSeconds,
                startedAt: model.elapsedStartedAt)

            Button {
                model.onAction?(.minimize(runID: snapshot.runID))
            } label: {
                Image(systemName: "minus")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Minimize conversation")
            .accessibilityLabel("Minimize conversation")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    func compactContent(_ snapshot: AgentRunSnapshot) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                ProfileIconGlyph(icon: snapshot.profileIcon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.profileName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(compactStatus(snapshot))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay { AgentRunPanelDragSurface() }

            AgentRunElapsedTimeView(
                phase: snapshot.phase,
                elapsedSeconds: snapshot.elapsedSeconds,
                startedAt: model.elapsedStartedAt)

            Button {
                model.onAction?(.restore(runID: snapshot.runID))
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Restore conversation")
            .accessibilityLabel("Restore conversation")
        }
        .padding(.horizontal, 16)
    }

    private var presentationTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }

}
