import AppKit
import Foundation
@testable import Ghostty
import Testing

struct ExtensionCatalogGroupTests {
    static func entry(
        _ id: String,
        contributes: [String],
        languages: [String] = [],
        categories: [String] = []
    ) -> ExtensionIndex.Entry {
        ExtensionIndex.Entry(
            id: id,
            name: id,
            version: "1.0.0",
            publisher: "phantom",
            summary: "",
            homepage: nil,
            minimumPhantomVersion: nil,
            contributes: contributes,
            languages: languages,
            downloadURL: URL(string: "https://example.com/a.zip")!,
            sha256: String(repeating: "a", count: 64),
            bytes: 1,
            card: nil,
            categories: categories)
    }

    @Test func filesALanguageUnderTheFamilyTheIndexNames() {
        let go = Self.entry("phantom.go", contributes: ["languages"], categories: ["compiled"])
        #expect(ExtensionCatalogGrouping.group(for: go) == .language(.compiled))
    }

    @Test func aLanguageIsFiledOnceEvenWhenItBringsMore() {
        let lua = Self.entry(
            "ipetinate.lua",
            contributes: ["languages", "formatters", "iconThemes"],
            categories: ["script"])
        #expect(ExtensionCatalogGrouping.group(for: lua) == .language(.script))
    }

    /// An index built before `categories` existed declares none, and none is
    /// the whole answer: the compiled-in table that could once have said
    /// "rust is compiled" left with the server registry, so the entry files
    /// under Languages instead of being guessed at.
    @Test func anOlderIndexIsNotGuessedAtFromTheLanguageItNames() {
        let rust = Self.entry("phantom.rust", contributes: ["languages"], languages: ["rust"])
        #expect(ExtensionCatalogGrouping.group(for: rust) == .languages)
    }

    @Test func aLanguageNobodyKnowsStillLandsUnderLanguages() {
        let mystery = Self.entry("phantom.mystery", contributes: ["languages"], languages: ["mystery"])
        #expect(ExtensionCatalogGrouping.group(for: mystery) == .languages)
    }

    @Test func aGrammarPackHasAHeadingRatherThanFallingUnderOther() {
        let grammar = Self.entry("phantom.tsx-grammar", contributes: ["grammars"])
        #expect(ExtensionCatalogGrouping.group(for: grammar) == .grammars)
    }

    @Test(arguments: [
        (["themes"], ExtensionCatalogGroup.themes),
        (["iconThemes"], ExtensionCatalogGroup.iconThemes),
        (["formatters"], ExtensionCatalogGroup.formatters),
        (["agents"], ExtensionCatalogGroup.agents),
        ([], ExtensionCatalogGroup.other),
    ])
    func anExtensionWithoutALanguageIsFiledByWhatItAdds(
        _ contributes: [String],
        _ expected: ExtensionCatalogGroup
    ) {
        #expect(ExtensionCatalogGrouping.group(for: Self.entry("phantom.x", contributes: contributes)) == expected)
    }

    @Test func headingsFollowOneOrderAndSkipTheEmptyOnes() {
        let groups = ExtensionCatalogGrouping.groups([
            Self.entry("phantom.dracula", contributes: ["themes"]),
            Self.entry("phantom.go", contributes: ["languages"], categories: ["compiled"]),
            Self.entry("phantom.lua", contributes: ["languages"], categories: ["script"]),
            Self.entry("phantom.zig", contributes: ["languages"], categories: ["compiled"]),
        ])

        #expect(groups.map(\.title) == ["Compiled", "Script", "Themes"])
        #expect(groups[0].entries.map(\.id) == ["phantom.go", "phantom.zig"])
    }

    @Test func everyHeadingHasItsOwnIdentity() {
        let ids = ExtensionCatalogGrouping.order.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ExtensionCatalogGroup.iconThemes.title == "Icon Packs")
    }
}

/// The chip beside a row, for every kind a manifest may contribute.
///
/// Two failures live here and neither one reports itself. A kind with no
/// case of its own shows its manifest spelling — `iconThemes`, `grammars` —
/// where a label belongs, and a symbol name that does not resolve draws an
/// 18-point hole that can take the whole row with it.
///
/// The list is written out rather than read from the parser, deliberately:
/// `LanguageManifest.knownContributesKeys` is the other copy, and a kind
/// added there without a chip is exactly what this is here to catch.
@MainActor
struct ExtensionContributionChipTests {
    static let kinds = [
        "languages", "servers", "formatters", "themes", "iconThemes", "grammars", "agents",
    ]

    @Test func everyKindHasALabelOfItsOwn() {
        for kind in Self.kinds {
            #expect(
                ExtensionContributionChip.of(kind).title != kind,
                "\(kind) falls through to the raw manifest spelling")
        }
    }

    @Test func everyKindDrawsItsSymbol() {
        for kind in Self.kinds + ["somethingLater"] {
            let symbol = ExtensionContributionChip.of(kind).systemImage
            #expect(
                NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil,
                "\(kind) names \(symbol), which is not an SF Symbol")
        }
    }

    @Test func everyHeadingDrawsItsSymbol() {
        for group in ExtensionCatalogGrouping.order {
            #expect(
                NSImage(systemSymbolName: group.systemImage, accessibilityDescription: nil) != nil,
                "\(group.id) names \(group.systemImage), which is not an SF Symbol")
        }
    }

    @Test func everyTabDrawsItsSymbol() {
        for kind in ExtensionCatalogFilter.Kind.allCases {
            #expect(
                NSImage(systemSymbolName: kind.systemImage, accessibilityDescription: nil) != nil,
                "\(kind.rawValue) names \(kind.systemImage), which is not an SF Symbol")
        }
    }
}
