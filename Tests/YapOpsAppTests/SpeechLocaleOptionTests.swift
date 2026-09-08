// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Testing
@testable import YapOpsApp

struct SpeechLocaleOptionTests {
    @Test(arguments: [
        ("en-US", "English (United States)"),
        ("en_GB", "English (United Kingdom)"),
        ("pt-PT", "Portuguese (Portugal)"),
    ])
    func title_WhenLocaleIsKnown_ShowsEnglishLanguageAndRegion(
        identifier: String, expected: String
    ) {
        #expect(SpeechLocaleOption(id: identifier).title == expected)
    }

    @Test func options_WhenSavedIdentifierUsesUnderscores_PreservesItWithoutDuplicateChoice() {
        let options = SpeechLocaleOption.options(
            supportedIdentifiers: ["en-US", "en_US", "pt-PT"],
            selectedIdentifier: "en_US")

        #expect(options.map(\.id) == ["en_US", "pt-PT"])
    }

    @Test func options_WhenCurrentLocaleIsMissing_KeepsTheSelection() {
        let options = SpeechLocaleOption.options(
            supportedIdentifiers: ["en-US"], selectedIdentifier: "en_PT")

        #expect(options.contains(SpeechLocaleOption(id: "en_PT")))
        #expect(options.first?.title == "English (Portugal)")
    }

    @Test func options_WhenCatalogHasLanguages_SortsByEnglishName() {
        let options = SpeechLocaleOption.options(
            supportedIdentifiers: ["de-DE", "fr-FR", "en-US"],
            selectedIdentifier: "en-US")

        #expect(options.map(\.id) == ["en-US", "fr-FR", "de-DE"])
    }

    @Test func options_WhenCatalogIsEmpty_KeepsTheCurrentIdentifier() {
        #expect(SpeechLocaleOption.options(
            supportedIdentifiers: [], selectedIdentifier: "pt_PT") == [
                SpeechLocaleOption(id: "pt_PT"),
            ])
    }

    @Test func title_WhenIdentifierIsUnknown_FallsBackWithoutInventingALanguage() {
        #expect(SpeechLocaleOption(id: "zz-ZZ").title == "zz-ZZ")
    }
}
