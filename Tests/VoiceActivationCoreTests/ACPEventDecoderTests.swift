// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationCore

struct ACPEventDecoderTests {
    @Test func event_WhenStableSessionUpdatesArrive_ReturnsTypedEvents() throws {
        let fixtures: [(String, AgentRunEvent)] = [
            (
                #"{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"Run tests"},"messageId":"user-1"}"#,
                .metadata(kind: "user_message_chunk", summary: "User message chunk (user-1)")),
            (
                #"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Working"},"messageId":"agent-1"}"#,
                .agentMessageDelta(messageID: "agent-1", text: "Working")),
            (
                #"{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"Inspecting"},"messageId":"thought-1"}"#,
                .thoughtDelta(messageID: "thought-1", text: "Inspecting")),
            (
                #"{"sessionUpdate":"tool_call","toolCallId":"tool-1","title":"Read files","kind":"read","status":"in_progress","rawInput":{"secret":"discard me"}}"#,
                .toolCall(AgentToolCall(
                    id: "tool-1",
                    title: "Read files",
                    kind: .read,
                    status: .inProgress))),
            (
                #"{"sessionUpdate":"tool_call_update","toolCallId":"tool-1","title":"Read files","kind":"read","status":"completed","rawOutput":{"secret":"discard me"}}"#,
                .toolCallUpdate(AgentToolCallUpdate(
                    id: "tool-1",
                    title: "Read files",
                    kind: .read,
                    status: .completed))),
            (
                #"{"sessionUpdate":"plan","entries":[{"content":"Inspect","priority":"high","status":"completed"},{"content":"Fix","priority":"medium","status":"in_progress"}]}"#,
                .plan([
                    AgentPlanEntry(content: "Inspect", priority: .high, status: .completed),
                    AgentPlanEntry(content: "Fix", priority: .medium, status: .inProgress),
                ])),
            (
                #"{"sessionUpdate":"available_commands_update","availableCommands":[{"name":"review","description":"Review code"},{"name":"test","description":"Run tests"}]}"#,
                .metadata(kind: "available_commands_update", summary: "2 commands available: review, test")),
            (
                #"{"sessionUpdate":"current_mode_update","currentModeId":"code"}"#,
                .metadata(kind: "current_mode_update", summary: "Current mode: code")),
            (
                #"{"sessionUpdate":"config_option_update","configOptions":[{"id":"model","name":"Model","type":"select","currentValue":"fast","options":[{"value":"fast","name":"Fast"}]}]}"#,
                .metadata(kind: "config_option_update", summary: "1 configuration option available: model")),
            (
                #"{"sessionUpdate":"session_info_update","title":"ACP work","updatedAt":"2026-09-03T12:00:00Z"}"#,
                .metadata(kind: "session_info_update", summary: "Session title: ACP work; updated: 2026-09-03T12:00:00Z")),
            (
                #"{"sessionUpdate":"usage_update","used":42,"size":100,"cost":{"amount":0.25,"currency":"USD"}}"#,
                .metadata(kind: "usage_update", summary: "Context usage: 42 of 100 tokens; cost: 0.25 USD")),
        ]
        let decoder = ACPEventDecoder()

        for (update, expectedEvent) in fixtures {
            let message = try message(update: update)

            #expect(try decoder.event(from: message) == expectedEvent)
        }
    }

    @Test func event_WhenKnownSessionUpdateIsMalformed_Throws() throws {
        let malformedUpdates = [
            #"{"sessionUpdate":"user_message_chunk","messageId":"user-1"}"#,
            #"{"sessionUpdate":"agent_message_chunk","content":{"type":"text"}}"#,
            #"{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":7}}"#,
            #"{"sessionUpdate":"tool_call","title":"Missing ID"}"#,
            #"{"sessionUpdate":"tool_call_update","toolCallId":9}"#,
            #"{"sessionUpdate":"plan","entries":[{"content":"Inspect","priority":"urgent","status":"pending"}]}"#,
            #"{"sessionUpdate":"available_commands_update","availableCommands":[{"name":"review"}]}"#,
            #"{"sessionUpdate":"current_mode_update","currentModeId":false}"#,
            #"{"sessionUpdate":"config_option_update","configOptions":[{"id":"model","name":"Model","type":"select"}]}"#,
            #"{"sessionUpdate":"session_info_update","title":3}"#,
            #"{"sessionUpdate":"usage_update","used":-1,"size":100}"#,
        ]
        let decoder = ACPEventDecoder()

        for update in malformedUpdates {
            let malformedMessage = try message(update: update)

            #expect(throws: (any Error).self) {
                try decoder.event(from: malformedMessage)
            }
        }
    }

    @Test func event_WhenConfigSelectOptionsAreGrouped_ReturnsMetadataSummary() throws {
        let update = #"{"sessionUpdate":"config_option_update","configOptions":[{"id":"model","name":"Model","type":"select","currentValue":"fast","options":[{"group":"speed","name":"Speed","options":[{"value":"fast","name":"Fast"},{"value":"balanced","name":"Balanced"}]}]}]}"#

        let event = try ACPEventDecoder().event(from: message(update: update))

        #expect(event == .metadata(
            kind: "config_option_update",
            summary: "1 configuration option available: model"))
    }

    @Test func event_WhenGroupedConfigOptionContainsMalformedChoice_Throws() throws {
        let update = #"{"sessionUpdate":"config_option_update","configOptions":[{"id":"model","name":"Model","type":"select","currentValue":"fast","options":[{"group":"speed","name":"Speed","options":[{"value":"fast"}]}]}]}"#
        let malformedMessage = try message(update: update)

        #expect(throws: (any Error).self) {
            try ACPEventDecoder().event(from: malformedMessage)
        }
    }

    @Test func event_WhenAgentMessageContainsArtifact_ReturnsTypedArtifact() throws {
        let decoder = ACPEventDecoder()
        let image = AgentArtifact(
            uri: "file:///tmp/preview.png",
            name: "preview.png",
            title: nil,
            descriptiveText: nil,
            mimeType: "image/png",
            declaredSize: nil,
            payload: .image(data: Data("png".utf8), mimeType: "image/png"))
        let document = AgentArtifact(
            uri: "file:///tmp/report.pdf",
            name: "report.pdf",
            title: "Security report",
            descriptiveText: "Generated report",
            mimeType: "application/pdf",
            declaredSize: 1_024,
            payload: .linked)

        #expect(try decoder.event(from: message(update:
            #"{"sessionUpdate":"agent_message_chunk","messageId":"image-1","content":{"type":"image","data":"cG5n","mimeType":"image/png","uri":"file:///tmp/preview.png"}}"#
        )) == .artifact(image))
        #expect(try decoder.event(from: message(update:
            #"{"sessionUpdate":"agent_message_chunk","content":{"type":"resource_link","uri":"file:///tmp/report.pdf","name":"report.pdf","title":"Security report","description":"Generated report","mimeType":"application/pdf","size":1024}}"#
        )) == .artifact(document))
    }

    @Test func event_WhenToolContentContainsResults_RetainsTextAndArtifactsInOrder() throws {
        let decoder = ACPEventDecoder()
        let document = AgentArtifact(
            uri: "file:///tmp/report.pdf",
            name: "report.pdf",
            title: nil,
            descriptiveText: nil,
            mimeType: "application/pdf",
            declaredSize: nil,
            payload: .linked)
        let content = #"[{"type":"content","content":{"type":"text","text":"Rendered"}},{"type":"content","content":{"type":"resource_link","uri":"file:///tmp/report.pdf","name":"report.pdf","mimeType":"application/pdf"}},{"type":"diff","path":"/tmp/a","newText":"x"},{"type":"terminal","terminalId":"term-1"}]"#

        let initialEvent = try #require(try decoder.event(from: message(update:
            #"{"sessionUpdate":"tool_call","toolCallId":"render","title":"Render","status":"in_progress","content":\#(content)}"#
        )))
        let updateEvent = try #require(try decoder.event(from: message(update:
            #"{"sessionUpdate":"tool_call_update","toolCallId":"render","status":"completed","content":\#(content)}"#
        )))

        guard case let .toolCall(toolCall) = initialEvent,
              case let .toolCallUpdate(toolUpdate) = updateEvent
        else {
            Issue.record("Expected typed tool events")
            return
        }
        #expect(toolCall.content == [.text("Rendered"), .artifact(document)])
        #expect(toolUpdate.content == [.text("Rendered"), .artifact(document)])
    }

    @Test func event_WhenAudioContentBlockIsValid_ReturnsMetadataWithoutRawPayload() throws {
        let update = #"{"sessionUpdate":"agent_message_chunk","content":{"type":"audio","data":"cHJpdmF0ZS1hdWRpbw==","mimeType":"audio/wav"}}"#

        let event = try ACPEventDecoder().event(from: message(update: update))

        #expect(event == .metadata(
            kind: "agent_message_chunk",
            summary: "Agent sent audio content"))
    }

    @Test func event_WhenNonTextContentBlockIsMalformed_Throws() throws {
        let malformedContent = [
            #"{"type":"image","data":"aW1hZ2U="}"#,
            #"{"type":"audio","data":17,"mimeType":"audio/wav"}"#,
            #"{"type":"resource_link","name":"Build log"}"#,
            #"{"type":"resource","resource":{"text":"missing URI"}}"#,
            #"{"type":"resource","resource":{"uri":"file:///tmp/result.bin"}}"#,
            #"{"type":"vendor_binary","data":"opaque"}"#,
        ]

        for content in malformedContent {
            let update = #"{"sessionUpdate":"agent_message_chunk","content":\#(content)}"#
            let malformedMessage = try message(update: update)

            #expect(throws: (any Error).self) {
                try ACPEventDecoder().event(from: malformedMessage)
            }
        }
    }

    @Test func event_WhenArtifactContentExceedsItsBound_Throws() throws {
        let oversizedURI = "file:///" + String(
            repeating: "u",
            count: AgentArtifactLimits.maximumURIBytes)
        let oversizedMIMEType = String(
            repeating: "m",
            count: AgentArtifactLimits.maximumMIMETypeBytes + 1)
        let oversizedTitle = String(
            repeating: "t",
            count: AgentArtifactLimits.maximumDisplayTextBytes + 1)
        let oversizedBlob = Data(
            repeating: 0x41,
            count: AgentArtifactLimits.maximumEmbeddedPayloadBytes + 1).base64EncodedString()
        let malformedContent = [
            #"{"type":"image","data":"not base64!","mimeType":"image/png"}"#,
            #"{"type":"resource_link","name":"report.pdf","uri":"file:///tmp/report.pdf","size":-1}"#,
            #"{"type":"resource_link","name":"report.pdf","uri":"\#(oversizedURI)"}"#,
            #"{"type":"resource_link","name":"report.pdf","uri":"file:///tmp/report.pdf","mimeType":"\#(oversizedMIMEType)"}"#,
            #"{"type":"resource_link","name":"report.pdf","title":"\#(oversizedTitle)","uri":"file:///tmp/report.pdf"}"#,
            #"{"type":"resource","resource":{"uri":"file:///tmp/result.bin","blob":"\#(oversizedBlob)"}}"#,
        ]

        for content in malformedContent {
            let update = #"{"sessionUpdate":"agent_message_chunk","content":\#(content)}"#

            #expect(throws: (any Error).self) {
                try ACPEventDecoder().event(from: message(update: update))
            }
        }
    }

    @Test func event_WhenUpdateDiscriminatorIsUnknown_ReturnsBoundedSummaryWithoutRawPayload() throws {
        let secret = String(repeating: "provider-private-payload", count: 20_000)
        let update = #"{"sessionUpdate":"vendor_progress","payload":"\#(secret)"}"#
        let decoder = ACPEventDecoder()

        let decodedEvent = try decoder.event(from: message(update: update))
        let event = try #require(decodedEvent)

        guard case let .unknown(discriminator, summary) = event else {
            Issue.record("Expected an unknown event")
            return
        }
        #expect(discriminator == "vendor_progress")
        #expect(summary == "Unsupported ACP session update: vendor_progress")
        #expect(summary.utf8.count <= ACPEventDecoder.maximumSummaryBytes)
        #expect(!summary.contains("provider-private-payload"))
    }

    @Test func event_WhenOpaqueCorrelationIdentifierExceedsBound_Throws() throws {
        let oversized = String(
            repeating: "i",
            count: ACPEventDecoder.maximumOpaqueIdentifierBytes + 1)
        let updates = [
            #"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"x"},"messageId":"\#(oversized)"}"#,
            #"{"sessionUpdate":"tool_call","toolCallId":"\#(oversized)","title":"Read"}"#,
            #"{"sessionUpdate":"tool_call_update","toolCallId":"\#(oversized)"}"#,
        ]
        let decoder = ACPEventDecoder()

        for update in updates {
            #expect(throws: (any Error).self) {
                try decoder.event(from: message(update: update))
            }
        }
        #expect(throws: (any Error).self) {
            try decoder.event(from: message(update: updates[0], sessionID: oversized))
        }
    }

    @Test func event_WhenEnvelopeIsNotSessionUpdate_ReturnsNil() throws {
        let data = Data(#"{"jsonrpc":"2.0","method":"other/event","params":{"value":1}}"#.utf8)
        let message = try JSONDecoder().decode(ACPMessage.self, from: data)

        #expect(try ACPEventDecoder().event(from: message) == nil)
    }

    @Test func coding_WhenIntegerRequestIDExceedsDoublePrecision_RoundTripsExactly() throws {
        let data = Data(#"{"jsonrpc":"2.0","id":9007199254740993,"method":"initialize","params":{}}"#.utf8)

        let message = try JSONDecoder().decode(ACPMessage.self, from: data)
        let roundTripped = try JSONDecoder().decode(
            ACPMessage.self,
            from: JSONEncoder().encode(message))

        #expect(message == .request(
            id: .integer(9_007_199_254_740_993),
            method: "initialize",
            params: .object([:])))
        #expect(roundTripped == message)
    }

    @Test func decoding_WhenJSONRPCVersionIsUnsupported_Throws() {
        let data = Data(#"{"jsonrpc":"1.0","method":"session/update"}"#.utf8)

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ACPMessage.self, from: data)
        }
    }

    @Test func init_WhenPermissionRequestUsesEveryJSONRPCIDShape_PreservesIt() {
        let identifiers: [ACPRequestID] = [
            .integer(9_007_199_254_740_993),
            .string("permission-17"),
            .null,
        ]

        for identifier in identifiers {
            let request = AgentPermissionRequest(
                turnToken: AgentTurnToken(),
                requestID: identifier,
                toolCall: AgentToolCallUpdate(id: "tool-1"),
                options: [])

            #expect(request.requestID == identifier)
        }
    }

    private func message(update: String, sessionID: String = "session-1") throws -> ACPMessage {
        let data = Data(
            #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"\#(sessionID)","update":\#(update)}}"#.utf8)
        return try JSONDecoder().decode(ACPMessage.self, from: data)
    }
}
