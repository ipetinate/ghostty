import Foundation

/// One heading in the store's All listing.
///
/// The kind tabs answer "show me only themes". This answers the other
/// question a reader has in front of twenty-five rows sorted by name: which
/// of these are languages I compile, which are languages I run, and which are
/// not languages at all. Languages split by the same category the settings
/// list already groups servers under, so the two read alike.
enum ExtensionCatalogGroup: Hashable, Identifiable, Sendable {
    case language(LSPServerCategory)
    case languages
    case formatters
    case themes
    case iconThemes
    case agents
    case other

    var id: String {
        switch self {
        case .language(let category): return "language." + category.rawValue
        case .languages: return "languages"
        case .formatters: return "formatters"
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
        case .formatters: return "Formatters"
        case .themes: return "Themes"
        case .iconThemes: return "Icon Packs"
        case .agents: return "Agents"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .language(let category): return category.systemImage
        case .languages: return ExtensionContributionChip.of("languages").systemImage
        case .formatters: return ExtensionContributionChip.of("formatters").systemImage
        case .themes: return ExtensionContributionChip.of("themes").systemImage
        case .iconThemes: return ExtensionContributionChip.of("iconThemes").systemImage
        case .agents: return "sparkles"
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

    /// The order the headings appear in. Languages first, by the same
    /// category order the settings list uses, then what an extension can add
    /// beside a language.
    static let order: [ExtensionCatalogGroup] =
        LSPServerCategory.allCases.sorted { $0.title < $1.title }.map(ExtensionCatalogGroup.language)
            + [.languages, .formatters, .themes, .iconThemes, .agents, .other]

    /// Where one entry belongs.
    ///
    /// An extension that contributes a language is filed under its language
    /// family and nowhere else, however much else it carries: the Lua package
    /// brings a formatter and an icon, and a reader looking for Lua wants it
    /// under Script, not repeated in three places. Only an extension that
    /// contributes no language is filed by what it does contribute.
    static func group(for entry: ExtensionIndex.Entry) -> ExtensionCatalogGroup {
        if entry.contributes.contains("languages") {
            guard let category = category(for: entry) else { return .languages }
            return .language(category)
        }
        for kind in ["formatters", "themes", "iconThemes", "agents"] where entry.contributes.contains(kind) {
            switch kind {
            case "formatters": return .formatters
            case "themes": return .themes
            case "iconThemes": return .iconThemes
            default: return .agents
            }
        }
        return .other
    }

    /// The family a language extension belongs to.
    ///
    /// Read from the index when the registry published it. An index built
    /// before that field existed has none, so the language identifiers are
    /// matched against the servers the app already ships — which covers every
    /// language in the registry today and costs nothing when it does not.
    static func category(for entry: ExtensionIndex.Entry) -> LSPServerCategory? {
        let declared = entry.categories.compactMap(LSPServerCategory.init(rawValue:))
        if let first = ordered(declared).first { return first }
        let known = entry.languages.compactMap { LSPServerRegistry.category(forLanguageID: $0) }
        return ordered(known).first
    }

    private static func ordered(_ categories: [LSPServerCategory]) -> [LSPServerCategory] {
        categories.sorted { $0.title < $1.title }
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
