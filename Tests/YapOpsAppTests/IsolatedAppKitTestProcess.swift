// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import MachO
import Testing

enum IsolatedAppKitTestProcess {
    private static let childProcessQueue = DispatchQueue(label: "dev.alex.yapops.tests.appkit-child")

    static func run(environmentKey: String, testFilter: String) async throws {
        let testExecutable = try #require(CommandLine.arguments.first { argument in
            argument.contains(".xctest/Contents/MacOS/")
        })
        let helperExecutable = URL(fileURLWithPath: CommandLine.arguments[0])
        var environment = ProcessInfo.processInfo.environment
        environment[environmentKey] = "1"
        let sanitizerPaths = loadedSanitizerRuntimePaths()
        if !sanitizerPaths.isEmpty {
            var insertionPaths = environment["DYLD_INSERT_LIBRARIES"]
                .map { $0.split(separator: ":").map(String.init) } ?? []
            for path in sanitizerPaths where !insertionPaths.contains(path) {
                insertionPaths.append(path)
            }
            environment["DYLD_INSERT_LIBRARIES"] = insertionPaths.joined(separator: ":")
        }
        let arguments = [
            "--test-bundle-path", testExecutable,
            "--filter", testFilter,
            testExecutable,
            "--testing-library", "swift-testing",
        ]
        let childEnvironment = environment
        let outcome: (succeeded: Bool, details: String) = try await withCheckedThrowingContinuation {
            continuation in
            childProcessQueue.async {
                let process = Process()
                let output = Pipe()
                process.executableURL = helperExecutable
                process.arguments = arguments
                process.environment = childEnvironment
                process.standardOutput = output
                process.standardError = output
                do {
                    try process.run()
                    // Drain while the child runs so a full pipe cannot prevent its exit.
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: (
                        process.terminationReason == .exit && process.terminationStatus == 0,
                        String(decoding: data, as: UTF8.self)))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        #expect(
            outcome.succeeded,
            Comment(rawValue: outcome.details))
    }

    private static func loadedSanitizerRuntimePaths() -> [String] {
        (0..<_dyld_image_count()).compactMap { index in
            guard let imageName = _dyld_get_image_name(index) else { return nil }
            let path = String(cString: imageName)
            guard path.contains("/libclang_rt."), path.hasSuffix("_dynamic.dylib") else {
                return nil
            }
            return path
        }
    }
}
