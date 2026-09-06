// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationCore

extension ACPClientConnectionTests {
    @Test func requestPermission_WithV1Metadata_PublishesExactPromptAndOptions() async throws {
        let transport = FakeACPTransport()
        let connection = try await establishConnection(transport: transport, policy: .ask)
        let recorder = AgentEventRecorder()
        let promptTask = prompt(connection, text: "Clean up", recorder: recorder)
        _ = await recorder.nextEvent()
        _ = await transport.nextSentMessage()
        let requestIDs: [ACPRequestID] = [
            .string("permission-exact"),
            .integer(9_007_199_254_740_993),
        ]
        var turnToken: AgentTurnToken?

        for (index, requestID) in requestIDs.enumerated() {
            try await transport.feed(permissionPromptRequest(
                id: requestID,
                toolID: "tool-\(index)",
                toolTitle: "Standard title \(index)",
                metadata: .object([
                    "permission": .object([
                        "version": .integer(1),
                        "title": .string("  Move 43 old downloads to Trash? \n"),
                        "description": .string("Provider detail\tkept exactly. "),
                    ]),
                ])))

            guard case let .permissionRequested(request) = await recorder.nextEvent() else {
                Issue.record("Expected a permission event")
                await connection.close()
                return
            }
            turnToken = turnToken ?? request.turnToken
            #expect(request.turnToken == turnToken)
            #expect(request.requestID == requestID)
            #expect(request.toolCall.id == "tool-\(index)")
            #expect(request.toolCall.title == "Standard title \(index)")
            #expect(request.presentationText == AgentPermissionPresentationText(
                title: "  Move 43 old downloads to Trash? \n",
                description: "Provider detail\tkept exactly. "))
            #expect(request.options == [
                AgentPermissionOption(id: "once", label: "Allow once", kind: .allowOnce),
                AgentPermissionOption(id: "deny", label: "Deny", kind: .rejectOnce),
            ])

            await connection.resolvePermission(
                turnToken: request.turnToken,
                requestID: request.requestID,
                optionID: "once")
            #expect(await transport.nextSentMessage() == permissionSelection(
                id: requestID,
                optionID: "once"))
        }

        try await transport.feed(promptResponse(id: 3, stopReason: "end_turn"))
        _ = try await promptTask.value
        await connection.close()
    }

    @Test func requestPermission_WithMissingUnknownOrMalformedMetadata_FallsBackToStandardFields()
        async throws
    {
        let transport = FakeACPTransport()
        let connection = try await establishConnection(transport: transport, policy: .ask)
        let recorder = AgentEventRecorder()
        let promptTask = prompt(connection, text: "Fallback", recorder: recorder)
        _ = await recorder.nextEvent()
        _ = await transport.nextSentMessage()
        let metadataFixtures: [ACPJSONValue?] = [
            nil,
            .object(["differentExtension": .string("ignored")]),
            .object(["permission": .string("not an object")]),
            .object(["permission": .object([
                "version": .integer(2),
                "title": .string("Unknown version"),
            ])]),
            .object(["permission": .object([
                "version": .string("1"),
                "title": .string("Wrong version type"),
            ])]),
            .object(["permission": .object([
                "version": .integer(1),
                "title": .integer(7),
            ])]),
            .object(["permission": .object([
                "version": .integer(1),
                "title": .string(" \n\t "),
            ])]),
            .object(["permission": .object([
                "version": .integer(1),
                "title": .string("Unsafe\0title"),
            ])]),
            .object(["permission": .object([
                "version": .integer(1),
                "title": .string("Valid title"),
                "description": .integer(8),
            ])]),
            .object(["permission": .object([
                "version": .integer(1),
                "title": .string("Valid title"),
                "description": .string("Unsafe\0description"),
            ])]),
        ]

        for (index, metadata) in metadataFixtures.enumerated() {
            let requestID = ACPRequestID.string("fallback-\(index)")
            try await transport.feed(permissionPromptRequest(
                id: requestID,
                toolTitle: "Standard fallback \(index)",
                metadata: metadata))

            guard case let .permissionRequested(request) = await recorder.nextEvent() else {
                Issue.record("Expected a standard fallback permission")
                await connection.close()
                return
            }
            #expect(request.requestID == requestID)
            #expect(request.presentationText == nil)
            #expect(request.toolCall.title == "Standard fallback \(index)")
            #expect(request.options.map(\.label) == ["Allow once", "Deny"])

            await connection.resolvePermission(
                turnToken: request.turnToken,
                requestID: requestID,
                optionID: "deny")
            #expect(await transport.nextSentMessage() == permissionSelection(
                id: requestID,
                optionID: "deny"))
        }

        try await transport.feed(promptResponse(id: 3, stopReason: "end_turn"))
        _ = try await promptTask.value
        await connection.close()
    }

    @Test func requestPermission_WithOversizedMetadata_DoesNotRejectValidStandardPermission()
        async throws
    {
        let transport = FakeACPTransport()
        let connection = try await establishConnection(transport: transport, policy: .ask)
        let recorder = AgentEventRecorder()
        let promptTask = prompt(connection, text: "Bound metadata", recorder: recorder)
        _ = await recorder.nextEvent()
        _ = await transport.nextSentMessage()
        let exactTitle = String(
            repeating: "é",
            count: AgentPermissionPresentationText.maximumPermissionPromptTitleBytes / 2)
        let exactDescription = String(
            repeating: "🧪",
            count: AgentPermissionPresentationText.maximumPermissionPromptDescriptionBytes / 4)
        let fixtures: [(String, String, String?, AgentPermissionPresentationText?)] = [
            (
                "exact-bound",
                exactTitle,
                exactDescription,
                AgentPermissionPresentationText(title: exactTitle, description: exactDescription)),
            ("title-oversized", exactTitle + "é", nil, nil),
            ("description-oversized", "Valid title", exactDescription + "🧪", nil),
        ]

        for (identifier, title, description, expectedPresentation) in fixtures {
            var permission: [String: ACPJSONValue] = [
                "version": .integer(1),
                "title": .string(title),
            ]
            if let description {
                permission["description"] = .string(description)
            }
            let requestID = ACPRequestID.string(identifier)
            try await transport.feed(permissionPromptRequest(
                id: requestID,
                toolTitle: "Standard bounded fallback",
                metadata: .object(["permission": .object(permission)])))

            guard case let .permissionRequested(request) = await recorder.nextEvent() else {
                Issue.record("Expected an admitted standard permission")
                await connection.close()
                return
            }
            #expect(request.presentationText == expectedPresentation)
            #expect(request.toolCall.title == "Standard bounded fallback")
            await connection.resolvePermission(
                turnToken: request.turnToken,
                requestID: requestID,
                optionID: "deny")
            #expect(await transport.nextSentMessage() == permissionSelection(
                id: requestID,
                optionID: "deny"))
        }

        try await transport.feed(promptResponse(id: 3, stopReason: "end_turn"))
        _ = try await promptTask.value
        await connection.close()
    }

    @Test func requestPermission_WithRawToolPayload_DoesNotRetainOrPublishPayload() async throws {
        let secret = "RAW-SECRET-SENTINEL-DO-NOT-RETAIN"
        let transport = FakeACPTransport()
        let connection = try await establishConnection(transport: transport, policy: .ask)
        let recorder = AgentEventRecorder()
        let promptTask = prompt(connection, text: "Keep raw private", recorder: recorder)
        _ = await recorder.nextEvent()
        _ = await transport.nextSentMessage()
        let requestID = ACPRequestID.string("raw-private")
        try await transport.feed(permissionPromptRequest(
            id: requestID,
            toolID: "tool-private",
            toolTitle: "Review operation",
            metadata: .object([
                "permission": .object([
                    "version": .integer(1),
                    "title": .string("Confirm operation"),
                    "description": .string("Only this description is retained"),
                ]),
                "unknown": .string(secret),
            ]),
            rawSentinel: secret))

        guard case let .permissionRequested(request) = await recorder.nextEvent() else {
            Issue.record("Expected a permission event")
            await connection.close()
            return
        }
        let expectedRetainedBytes =
            "tool-private".utf8.count
            + "Review operation".utf8.count
            + "raw-private".utf8.count
            + "once".utf8.count + "Allow once".utf8.count
            + "deny".utf8.count + "Deny".utf8.count
            + "Confirm operation".utf8.count
            + "Only this description is retained".utf8.count
        #expect(request.toolCall.content.isEmpty)
        #expect(!String(reflecting: request).contains(secret))
        #expect(permissionRetainedByteCount(request) == expectedRetainedBytes)
        #expect(AgentRunEventDeliveryEntry.controlByteCount(
            for: .permissionRequested(request)) == expectedRetainedBytes)

        await connection.resolvePermission(
            turnToken: request.turnToken,
            requestID: requestID,
            optionID: "deny")
        #expect(await transport.nextSentMessage() == permissionSelection(
            id: requestID,
            optionID: "deny"))
        try await transport.feed(promptResponse(id: 3, stopReason: "end_turn"))
        _ = try await promptTask.value
        await connection.close()
    }

    private func permissionPromptRequest(
        id: ACPRequestID,
        toolID: String = "tool-1",
        toolTitle: String = "Edit a file",
        metadata: ACPJSONValue?,
        rawSentinel: String? = nil
    ) -> ACPMessage {
        var toolCall: [String: ACPJSONValue] = [
            "toolCallId": .string(toolID),
            "title": .string(toolTitle),
            "kind": .string("edit"),
            "status": .string("pending"),
        ]
        if let rawSentinel {
            toolCall["rawInput"] = .object(["command": .string(rawSentinel)])
            toolCall["rawOutput"] = .object(["result": .string(rawSentinel)])
            toolCall["content"] = .array([.object([
                "type": .string("content"),
                "content": .string(rawSentinel),
            ])])
            toolCall["locations"] = .array([.object([
                "path": .string(rawSentinel),
            ])])
        }
        var params: [String: ACPJSONValue] = [
            "sessionId": .string("session-1"),
            "toolCall": .object(toolCall),
            "options": .array([
                permissionOption(id: "once", name: "Allow once", kind: "allow_once"),
                permissionOption(id: "deny", name: "Deny", kind: "reject_once"),
            ]),
        ]
        if let metadata {
            params["_meta"] = metadata
        }
        return .request(
            id: id,
            method: "session/request_permission",
            params: .object(params))
    }
}
