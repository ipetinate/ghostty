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

/// One set of injected rules in play for a document, with the grammar that
/// declared it.
///
/// The grammar travels along for the same reason it does in ``ResolvedRule``,
/// and it matters more here: an injected `#key` is a key in the *declaring*
/// grammar's repository. PHP's `<?php` rule is injected as `#php-tag`, and
/// resolving that against the document instead would find nothing.
struct ResolvedInjection {
    let selector: ScopeSelector
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
    private var injectingScopes: [String: [String]] = [:]

    init() {}

    /// Registers a grammar. A second grammar claiming the same scope
    /// replaces the first: the store holds what is installed now, and
    /// deciding *which* extension owns a scope is the catalog's job, not
    /// this one's.
    ///
    /// `injectTo` is the manifest's, not the grammar file's. A grammar
    /// cannot volunteer itself into somebody else's document — the
    /// extension has to ask, in `contributes.grammars[].injectTo` — which
    /// is why the two halves of a cross-grammar injection arrive here from
    /// different files and are joined by this method.
    func add(_ grammar: Grammar, languageId: String? = nil, injectTo: [String] = []) {
        byScope[grammar.scopeName] = grammar
        if let languageId, !languageId.isEmpty {
            scopeByLanguage[languageId] = grammar.scopeName
        }
        for fileType in grammar.fileTypes where scopeByFileType[fileType] == nil {
            scopeByFileType[fileType] = grammar.scopeName
        }
        for target in injectTo {
            var scopes = injectingScopes[target] ?? []
            guard !scopes.contains(grammar.scopeName) else { continue }
            scopes.append(grammar.scopeName)
            injectingScopes[target] = scopes
        }
    }

    /// Every injection in play for a document whose root grammar claims
    /// `scope`, `L:` first.
    ///
    /// **Two sources, and they are not symmetrical.**
    ///
    /// A grammar's own `injections` dictionary asks for rules inside its
    /// own documents, and is read from the **root** grammar only. A grammar
    /// reached through an `include` contributes none, which is why PHP's
    /// rule for entering `<?php … ?>` is declared by `text.html.php` and
    /// not by `source.php`: the HTML shell is what a `.php` file starts in,
    /// and `source.php` is only ever the guest.
    ///
    /// A grammar another extension named in its `injectTo` contributes its
    /// whole pattern list, bounded by the `injectionSelector` it wrote for
    /// itself. That is how `vue.directives` colours `:prop="expr"` inside a
    /// `.vue` template without `text.html.vue` having heard of it.
    ///
    /// Answered per document rather than cached, because a store is read
    /// from several threads and holds no cache — see the type's own note.
    /// One call per tokenizer, at its construction.
    func injections(forRootScope scope: String) -> [ResolvedInjection] {
        var result: [ResolvedInjection] = []
        if let root = byScope[scope] {
            for injection in root.injections {
                result.append(
                    ResolvedInjection(selector: injection.selector, rule: injection.rule, grammar: root))
            }
        }

        for injecting in injectingScopes[scope] ?? [] {
            guard let grammar = byScope[injecting] else { continue }
            for selector in grammar.injectionSelectors {
                result.append(
                    ResolvedInjection(selector: selector, rule: grammar.injectedRule, grammar: grammar))
            }
        }

        return ScopeSelector.ordered(result) { $0.selector.priority }
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
