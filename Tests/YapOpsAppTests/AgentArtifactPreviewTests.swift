// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
import YapOpsCore
@testable import YapOpsApp

struct AgentArtifactPreviewTests {
    @Test func source_WhenArtifactVaries_SelectsOnlySafeAutomaticPreview() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let localFile = directory.appendingPathComponent("report.pdf")
        try Data("pdf".utf8).write(to: localFile)
        let imageData = Data([0, 0, 0, 255])
        let loader = SystemAgentArtifactPreviewLoader()

        let embedded = await loader.previewSource(for: artifact(
            uri: nil,
            mimeType: "image/png",
            payload: .image(data: imageData, mimeType: "image/png")))
        let local = await loader.previewSource(for: artifact(
            uri: localFile.absoluteString,
            mimeType: "application/pdf",
            payload: .linked))
        let remote = await loader.previewSource(for: artifact(
            uri: "https://example.com/report.pdf",
            mimeType: "application/pdf",
            payload: .linked))
        let remoteAuthority = await loader.previewSource(for: artifact(
            uri: "file://example.invalid/tmp/report.pdf",
            mimeType: "application/pdf",
            payload: .linked))
        let privateText = await loader.previewSource(for: artifact(
            uri: localFile.absoluteString,
            mimeType: "text/plain",
            payload: .embeddedText("private")))
        let memory = await loader.previewSource(for: artifact(
            uri: "memory:///report.pdf",
            mimeType: "application/pdf",
            payload: .linked))

        #expect(embedded == .embeddedImage(imageData))
        #expect(local == .localFile(localFile))
        #expect(remote == nil)
        #expect(remoteAuthority == nil)
        #expect(privateText == nil)
        #expect(memory == nil)
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
