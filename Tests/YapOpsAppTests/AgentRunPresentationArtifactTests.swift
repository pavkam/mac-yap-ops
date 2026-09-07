// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
import YapOpsCore
@testable import YapOpsApp

@Suite
struct AgentRunPresentationArtifactTests {
    @MainActor @Test
    func receive_WhenDirectAndToolArtifactsArrive_PresentsResultsAndToolText() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        let direct = linked(name: "preview.png", uri: "file:///tmp/preview.png")
        let toolResult = linked(name: "report.pdf", uri: "file:///tmp/report.pdf")
        let updatedResult = linked(name: "summary.docx", uri: "file:///tmp/summary.docx")
        presentation.start(runID: runID, profile: try makeAgentProfile(), prompt: "Render")

        presentation.receive(runID: runID, event: .artifact(direct))
        presentation.receive(runID: runID, event: .toolCall(AgentToolCall(
            id: "render",
            title: "Render report",
            status: .completed,
            content: [.text("Rendered successfully"), .artifact(toolResult)])))
        presentation.receive(runID: runID, event: .toolCallUpdate(AgentToolCallUpdate(
            id: "render",
            content: [.text("Final files ready"), .artifact(updatedResult)])))

        #expect(presentation.snapshot?.artifacts.map(\.artifact) == [
            direct,
            toolResult,
            updatedResult,
        ])
        #expect(presentation.snapshot?.tools.first?.content == ["Final files ready"])
    }

    @MainActor @Test
    func receive_WhenArtifactURIRepeats_UpdatesResultWithoutChangingIdentity() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        presentation.start(runID: runID, profile: try makeAgentProfile(), prompt: "Render")
        presentation.receive(runID: runID, event: .artifact(linked(
            name: "report.pdf",
            title: "Draft",
            uri: "FILE://LOCALHOST/tmp/report.pdf")))
        let firstID = try #require(presentation.snapshot?.artifacts.first?.id)

        presentation.receive(runID: runID, event: .artifact(linked(
            name: "report.pdf",
            title: "Final",
            uri: "file://localhost/tmp/report.pdf")))

        #expect(presentation.snapshot?.artifacts.count == 1)
        #expect(presentation.snapshot?.artifacts.first?.id == firstID)
        #expect(presentation.snapshot?.artifacts.first?.artifact.title == "Final")
    }

    @MainActor @Test
    func receive_WhenArtifactsHaveNoURI_DoesNotGuessThatTheyAreEqual() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        presentation.start(runID: runID, profile: try makeAgentProfile(), prompt: "Draw")

        presentation.receive(runID: runID, event: .artifact(embeddedImage(index: 1, bytes: 4)))
        presentation.receive(runID: runID, event: .artifact(embeddedImage(index: 2, bytes: 4)))

        #expect(presentation.snapshot?.artifacts.count == 2)
    }

    @MainActor @Test
    func receive_WhenThirtyThreeUniqueArtifactsArrive_EvictsOldest() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        presentation.start(runID: runID, profile: try makeAgentProfile(), prompt: "Render")

        for index in 0..<33 {
            presentation.receive(runID: runID, event: .artifact(linked(
                name: "result-\(index).pdf",
                uri: "file:///tmp/result-\(index).pdf")))
        }

        #expect(presentation.snapshot?.artifacts.count == 32)
        #expect(presentation.snapshot?.artifacts.first?.artifact.name == "result-1.pdf")
        #expect(presentation.snapshot?.omittedArtifactCount == 1)
        #expect(presentation.snapshot?.notices.filter { $0.contains("results were omitted") }.count == 1)
    }

    @MainActor @Test
    func receive_WhenEmbeddedResultsExceedMemoryBound_EvictsWholeOldestArtifacts() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        presentation.start(runID: runID, profile: try makeAgentProfile(), prompt: "Draw")

        for index in 0..<6 {
            presentation.receive(runID: runID, event: .artifact(embeddedImage(
                index: index,
                bytes: 700 * 1_024)))
        }

        let snapshot = try #require(presentation.snapshot)
        #expect(snapshot.artifacts.reduce(0) { $0 + $1.embeddedByteCount }
            <= AgentRunPresentation.maximumArtifactBytes)
        #expect(snapshot.artifacts.count == 5)
        #expect(snapshot.artifacts.first?.artifact.name == "image-1.png")
        #expect(snapshot.omittedArtifactCount == 1)
    }

    @MainActor @Test
    func receive_WhenRunIDIsStale_DoesNotMutateResults() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        presentation.start(runID: runID, profile: try makeAgentProfile(), prompt: "Render")

        presentation.receive(runID: UUID(), event: .artifact(linked(
            name: "stale.pdf",
            uri: "file:///tmp/stale.pdf")))

        #expect(presentation.snapshot?.artifacts.isEmpty == true)
    }

    @MainActor @Test
    func start_WhenReplacingRetainedConversation_ClearsArtifactsAndOmissionCount() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let firstRunID = UUID()
        presentation.start(
            runID: firstRunID,
            profile: try makeAgentProfile(),
            prompt: "First")
        for index in 0..<33 {
            presentation.receive(runID: firstRunID, event: .artifact(linked(
                name: "result-\(index).pdf",
                uri: "file:///tmp/result-\(index).pdf")))
        }

        presentation.start(
            runID: UUID(),
            profile: try makeAgentProfile(),
            prompt: "Second")

        #expect(presentation.snapshot?.artifacts.isEmpty == true)
        #expect(presentation.snapshot?.omittedArtifactCount == 0)
    }

    @MainActor @Test
    func copyText_WhenResultsExist_ListsNamesAndURIsWithoutEmbeddedPayload() throws {
        let presentation = AgentRunPresentation(startsElapsedTimer: false)
        let runID = UUID()
        presentation.start(runID: runID, profile: try makeAgentProfile(), prompt: "Render")
        presentation.receive(runID: runID, event: .artifact(linked(
            name: "report.pdf",
            uri: "file:///tmp/report.pdf")))
        presentation.receive(runID: runID, event: .artifact(AgentArtifact(
            uri: "memory:///notes.txt",
            name: "notes.txt",
            title: nil,
            descriptiveText: nil,
            mimeType: "text/plain",
            declaredSize: nil,
            payload: .embeddedText("PRIVATE EMBEDDED PAYLOAD"))))

        let copyText = try #require(presentation.snapshot?.copyText)

        #expect(copyText.contains("Results\n"))
        #expect(copyText.contains("- report.pdf — file:///tmp/report.pdf"))
        #expect(copyText.contains("- notes.txt — memory:///notes.txt"))
        #expect(!copyText.contains("PRIVATE EMBEDDED PAYLOAD"))
    }

    private func makeAgentProfile() throws -> WakeProfile {
        try WakeProfile(
            wakePhrase: "computer",
            action: .agent(AgentHarnessConfiguration(
                preset: .codex,
                displayName: "Codex",
                executablePath: "/usr/bin/env",
                arguments: ["codex-acp"],
                workingDirectory: "/tmp",
                permissionPolicy: .ask)),
            accent: .purple)
    }

    private func linked(name: String, title: String? = nil, uri: String) -> AgentArtifact {
        AgentArtifact(
            uri: uri,
            name: name,
            title: title,
            descriptiveText: nil,
            mimeType: name.hasSuffix(".pdf") ? "application/pdf" : "image/png",
            declaredSize: 1_024,
            payload: .linked)
    }

    private func embeddedImage(index: Int, bytes: Int) -> AgentArtifact {
        AgentArtifact(
            uri: nil,
            name: "image-\(index).png",
            title: nil,
            descriptiveText: nil,
            mimeType: "image/png",
            declaredSize: UInt64(bytes),
            payload: .image(
                data: Data(repeating: UInt8(index), count: bytes),
                mimeType: "image/png"))
    }
}
