import Foundation

/// One TextMate grammar, parsed from a `.tmLanguage.json` document.
///
/// A grammar is the whole of what a language contributes to the editor's
/// colouring: the scope it claims, the file types it answers for, the rules
/// it starts a document with, the named rules those rules reach for, and the
/// rules it asks to have injected into other people's documents.
///
/// **Strict about what it accepts, lenient about what it ignores.** A key
/// this engine does not know is skipped rather than refused, because a
/// grammar written for another editor carries folding markers, comments and
/// editor hints this one has no use for. A rule that is structurally
/// malformed — no `match`, no `begin`, no `include`, no `patterns` — is
/// dropped on its own, and the rest of the grammar stays usable. Only a
/// document that is not an object, or that names no scope, is refused
/// outright: without a `scopeName` nothing can include it and nothing can
/// theme it.
///
/// A pattern that Oniguruma cannot compile is *not* a parse failure. Nothing
/// here touches the regex engine — compilation happens in
/// ``GrammarTokenizer``, per thread — so a rule with a bad pattern parses
/// and then never matches.
///
/// Plist grammars are not read. The JSON form is what the store publishes.
final class Grammar {
    /// The scope this grammar claims, such as `source.elixir`. Another
    /// grammar includes this one by naming it.
    let scopeName: String

    /// The human name, for a picker. Not used for resolution.
    let name: String?

    /// File extensions, without the leading dot, lowercased.
    let fileTypes: [String]

    /// A pattern matched against a file's first line when the extension
    /// decided nothing. Stored, not compiled.
    let firstLineMatch: String?

    /// The rules a document starts with.
    let patterns: [GrammarRule]

    /// Rules an `include` reaches by name, as `#key`.
    let repository: [String: GrammarRule]

    /// Rules this grammar asks to have considered inside its own documents,
    /// wherever a selector matches the scope stack. Read from the document's
    /// root grammar only — see ``GrammarStore/injections(forRootScope:)``.
    let injections: [GrammarInjection]

    /// Where in somebody else's document this grammar's own patterns apply,
    /// from its top-level `injectionSelector`.
    ///
    /// Half of a cross-grammar injection and inert without the other half:
    /// the manifest's `contributes.grammars[].injectTo` names *which*
    /// documents, and this says *where* in them.
    let injectionSelectors: [ScopeSelector]

    /// The whole grammar as one rule, for a cross-grammar injection to be
    /// cached against.
    ///
    /// Made with the grammar rather than at the point of use, because the
    /// tokenizer's expansion cache keys on rule identity: a container built
    /// per candidate list would miss every time.
    let injectedRule: GrammarRule

    init(
        scopeName: String,
        name: String? = nil,
        fileTypes: [String] = [],
        firstLineMatch: String? = nil,
        patterns: [GrammarRule] = [],
        repository: [String: GrammarRule] = [:],
        injections: [GrammarInjection] = [],
        injectionSelectors: [ScopeSelector] = []
    ) {
        self.scopeName = scopeName
        self.name = name
        self.fileTypes = fileTypes
        self.firstLineMatch = firstLineMatch
        self.patterns = patterns
        self.repository = repository
        self.injections = injections
        self.injectionSelectors = injectionSelectors
        self.injectedRule = GrammarRule(kind: .group, patterns: patterns)
        GrammarRule.link(
            [patterns] + repository.values.map { [$0] } + injections.map(\.rules),
            to: repository)
    }
}

extension Grammar {
    /// Parses a `.tmLanguage.json` document, or returns nil when it is not
    /// one.
    static func parse(_ data: Data) -> Grammar? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return parse(object: root)
    }

    static func parse(contentsOf url: URL) -> Grammar? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    static func parse(object: Any) -> Grammar? {
        guard let root = object as? [String: Any] else { return nil }
        guard let scopeName = root["scopeName"] as? String, !scopeName.isEmpty else { return nil }

        return Grammar(
            scopeName: scopeName,
            name: root["name"] as? String,
            fileTypes: fileTypes(from: root["fileTypes"]),
            firstLineMatch: root["firstLineMatch"] as? String,
            patterns: GrammarRule.parse(list: root["patterns"]),
            repository: GrammarRule.parse(repository: root["repository"]),
            injections: injections(from: root["injections"]),
            injectionSelectors: ScopeSelector.parse(root["injectionSelector"] as? String ?? ""))
    }

    private static func fileTypes(from raw: Any?) -> [String] {
        guard let list = raw as? [Any] else { return [] }
        return list.compactMap { entry in
            guard let text = entry as? String, !text.isEmpty else { return nil }
            let trimmed = text.hasPrefix(".") ? String(text.dropFirst()) : text
            return trimmed.isEmpty ? nil : trimmed.lowercased()
        }
    }

    /// Reads the `injections` dictionary: each key a selector, each value a
    /// `patterns` list.
    ///
    /// One key may name several alternatives, and each becomes an injection
    /// of its own so it can carry its own priority — sharing the one
    /// container rule, so the tokenizer expands the patterns once however
    /// many alternatives reach them.
    ///
    /// Keys are taken in sorted order and the result sorted by priority.
    /// The order of two injections of equal priority decides which of them
    /// wins a position they both match, so it cannot be left to however a
    /// JSON dictionary chose to hand its keys over.
    private static func injections(from raw: Any?) -> [GrammarInjection] {
        guard let object = raw as? [String: Any] else { return [] }
        var result: [GrammarInjection] = []
        for key in object.keys.sorted() {
            guard let entry = object[key] as? [String: Any] else { continue }
            let rules = GrammarRule.parse(list: entry["patterns"])
            guard !rules.isEmpty else { continue }
            let container = GrammarRule(kind: .group, patterns: rules)
            for selector in ScopeSelector.parse(key) {
                result.append(GrammarInjection(selector: selector, rule: container))
            }
        }
        return ScopeSelector.ordered(result) { $0.selector.priority }
    }
}

/// Rules one grammar offers to documents it does not own.
///
/// The rules are wrapped in a container rule rather than left as a list so
/// the tokenizer has something with an identity to cache their expansion
/// against, the same way it caches a region's children.
struct GrammarInjection {
    let selector: ScopeSelector
    let rule: GrammarRule

    var rules: [GrammarRule] { rule.patterns }
}
