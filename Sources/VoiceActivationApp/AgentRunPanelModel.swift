// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import Observation
import VoiceActivationCore

@MainActor
@Observable
final class AgentRunPanelModel {
    var snapshot: AgentRunSnapshot?
    var isAutoFollowing = true
    private(set) var isMinimized = false
    private(set) var expandedSize = AgentRunPanelLayout.preferredExpandedSize
    var resolvingPermissions: Set<AgentPermissionKey> = []
    private(set) var expandedThinkingIDs: Set<UUID> = []
    private(set) var artifactPreviewStates: [UUID: AgentArtifactPreviewState] = [:]
    private(set) var elapsedStartedAt: Date
    @ObservationIgnored var onAction: ((AgentRunPanelAction) -> Void)?
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let diagnostics: any VoiceActivationDiagnosticRecording
    @ObservationIgnored private let previewLoader: any AgentArtifactPreviewLoading
    @ObservationIgnored private let previewSize: CGSize
    @ObservationIgnored private let previewScale: CGFloat
    @ObservationIgnored private var previewTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var isUserScrolling = false

    init(
        previewLoader: any AgentArtifactPreviewLoading = SystemAgentArtifactPreviewLoader(),
        previewSize: CGSize = CGSize(width: 320, height: 180),
        previewScale: CGFloat = 2,
        now: @escaping @MainActor () -> Date = Date.init,
        diagnostics: any VoiceActivationDiagnosticRecording = VoiceActivationDiagnostics.shared
    ) {
        self.previewLoader = previewLoader
        self.previewSize = previewSize
        self.previewScale = previewScale
        self.now = now
        self.diagnostics = diagnostics
        elapsedStartedAt = now()
    }

    func begin(
        _ snapshot: AgentRunSnapshot,
        expandedSize: CGSize = AgentRunPanelLayout.preferredExpandedSize)
    {
        cancelAllPreviewTasks()
        artifactPreviewStates.removeAll(keepingCapacity: true)
        elapsedStartedAt = now().addingTimeInterval(-TimeInterval(snapshot.elapsedSeconds))
        self.snapshot = snapshot
        self.expandedSize = expandedSize
        isAutoFollowing = true
        isMinimized = false
        resolvingPermissions = []
        expandedThinkingIDs = []
        isUserScrolling = false
        synchronizePreviews(previous: nil, current: snapshot)
        diagnostics.record(
            category: .ui,
            event: "agent_panel.model_began",
            fields: ["run_id": snapshot.runID.uuidString])
    }

    func update(_ snapshot: AgentRunSnapshot) {
        guard let previousSnapshot = self.snapshot,
            previousSnapshot.runID == snapshot.runID
        else {
            diagnostics.record(
                category: .ui,
                event: "agent_panel.model_update_ignored",
                fields: [
                    "run_id": snapshot.runID.uuidString,
                    "reason": "stale_or_missing_snapshot",
                ])
            return
        }
        let previousThinking = previousSnapshot.timeline.compactMap {
            item -> AgentThinkingPresentation? in
            guard case .thinking(let thinking) = item else { return nil }
            return thinking
        }
        let currentThinking = snapshot.timeline.compactMap { item -> AgentThinkingPresentation? in
            guard case .thinking(let thinking) = item else { return nil }
            return thinking
        }
        let previouslySettled = Dictionary(
            uniqueKeysWithValues: previousThinking.map { ($0.id, $0.isSettled) })
        let newlySettledThinkingIDs = currentThinking.lazy.filter { thinking in
            thinking.isSettled && previouslySettled[thinking.id] != true
        }.map(\.id)
        expandedThinkingIDs.subtract(newlySettledThinkingIDs)
        expandedThinkingIDs.formIntersection(currentThinking.lazy.map(\.id))
        if snapshot.phase.advancesElapsedTime,
            !previousSnapshot.phase.advancesElapsedTime
        {
            elapsedStartedAt = now().addingTimeInterval(-TimeInterval(snapshot.elapsedSeconds))
        }
        self.snapshot = snapshot
        synchronizePreviews(previous: previousSnapshot, current: snapshot)
        resolvingPermissions = Set(snapshot.permissions.lazy.filter(\.isResolving).map(\.key))
        diagnostics.record(
            category: .ui,
            event: "agent_panel.model_updated",
            level: .debug,
            fields: [
                "run_id": snapshot.runID.uuidString,
                "timeline_item_count": String(snapshot.timeline.count),
                "thinking_group_count": String(currentThinking.count),
                "permission_count": String(snapshot.permissions.count),
            ])
    }

    func toggleThinkingDetails(thinkingID: UUID) {
        guard
            snapshot?.timeline.contains(where: { item in
                guard case .thinking(let thinking) = item else { return false }
                return thinking.id == thinkingID
            }) == true
        else {
            diagnostics.record(
                category: .ui,
                event: "agent_panel.thinking_toggle_ignored",
                fields: ["reason": "thinking_group_missing"])
            return
        }
        if !expandedThinkingIDs.insert(thinkingID).inserted {
            expandedThinkingIDs.remove(thinkingID)
        }
        diagnostics.record(
            category: .ui,
            event: "agent_panel.thinking_toggled",
            fields: [
                "thinking_id": thinkingID.uuidString,
                "expanded": String(expandedThinkingIDs.contains(thinkingID)),
            ])
    }

    func isThinkingExpanded(thinkingID: UUID) -> Bool {
        expandedThinkingIDs.contains(thinkingID)
    }

    func previewStatus(for artifactID: UUID) -> AgentArtifactPreviewStatus? {
        artifactPreviewStates[artifactID]?.status
    }

    func previewState(for artifactID: UUID) -> AgentArtifactPreviewState? {
        artifactPreviewStates[artifactID]
    }

    func preview(for artifactID: UUID) -> AgentArtifactPreview? {
        guard case let .available(preview) = artifactPreviewStates[artifactID] else {
            return nil
        }
        return preview
    }

    func setMinimized(_ isMinimized: Bool) {
        guard snapshot != nil else { return }
        self.isMinimized = isMinimized
        diagnostics.record(
            category: .ui,
            event: "agent_panel.minimized_changed",
            fields: ["minimized": String(isMinimized)])
    }

    func setExpandedSize(_ expandedSize: CGSize) {
        guard expandedSize.width > 0, expandedSize.height > 0 else { return }
        self.expandedSize = expandedSize
    }

    func selectPermission(_ permission: AgentPermissionPresentation, optionID: String) {
        guard let snapshot,
            !snapshot.phase.isTerminal,
            resolvingPermissions.insert(permission.key).inserted
        else {
            diagnostics.record(
                category: .ui,
                event: "agent_panel.permission_click_ignored",
                fields: ["reason": "terminal_or_already_resolving"])
            return
        }
        diagnostics.record(
            category: .ui,
            event: "agent_panel.permission_clicked",
            fields: ["run_id": snapshot.runID.uuidString])
        onAction?(
            .permission(
                runID: snapshot.runID,
                key: permission.key,
                optionID: optionID))
    }

    func beginUserScrolling(distanceFromBottom: CGFloat) {
        isUserScrolling = true
        updateAutoFollowing(distanceFromBottom: distanceFromBottom)
    }

    func endUserScrolling(distanceFromBottom: CGFloat) {
        guard isUserScrolling else { return }
        updateAutoFollowing(distanceFromBottom: distanceFromBottom)
        isUserScrolling = false
    }

    func updateScrollGeometry(distanceFromBottom: CGFloat) {
        guard isUserScrolling else { return }
        updateAutoFollowing(distanceFromBottom: distanceFromBottom)
    }

    private func updateAutoFollowing(distanceFromBottom: CGFloat) {
        let follows = distanceFromBottom <= 24
        guard follows != isAutoFollowing else { return }
        isAutoFollowing = follows
        diagnostics.record(
            category: .ui,
            event: "agent_panel.auto_follow_changed",
            fields: [
                "enabled": String(follows),
                "distance_from_bottom": String(describing: distanceFromBottom),
            ])
    }

    private func synchronizePreviews(
        previous: AgentRunSnapshot?,
        current: AgentRunSnapshot)
    {
        let currentByID = Dictionary(uniqueKeysWithValues: current.artifacts.map { ($0.id, $0) })
        let previousByID = Dictionary(
            uniqueKeysWithValues: (previous?.artifacts ?? []).map { ($0.id, $0) })

        for id in Array(previewTasks.keys) where currentByID[id] == nil {
            previewTasks.removeValue(forKey: id)?.cancel()
            artifactPreviewStates.removeValue(forKey: id)
        }
        for id in Array(artifactPreviewStates.keys) where currentByID[id] == nil {
            artifactPreviewStates.removeValue(forKey: id)
        }

        for artifact in current.artifacts {
            if previousByID[artifact.id] == artifact,
               artifactPreviewStates[artifact.id] != nil
            {
                continue
            }
            previewTasks.removeValue(forKey: artifact.id)?.cancel()
            startPreview(for: artifact, runID: current.runID)
        }
    }

    private func startPreview(for artifact: AgentArtifactPresentation, runID: UUID) {
        artifactPreviewStates[artifact.id] = .loading
        let loader = previewLoader
        let size = previewSize
        let scale = previewScale
        previewTasks[artifact.id] = Task { [weak self] in
            let preview = await loader.loadPreview(for: artifact, size: size, scale: scale)
            guard !Task.isCancelled else { return }
            self?.completePreview(
                preview,
                for: artifact,
                runID: runID)
        }
    }

    private func completePreview(
        _ preview: AgentArtifactPreview?,
        for artifact: AgentArtifactPresentation,
        runID: UUID)
    {
        guard snapshot?.runID == runID,
              snapshot?.artifacts.contains(where: {
                  $0.id == artifact.id && $0.artifact == artifact.artifact
              }) == true
        else {
            return
        }
        previewTasks.removeValue(forKey: artifact.id)
        artifactPreviewStates[artifact.id] = preview.map(AgentArtifactPreviewState.available)
            ?? .unavailable
    }

    private func cancelAllPreviewTasks() {
        for task in previewTasks.values {
            task.cancel()
        }
        previewTasks.removeAll(keepingCapacity: true)
    }
}
