import Foundation

/// One rule, and the grammar it was written in.
///
/// The pair travels together because an `include` is resolved relative to
/// its own grammar. A rule from `source.ts` that says `#comment` means
/// TypeScript's comment, even while it runs inside a `.vue` document, and
/// losing the second half of this pair is how an engine ends up resolving
/// it against whatever grammar happens to be on top.
struct ResolvedRule {
    let rule: GrammarRule
    let grammar: Grammar
}

/// Every grammar the editor knows, and the resolution of `include` between
/// them.
///
/// Grammars are held by `scopeName`, which is the only name an `include`
/// can use. A `languageId` is a second, optional key: the editor knows a
/// document by its language, and a language names exactly one grammar.
///
/// **Lookup only, no cache.** One store is read by every tokenizer, and a
/// tokenizer is per thread, so nothing here memoizes — a cache would be
/// written from several threads at once. Populate the store, then read it.
/// ``GrammarTokenizer`` keeps the expansion cache instead, one per
/// tokenizer.
final class GrammarStore {
    private var byScope: [String: Grammar] = [:]
    private var scopeByLanguage: [String: String] = [:]
    private var scopeByFileType: [String: String] = [:]

    init() {}

    /// Registers a grammar. A second grammar claiming the same scope
    /// replaces the first: the store holds what is installed now, and
    /// deciding *which* extension owns a scope is the catalog's job, not
    /// this one's.
    func add(_ grammar: Grammar, languageId: String? = nil) {
        byScope[grammar.scopeName] = grammar
        if let languageId, !languageId.isEmpty {
            scopeByLanguage[languageId] = grammar.scopeName
        }
        for fileType in grammar.fileTypes where scopeByFileType[fileType] == nil {
            scopeByFileType[fileType] = grammar.scopeName
        }
    }

    func grammar(scope: String) -> Grammar? {
        byScope[scope]
    }

    func grammar(language: String) -> Grammar? {
        guard let scope = scopeByLanguage[language] else { return nil }
        return byScope[scope]
    }

    /// The grammar claiming a file extension, given with or without its dot.
    func grammar(fileType: String) -> Grammar? {
        let normalized = (fileType.hasPrefix(".") ? String(fileType.dropFirst()) : fileType).lowercased()
        guard let scope = scopeByFileType[normalized] else { return nil }
        return byScope[scope]
    }

    var scopeNames: [String] {
        Array(byScope.keys)
    }

    /// What an `include` string points at.
    ///
    /// Four forms, all of them in real grammars:
    ///
    /// - `#key` — a rule in `grammar`'s own repository
    /// - `$self` — the whole of `grammar`, which is how a nested region
    ///   re-enters the language it is written in
    /// - `$base` — the whole of the grammar the document started in, which
    ///   for an embedded grammar is the *outer* one and not itself
    /// - `source.x` or `source.x#key` — another grammar, by scope
    ///
    /// Returns nil when nothing answers to the name. An unresolvable
    /// include is dropped rather than treated as an error: a grammar
    /// commonly includes a scope its author shipped in a second package,
    /// and the language still colours without it.
    func resolve(include reference: String, from grammar: Grammar, base: Grammar) -> ResolvedInclude? {
        if reference == "$self" {
            return ResolvedInclude(rules: grammar.patterns, grammar: grammar)
        }
        if reference == "$base" {
            return ResolvedInclude(rules: base.patterns, grammar: base)
        }
        if reference.hasPrefix("#") {
            let key = String(reference.dropFirst())
            guard let rule = grammar.repository[key] else { return nil }
            return ResolvedInclude(rules: [rule], grammar: grammar)
        }

        let parts = reference.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard let scope = parts.first.map(String.init), !scope.isEmpty else { return nil }
        guard let target = byScope[scope] else { return nil }
        guard parts.count == 2 else {
            return ResolvedInclude(rules: target.patterns, grammar: target)
        }
        guard let rule = target.repository[String(parts[1])] else { return nil }
        return ResolvedInclude(rules: [rule], grammar: target)
    }

    struct ResolvedInclude {
        let rules: [GrammarRule]
        let grammar: Grammar
    }
}
