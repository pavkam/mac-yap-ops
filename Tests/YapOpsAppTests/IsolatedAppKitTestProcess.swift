// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation
import MachO
import Testing

enum IsolatedAppKitTestProcess {
    static func run(environmentKey: String, testFilter: String) throws {
        let testExecutable = try #require(CommandLine.arguments.first { argument in
            argument.contains(".xctest/Contents/MacOS/")
        })
        let helperExecutable = URL(fileURLWithPath: CommandLine.arguments[0])
        let process = Process()
        let output = Pipe()
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
        process.executableURL = helperExecutable
        process.arguments = [
            "--test-bundle-path", testExecutable,
            "--filter", testFilter,
            testExecutable,
            "--testing-library", "swift-testing",
        ]
        process.environment = environment
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let details = String(decoding: data, as: UTF8.self)

        #expect(
            process.terminationReason == .exit && process.terminationStatus == 0,
            Comment(rawValue: details))
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
