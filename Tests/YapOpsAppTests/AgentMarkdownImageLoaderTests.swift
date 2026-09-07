// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import YapOpsApp

struct AgentMarkdownImageLoaderTests {
    private static let tinyPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!

    @Test func image_WhenHTTPSReturnsPNG_DecodesIt() async throws {
        let url = try #require(URL(string: "https://images.example/picture.png"))
        let loader = AgentMarkdownImageLoader(
            maximumByteCount: Self.tinyPNG.count,
            fetch: { requestedURL, _ in
                AgentMarkdownImageDownload(
                    data: Self.tinyPNG,
                    responseURL: requestedURL,
                    statusCode: 200,
                    mimeType: "image/png")
            })

        let image = try await loader.image(from: url)

        #expect(image.width == 1)
        #expect(image.height == 1)
    }

    @Test func image_WhenURLIsNotHTTPS_RejectsItBeforeDownload() async throws {
        let url = try #require(URL(string: "http://images.example/picture.png"))
        let loader = AgentMarkdownImageLoader(fetch: { requestedURL, _ in
            AgentMarkdownImageDownload(
                data: Self.tinyPNG,
                responseURL: requestedURL,
                statusCode: 200,
                mimeType: "image/png")
        })

        await #expect(throws: AgentMarkdownImageError.unsupportedURL) {
            try await loader.image(from: url)
        }
    }

    @Test func image_WhenResponseExceedsBound_RejectsIt() async throws {
        let url = try #require(URL(string: "https://images.example/picture.png"))
        let loader = AgentMarkdownImageLoader(
            maximumByteCount: Self.tinyPNG.count - 1,
            fetch: { requestedURL, _ in
                AgentMarkdownImageDownload(
                    data: Self.tinyPNG,
                    responseURL: requestedURL,
                    statusCode: 200,
                    mimeType: "image/png")
            })

        await #expect(throws: AgentMarkdownImageError.tooLarge) {
            try await loader.image(from: url)
        }
    }
}
