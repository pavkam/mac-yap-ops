// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import VoiceActivationCore

struct AgentSessionPresentationKey: Hashable, Sendable {
    let profileID: UUID
    let sessionID: String
}

@MainActor
final class AgentSessionPresentationRegistry {
    static let maximumSessions = 4

    struct Entry {
        let key: AgentSessionPresentationKey
        let runID: UUID
        let appRunGeneration: UInt64
        let profile: WakeProfile
        let presentation: AgentRunPresentation
    }

    private(set) var entries: [Entry] = []
    private(set) var visibleKey: AgentSessionPresentationKey?

    var activeEntries: [Entry] {
        entries.filter { $0.presentation.snapshot?.hasActiveBackgroundTasks == true }
    }

    @discardableResult
    func register(
        presentation: AgentRunPresentation,
        profile: WakeProfile,
        sessionID: String,
        appRunGeneration: UInt64
    ) -> Bool {
        let key = AgentSessionPresentationKey(profileID: profile.id, sessionID: sessionID)
        if let index = entries.firstIndex(where: { $0.key == key }) {
            entries[index] = Entry(
                key: key,
                runID: presentation.snapshot?.runID ?? entries[index].runID,
                appRunGeneration: appRunGeneration,
                profile: profile,
                presentation: presentation)
            visibleKey = key
            return true
        }
        if entries.count == Self.maximumSessions {
            guard let removable = entries.firstIndex(where: {
                $0.presentation.snapshot?.hasActiveBackgroundTasks != true
            }) else { return false }
            entries.remove(at: removable)
        }
        guard let runID = presentation.snapshot?.runID else { return false }
        entries.append(Entry(
            key: key,
            runID: runID,
            appRunGeneration: appRunGeneration,
            profile: profile,
            presentation: presentation))
        visibleKey = key
        return true
    }

    func entry(for key: AgentSessionPresentationKey) -> Entry? {
        entries.first { $0.key == key }
    }

    func entry(runID: UUID) -> Entry? {
        entries.first { $0.runID == runID }
    }

    @discardableResult
    func select(_ key: AgentSessionPresentationKey) -> Entry? {
        guard let entry = entry(for: key) else { return nil }
        visibleKey = key
        return entry
    }

    func remove(runID: UUID) {
        entries.removeAll { $0.runID == runID }
        if visibleKey.map({ key in entries.contains { $0.key == key } }) != true {
            visibleKey = nil
        }
    }

    func remove(profileIDs: Set<UUID>) {
        entries.removeAll { profileIDs.contains($0.key.profileID) }
        if visibleKey.map({ key in entries.contains { $0.key == key } }) != true {
            visibleKey = nil
        }
    }

    func removeAll() {
        entries.removeAll(keepingCapacity: false)
        visibleKey = nil
    }
}
