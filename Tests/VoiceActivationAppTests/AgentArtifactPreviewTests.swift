// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
import VoiceActivationCore
@testable import VoiceActivationApp

struct AgentArtifactPreviewTests {
    @Test func source_WhenArtifactVaries_SelectsOnlySafeAutomaticPreview() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let localFile = directory.appendingPathComponent("report.pdf")
        try Data("pdf".utf8).write(to: localFile)
        let imageData = Data([0, 0, 0, 255])
        let loader = SystemAgentArtifactPreviewLoader()

        #expect(loader.previewSource(for: artifact(
            uri: nil,
            mimeType: "image/png",
            payload: .image(data: imageData, mimeType: "image/png")))
            == .embeddedImage(imageData))
        #expect(loader.previewSource(for: artifact(
            uri: localFile.absoluteString,
            mimeType: "application/pdf",
            payload: .linked)) == .localFile(localFile))
        #expect(loader.previewSource(for: artifact(
            uri: "https://example.com/report.pdf",
            mimeType: "application/pdf",
            payload: .linked)) == nil)
        #expect(loader.previewSource(for: artifact(
            uri: localFile.absoluteString,
            mimeType: "text/plain",
            payload: .embeddedText("private"))) == nil)
        #expect(loader.previewSource(for: artifact(
            uri: "memory:///report.pdf",
            mimeType: "application/pdf",
            payload: .linked)) == nil)
    }

    private func artifact(
        uri: String?,
        mimeType: String,
        payload: AgentArtifactPayload
    ) -> AgentArtifactPresentation {
        AgentArtifactPresentation(
            id: UUID(),
            artifact: AgentArtifact(
                uri: uri,
                name: "result",
                title: nil,
                descriptiveText: nil,
                mimeType: mimeType,
                declaredSize: nil,
                payload: payload))
    }
}
