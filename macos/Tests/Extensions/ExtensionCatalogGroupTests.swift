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

    @Test func anOlderIndexIsClassifiedFromTheLanguageItNames() {
        let rust = Self.entry("phantom.rust", contributes: ["languages"], languages: ["rust"])
        #expect(ExtensionCatalogGrouping.group(for: rust) == .language(.compiled))
    }

    @Test func aLanguageNobodyKnowsStillLandsUnderLanguages() {
        let mystery = Self.entry("phantom.mystery", contributes: ["languages"], languages: ["mystery"])
        #expect(ExtensionCatalogGrouping.group(for: mystery) == .languages)
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
