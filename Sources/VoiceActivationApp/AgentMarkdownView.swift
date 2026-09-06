// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import MarkdownUI
import SwiftUI

struct AgentMarkdownView: View {
    let markdown: String
    let accent: Color
    var style: AgentMarkdownRenderStyle = .response

    var body: some View {
        Markdown(markdown)
            .markdownTheme(AgentMarkdownRendering.theme(accent: accent, style: style))
            .markdownImageProvider(AgentMarkdownBlockImageProvider())
            .markdownInlineImageProvider(AgentMarkdownInlineImageProvider())
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
