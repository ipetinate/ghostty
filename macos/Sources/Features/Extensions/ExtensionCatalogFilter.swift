import Foundation

enum ExtensionCatalogFilter {
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case all
        case languages
        case formatters
        case themes
        case iconThemes
        case agents

        var id: String { rawValue }

        var contribution: String? { self == .all ? nil : rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .languages: return "Languages"
            case .formatters: return "Formatters"
            case .themes: return "Themes"
            case .iconThemes: return "Icons"
            case .agents: return "Agents"
            }
        }

        var systemImage: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .agents: return "sparkles"
            default: return ExtensionContributionChip.of(rawValue).systemImage
            }
        }
    }

    enum Sort: String, CaseIterable, Identifiable, Sendable {
        case name
        case updated
        case publisher

        var id: String { rawValue }

        var title: String {
            switch self {
            case .name: return "Name"
            case .updated: return "Recently Updated"
            case .publisher: return "Publisher"
            }
        }
    }

    struct Term: Equatable, Sendable {
        enum Test: Equatable, Sendable {
            case text(String)
            case language(String)
            case tag(String)
            case publisher(String)
            case identifier(String)
            case contribution(String)
            case installed(Bool)
            case updatable(Bool)
        }

        let test: Test
        var isNegated = false
    }

    struct Sections: Equatable {
        let entries: [ExtensionIndex.Entry]
        let orphans: [InstalledExtension]
        let counts: [Kind: Int]

        var isEmpty: Bool { entries.isEmpty && orphans.isEmpty }

        func count(_ kind: Kind) -> Int { counts[kind] ?? 0 }
    }

    static func sections(
        entries: [ExtensionIndex.Entry],
        installed: [InstalledExtension],
        query: String,
        kind: Kind = .all,
        sort: Sort = .name
    ) -> Sections {
        let parsed = terms(in: query)
        let listed = Set(entries.map(\.id))
        let versions = Dictionary(installed.map { ($0.id, $0.version) }) { first, _ in first }

        let matched = entries.filter { entry in
            let state = ExtensionStore.state(
                installedVersion: versions[entry.id], available: entry.version)
            return parsed.allSatisfy { matches($0, entry: entry, state: state) }
        }
        let orphans = installed
            .filter { !listed.contains($0.id) }
            .filter { orphan in parsed.allSatisfy { matches($0, orphan: orphan) } }

        var counts: [Kind: Int] = [:]
        for tab in Kind.allCases {
            let listedCount = matched.filter { contributes($0, to: tab) }.count
            counts[tab] = tab == .all ? listedCount + orphans.count : listedCount
        }

        return Sections(
            entries: sorted(matched.filter { contributes($0, to: kind) }, by: sort),
            orphans: kind == .all ? stable(orphans, by: { before($0.name, $1.name) }) : [],
            counts: counts
        )
    }

    // MARK: Query

    static let folding: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    static func terms(in query: String) -> [Term] {
        tokens(in: query).compactMap(term(from:))
    }

    private static func tokens(in query: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var isQuoted = false

        for character in query {
            if character == "\"" {
                isQuoted.toggle()
                current.append(character)
            } else if character.isWhitespace, !isQuoted {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func term(from token: String) -> Term? {
        var body = Substring(token)
        var isNegated = false
        if body.hasPrefix("-"), body.count > 1 {
            isNegated = true
            body = body.dropFirst()
        }
        guard let test = test(in: String(body)) else { return nil }
        return Term(test: test, isNegated: isNegated)
    }

    private static func test(in body: String) -> Term.Test? {
        guard !body.hasPrefix("\""), let colon = body.firstIndex(of: ":") else {
            return freeText(body)
        }

        let scope = body[body.startIndex..<colon].lowercased()
        let value = unquoted(String(body[body.index(after: colon)...]))
        guard !value.isEmpty else { return freeText(body) }

        switch scope {
        case "lang": return .language(value)
        case "tag": return .tag(value)
        case "by": return .publisher(value)
        case "id": return .identifier(value)
        case "contributes": return .contribution(value)
        case "installed": return flag(value).map(Term.Test.installed) ?? freeText(body)
        case "updatable": return flag(value).map(Term.Test.updatable) ?? freeText(body)
        default: return freeText(body)
        }
    }

    private static func freeText(_ body: String) -> Term.Test? {
        let value = unquoted(body)
        return value.isEmpty ? nil : .text(value)
    }

    private static func unquoted(_ value: String) -> String {
        value.filter { $0 != "\"" }
    }

    private static func flag(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "yes", "true", "y", "1": return true
        case "no", "false", "n", "0": return false
        default: return nil
        }
    }

    // MARK: Matching

    static func matches(_ term: Term, entry: ExtensionIndex.Entry, state: ExtensionState) -> Bool {
        term.isNegated != holds(term.test, entry: entry, state: state)
    }

    static func matches(_ term: Term, orphan: InstalledExtension) -> Bool {
        term.isNegated != holds(term.test, orphan: orphan)
    }

    private static func holds(
        _ test: Term.Test,
        entry: ExtensionIndex.Entry,
        state: ExtensionState
    ) -> Bool {
        switch test {
        case .text(let value):
            return fields(of: entry).contains { contains($0, value) }
        case .language(let value):
            return entry.languages.contains { same($0, value) }
        case .tag(let value):
            return (entry.card?.tags ?? []).contains { same($0, value) }
        case .publisher(let value):
            return [entry.publisher, entry.card?.author.name]
                .compactMap { $0 }
                .contains { contains($0, value) }
        case .identifier(let value):
            return contains(entry.id, value)
        case .contribution(let value):
            return entry.contributes.contains { same($0, value) }
        case .installed(let wanted):
            return (state != .notInstalled) == wanted
        case .updatable(let wanted):
            return isUpdatable(state) == wanted
        }
    }

    private static func holds(_ test: Term.Test, orphan: InstalledExtension) -> Bool {
        switch test {
        case .text(let value):
            return [orphan.name, orphan.id].contains { contains($0, value) }
        case .publisher(let value):
            return contains(orphan.publisher, value)
        case .identifier(let value):
            return contains(orphan.id, value)
        case .installed(let wanted):
            return wanted
        case .updatable(let wanted):
            return !wanted
        case .language, .tag, .contribution:
            return false
        }
    }

    private static func fields(of entry: ExtensionIndex.Entry) -> [String] {
        [entry.name, entry.id, entry.publisher, entry.summary]
            + entry.languages
            + (entry.card?.tags ?? [])
    }

    private static func contributes(_ entry: ExtensionIndex.Entry, to kind: Kind) -> Bool {
        guard let contribution = kind.contribution else { return true }
        return entry.contributes.contains { same($0, contribution) }
    }

    private static func isUpdatable(_ state: ExtensionState) -> Bool {
        if case .updateAvailable = state { return true }
        return false
    }

    private static func contains(_ field: String, _ value: String) -> Bool {
        field.range(of: value, options: folding) != nil
    }

    private static func same(_ field: String, _ value: String) -> Bool {
        field.compare(value, options: folding) == .orderedSame
    }

    // MARK: Order

    private static func sorted(_ entries: [ExtensionIndex.Entry], by sort: Sort) -> [ExtensionIndex.Entry] {
        switch sort {
        case .name:
            return stable(entries) { before($0.name, $1.name) }
        case .publisher:
            return stable(entries) { before($0.publisher, $1.publisher) }
        case .updated:
            return stable(entries) { newer($0, $1) }
        }
    }

    private static func stable<Item>(_ items: [Item], by isBefore: (Item, Item) -> Bool) -> [Item] {
        items.enumerated()
            .sorted { lhs, rhs in
                if isBefore(lhs.element, rhs.element) { return true }
                if isBefore(rhs.element, lhs.element) { return false }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func before(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private static func newer(_ lhs: ExtensionIndex.Entry, _ rhs: ExtensionIndex.Entry) -> Bool {
        switch (moment(of: lhs), moment(of: rhs)) {
        case (let left?, let right?): return left > right
        case (.some, .none): return true
        case (.none, .some), (.none, .none): return false
        }
    }

    private static func moment(of entry: ExtensionIndex.Entry) -> Date? {
        guard let card = entry.card else { return nil }
        return card.updated ?? card.created
    }
}
