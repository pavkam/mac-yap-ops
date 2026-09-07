// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

enum ACPAgentInstruction {
    static let responseChannelContract = """
        Begin every user-facing response with this exact marker as its first bytes:
        \(AgentResponseChannelRouter.spokenMarker)Write concise agent-authored plain text for speech after it.

        When richer visual detail is useful, append this exact delimiter and then GitHub-flavored \
        Markdown for the panel:
        \(AgentResponseChannelRouter.displayMarker)Write the optional display response here.

        Never put Markdown, tool payloads, diagnostics, or hidden reasoning in the spoken section. \
        The display section is optional. Do not alter either marker.
        """

    static let responseStyle = """
        \(responseChannelContract)

        Format the optional display response as GitHub-flavored Markdown. Use headings, lists, \
        emphasis, links, and fenced code when they improve clarity. Do not wrap the entire display \
        response in a code fence.

        Keep progress narration sparse and conversational. Before or between work batches, \
        use at most one short sentence, such as “Let me check.” or “Whoops, I need to \
        initialize this first.” Do not narrate individual tool calls, command details, or \
        routine intermediate results. Put useful detail in the final answer.
        """
}
