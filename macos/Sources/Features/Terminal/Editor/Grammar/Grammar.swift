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

    /// Rules this grammar asks to have considered inside documents whose
    /// scope stack a selector matches.
    let injections: [GrammarInjection]

    init(
        scopeName: String,
        name: String? = nil,
        fileTypes: [String] = [],
        firstLineMatch: String? = nil,
        patterns: [GrammarRule] = [],
        repository: [String: GrammarRule] = [:],
        injections: [GrammarInjection] = []
    ) {
        self.scopeName = scopeName
        self.name = name
        self.fileTypes = fileTypes
        self.firstLineMatch = firstLineMatch
        self.patterns = patterns
        self.repository = repository
        self.injections = injections
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
            repository: repository(from: root["repository"]),
            injections: injections(from: root["injections"]))
    }

    private static func fileTypes(from raw: Any?) -> [String] {
        guard let list = raw as? [Any] else { return [] }
        return list.compactMap { entry in
            guard let text = entry as? String, !text.isEmpty else { return nil }
            let trimmed = text.hasPrefix(".") ? String(text.dropFirst()) : text
            return trimmed.isEmpty ? nil : trimmed.lowercased()
        }
    }

    private static func repository(from raw: Any?) -> [String: GrammarRule] {
        guard let object = raw as? [String: Any] else { return [:] }
        var result: [String: GrammarRule] = [:]
        for (key, value) in object {
            guard let rule = GrammarRule.parse(value) else { continue }
            result[key] = rule
        }
        return result
    }

    private static func injections(from raw: Any?) -> [GrammarInjection] {
        guard let object = raw as? [String: Any] else { return [] }
        var result: [GrammarInjection] = []
        for (key, value) in object {
            guard let selector = ScopeSelector(key) else { continue }
            guard let entry = value as? [String: Any] else { continue }
            let rules = GrammarRule.parse(list: entry["patterns"])
            guard !rules.isEmpty else { continue }
            result.append(GrammarInjection(selector: selector, rule: GrammarRule(kind: .group, patterns: rules)))
        }
        return result.sorted { $0.selector.priority.rawValue > $1.selector.priority.rawValue }
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

/// The key of an `injections` entry: which scope stacks the rules apply to,
/// and whether they are considered before or after the document's own rules.
///
/// **A deliberate subset of the TextMate selector language.** A selector is
/// a comma-separated list of alternatives; an alternative is a whitespace
/// separated path of scope-name prefixes that must appear on the stack in
/// order, innermost last. `L:` puts the rules ahead of the document's own,
/// `R:` and a bare selector put them behind.
///
/// Negation (`-source.js`), grouping (`(a | b)`) and the `<` containment
/// operator are **not** implemented. An alternative that uses one is
/// dropped rather than approximated, because approximating it the other way
/// would inject rules where the author asked for them not to be. A selector
/// whose every alternative is dropped matches nothing.
struct ScopeSelector {
    enum Priority: Int {
        case before = 1
        case normal = 0
        case after = -1
    }

    let priority: Priority

    private let alternatives: [[String]]

    init?(_ text: String) {
        var priority = Priority.normal
        var alternatives: [[String]] = []

        for piece in text.split(separator: ",", omittingEmptySubsequences: true) {
            var body = piece.trimmingCharacters(in: .whitespaces)
            if body.hasPrefix("L:") {
                priority = .before
                body = String(body.dropFirst(2))
            } else if body.hasPrefix("R:") {
                if priority == .normal { priority = .after }
                body = String(body.dropFirst(2))
            }

            let identifiers = body.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard !identifiers.isEmpty else { continue }
            if identifiers == ["*"] {
                alternatives.append([])
                continue
            }
            guard identifiers.allSatisfy(Self.isPlainIdentifier) else { continue }
            alternatives.append(identifiers)
        }

        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        self.priority = priority
        self.alternatives = alternatives
    }

    /// Whether this selector applies to a scope stack, outermost first.
    func matches(_ scopes: [String]) -> Bool {
        alternatives.contains { alternative in
            guard alternative.count <= scopes.count else { return false }
            var next = 0
            for identifier in alternative {
                guard let hit = scopes[next...].firstIndex(where: { Self.scope($0, hasPrefix: identifier) }) else {
                    return false
                }
                next = hit + 1
            }
            return true
        }
    }

    /// A scope name matches a selector identifier when it is that
    /// identifier or a dotted descendant of it. `source.js` matches
    /// `source`, and `sourcemap.x` does not.
    static func scope(_ scope: String, hasPrefix identifier: String) -> Bool {
        if scope == identifier { return true }
        guard scope.count > identifier.count, scope.hasPrefix(identifier) else { return false }
        return scope[scope.index(scope.startIndex, offsetBy: identifier.count)] == "."
    }

    private static func isPlainIdentifier(_ identifier: String) -> Bool {
        !identifier.contains(where: { "-()<>|&*".contains($0) })
    }
}
