// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import VoiceActivationCore

@MainActor
final class ApplicationStartup {
    private let model: AppModel
    private let activationMonitor: ApplicationActivationMonitor
    private let beforeMonitorArm: @MainActor @Sendable () async -> Void
    private var task: Task<Void, Never>?
    private var taskGeneration: UInt64?
    private var generation: UInt64 = 0

    init(
        model: AppModel,
        activationMonitor: ApplicationActivationMonitor,
        beforeMonitorArm: @escaping @MainActor @Sendable () async -> Void = {}
    ) {
        self.model = model
        self.activationMonitor = activationMonitor
        self.beforeMonitorArm = beforeMonitorArm
    }

    @discardableResult
    func run() async -> Bool {
        generation &+= 1
        return await run(generation: generation)
    }

    private func run(generation expectedGeneration: UInt64) async -> Bool {
        guard generation == expectedGeneration, !Task.isCancelled else { return false }
        guard await model.start() else { return false }
        guard generation == expectedGeneration, !Task.isCancelled else { return false }
        await beforeMonitorArm()
        guard generation == expectedGeneration, !Task.isCancelled else { return false }
        activationMonitor.start(model: model)
        return true
    }

    func start() {
        guard task == nil else { return }
        generation &+= 1
        let expectedGeneration = generation
        taskGeneration = expectedGeneration
        task = Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.run(generation: expectedGeneration)
            guard self.taskGeneration == expectedGeneration else { return }
            self.task = nil
            self.taskGeneration = nil
        }
    }

    func cancel() {
        generation &+= 1
        model.cancelStartupAttempt()
        task?.cancel()
        task = nil
        taskGeneration = nil
        activationMonitor.stop()
    }
}

@MainActor
struct VoiceActivationAppComposition {
    let model: AppModel
    let startup: ApplicationStartup

    static func make(
        continuityStore: any AgentContinuityStoring,
        activationMonitor: ApplicationActivationMonitor,
        beforeMonitorArm: @escaping @MainActor @Sendable () async -> Void = {},
        makeAgentRunner: (any AgentContinuityStoring) -> any AgentHarnessRunning,
        makeModel: (any AgentHarnessRunning, any AgentContinuityStoring) -> AppModel
    ) -> VoiceActivationAppComposition {
        let runner = makeAgentRunner(continuityStore)
        let model = makeModel(runner, continuityStore)
        return VoiceActivationAppComposition(
            model: model,
            startup: ApplicationStartup(
                model: model,
                activationMonitor: activationMonitor,
                beforeMonitorArm: beforeMonitorArm))
    }
}
