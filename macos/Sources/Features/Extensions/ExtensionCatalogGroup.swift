import Foundation

/// One heading in the store's All listing.
///
/// The kind tabs answer "show me only themes". This answers the other
/// question a reader has in front of twenty-five rows sorted by name: which
/// of these are languages I compile, which are languages I run, and which are
/// not languages at all. Languages split by `LSPServerCategory`, which the
/// registry index declares per entry.
enum ExtensionCatalogGroup: Hashable, Identifiable, Sendable {
    case language(LSPServerCategory)
    case languages
    case servers
    case formatters
    case grammars
    case themes
    case iconThemes
    case agents
    case other

    var id: String {
        switch self {
        case .language(let category): return "language." + category.rawValue
        case .languages: return "languages"
        case .servers: return "servers"
        case .formatters: return "formatters"
        case .grammars: return "grammars"
        case .themes: return "themes"
        case .iconThemes: return "iconThemes"
        case .agents: return "agents"
        case .other: return "other"
        }
    }

    var title: String {
        switch self {
        case .language(let category): return category.title
        case .languages: return "Languages"
        case .servers: return "Servers"
        case .formatters: return "Formatters"
        case .grammars: return "Grammars"
        case .themes: return "Themes"
        case .iconThemes: return "Icon Packs"
        case .agents: return "Agents"
        case .other: return "Other"
        }
    }

    /// The same mark the entry's own chip carries, so a heading and the row
    /// under it are one thing rather than two drawings of it.
    var systemImage: String {
        switch self {
        case .language(let category): return category.systemImage
        case .languages: return ExtensionContributionChip.of("languages").systemImage
        case .servers: return ExtensionContributionChip.of("servers").systemImage
        case .formatters: return ExtensionContributionChip.of("formatters").systemImage
        case .grammars: return ExtensionContributionChip.of("grammars").systemImage
        case .themes: return ExtensionContributionChip.of("themes").systemImage
        case .iconThemes: return ExtensionContributionChip.of("iconThemes").systemImage
        case .agents: return ExtensionContributionChip.of("agents").systemImage
        case .other: return "shippingbox"
        }
    }
}

enum ExtensionCatalogGrouping {
    struct Group: Equatable, Identifiable {
        let group: ExtensionCatalogGroup
        let entries: [ExtensionIndex.Entry]

        var id: String { group.id }
        var title: String { group.title }
        var systemImage: String { group.systemImage }
    }

    /// The order the headings appear in. Languages first, by category title,
    /// then what an extension can add beside a language, and themes after
    /// all of it — see `deferred`.
    static let order: [ExtensionCatalogGroup] =
        LSPServerCategory.allCases.sorted { $0.title < $1.title }.map(ExtensionCatalogGroup.language)
            + [.languages, .servers, .formatters, .grammars, .iconThemes, .agents, .other, .themes]

    /// The groups that go after everything else, whatever the sort says.
    ///
    /// Themes are most of the registry by count — ninety of the hundred and
    /// sixteen published — so their heading stops reading as a section and
    /// becomes a wall between the reader and every group under it. Sorting
    /// cannot help: by name, by publisher or by date, the block is the same
    /// size wherever it lands. It goes to the bottom, and the Themes tab is
    /// where anyone shopping for one looks.
    static let deferred: Set<ExtensionCatalogGroup> = [.themes]

    /// The listing split at that line: what a reader scrolls through, and
    /// what waits at the end.
    ///
    /// Both stores read this rather than naming themes themselves, so the
    /// sidebar and the Settings pane cannot drift apart on it.
    static func partitioned(_ entries: [ExtensionIndex.Entry]) -> (leading: [Group], trailing: [Group]) {
        let all = groups(entries)
        return (
            all.filter { !deferred.contains($0.group) },
            all.filter { deferred.contains($0.group) }
        )
    }

    /// Where one entry belongs.
    ///
    /// An extension that contributes a language is filed under its language
    /// family and nowhere else, however much else it carries: the Lua package
    /// brings a formatter and an icon, and a reader looking for Lua wants it
    /// under Script, not repeated in three places. Only an extension that
    /// contributes no language is filed by what it does contribute.
    ///
    /// Servers are asked about first among those, and sit next to the
    /// languages in the order: Tailwind is a server for five languages and
    /// the language of none, so it has no family to file under, and a reader
    /// hunting for it is hunting among the things that read code.
    static func group(for entry: ExtensionIndex.Entry) -> ExtensionCatalogGroup {
        if entry.contributes.contains("languages") {
            guard let category = category(for: entry) else { return .languages }
            return .language(category)
        }
        for kind in ["servers", "formatters", "grammars", "themes", "iconThemes", "agents"]
        where entry.contributes.contains(kind) {
            switch kind {
            case "servers": return .servers
            case "formatters": return .formatters
            case "grammars": return .grammars
            case "themes": return .themes
            case "iconThemes": return .iconThemes
            default: return .agents
            }
        }
        return .other
    }

    /// The family a language extension belongs to.
    ///
    /// Read from the index, and from nowhere else. An index built before
    /// that field existed declares none, and an entry that declares none
    /// files under Languages rather than being guessed at — there is no
    /// compiled-in table of language families left to guess from, and a
    /// heading is not worth inventing one for.
    /// **The first one declared, in the order the manifest declared it.**
    /// Sorting them and taking the first files an extension under whichever
    /// family happens to sort earliest, which is arbitrary and was wrong:
    /// Elixir contributes Elixir, EEx and HEEx, so it declares script and
    /// markup, and "Markup" sorts before "Script" — the Elixir extension
    /// appeared under Markup. An extension's first language is what it is.
    static func category(for entry: ExtensionIndex.Entry) -> LSPServerCategory? {
        entry.categories.compactMap(LSPServerCategory.init(rawValue:)).first
    }

    static func groups(_ entries: [ExtensionIndex.Entry]) -> [Group] {
        var byGroup: [ExtensionCatalogGroup: [ExtensionIndex.Entry]] = [:]
        for entry in entries { byGroup[group(for: entry), default: []].append(entry) }
        return order.compactMap { group in
            guard let entries = byGroup[group], !entries.isEmpty else { return nil }
            return Group(group: group, entries: entries)
        }
    }
}
