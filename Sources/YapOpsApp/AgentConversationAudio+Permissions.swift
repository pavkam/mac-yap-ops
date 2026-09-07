// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import YapOpsCore

struct AgentPermissionAudioKey: Equatable, Hashable, Sendable {
    let runID: UUID
    let turnToken: AgentTurnToken
    let requestID: ACPRequestID
}

struct PendingPermissionNarration: Equatable, Sendable {
    let key: AgentPermissionAudioKey
    let utterances: [String]
}

extension AgentConversationAudioPresenter {
    private static var maximumPendingPermissionNarrations: Int { 32 }
    private static var maximumPermissionNarrationCharacters: Int { 20_000 }

    func permissionResolutionBegan(
        runID: UUID,
        turnToken: AgentTurnToken,
        requestID: ACPRequestID
    ) {
        let key = AgentPermissionAudioKey(
            runID: runID,
            turnToken: turnToken,
            requestID: requestID)
        guard self.runID == runID,
            let index = pendingPermissionNarrations.firstIndex(where: { $0.key == key })
        else {
            diagnostics.record(
                category: .audio,
                event: "conversation_audio.permission_resolution_ignored",
                fields: ["reason": "stale_identity"])
            return
        }

        pendingPermissionNarrations.remove(at: index)
        player.stopSpeaking()
        for narration in pendingPermissionNarrations {
            enqueuePermissionNarration(narration)
        }
        updateWorking(pendingPermissionNarrations.isEmpty)
        diagnostics.record(
            category: .audio,
            event: "conversation_audio.permission_resolved",
            fields: ["pending_count": String(pendingPermissionNarrations.count)])
    }

    func handlePermissionRequest(_ request: AgentPermissionRequest) {
        guard let runID, !rejectsAgentSpeechUntilNextTurn else {
            diagnostics.record(
                category: .audio,
                event: "conversation_audio.permission_suppressed",
                fields: ["reason": "retired_turn"])
            return
        }
        let key = AgentPermissionAudioKey(
            runID: runID,
            turnToken: request.turnToken,
            requestID: request.requestID)
        guard !pendingPermissionNarrations.contains(where: { $0.key == key }) else {
            diagnostics.record(
                category: .audio,
                event: "conversation_audio.permission_suppressed",
                fields: ["reason": "duplicate_identity"])
            return
        }
        guard pendingPermissionNarrations.count < Self.maximumPendingPermissionNarrations else {
            diagnostics.record(
                category: .audio,
                event: "conversation_audio.permission_suppressed",
                fields: ["reason": "pending_limit"])
            updateWorking(false)
            return
        }

        var utterances: [String] = []
        if let title = request.presentationText?.title ?? request.toolCall.title,
            !title.isEmpty
        {
            utterances.append(title)
        }
        if let description = request.presentationText?.description,
            !description.isEmpty
        {
            utterances.append(description)
        }
        utterances.append(contentsOf: request.options.lazy.map(\.label).filter { !$0.isEmpty })
        let narration = PendingPermissionNarration(key: key, utterances: utterances)
        pendingPermissionNarrations.append(narration)
        enqueuePermissionNarration(narration)
        updateWorking(false)
    }

    private func enqueuePermissionNarration(_ narration: PendingPermissionNarration) {
        guard readsActiveReplies else {
            diagnostics.record(
                category: .audio,
                event: "conversation_audio.permission_suppressed",
                fields: ["reason": "speech_disabled"])
            return
        }
        let characterCount = narration.utterances.reduce(0) { count, utterance in
            let (value, overflow) = count.addingReportingOverflow(utterance.count)
            return overflow ? Int.max : value
        }
        guard !narration.utterances.isEmpty,
            characterCount <= Self.maximumPermissionNarrationCharacters
        else {
            diagnostics.record(
                category: .audio,
                event: "conversation_audio.permission_suppressed",
                fields: ["reason": narration.utterances.isEmpty ? "empty" : "oversized"])
            return
        }
        _ = player.speakVerbatim(narration.utterances, localeID: localeID())
    }
}
