// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import VoiceActivationCore

@Suite(.serialized)
struct AgentRunEventDeliveryResponseChannelTests {
    @Test func sameChannelAndMessageID_CoalescesWithinBudget() async {
        let queue = AgentRunEventDeliveryQueue()
        #expect(queue.send(.agentSpokenMessageDelta(messageID: "m", text: "Hello")) == .accepted)
        #expect(queue.send(.agentSpokenMessageDelta(messageID: "m", text: " world")) == .accepted)

        #expect(await drain(queue) == [
            .agentSpokenMessageDelta(messageID: "m", text: "Hello world"),
        ])
    }

    @Test func differentChannelOrMessageID_PreservesBoundaryAndOrder() async {
        let queue = AgentRunEventDeliveryQueue()
        #expect(queue.send(.agentSpokenMessageDelta(messageID: "one", text: "A")) == .accepted)
        #expect(queue.send(.agentDisplayMessageDelta(messageID: "one", text: "B")) == .accepted)
        #expect(queue.send(.agentSpokenMessageDelta(messageID: "two", text: "C")) == .accepted)

        #expect(await drain(queue) == [
            .agentSpokenMessageDelta(messageID: "one", text: "A"),
            .agentDisplayMessageDelta(messageID: "one", text: "B"),
            .agentSpokenMessageDelta(messageID: "two", text: "C"),
        ])
    }

    @Test func narrationReady_IsAdmittedAtomicallyWithoutSuffixTruncation() async {
        let exactQueue = AgentRunEventDeliveryQueue()
        let exactText = "  exact words with unicode 🩷  "
        #expect(exactQueue.send(.agentSpokenNarrationReady(
            messageID: "exact",
            text: exactText)) == .accepted)
        #expect(await drain(exactQueue) == [
            .agentSpokenNarrationReady(messageID: "exact", text: exactText),
        ])

        let pressureQueue = AgentRunEventDeliveryQueue()
        let chunk = String(repeating: "c", count: 64 * 1_024)
        for _ in 0..<7 {
            #expect(pressureQueue.send(.metadata(kind: "", summary: chunk)) == .accepted)
        }
        let remainingForSuppression = AgentRunEventDelivery.maximumPendingControlBytes
            - (7 * chunk.utf8.count) - 1
        #expect(pressureQueue.send(.metadata(
            kind: "",
            summary: String(repeating: "r", count: remainingForSuppression))) == .accepted)

        #expect(pressureQueue.send(.agentSpokenNarrationReady(
            messageID: "m",
            text: String(repeating: "word ", count: 4_000))) == .accepted)
        let events = await drain(pressureQueue)
        #expect(events.last == .agentSpokenNarrationSuppressed(
            messageID: "m",
            reason: .incompleteDelivery))
        #expect(!events.contains { event in
            if case .agentSpokenNarrationReady = event { return true }
            return false
        })
    }

    @Test func droppedSpokenFragment_SuppressesWholeNarrationUnit() async {
        let queue = AgentRunEventDeliveryQueue()
        #expect(queue.send(.agentSpokenMessageDelta(
            messageID: "m",
            text: String(repeating: "a", count: 400 * 1_024))) == .accepted)
        #expect(queue.send(.agentSpokenMessageDelta(
            messageID: "m",
            text: String(repeating: "b", count: 200 * 1_024))) == .accepted)
        #expect(queue.send(.agentSpokenNarrationReady(
            messageID: "m",
            text: "complete original narration")) == .accepted)

        let events = await drain(queue)
        #expect(events.contains(.agentSpokenNarrationSuppressed(
            messageID: "m",
            reason: .incompleteDelivery)))
        #expect(!events.contains(.agentSpokenNarrationReady(
            messageID: "m",
            text: "complete original narration")))
    }

    @Test func pressureAfterNarrationReady_ReplacesQueuedReadyWithSuppression() async {
        let queue = AgentRunEventDeliveryQueue()
        #expect(queue.send(.agentSpokenMessageDelta(
            messageID: "m",
            text: String(repeating: "a", count: 400 * 1_024))) == .accepted)
        #expect(queue.send(.agentSpokenNarrationReady(
            messageID: "m",
            text: "complete original narration")) == .accepted)

        #expect(queue.send(.agentMessageDelta(
            messageID: "later",
            text: String(repeating: "b", count: 200 * 1_024))) == .accepted)

        let events = await drain(queue)
        #expect(events.contains(.agentSpokenNarrationSuppressed(
            messageID: "m",
            reason: .incompleteDelivery)))
        #expect(!events.contains(.agentSpokenNarrationReady(
            messageID: "m",
            text: "complete original narration")))
    }

    private func drain(_ queue: AgentRunEventDeliveryQueue) async -> [AgentRunEvent] {
        queue.startDraining()
        var events: [AgentRunEvent] = []
        while let event = await queue.next() {
            events.append(event)
        }
        return events
    }
}
