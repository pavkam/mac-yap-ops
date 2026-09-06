// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

@preconcurrency import ApplicationServices
import Foundation

enum MacContextAccessStatus: Equatable, Sendable {
    case notAuthorized
    case authorized
}

@MainActor
protocol MacContextAccessControlling: Sendable {
    func currentStatus() -> MacContextAccessStatus
    func requestMacContextAccess()
}

@MainActor
protocol MacContextAccessNativeChecking: Sendable {
    func isProcessTrusted() -> Bool
    func requestProcessTrust()
}

@MainActor
struct SystemMacContextAccessNativeChecker: MacContextAccessNativeChecking {
    func isProcessTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func requestProcessTrust() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

@MainActor
final class MacContextAccessController: MacContextAccessControlling {
    private let native: any MacContextAccessNativeChecking

    init(native: any MacContextAccessNativeChecking = SystemMacContextAccessNativeChecker()) {
        self.native = native
    }

    func currentStatus() -> MacContextAccessStatus {
        native.isProcessTrusted() ? .authorized : .notAuthorized
    }

    func requestMacContextAccess() {
        native.requestProcessTrust()
    }
}

@MainActor
struct UnavailableMacContextAccessController: MacContextAccessControlling {
    func currentStatus() -> MacContextAccessStatus {
        .notAuthorized
    }

    func requestMacContextAccess() {}
}
