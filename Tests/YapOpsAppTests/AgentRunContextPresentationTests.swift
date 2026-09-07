// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import YapOpsApp
import YapOpsCore

@MainActor
struct AgentRunContextPresentationTests {
    @Test func captureFeedback_BelongsToItsRequestAndDoesNotReplaceOtherInputs() throws {
        let subject = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        let followUpID = UUID()
        let first = summary(app: "Editor", text: "first selection")
        let second = summary(app: "Finder")
        subject.start(runID: runID, profile: .defaultValue, prompt: "Summarize this")
        subject.submitFollowUp(
            runID: runID, inputID: followUpID, prompt: "And this", disposition: .queued)

        subject.receiveContext(runID: runID, inputID: followUpID, summary: second)
        subject.receiveContext(runID: runID, inputID: nil, summary: first)

        let snapshot = try #require(subject.snapshot)
        #expect(snapshot.promptContext == first)
        let message = try #require(snapshot.timeline.compactMap { item in
            guard case .userMessage(let message) = item else { return nil as AgentUserMessagePresentation? }
            return message
        }.first)
        #expect(message.contextSummary == second)
        #expect(message.disposition == .queued)
    }

    @Test func captureFeedback_IgnoresUnknownInputsRetiredRunsAndCancelledTurns() throws {
        let subject = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        subject.start(runID: runID, profile: .defaultValue, prompt: "Current")
        let initial = try #require(subject.snapshot)

        subject.receiveContext(runID: UUID(), inputID: nil, summary: summary(app: "Stale"))
        subject.receiveContext(runID: runID, inputID: UUID(), summary: summary(app: "Unknown"))
        #expect(subject.snapshot == initial)
        _ = subject.beginCancellation(runID: runID)
        let cancelling = subject.snapshot
        subject.receiveContext(runID: runID, inputID: nil, summary: summary(app: "Late"))
        #expect(subject.snapshot == cancelling)
    }

    @Test func captureFeedback_NewConversationDropsPreviousContext() {
        let subject = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        subject.start(runID: runID, profile: .defaultValue, prompt: "First")
        subject.receiveContext(runID: runID, inputID: nil, summary: summary(app: "Editor"))
        #expect(subject.snapshot?.promptContext != nil)

        subject.start(runID: UUID(), profile: .defaultValue, prompt: "Second")

        #expect(subject.snapshot?.promptContext == nil)
    }

    @Test func captureFeedback_DiagnosticsExcludeAppNameAndSelection() {
        let event = AgentRunLifecycleEvent.inputContextCaptured(
            runID: UUID(), inputID: nil,
            summary: summary(app: "Private App", text: "private selected text"))
        #expect(event.appModelDiagnosticFields.count == 2)
        #expect(!event.appModelDiagnosticFields.values.contains { $0.contains("Private") })
        #expect(!event.appModelDiagnosticFields.values.contains { $0.contains("private") })
    }

    @Test func captureFeedback_TrimmingOldMessageTextPreservesItsContext() throws {
        let context = summary(app: "Editor", text: "selection")
        var message = AgentUserMessagePresentation(id: UUID(), text: "Older request", disposition: .queued)
        message.contextSummary = context

        let shortened = AgentRunTimelineItem.userMessage(message).droppingTextPrefix(
            atLeast: 6, using: { text, count in String(text.dropFirst(count)) })

        guard case .userMessage(let retained) = shortened else {
            Issue.record("Expected the retained user message")
            return
        }
        #expect(retained.text == "request")
        #expect(retained.contextSummary == context)
        #expect(retained.id == message.id)
    }

    @Test func contextCopy_ExplainsMissingSelectionAndPermissionWithoutClaimingDelivery() {
        let empty = AgentInputContextPresentation(summary: summary(app: "Editor"))
        let selected = AgentInputContextPresentation(summary: summary(app: "Editor", text: "sample"))
        let denied = AgentInputContextPresentation(summary: summary(
            app: "Editor", state: .accessibilityNotAuthorized))
        let absent = AgentInputContextPresentation(summary: .init(context: nil))

        #expect(empty.detail == "Window · No selection")
        #expect(selected.detail == "Window · Selected text")
        #expect(!selected.isLimited)
        #expect(denied.isLimited)
        #expect(denied.detail.contains("Enable Accessibility"))
        #expect(absent.title == "No Mac context")
        #expect(absent.detail.contains("off or no focused app"))
    }

    private func summary(
        app: String, text: String? = nil, state: MacContextCaptureState = .complete
    ) -> AgentInputContextSummary {
        AgentInputContextSummary(context: .normalized(
            state: state,
            target: .init(processIdentifier: 42, applicationName: app, bundleIdentifier: nil),
            windowTitle: "Document", documentURL: nil, selectedText: text, resources: []))
    }
}
