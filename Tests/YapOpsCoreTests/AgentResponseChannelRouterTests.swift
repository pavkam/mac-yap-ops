// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Testing
@testable import YapOpsCore

struct AgentResponseChannelRouterTests {
    @Test func spokenMarker_WhenSplitAtEveryPosition_RoutesWithoutLeakingMarker() {
        let marker = AgentResponseChannelRouter.spokenMarker

        for split in marker.indicesIncludingEnd {
            var router = AgentResponseChannelRouter()
            var events = router.route(.agentMessageDelta(
                messageID: "answer",
                text: String(marker[..<split])))
            events += router.route(.agentMessageDelta(
                messageID: "answer",
                text: String(marker[split...]) + "Hello 👋"))
            events += router.finishMessage()

            #expect(spokenText(in: events) == "Hello 👋")
            #expect(displayText(in: events).isEmpty)
            #expect(legacyText(in: events).isEmpty)
            #expect(narrationReady(in: events) == [
                NarrationRecord(messageID: "answer", text: "Hello 👋"),
            ])
        }
    }

    @Test func spokenMarkerWithoutNewline_WhenSplitAtEveryPosition_RoutesWithoutLeakingMarker() {
        let marker = AgentResponseChannelRouter.spokenMarkerBody

        for split in marker.indicesIncludingEnd {
            var router = AgentResponseChannelRouter()
            var events = router.route(.agentMessageDelta(
                messageID: "answer",
                text: String(marker[..<split])))
            events += router.route(.agentMessageDelta(
                messageID: "answer",
                text: String(marker[split...]) + "Let me check."))
            events += router.finishMessage()

            #expect(spokenText(in: events) == "Let me check.")
            #expect(displayText(in: events).isEmpty)
            #expect(legacyText(in: events).isEmpty)
            #expect(narrationReady(in: events) == [
                NarrationRecord(messageID: "answer", text: "Let me check."),
            ])
        }
    }

    @Test func spokenMarkerWithNewline_ConsumesOnlyTheMarkerNewline() {
        var router = AgentResponseChannelRouter()
        var events = router.route(.agentMessageDelta(
            messageID: "answer",
            text: AgentResponseChannelRouter.spokenMarker + "\nLeading blank line"))
        events += router.finishMessage()

        #expect(spokenText(in: events) == "\nLeading blank line")
        #expect(legacyText(in: events).isEmpty)
    }

    @Test func markerOnlyMessage_WhenFinished_EmitsNothingInsteadOfLeakingMarker() {
        for marker in [
            AgentResponseChannelRouter.spokenMarkerBody,
            AgentResponseChannelRouter.spokenMarker,
        ] {
            var router = AgentResponseChannelRouter()
            var events = router.route(.agentMessageDelta(messageID: "empty", text: marker))
            events += router.finishMessage()

            #expect(events.isEmpty)
        }
    }

    @Test func displayMarker_WhenSplitAtEveryPosition_RoutesBothChannelsWithoutLeakingMarker() {
        let marker = AgentResponseChannelRouter.displayMarker

        for split in marker.indicesIncludingEnd {
            var router = AgentResponseChannelRouter()
            var events = router.route(.agentMessageDelta(
                messageID: "answer",
                text: AgentResponseChannelRouter.spokenMarker + "Say this"))
            events += router.route(.agentMessageDelta(
                messageID: "answer",
                text: String(marker[..<split])))
            events += router.route(.agentMessageDelta(
                messageID: "answer",
                text: String(marker[split...]) + "**Show this**"))
            events += router.finishMessage()

            #expect(spokenText(in: events) == "Say this")
            #expect(displayText(in: events) == "**Show this**")
            #expect(legacyText(in: events).isEmpty)
            #expect(narrationReady(in: events) == [
                NarrationRecord(messageID: "answer", text: "Say this"),
            ])
        }
    }

    @Test func markerTypedContent_WhenUnicodeArrivesAcrossChunks_PreservesCharactersExactly() {
        var router = AgentResponseChannelRouter()
        var events = router.route(.agentMessageDelta(
            messageID: "unicode",
            text: AgentResponseChannelRouter.spokenMarker))
        for character in "Café 👩‍💻 — pronto" {
            events += router.route(.agentMessageDelta(
                messageID: "unicode",
                text: String(character)))
        }
        events += router.finishMessage()

        #expect(spokenText(in: events) == "Café 👩‍💻 — pronto")
        #expect(narrationReady(in: events) == [
            NarrationRecord(messageID: "unicode", text: "Café 👩‍💻 — pronto"),
        ])
    }

    @Test func unmarkedMessage_WhenSplitAtEveryPosition_PreservesEveryLegacyByte() {
        let original = "Ordinary 🧑🏽‍💻 **Markdown**\n"

        for split in original.indicesIncludingEnd {
            var router = AgentResponseChannelRouter()
            var events = router.route(.agentMessageDelta(
                messageID: "legacy",
                text: String(original[..<split])))
            events += router.route(.agentMessageDelta(
                messageID: "legacy",
                text: String(original[split...])))
            events += router.finishMessage()

            #expect(Array(legacyText(in: events).utf8) == Array(original.utf8))
            #expect(spokenText(in: events).isEmpty)
            #expect(displayText(in: events).isEmpty)
            #expect(narrationReady(in: events).isEmpty)
        }
    }

    @Test func partialStartMarker_WhenSemanticBoundaryArrives_FlushesLegacyBeforeBoundary() {
        let marker = AgentResponseChannelRouter.spokenMarkerBody

        for split in marker.indices.dropFirst() {
            let prefix = String(marker[..<split])
            var router = AgentResponseChannelRouter()
            #expect(router.route(.agentMessageDelta(messageID: "partial", text: prefix)).isEmpty)

            let events = router.route(.metadata(kind: "phase", summary: "working"))

            #expect(events == [
                .agentMessageDelta(messageID: "partial", text: prefix),
                .metadata(kind: "phase", summary: "working"),
            ])
        }
    }

    @Test func unknownStartMarker_FallsBackAndKeepsFollowingChunksLegacy() {
        var router = AgentResponseChannelRouter()
        let malformed = "[[yapops:spoken:v2]]\n"

        var events = router.route(.agentMessageDelta(messageID: "legacy", text: malformed))
        events += router.route(.agentMessageDelta(
            messageID: "legacy",
            text: AgentResponseChannelRouter.spokenMarker + "still legacy"))
        events += router.finishMessage()

        #expect(legacyText(in: events) == malformed
            + AgentResponseChannelRouter.spokenMarker + "still legacy")
        #expect(spokenText(in: events).isEmpty)
    }

    @Test func messageIDChange_FinishesPreviousMessageBeforeRoutingNext() {
        var router = AgentResponseChannelRouter()
        let partial = "[[yapops:sp"
        #expect(router.route(.agentMessageDelta(messageID: "first", text: partial)).isEmpty)

        var events = router.route(.agentMessageDelta(
            messageID: "second",
            text: AgentResponseChannelRouter.spokenMarker + "Done"))
        events += router.finishMessage()

        #expect(events.first == .agentMessageDelta(messageID: "first", text: partial))
        #expect(spokenText(in: events) == "Done")
        #expect(narrationReady(in: events) == [
            NarrationRecord(messageID: "second", text: "Done"),
        ])
    }

    @Test func typedMetadataEvents_BypassMarkerParsingAndPreserveLiteralText() {
        var router = AgentResponseChannelRouter()
        let markerLookingSpoken = "Literal"
            + AgentResponseChannelRouter.displayMarker + "still speech"

        var events = router.route(.agentSpokenMessageDelta(
            messageID: "typed",
            text: markerLookingSpoken))
        events += router.route(.agentDisplayMessageDelta(
            messageID: "typed",
            text: AgentResponseChannelRouter.spokenMarker + "literal display"))
        events += router.finishMessage()

        #expect(spokenText(in: events) == markerLookingSpoken)
        #expect(displayText(in: events)
            == AgentResponseChannelRouter.spokenMarker + "literal display")
        #expect(narrationReady(in: events) == [
            NarrationRecord(messageID: "typed", text: markerLookingSpoken),
        ])
        #expect(legacyText(in: events).isEmpty)
    }

    @Test func spokenOnlyMessage_WhenFinished_EmitsOneExactNarrationUnit() {
        var router = AgentResponseChannelRouter()

        var events = router.route(.agentMessageDelta(
            messageID: "spoken-only",
            text: AgentResponseChannelRouter.spokenMarker + "One "))
        events += router.route(.agentMessageDelta(
            messageID: "spoken-only",
            text: "exact answer."))
        events += router.finishMessage()

        #expect(spokenText(in: events) == "One exact answer.")
        #expect(narrationReady(in: events) == [
            NarrationRecord(messageID: "spoken-only", text: "One exact answer."),
        ])
        #expect(suppressionReasons(in: events).isEmpty)
    }

    @Test func oversizedSpokenMessage_RemainsVisibleButSuppressesNarrationAtomically() {
        var router = AgentResponseChannelRouter()
        let admitted = String(repeating: "a", count: 20_000)
        let overflow = "💅"

        var events = router.route(.agentMessageDelta(
            messageID: "large",
            text: AgentResponseChannelRouter.spokenMarker + admitted))
        events += router.route(.agentMessageDelta(messageID: "large", text: overflow))
        events += router.finishMessage()

        #expect(spokenText(in: events) == admitted + overflow)
        #expect(narrationReady(in: events).isEmpty)
        #expect(suppressionReasons(in: events) == [.oversized])
    }

    @Test func semanticBoundary_FinishesSpokenNarrationBeforePreservingControlEvent() {
        var router = AgentResponseChannelRouter()
        _ = router.route(.agentMessageDelta(
            messageID: "answer",
            text: AgentResponseChannelRouter.spokenMarker + "Done"))

        let events = router.route(.metadata(kind: "phase", summary: "complete"))

        #expect(events == [
            .agentSpokenNarrationReady(messageID: "answer", text: "Done"),
            .metadata(kind: "phase", summary: "complete"),
        ])
    }

    @Test func reset_DropsOnlyUnadmittedBufferedStateAndEmitsNothing() {
        var router = AgentResponseChannelRouter()
        #expect(router.route(.agentMessageDelta(
            messageID: "retired",
            text: "[[yapops:sp")).isEmpty)

        router.reset()

        #expect(router.finishMessage().isEmpty)
        var events = router.route(.agentMessageDelta(
            messageID: "current",
            text: AgentResponseChannelRouter.spokenMarker + "Current"))
        events += router.finishMessage()
        #expect(spokenText(in: events) == "Current")
        #expect(narrationReady(in: events) == [
            NarrationRecord(messageID: "current", text: "Current"),
        ])
    }
}

private func legacyText(in events: [AgentRunEvent]) -> String {
    events.compactMap { event in
        guard case let .agentMessageDelta(_, text) = event else { return nil }
        return text
    }.joined()
}

private func spokenText(in events: [AgentRunEvent]) -> String {
    events.compactMap { event in
        guard case let .agentSpokenMessageDelta(_, text) = event else { return nil }
        return text
    }.joined()
}

private func displayText(in events: [AgentRunEvent]) -> String {
    events.compactMap { event in
        guard case let .agentDisplayMessageDelta(_, text) = event else { return nil }
        return text
    }.joined()
}

private struct NarrationRecord: Equatable {
    let messageID: String?
    let text: String
}

private func narrationReady(in events: [AgentRunEvent]) -> [NarrationRecord] {
    events.compactMap { event in
        guard case let .agentSpokenNarrationReady(messageID, text) = event else { return nil }
        return NarrationRecord(messageID: messageID, text: text)
    }
}

private func suppressionReasons(
    in events: [AgentRunEvent]
) -> [AgentSpokenSuppressionReason] {
    events.compactMap { event in
        guard case let .agentSpokenNarrationSuppressed(_, reason) = event else { return nil }
        return reason
    }
}

private extension String {
    var indicesIncludingEnd: [String.Index] {
        Array(indices) + [endIndex]
    }
}
