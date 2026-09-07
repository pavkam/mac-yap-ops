// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import MarkdownUI
import SwiftUI
import Testing
@testable import YapOpsApp

struct AgentMarkdownRenderingTests {
    private static let tinyPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    private static let representativeMarkdown = """
        # Release report

        > Validate the renderer, not our optimism.

        See [the runbook](https://example.com/runbook).

        - [x] Parse **structured** output
          - Keep nested items
        - [ ] Preserve follow-up work

        | Boundary | Result |
        | --- | --- |
        | Links | Restricted |
        | Images | Omitted |

        ~~Retired formatting~~ remains visibly struck through.

        ```swift
        let result = "rendered"
        ```
        """

    @Test(arguments: [
        "http://example.com/report",
        "https://example.com/report",
        "HTTPS://EXAMPLE.COM/report",
    ])
    func linkPolicy_WhenURLUsesWebScheme_AllowsActivation(_ value: String) throws {
        let url = try #require(URL(string: value))

        #expect(AgentMarkdownLinkPolicy.allows(url))
    }

    @Test(arguments: [
        "relative/path",
        "file:///tmp/private-report",
        "yapops://run",
        "javascript:alert(1)",
        "JaVaScRiPt:alert(1)",
        "data:text/plain,private",
        "ftp://example.com/report",
        "mailto:agent@example.com",
        "//example.com/report",
    ])
    func linkPolicy_WhenURLIsNotWebLink_RejectsActivation(_ value: String) throws {
        let url = try #require(URL(string: value))

        #expect(!AgentMarkdownLinkPolicy.allows(url))
    }

    @Test func parserContract_WhenRepresentativeAgentMarkdownIsParsed_RetainsGFMStructure() {
        let html = MarkdownContent(Self.representativeMarkdown).renderHTML()

        #expect(html.contains("<h1>Release report</h1>"))
        #expect(html.contains("<blockquote>"))
        #expect(html.contains("<a href=\"https://example.com/runbook\">the runbook</a>"))
        #expect(html.contains("<input type=\"checkbox\""))
        #expect(html.contains("checked=\"\""))
        #expect(html.components(separatedBy: "<ul>").count == 3)
        #expect(html.contains("<strong>structured</strong>"))
        #expect(html.contains("<table>"))
        #expect(html.contains("<del>Retired formatting</del>"))
        #expect(html.contains("<pre><code class=\"language-swift\">"))
    }

    @Test(arguments: [
        "http://example.com/private.png",
        "file:///tmp/private.png",
        "data:image/png;base64,AAAA",
    ])
    func inlineImageProvider_WhenImageURLIsNotHTTPS_RejectsIt(_ value: String) async throws {
        let imageURL = try #require(URL(string: value))

        await #expect(throws: AgentMarkdownImageError.unsupportedURL) {
            try await AgentMarkdownInlineImageProvider().image(
                with: imageURL,
                label: "private")
        }
    }

    @Test func inlineImageProvider_WhenHTTPSImageLoads_ReturnsImage() async throws {
        let imageURL = try #require(URL(string: "https://images.example/picture.png"))
        let loader = AgentMarkdownImageLoader(fetch: { requestedURL, _ in
            AgentMarkdownImageDownload(
                data: Self.tinyPNG,
                responseURL: requestedURL,
                statusCode: 200,
                mimeType: "image/png")
        })

        _ = try await AgentMarkdownInlineImageProvider(loader: loader).image(
            with: imageURL,
            label: "Picture")
    }

    @MainActor @Test
    func view_WhenRepresentativeGFMIsRendered_ProducesAReadableDocument() throws {
        let image = try renderedImage(markdown: Self.representativeMarkdown)

        #expect(image.width == 420)
        #expect(image.height > 220)
        #expect(image.height < 900)
    }

    @MainActor @Test(arguments: [
        "# Partial heading",
        "**unfinished emphasis",
        "```swift\nlet value = 1",
        "| Name | State |\n| --- |",
        "1. first\n   - nested",
        "[unfinished link](https://example.com",
        "Café 👩🏽‍💻 — **pronto**",
    ])
    func view_WhenStreamingSnapshotEndsMidConstruct_RemainsRenderable(
        _ markdown: String
    ) throws {
        let image = try renderedImage(markdown: markdown)

        #expect(image.width == 420)
        #expect(image.height > 8)
    }

    @MainActor @Test
    func view_WhenRemoteBlockImageIsRendered_ReservesBoundedImageArea() throws {
        let loader = AgentMarkdownImageLoader(fetch: { requestedURL, _ in
            AgentMarkdownImageDownload(
                data: Self.tinyPNG,
                responseURL: requestedURL,
                statusCode: 200,
                mimeType: "image/png")
        })
        let image = try renderedImage(
            markdown: "![Picture](https://images.example/picture.png)",
            imageLoader: loader)

        #expect(image.width == 420)
        #expect(image.height >= 80)
        #expect(image.height <= 440)
    }

    @MainActor @Test
    func view_WhenCodeLineIsLong_PreservesPanelWidthWithoutVerticalExplosion() throws {
        let code = String(repeating: "let_result_equal_value;", count: 400)
        let image = try renderedImage(markdown: "```text\n\(code)\n```")

        #expect(image.width == 420)
        #expect(image.height < 160)
    }

    @MainActor @Test
    func view_WhenTimelineRoleChanges_RendersResponseMoreProminentlyThanDetail() throws {
        let markdown = "# Result\n\nThe agent returned a useful answer."
        let response = try renderedImage(markdown: markdown, style: .response)
        let detail = try renderedImage(markdown: markdown, style: .detail)

        #expect(response.height > detail.height)
    }

    @MainActor
    private func renderedImage(
        markdown: String,
        style: AgentMarkdownRenderStyle = .response,
        imageLoader: any AgentMarkdownImageLoading = AgentMarkdownImageLoader.shared
    ) throws -> CGImage {
        let renderer = ImageRenderer(
            content: AgentMarkdownView(
                markdown: markdown,
                accent: .blue,
                style: style,
                imageLoader: imageLoader)
                .frame(width: 420)
                .fixedSize(horizontal: false, vertical: true))
        renderer.scale = 1

        return try #require(renderer.cgImage)
    }
}
