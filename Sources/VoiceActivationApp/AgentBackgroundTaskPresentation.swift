// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import VoiceActivationCore

/// App-owned state for one provider background task.
struct AgentBackgroundTaskPresentation: Equatable, Identifiable, Sendable {
    enum StopState: Equatable, Sendable {
        case available
        case requested
        case failed
        case unavailable
    }

    let id: AgentBackgroundTaskID
    var name: String
    var taskType: String
    var description: String
    var summary: String?
    var lastToolName: String?
    var state: AgentBackgroundTaskState
    var canStop: Bool
    var usage: AgentBackgroundTaskUsage?
    var outputFilePath: String?
    var toolCallID: String?
    var stopState: StopState

    var isActive: Bool {
        state == .running || state == .paused
    }

    var statusLabel: String {
        if stopState == .requested { return "Stop requested" }
        if stopState == .failed { return "Couldn’t stop task" }
        return switch state {
        case .running: "Working in background"
        case .paused: "Paused"
        case .completed: "Completed"
        case .failed: "Failed"
        case .stopped: "Stopped"
        }
    }

    var accessibilityLabel: String {
        "\(name), \(statusLabel)"
    }

    var offersStopAction: Bool {
        isActive && stopState != .requested && canStop
    }

    init(
        id: AgentBackgroundTaskID,
        name: String = "Background task",
        taskType: String = "",
        description: String = "",
        summary: String? = nil,
        lastToolName: String? = nil,
        state: AgentBackgroundTaskState = .running,
        canStop: Bool = false,
        usage: AgentBackgroundTaskUsage? = nil,
        outputFilePath: String? = nil,
        toolCallID: String? = nil,
        stopState: StopState? = nil
    ) {
        self.id = id
        self.name = name
        self.taskType = taskType
        self.description = description
        self.summary = summary
        self.lastToolName = lastToolName
        self.state = state
        self.canStop = canStop
        self.usage = usage
        self.outputFilePath = outputFilePath
        self.toolCallID = toolCallID
        self.stopState = stopState ?? (canStop ? .available : .unavailable)
    }

    mutating func apply(_ update: AgentBackgroundTaskUpdate) {
        switch update {
        case .spawned(
            _, let name, let taskType, let description, _, let canStop,
            let outputFilePath, let toolCallID):
            self.name = name
            self.taskType = taskType
            self.description = description
            state = .running
            self.canStop = canStop
            self.outputFilePath = outputFilePath
            self.toolCallID = toolCallID
            if stopState != .requested {
                stopState = canStop ? .available : .unavailable
            }
        case .progress(
            _, let description, let summary, let lastToolName, let usage,
            let outputFilePath, let toolCallID):
            if let description { self.description = description }
            if let summary { self.summary = summary }
            if let lastToolName { self.lastToolName = lastToolName }
            if let usage { self.usage = usage }
            if let outputFilePath { self.outputFilePath = outputFilePath }
            if let toolCallID { self.toolCallID = toolCallID }
        case .stateChanged(
            _, let state, let summary, let outputFilePath, let toolCallID):
            self.state = state
            if let summary { self.summary = summary }
            if let outputFilePath { self.outputFilePath = outputFilePath }
            if let toolCallID { self.toolCallID = toolCallID }
            if !isActive {
                stopState = .unavailable
            }
        }
    }
}

extension AgentBackgroundTaskUpdate {
    var presentationTaskID: AgentBackgroundTaskID {
        switch self {
        case .spawned(let id, _, _, _, _, _, _, _),
            .progress(let id, _, _, _, _, _, _),
            .stateChanged(let id, _, _, _, _):
            id
        }
    }
}
