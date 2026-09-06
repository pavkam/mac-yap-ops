// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import VoiceActivationCore

@MainActor
final class ApplicationStartup {
    private let model: AppModel
    private let activationMonitor: ApplicationActivationMonitor
    private var task: Task<Void, Never>?

    init(model: AppModel, activationMonitor: ApplicationActivationMonitor) {
        self.model = model
        self.activationMonitor = activationMonitor
    }

    @discardableResult
    func run() async -> Bool {
        guard await model.start() else { return false }
        activationMonitor.start(model: model)
        return true
    }

    func start() {
        guard task == nil else { return }
        task = Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.run()
            self.task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
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
        makeAgentRunner: (any AgentContinuityStoring) -> any AgentHarnessRunning,
        makeModel: (any AgentHarnessRunning, any AgentContinuityStoring) -> AppModel
    ) -> VoiceActivationAppComposition {
        let runner = makeAgentRunner(continuityStore)
        let model = makeModel(runner, continuityStore)
        return VoiceActivationAppComposition(
            model: model,
            startup: ApplicationStartup(
                model: model,
                activationMonitor: activationMonitor))
    }
}
