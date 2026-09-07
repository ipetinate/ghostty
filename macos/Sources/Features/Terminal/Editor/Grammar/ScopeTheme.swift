import Foundation

/// Turns a TextMate scope stack into one of the nine kinds a `CodeTheme`
/// paints.
///
/// TextMate scopes are open-ended: a grammar names
/// `constant.language.symbol.elixir` and nobody has to have heard of it
/// first. A theme with nine colours has to collapse that, and the rule is
/// the one TextMate themes use — **the longest prefix that matches wins**,
/// on dotted boundaries, so `constant.language` claims
/// `constant.language.symbol.elixir` and `constant` alone would claim
/// nothing.
///
/// Scopes are read innermost first. A span inside a function name inside a
/// string is a function name: the deepest scope that any rule recognises is
/// the one that decides, and only if no rule recognises it does the search
/// move outwards.
///
/// **This is a parity map, not a theme model.** A real TextMate theme picks
/// colours with scope selectors of its own and would replace this whole
/// type. What it buys today is that a grammar nobody compiled in comes out
/// the same colours as a language that was.
struct ScopeTheme {
    struct Rule: Equatable {
        let prefix: String
        let kind: TokenKind
    }

    private let rules: [Rule]

    init(rules: [Rule]) {
        self.rules = rules.sorted { $0.prefix.count > $1.prefix.count }
    }

    /// The mapping the editor ships with.
    static let standard = ScopeTheme(rules: [
        Rule(prefix: "comment", kind: .comment),
        Rule(prefix: "string", kind: .string),
        Rule(prefix: "constant.character.escape", kind: .string),
        Rule(prefix: "constant.numeric", kind: .number),
        Rule(prefix: "keyword", kind: .keyword),
        Rule(prefix: "storage", kind: .keyword),
        Rule(prefix: "constant.language", kind: .keyword),
        Rule(prefix: "entity.name.tag", kind: .keyword),
        Rule(prefix: "entity.name.type", kind: .type),
        Rule(prefix: "entity.name.class", kind: .type),
        Rule(prefix: "support.type", kind: .type),
        Rule(prefix: "support.class", kind: .type),
        Rule(prefix: "support.constant", kind: .keyword),
        Rule(prefix: "variable.language", kind: .keyword),
        Rule(prefix: "entity.name.function", kind: .function),
        Rule(prefix: "support.function", kind: .function),
        Rule(prefix: "entity.other.attribute-name", kind: .attribute),
        Rule(prefix: "variable.parameter", kind: .attribute),
        Rule(prefix: "punctuation", kind: .punctuation),
    ])

    /// The kind for a span, given its scope stack outermost first.
    func kind(for scopes: [String]) -> TokenKind {
        for scope in scopes.reversed() {
            if let kind = kind(forScope: scope) { return kind }
        }
        return .plain
    }

    /// The kind one scope name maps to on its own, or nil when no rule
    /// claims it.
    func kind(forScope scope: String) -> TokenKind? {
        rules.first { ScopeSelector.scope(scope, hasPrefix: $0.prefix) }?.kind
    }
}
