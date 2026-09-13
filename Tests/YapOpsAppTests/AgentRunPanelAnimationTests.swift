// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AppKit
import Foundation
import SwiftUI
import Testing

@testable import YapOpsApp
@testable import YapOpsCore

@MainActor
private struct AgentRunActionDockHarness: View {
    @Bindable var model: AgentRunPanelModel

    var body: some View {
        if let snapshot = model.snapshot {
            AgentRunPanelView(model: model).actionDock(snapshot)
        }
    }
}

struct AgentRunPanelAnimationTests {
    private static let childEnvironmentKey =
        "YAPOPS_ACTION_DOCK_ANIMATION_TEST_CHILD"
    private static let testFilter =
        "actionDock_WhenAgentFinishes_ReplacesComposerWithTerminalActions"

    /// While a conversation is live the composer owns the bottom of the panel;
    /// a terminal phase replaces it with the Delete / Copy / Close dock. This
    /// guards that the swap actually happens on a phase change — a dock that
    /// keeps rendering the previous phase's controls is the regression that
    /// matters, and it is invisible to a snapshot of either state alone.
    @MainActor @Test(.timeLimit(.minutes(1)))
    func actionDock_WhenAgentFinishes_ReplacesComposerWithTerminalActions() async throws {
        guard ProcessInfo.processInfo.environment[Self.childEnvironmentKey] == "1" else {
            try await IsolatedAppKitTestProcess.run(
                environmentKey: Self.childEnvironmentKey,
                testFilter: Self.testFilter)
            return
        }

        let model = AgentRunPanelModel()
        let running = runningSnapshot(runID: UUID())
        model.begin(running)
        let hostingView = NSHostingView(rootView: AgentRunActionDockHarness(model: model))
        hostingView.frame = NSRect(x: 0, y: 0, width: 680, height: 96)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        // Swift owns this window; close must not release it a second time.
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = hostingView
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        hostingView.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        let liveRender = try renderFingerprint(of: hostingView)

        // The composer draws content on the leading edge — the microphone
        // button — where the terminal dock leaves empty space.
        #expect(liveRender.leadingInkPixels > 20)

        model.update(replacingPhase(.completed(.endTurn), in: running))
        hostingView.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        let terminalRender = try renderFingerprint(of: hostingView)

        #expect(terminalRender.leadingInkPixels < liveRender.leadingInkPixels)
        #expect(terminalRender.fingerprint != liveRender.fingerprint)
    }

    private struct RenderFingerprint {
        let leadingInkPixels: Int
        let fingerprint: Int
    }

    /// Counts ink on the leading half and hashes the whole render.
    ///
    /// Colour geometry is an implementation detail — the stop control moved from
    /// the dock's leading edge to the composer's trailing edge once the composer
    /// landed — so this measures "something is drawn here" and "the render
    /// changed" rather than pinning a specific hue to a specific side.
    @MainActor
    private func renderFingerprint(of view: NSView) throws -> RenderFingerprint {
        let representation = try #require(
            view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)

        var leadingInk = 0
        var hasher = Hasher()
        for x in 0..<representation.pixelsWide {
            for y in 0..<representation.pixelsHigh {
                guard let color = representation.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                else { continue }
                hasher.combine(Int(color.redComponent * 32))
                hasher.combine(Int(color.greenComponent * 32))
                hasher.combine(Int(color.blueComponent * 32))
                if x < representation.pixelsWide / 2, color.alphaComponent > 0.25 {
                    leadingInk += 1
                }
            }
        }
        return RenderFingerprint(leadingInkPixels: leadingInk, fingerprint: hasher.finalize())
    }

    @MainActor
    private func redPixelCount(inLeadingHalfOf view: NSView) throws -> Int {
        let representation = try #require(
            view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        var count = 0
        for x in 0..<(representation.pixelsWide / 2) {
            for y in 0..<representation.pixelsHigh {
                guard let color = representation.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                else { continue }
                if color.redComponent > 0.45,
                    color.redComponent > color.greenComponent * 1.35,
                    color.redComponent > color.blueComponent * 1.18,
                    color.alphaComponent > 0.25
                {
                    count += 1
                }
            }
        }
        return count
    }

    @MainActor
    private func runningSnapshot(runID: UUID) -> AgentRunSnapshot {
        AgentRunSnapshot(
            runID: runID,
            profileID: UUID(),
            profileName: "Computer",
            profileIcon: .defaultValue,
            accent: .purple,
            prompt: "Question",
            providerName: "Codex",
            phase: .running,
            voiceInput: "",
            output: "",
            timeline: [],
            diagnostics: "",
            plan: [],
            tools: [],
            permissions: [],
            notices: [],
            elapsedSeconds: 0,
            evictedToolCount: 0,
            ignoredToolUpdateCount: 0)
    }

    @MainActor
    private func replacingPhase(
        _ phase: AgentRunPhase,
        in snapshot: AgentRunSnapshot
    ) -> AgentRunSnapshot {
        AgentRunSnapshot(
            runID: snapshot.runID,
            profileID: snapshot.profileID,
            profileName: snapshot.profileName,
            profileIcon: snapshot.profileIcon,
            accent: snapshot.accent,
            prompt: snapshot.prompt,
            providerName: snapshot.providerName,
            phase: phase,
            voiceInput: snapshot.voiceInput,
            output: snapshot.output,
            timeline: snapshot.timeline,
            diagnostics: snapshot.diagnostics,
            plan: snapshot.plan,
            tools: snapshot.tools,
            permissions: snapshot.permissions,
            notices: snapshot.notices,
            elapsedSeconds: snapshot.elapsedSeconds,
            evictedToolCount: snapshot.evictedToolCount,
            ignoredToolUpdateCount: snapshot.ignoredToolUpdateCount)
    }
}
