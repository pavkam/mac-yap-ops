// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Speech
import SwiftUI

struct SpeechLocalePicker: View {
    @Binding var localeID: String
    var loadIdentifiers: @Sendable () async -> [String] = SpeechLocaleCatalog.supportedIdentifiers
    @State private var supportedIdentifiers: [String] = []

    var body: some View {
        Picker("Speech language", selection: $localeID) {
            ForEach(SpeechLocaleOption.options(
                supportedIdentifiers: supportedIdentifiers,
                selectedIdentifier: localeID)) { option in
                Text(option.title).tag(option.id)
            }
        }
        .pickerStyle(.menu)
        .help("Choose the language and region you speak. Save Settings to apply.")
        .task {
            let identifiers = await loadIdentifiers()
            guard !Task.isCancelled else { return }
            supportedIdentifiers = identifiers
        }
    }
}

private enum SpeechLocaleCatalog {
    private static let queue = DispatchQueue(label: "YapOps.speech-locales", qos: .userInitiated)

    static func supportedIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: SFSpeechRecognizer.supportedLocales().map(\.identifier))
            }
        }
    }
}
