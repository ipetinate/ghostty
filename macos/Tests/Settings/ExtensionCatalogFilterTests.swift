import Foundation
@testable import Ghostty
import Testing

struct ExtensionCatalogFilterTests {
    private func entry(
        id: String,
        name: String,
        version: String = "1.0.0",
        publisher: String = "acme",
        summary: String = "",
        contributes: [String] = ["languages"],
        languages: [String] = []
    ) -> ExtensionIndex.Entry {
        ExtensionIndex.Entry(
            id: id,
            name: name,
            version: version,
            publisher: publisher,
            summary: summary,
            homepage: nil,
            minimumPhantomVersion: nil,
            contributes: contributes,
            languages: languages,
            downloadURL: URL(fileURLWithPath: "/tmp/phantom-extensions/\(id).zip"),
            sha256: "",
            bytes: 0
        )
    }

    private func card(
        author: String = "acme",
        tags: [String] = [],
        created: Date = Date(timeIntervalSince1970: 0),
        updated: Date? = nil
    ) -> ExtensionCard {
        ExtensionCard(
            title: "", tagline: "", license: "MIT",
            author: ExtensionCard.Author(name: author, url: nil),
            created: created, updated: updated, icon: nil, cover: nil,
            tags: tags, screenshots: [], document: "extension.mdx", documentBytes: 1,
            media: [], mediaBytes: 0)
    }

    private func installed(id: String, name: String, version: String = "1.0.0") -> InstalledExtension {
        InstalledExtension(
            id: id,
            name: name,
            version: version,
            root: URL(fileURLWithPath: "/tmp/phantom-extensions/\(id)")
        )
    }

    private func sections(
        _ entries: [ExtensionIndex.Entry],
        installed: [InstalledExtension] = [],
        query: String = "",
        kind: ExtensionCatalogFilter.Kind = .all,
        sort: ExtensionCatalogFilter.Sort = .name
    ) -> ExtensionCatalogFilter.Sections {
        ExtensionCatalogFilter.sections(
            entries: entries, installed: installed, query: query, kind: kind, sort: sort)
    }

    private var lua: ExtensionIndex.Entry {
        entry(id: "acme.lua", name: "Lua", summary: "Lua scripts", languages: ["lua"])
    }

    private var zig: ExtensionIndex.Entry {
        entry(id: "acme.zig", name: "Zig", publisher: "ziglings", summary: "The Zig language",
              languages: ["zig"])
    }

    private var elixir: ExtensionIndex.Entry {
        entry(id: "beam.elixir", name: "Elixir", publisher: "beam",
              summary: "Elixir, mix and HEEx templates", languages: ["elixir", "heex"])
    }

    // MARK: Free text

    @Test func anEmptyQueryKeepsEveryEntry() {
        let found = sections([lua, zig, elixir])
        #expect(found.entries.map(\.id) == ["beam.elixir", "acme.lua", "acme.zig"])
        #expect(found.orphans.isEmpty)
    }

    @Test func anEmptyQueryOnAllCountsEverything() {
        let found = sections([lua, zig, elixir], installed: [installed(id: "acme.ada", name: "Ada")])
        #expect(found.entries.count == 3)
        #expect(found.orphans.count == 1)
        #expect(found.count(.all) == 4)
    }

    @Test func whitespaceIsNotAQuery() {
        #expect(sections([lua, zig], query: "   ").entries.map(\.id) == ["acme.lua", "acme.zig"])
    }

    @Test func entriesSortByNameWhateverTheIndexOrder() {
        let names = ["zig", "Elixir", "lua", "Ada"].map { entry(id: "acme.\($0.lowercased())", name: $0) }
        #expect(sections(names).entries.map(\.name) == ["Ada", "Elixir", "lua", "zig"])
    }

    @Test func entriesWithTheSameNameKeepTheirIndexOrder() {
        let twins = [
            entry(id: "second.lua", name: "Lua"),
            entry(id: "first.lua", name: "Lua"),
            entry(id: "acme.ada", name: "Ada"),
        ]
        #expect(sections(twins).entries.map(\.id) == ["acme.ada", "second.lua", "first.lua"])
    }

    @Test func aQueryMatchesTheId() {
        #expect(sections([lua, zig, elixir], query: "beam.").entries.map(\.id) == ["beam.elixir"])
    }

    @Test func aQueryMatchesTheName() {
        #expect(sections([lua, zig, elixir], query: "ZIG").entries.map(\.id) == ["acme.zig"])
    }

    @Test func aQueryMatchesThePublisher() {
        #expect(sections([lua, zig, elixir], query: "ziglings").entries.map(\.id) == ["acme.zig"])
    }

    @Test func aQueryMatchesTheSummary() {
        #expect(sections([lua, zig, elixir], query: "templates").entries.map(\.id) == ["beam.elixir"])
    }

    @Test func aQueryMatchesALanguageId() {
        #expect(sections([lua, zig, elixir], query: "heex").entries.map(\.id) == ["beam.elixir"])
    }

    @Test func aQueryMatchesACardTag() {
        var tagged = zig
        tagged.card = card(author: "ziglings", tags: ["systems", "comptime"])
        #expect(sections([lua, tagged, elixir], query: "comptime").entries.map(\.id) == ["acme.zig"])
        #expect(sections([lua, zig, elixir], query: "comptime").isEmpty)
    }

    @Test func aQueryIgnoresCaseAndDiacritics() {
        let accented = entry(id: "acme.doc", name: "Documentação", publisher: "Isác Petinate")
        #expect(sections([accented], query: "documentacao").entries.map(\.id) == ["acme.doc"])
        #expect(sections([accented], query: "ISAC").entries.map(\.id) == ["acme.doc"])
    }

    @Test func nothingMatchingIsEmptyRatherThanEverything() {
        #expect(sections([lua, zig], query: "rust").isEmpty)
    }

    // MARK: Scopes

    @Test func theLanguageScopeMatchesALanguageId() {
        #expect(sections([lua, zig, elixir], query: "lang:heex").entries.map(\.id) == ["beam.elixir"])
        #expect(sections([lua, zig, elixir], query: "lang:LUA").entries.map(\.id) == ["acme.lua"])
        #expect(sections([lua, zig, elixir], query: "lang:hee").isEmpty)
    }

    @Test func theTagScopeMatchesACardTag() {
        var tagged = zig
        tagged.card = card(tags: ["formatter", "lsp"])
        #expect(sections([tagged, lua], query: "tag:formatter").entries.map(\.id) == ["acme.zig"])
        #expect(sections([tagged, lua], query: "tag:themes").isEmpty)
    }

    @Test func thePublisherScopeMatchesThePublisherAndTheCardAuthor() {
        var byCard = lua
        byCard.card = card(author: "Isac Petinate")
        #expect(sections([byCard, zig], query: "by:ziglings").entries.map(\.id) == ["acme.zig"])
        #expect(sections([byCard, zig], query: "by:petinate").entries.map(\.id) == ["acme.lua"])
    }

    @Test func aQuotedValueHoldsItsSpacesTogether() {
        var byCard = lua
        byCard.card = card(author: "Isac Petinate")
        #expect(sections([byCard, zig], query: "by:\"Isac Petinate\"").entries.map(\.id) == ["acme.lua"])
        #expect(sections([byCard, zig], query: "by:\"Isac Zig\"").isEmpty)
    }

    @Test func theIdentifierScopeMatchesPartOfTheId() {
        #expect(sections([lua, zig, elixir], query: "id:acme.lua").entries.map(\.id) == ["acme.lua"])
        #expect(sections([lua, zig, elixir], query: "id:beam.").entries.map(\.id) == ["beam.elixir"])
    }

    @Test func theContributionScopeMatchesAContributedKind() {
        let theme = entry(id: "acme.dark", name: "Dark", contributes: ["themes", "iconThemes"])
        #expect(sections([lua, theme], query: "contributes:themes").entries.map(\.id) == ["acme.dark"])
        #expect(sections([lua, theme], query: "contributes:languages").entries.map(\.id) == ["acme.lua"])
        #expect(sections([lua, theme], query: "contributes:agents").isEmpty)
    }

    @Test func theInstalledScopeReadsTheStoreState() {
        let onDisk = [installed(id: "acme.lua", name: "Lua")]
        #expect(sections([lua, zig], installed: onDisk, query: "installed:yes").entries.map(\.id) == ["acme.lua"])
        #expect(sections([lua, zig], installed: onDisk, query: "installed:no").entries.map(\.id) == ["acme.zig"])
    }

    @Test func theUpdatableScopeReadsTheStoreState() {
        let onDisk = [
            installed(id: "acme.lua", name: "Lua", version: "0.9.0"),
            installed(id: "acme.zig", name: "Zig"),
        ]
        #expect(sections([lua, zig], installed: onDisk, query: "updatable:yes").entries.map(\.id) == ["acme.lua"])
        #expect(sections([lua, zig], installed: onDisk, query: "updatable:no").entries.map(\.id) == ["acme.zig"])
    }

    @Test func anUnknownPrefixStaysFreeText() {
        let linked = entry(id: "acme.web", name: "Web", summary: "See http://example.com for more")
        #expect(sections([linked, lua], query: "http://example.com").entries.map(\.id) == ["acme.web"])
        #expect(sections([linked, lua], query: "colour:red").isEmpty)
    }

    @Test func aScopeWithNoValueStaysFreeText() {
        let named = entry(id: "acme.lang", name: "lang:", summary: "")
        #expect(sections([named, lua], query: "lang:").entries.map(\.id) == ["acme.lang"])
    }

    @Test func aLeadingDashNegatesATerm() {
        var tagged = zig
        tagged.card = card(tags: ["lsp"])
        #expect(sections([lua, tagged], query: "-tag:lsp").entries.map(\.id) == ["acme.lua"])
        #expect(sections([lua, zig, elixir], query: "-lang:lua").entries.map(\.id) == ["beam.elixir", "acme.zig"])
    }

    @Test func termsAreAndedTogether() {
        let onDisk = [installed(id: "beam.elixir", name: "Elixir")]
        #expect(sections([lua, zig, elixir], installed: onDisk, query: "lang:heex installed:yes")
            .entries.map(\.id) == ["beam.elixir"])
        #expect(sections([lua, zig, elixir], installed: onDisk, query: "lang:heex installed:no").isEmpty)
        #expect(sections([lua, zig, elixir], query: "elixir templates").entries.map(\.id) == ["beam.elixir"])
        #expect(sections([lua, zig, elixir], query: "elixir lua").isEmpty)
    }

    // MARK: Kinds

    private var kinds: [ExtensionIndex.Entry] {
        [
            entry(id: "acme.lua", name: "Lua", contributes: ["languages", "formatters"]),
            entry(id: "acme.dark", name: "Dark", contributes: ["themes"]),
            entry(id: "acme.icons", name: "Icons", contributes: ["iconThemes"]),
            entry(id: "acme.bot", name: "Bot", contributes: ["agents"]),
        ]
    }

    @Test func aKindKeepsOnlyTheExtensionsThatContributeIt() {
        #expect(sections(kinds, kind: .themes).entries.map(\.id) == ["acme.dark"])
        #expect(sections(kinds, kind: .formatters).entries.map(\.id) == ["acme.lua"])
        #expect(sections(kinds, kind: .iconThemes).entries.map(\.id) == ["acme.icons"])
        #expect(sections(kinds, kind: .agents).entries.map(\.id) == ["acme.bot"])
        #expect(sections(kinds, kind: .all).entries.count == 4)
    }

    @Test func everyKindCarriesItsOwnCount() {
        let found = sections(kinds)
        #expect(found.count(.all) == 4)
        #expect(found.count(.languages) == 1)
        #expect(found.count(.formatters) == 1)
        #expect(found.count(.themes) == 1)
        #expect(found.count(.iconThemes) == 1)
        #expect(found.count(.agents) == 1)
    }

    @Test func theCountsAnswerTheQueryAndNotTheSelectedKind() {
        let found = sections(kinds, query: "acme.d", kind: .agents)
        #expect(found.count(.all) == 1)
        #expect(found.count(.themes) == 1)
        #expect(found.count(.agents) == 0)
        #expect(found.entries.isEmpty)
    }

    @Test func onlyAllCountsAndShowsTheOrphans() {
        let onDisk = [installed(id: "acme.rust", name: "Rust")]
        let all = sections(kinds, installed: onDisk, kind: .all)
        #expect(all.count(.all) == 5)
        #expect(all.orphans.map(\.id) == ["acme.rust"])

        let themes = sections(kinds, installed: onDisk, kind: .themes)
        #expect(themes.count(.themes) == 1)
        #expect(themes.orphans.isEmpty)
    }

    // MARK: Sorting

    private var dated: [ExtensionIndex.Entry] {
        var old = entry(id: "acme.old", name: "Old", publisher: "zeta")
        old.card = card(created: Date(timeIntervalSince1970: 100))
        var recent = entry(id: "acme.recent", name: "Recent", publisher: "alpha")
        recent.card = card(created: Date(timeIntervalSince1970: 100), updated: Date(timeIntervalSince1970: 900))
        var middle = entry(id: "acme.middle", name: "Middle", publisher: "alpha")
        middle.card = card(created: Date(timeIntervalSince1970: 500))
        let undated = entry(id: "acme.undated", name: "Undated", publisher: "beta")
        return [old, recent, middle, undated]
    }

    @Test func nameSortsAscending() {
        #expect(sections(dated, sort: .name).entries.map(\.id)
            == ["acme.middle", "acme.old", "acme.recent", "acme.undated"])
    }

    @Test func publisherSortsAscendingAndKeepsIndexOrderWithin() {
        #expect(sections(dated, sort: .publisher).entries.map(\.id)
            == ["acme.recent", "acme.middle", "acme.undated", "acme.old"])
    }

    @Test func updatedSortsNewestFirstAndPutsUndatedLast() {
        #expect(sections(dated, sort: .updated).entries.map(\.id)
            == ["acme.recent", "acme.middle", "acme.old", "acme.undated"])
    }

    @Test func equalDatesKeepTheirIndexOrder() {
        var first = entry(id: "acme.first", name: "Zulu")
        first.card = card(created: Date(timeIntervalSince1970: 300))
        var second = entry(id: "acme.second", name: "Alpha")
        second.card = card(created: Date(timeIntervalSince1970: 300))
        #expect(sections([first, second], sort: .updated).entries.map(\.id) == ["acme.first", "acme.second"])
    }

    @Test func theSortLeavesTheOrphansByName() {
        let onDisk = [
            installed(id: "acme.rust", name: "Rust"),
            installed(id: "acme.ada", name: "Ada"),
        ]
        #expect(sections(dated, installed: onDisk, sort: .updated).orphans.map(\.id)
            == ["acme.ada", "acme.rust"])
    }

    // MARK: Orphans

    @Test func installedExtensionsMissingFromTheIndexAreOrphans() {
        let onDisk = [
            installed(id: "acme.lua", name: "Lua"),
            installed(id: "acme.rust", name: "Rust"),
            installed(id: "acme.ada", name: "Ada"),
        ]
        let found = sections([lua, zig], installed: onDisk)
        #expect(found.entries.map(\.id) == ["acme.lua", "acme.zig"])
        #expect(found.orphans.map(\.id) == ["acme.ada", "acme.rust"])
    }

    @Test func orphansAnswerTheQueryOnNameAndId() {
        let onDisk = [
            installed(id: "acme.rust", name: "Rust"),
            installed(id: "acme.ada", name: "Ada"),
        ]
        let byName = sections([lua], installed: onDisk, query: "rust")
        #expect(byName.entries.isEmpty)
        #expect(byName.orphans.map(\.id) == ["acme.rust"])

        let byId = sections([lua], installed: onDisk, query: "acme.ada")
        #expect(byId.orphans.map(\.id) == ["acme.ada"])
    }

    @Test func orphansAnswerTheInstalledScope() {
        let onDisk = [installed(id: "acme.rust", name: "Rust")]
        #expect(sections([lua], installed: onDisk, query: "installed:yes").orphans.map(\.id) == ["acme.rust"])
        #expect(sections([lua], installed: onDisk, query: "installed:no").orphans.isEmpty)
        #expect(sections([lua], installed: onDisk, query: "updatable:yes").orphans.isEmpty)
        #expect(sections([lua], installed: onDisk, query: "lang:rust").orphans.isEmpty)
    }

    @Test func anEmptyIndexMakesEveryInstalledExtensionAnOrphan() {
        let onDisk = [installed(id: "acme.lua", name: "Lua")]
        let found = sections([], installed: onDisk)
        #expect(found.entries.isEmpty)
        #expect(found.orphans.map(\.id) == ["acme.lua"])
    }

    // MARK: Chips

    @Test func contributionChipsNameTheFourKnownKinds() {
        #expect(ExtensionContributionChip.of("languages").title == "Languages")
        #expect(ExtensionContributionChip.of("languages").systemImage == "chevron.left.forwardslash.chevron.right")
        #expect(ExtensionContributionChip.of("formatters").systemImage == "text.alignleft")
        #expect(ExtensionContributionChip.of("themes").systemImage == "paintpalette")
        #expect(ExtensionContributionChip.of("iconThemes") == ExtensionContributionChip(
            title: "Icon Themes", systemImage: "photo.on.rectangle"))
    }

    @Test func anUnknownContributionKeepsItsOwnName() {
        #expect(ExtensionContributionChip.of("snippets") == ExtensionContributionChip(
            title: "snippets", systemImage: "puzzlepiece"))
    }

    @Test func everyKindTabCarriesATitleAndASymbol() {
        #expect(ExtensionCatalogFilter.Kind.allCases.map(\.title)
            == ["All", "Languages", "Formatters", "Themes", "Icons", "Agents"])
        #expect(ExtensionCatalogFilter.Kind.languages.systemImage
            == ExtensionContributionChip.of("languages").systemImage)
        #expect(ExtensionCatalogFilter.Kind.all.contribution == nil)
        #expect(ExtensionCatalogFilter.Kind.iconThemes.contribution == "iconThemes")
        #expect(ExtensionCatalogFilter.Kind.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }
}
