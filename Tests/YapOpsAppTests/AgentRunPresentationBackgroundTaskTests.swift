// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import YapOpsApp
@testable import YapOpsCore

@Suite(.timeLimit(.minutes(1)))
struct AgentRunPresentationBackgroundTaskTests {
    @MainActor @Test
    func spawn_AfterPromptCompletion_PreservesListeningAndSetsActiveTaskFlag() throws {
        let fixture = try makePresentation()
        fixture.presentation.completeTurn(
            runID: fixture.runID,
            result: AgentRunResult(stopReason: .endTurn))

        fixture.presentation.receive(
            runID: fixture.runID,
            event: .backgroundTask(spawn(id: "watch", name: "Watch build")))

        #expect(fixture.presentation.snapshot?.phase == .listening)
        #expect(fixture.presentation.snapshot?.hasActiveBackgroundTasks == true)
    }

    @MainActor @Test
    func progressBeforeSpawn_CreatesGenericBoundedRow() throws {
        let fixture = try makePresentation()
        fixture.presentation.receive(
            runID: fixture.runID,
            event: .backgroundTask(.progress(
                id: AgentBackgroundTaskID(rawValue: "early"),
                description: "Checking tests",
                summary: "4 of 10",
                lastToolName: "swift test",
                usage: AgentBackgroundTaskUsage(
                    totalTokens: 20,
                    toolUses: 1,
                    durationMilliseconds: 400),
                outputFilePath: nil,
                toolCallID: nil)))

        let task = try #require(fixture.presentation.snapshot?.backgroundTasks.first)
        #expect(task.name == "Background task")
        #expect(task.description == "Checking tests")
        #expect(task.summary == "4 of 10")
    }

    @MainActor @Test
    func duplicateSpawn_UpdatesWithoutReordering() throws {
        let fixture = try makePresentation()
        fixture.presentation.receive(
            runID: fixture.runID,
            event: .backgroundTask(spawn(id: "one", name: "First")))
        fixture.presentation.receive(
            runID: fixture.runID,
            event: .backgroundTask(spawn(id: "two", name: "Second")))
        fixture.presentation.receive(
            runID: fixture.runID,
            event: .backgroundTask(spawn(id: "one", name: "Renamed")))

        let tasks = try #require(fixture.presentation.snapshot?.backgroundTasks)
        #expect(tasks.map(\.id.rawValue) == ["one", "two"])
        #expect(tasks.map(\.name) == ["Renamed", "Second"])
    }

    @MainActor @Test
    func thirtyThirdTask_EvictsOldestTerminalRow() throws {
        let fixture = try makePresentation()
        for index in 0..<AgentRunPresentation.maximumBackgroundTasks {
            fixture.presentation.receive(
                runID: fixture.runID,
                event: .backgroundTask(spawn(id: "task-\(index)", name: "Task \(index)")))
        }
        fixture.presentation.receive(
            runID: fixture.runID,
            event: .backgroundTask(.stateChanged(
                id: AgentBackgroundTaskID(rawValue: "task-0"),
                state: .completed,
                summary: "Done",
                outputFilePath: nil,
                toolCallID: nil)))

        fixture.presentation.receive(
            runID: fixture.runID,
            event: .backgroundTask(spawn(id: "task-32", name: "Newest")))

        let tasks = try #require(fixture.presentation.snapshot?.backgroundTasks)
        #expect(tasks.count == AgentRunPresentation.maximumBackgroundTasks)
        #expect(tasks.first?.id.rawValue == "task-1")
        #expect(tasks.last?.id.rawValue == "task-32")
    }

    @MainActor @Test
    func thirtyThirdActiveTask_IsIgnoredWithContentFreeDiagnostic() throws {
        let diagnostics = AppDiagnosticRecorderSpy()
        let fixture = try makePresentation(diagnostics: diagnostics)
        for index in 0...AgentRunPresentation.maximumBackgroundTasks {
            fixture.presentation.receive(
                runID: fixture.runID,
                event: .backgroundTask(spawn(id: "task-\(index)", name: "Private \(index)")))
        }

        let snapshot = try #require(fixture.presentation.snapshot)
        #expect(snapshot.backgroundTasks.count == AgentRunPresentation.maximumBackgroundTasks)
        #expect(snapshot.ignoredBackgroundTaskCount == 1)
        let diagnostic = try #require(diagnostics.snapshot().last {
            $0.event == "agent_presentation.background_task_ignored"
        })
        #expect(diagnostic.fields == ["reason": "active_limit"])
    }

    @MainActor @Test
    func closeDelete_DisabledUntilAllTasksTerminal() throws {
        let fixture = try makePresentation()
        fixture.presentation.receive(
            runID: fixture.runID,
            event: .backgroundTask(spawn(id: "watch", name: "Watch build")))
        fixture.presentation.complete(
            runID: fixture.runID,
            result: AgentRunResult(stopReason: .endTurn))
        #expect(fixture.presentation.snapshot?.canCloseOrDelete == false)

        fixture.presentation.applyBackgroundTaskUpdate(.stateChanged(
            id: AgentBackgroundTaskID(rawValue: "watch"),
            state: .completed,
            summary: nil,
            outputFilePath: nil,
            toolCallID: nil))

        #expect(fixture.presentation.snapshot?.canCloseOrDelete == true)
    }

    @MainActor @Test
    func fifthSession_WhenFourHaveActiveTasks_IsRefusedWithoutEviction() throws {
        let registry = AgentSessionPresentationRegistry()
        var retainedRunIDs: [UUID] = []
        for index in 0..<AgentSessionPresentationRegistry.maximumSessions {
            let fixture = try makePresentation()
            retainedRunIDs.append(fixture.runID)
            fixture.presentation.receive(
                runID: fixture.runID,
                event: .backgroundTask(spawn(id: "task", name: "Watch \(index)")))
            #expect(registry.register(
                presentation: fixture.presentation,
                profile: fixture.profile,
                sessionID: "session-\(index)",
                appRunGeneration: UInt64(index + 1)))
        }
        let fifth = try makePresentation()

        #expect(!registry.register(
            presentation: fifth.presentation,
            profile: fifth.profile,
            sessionID: "session-4",
            appRunGeneration: 5))
        #expect(registry.entries.map(\.runID) == retainedRunIDs)
    }

    @MainActor @Test
    func stopRequest_RetainsRequestedUntilProviderTerminalState() throws {
        let fixture = try makePresentation()
        let taskID = AgentBackgroundTaskID(rawValue: "watch")
        fixture.presentation.receive(
            runID: fixture.runID,
            event: .backgroundTask(spawn(id: taskID.rawValue, name: "Watch build")))

        #expect(fixture.presentation.beginBackgroundTaskStop(taskID: taskID))
        fixture.presentation.finishBackgroundTaskStop(taskID: taskID, accepted: true)
        #expect(fixture.presentation.snapshot?.backgroundTasks.first?.statusLabel == "Stop requested")

        fixture.presentation.applyBackgroundTaskUpdate(.stateChanged(
            id: taskID,
            state: .stopped,
            summary: "Stopped",
            outputFilePath: nil,
            toolCallID: nil))
        #expect(fixture.presentation.snapshot?.backgroundTasks.first?.statusLabel == "Stopped")
    }

    @MainActor
    private func makePresentation(
        diagnostics: any YapOpsDiagnosticRecording = YapOpsDiagnostics.shared
    ) throws -> (presentation: AgentRunPresentation, runID: UUID, profile: WakeProfile) {
        let presentation = AgentRunPresentation(startsElapsedTimer: false, diagnostics: diagnostics)
        let runID = UUID()
        let profile = try WakeProfile(
            wakePhrase: "assistant",
            urlTemplate: "https://example.com/?q={urlText}",
            accent: .purple)
        presentation.start(runID: runID, profile: profile, prompt: "Watch the build")
        return (presentation, runID, profile)
    }

    private func spawn(id: String, name: String) -> AgentBackgroundTaskUpdate {
        .spawned(
            id: AgentBackgroundTaskID(rawValue: id),
            name: name,
            taskType: "watcher",
            description: "Provider detail",
            showInTranscript: true,
            canStop: true,
            outputFilePath: nil,
            toolCallID: nil)
    }
}
