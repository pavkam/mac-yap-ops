// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import YapOpsCore

extension ACPAgentRunnerTests {
    @Test func freshConversation_WithSavedBookmark_DoesNotReadOrReplayPreviousSession() async throws {
        let configuration = try makeConfiguration()
        let profileID = UUID()
        let store = RecordingAgentContinuityStore(bookmarks: [AgentSessionBookmark(
            profileID: profileID,
            sessionID: "previous-session",
            providerFingerprint: AgentProviderFingerprint.make(configuration: configuration),
            lastAccessOrdinal: 1)])
        let transport = FakeACPTransport()
        await automaticallyCompleteSession(transport, sessionID: "fresh-session")
        let runner = ACPAgentRunner(
            transportFactory: RunnerTransportFactory(transports: [transport]),
            continuityStore: store)
        let events = RunnerStreamEventRecorder()

        _ = try await runner.run(
            profileID: profileID, configuration: configuration,
            prompt: AgentPrompt(request: "New request", context: nil),
            restorationNeed: .fresh, onEvent: { await events.record($0) })

        #expect(!(await store.recordedCalls()).contains(.read(profileID)))
        #expect((await store.snapshot()).bookmarks.map(\.sessionID) == ["fresh-session"])
        #expect((await events.recordedEvents()).allSatisfy {
            if case .live = $0 { return true }
            return false
        })
        #expect(await transport.allSentMessages().last == promptRequest(
            id: 3, text: "New request", sessionID: "fresh-session"))
        await runner.shutdown()
    }

    @Test func freshConversation_ReplacesWarmSession_WhileFollowUpsRetainContext() async throws {
        let profileID = UUID()
        let configuration = try makeConfiguration()
        let first = FakeACPTransport()
        let second = FakeACPTransport()
        await automaticallyCompleteSession(first, sessionID: "previous-session")
        await automaticallyCompleteSession(second, sessionID: "fresh-session")
        let factory = RunnerTransportFactory(transports: [first, second])
        let runner = ACPAgentRunner(transportFactory: factory)

        for (request, need) in [
            ("First", AgentSessionRestorationNeed.fresh),
            ("Follow-up", .visibleHistory),
            ("New conversation", .fresh),
        ] {
            _ = try await runner.run(
                profileID: profileID, configuration: configuration,
                prompt: AgentPrompt(request: request, context: nil),
                restorationNeed: need, onEvent: { _ in })
        }

        #expect(await factory.createdConfigurations().count == 2)
        #expect(await first.observedTerminationCount() == 1)
        #expect(await first.allSentMessages().last == promptRequest(
            id: 4, text: "Follow-up", sessionID: "previous-session"))
        #expect(await second.allSentMessages().last == promptRequest(
            id: 3, text: "New conversation", sessionID: "fresh-session"))
        await runner.shutdown()
    }

    private func automaticallyCompleteSession(
        _ transport: FakeACPTransport, sessionID: String
    ) async {
        await transport.handleSends { [weak transport] message in
            guard let transport, case let .request(id, method, _) = message else { return }
            let result: ACPJSONValue
            switch method {
            case "initialize":
                result = .object([
                    "protocolVersion": .integer(1),
                    "agentCapabilities": .object(["loadSession": .bool(true)]),
                    "agentInfo": .object(["name": .string("test-agent"), "version": .string("1")]),
                    "authMethods": .array([]),
                ])
            case "session/new":
                result = .object(["sessionId": .string(sessionID)])
            case "session/load":
                result = .object([:])
            case "session/prompt":
                result = .object(["stopReason": .string("end_turn")])
            default:
                Issue.record("Unexpected request: \(method)")
                return
            }
            try await transport.feed(.response(id: id, result: result))
        }
    }
}
