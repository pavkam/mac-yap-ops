// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import MarkdownUI
import SwiftUI

struct AgentMarkdownView: View {
    let markdown: String
    let accent: Color
    let style: AgentMarkdownRenderStyle
    let imageLoader: any AgentMarkdownImageLoading

    init(
        markdown: String,
        accent: Color,
        style: AgentMarkdownRenderStyle = .response,
        imageLoader: any AgentMarkdownImageLoading = AgentMarkdownImageLoader.shared)
    {
        self.markdown = markdown
        self.accent = accent
        self.style = style
        self.imageLoader = imageLoader
    }

    var body: some View {
        Markdown(markdown)
            .markdownTheme(AgentMarkdownRendering.theme(accent: accent, style: style))
            .markdownImageProvider(AgentMarkdownBlockImageProvider(loader: imageLoader))
            .markdownInlineImageProvider(AgentMarkdownInlineImageProvider(loader: imageLoader))
            .environment(\.openURL, OpenURLAction { url in
                if AgentMarkdownLinkPolicy.allows(url) {
                    return .systemAction(url)
                }
                return .discarded
            })
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
