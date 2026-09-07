// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import YapOpsCore

struct ACPEventDecoderResponseChannelTests {
    @Test func agentMessageChunk_WithSpokenMetadata_DecodesSpokenDelta() throws {
        let update = #"{"sessionUpdate":"agent_message_chunk","messageId":"answer-7","content":{"type":"text","text":"Done — moved ✅","_meta":{"ciobanu.org.yapOps":{"responseChannel":{"version":1,"channel":"spoken"}}}}}"#

        let event = try ACPEventDecoder().event(from: message(update: update))

        #expect(event == .agentSpokenMessageDelta(
            messageID: "answer-7",
            text: "Done — moved ✅"))
    }

    @Test func agentMessageChunk_WithDisplayMetadata_DecodesDisplayDelta() throws {
        let update = #"{"sessionUpdate":"agent_message_chunk","messageId":"answer-8","content":{"type":"text","text":"**18 files**\n\n- Archived","_meta":{"ciobanu.org.yapOps":{"responseChannel":{"version":1,"channel":"display"}}}}}"#

        let event = try ACPEventDecoder().event(from: message(update: update))

        #expect(event == .agentDisplayMessageDelta(
            messageID: "answer-8",
            text: "**18 files**\n\n- Archived"))
    }

    @Test func agentMessageChunk_WithUnknownOrMalformedMetadata_FallsBackToLegacyDelta() throws {
        let metadataFragments = [
            #""_meta":{"ciobanu.org.yapOps":{"responseChannel":{"version":2,"channel":"spoken"}}}"#,
            #""_meta":{"ciobanu.org.yapOps":{"responseChannel":{"version":"1","channel":"spoken"}}}"#,
            #""_meta":{"ciobanu.org.yapOps":{"responseChannel":{"version":1,"channel":"audio"}}}"#,
            #""_meta":{"ciobanu.org.yapOps":{"responseChannel":"spoken"}}"#,
            #""_meta":{"ciobanu.org.yapOps":{"responseChannel":{"version":1}}}"#,
            #""_meta":{"ciobanu.org.yapops":{"responseChannel":{"version":1,"channel":"spoken"}}}"#,
            #""_meta":false"#,
            #""responseChannel":{"version":1,"channel":"spoken"}"#,
        ]
        let decoder = ACPEventDecoder()

        for metadata in metadataFragments {
            let update = #"{"sessionUpdate":"agent_message_chunk","messageId":"unchanged-id","content":{"type":"text","text":"Keep <private> exactly","#
                + metadata + "}}"

            #expect(try decoder.event(from: message(update: update)) == .agentMessageDelta(
                messageID: "unchanged-id",
                text: "Keep <private> exactly"))
        }
    }

    @Test func agentMessageChunk_WithMetadataInUpdate_FallsBackWithoutSurfacingMetadata() throws {
        let update = #"{"sessionUpdate":"agent_message_chunk","messageId":"legacy","_meta":{"ciobanu.org.yapOps":{"responseChannel":{"version":1,"channel":"spoken"},"providerPrivate":"must-not-surface"}},"content":{"type":"text","text":"Legacy response"}}"#

        let event = try ACPEventDecoder().event(from: message(update: update))

        #expect(event == .agentMessageDelta(messageID: "legacy", text: "Legacy response"))
    }

    @Test func agentMessageChunk_WithoutResponseMetadata_PreservesLegacyEvent() throws {
        let update = #"{"sessionUpdate":"agent_message_chunk","messageId":"legacy-1","content":{"type":"text","text":"Ordinary **Markdown**"}}"#

        let event = try ACPEventDecoder().event(from: message(update: update))

        #expect(event == .agentMessageDelta(
            messageID: "legacy-1",
            text: "Ordinary **Markdown**"))
    }

    private func message(update: String) throws -> ACPMessage {
        let envelope = #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"session-1","update":"#
            + update + "}}"
        let data = Data(envelope.utf8)
        return try JSONDecoder().decode(ACPMessage.self, from: data)
    }
}
