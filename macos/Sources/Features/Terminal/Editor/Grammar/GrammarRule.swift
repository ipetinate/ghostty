import Foundation

/// One entry of a grammar's `patterns` list, or one named entry of its
/// `repository`.
///
/// A reference type on purpose. A rule is reached from several places — the
/// grammar's own list, a repository key, an `include` in somebody else's
/// grammar — and the tokenizer's state stack, its include-expansion cache
/// and its cycle guard all key on rule *identity*. Copying a rule would make
/// three different caches disagree about whether two rules are the same one.
final class GrammarRule {
    /// What the rule does. TextMate has four shapes and this enum is all of
    /// them, plus the container form: a rule that carries only `patterns`
    /// matches nothing itself and lends its children to whoever includes it.
    enum Kind {
        case match(String)
        case beginEnd(begin: String, end: String)
        case beginWhile(begin: String, continuation: String)
        case include(String)
        case group
    }

    let kind: Kind

    /// The scope pushed over the whole match, or over the whole region for a
    /// `begin` rule. May carry `$1`-style references to the begin match's
    /// captures.
    let name: String?

    /// The scope pushed over a region's body only, between the end of the
    /// `begin` match and the start of the `end` match.
    let contentName: String?

    /// Captures of a `match` rule, keyed by group number. Group zero is the
    /// whole match.
    let captures: [Int: GrammarCapture]

    /// Captures of a `begin` match. Falls back to `captures` when the
    /// grammar gave only that, which is what the TextMate format means by a
    /// `captures` key on a `begin`/`end` rule.
    let beginCaptures: [Int: GrammarCapture]

    /// Captures of an `end` match, with the same fallback.
    let endCaptures: [Int: GrammarCapture]

    /// Captures of a `while` match, with the same fallback.
    let whileCaptures: [Int: GrammarCapture]

    /// Rules that apply inside this rule's region.
    let patterns: [GrammarRule]

    /// A `repository` of the rule's own, which its children reach by name
    /// ahead of the grammar's.
    let ownRepository: [String: GrammarRule]

    /// The repository an `include` written in this rule resolves against,
    /// or nil for the grammar's own.
    ///
    /// Settled by ``Grammar`` once the whole document is parsed, by
    /// ``GrammarRule/link(_:to:)``, and never touched afterwards.
    var scopedRepository: [String: GrammarRule]?

    /// Whether the child patterns get first refusal at a position the `end`
    /// pattern also matches. The TextMate default is that `end` wins.
    let applyEndPatternLast: Bool

    init(
        kind: Kind,
        name: String? = nil,
        contentName: String? = nil,
        captures: [Int: GrammarCapture] = [:],
        beginCaptures: [Int: GrammarCapture]? = nil,
        endCaptures: [Int: GrammarCapture]? = nil,
        whileCaptures: [Int: GrammarCapture]? = nil,
        patterns: [GrammarRule] = [],
        ownRepository: [String: GrammarRule] = [:],
        applyEndPatternLast: Bool = false
    ) {
        self.kind = kind
        self.name = name
        self.contentName = contentName
        self.captures = captures
        self.beginCaptures = beginCaptures ?? captures
        self.endCaptures = endCaptures ?? captures
        self.whileCaptures = whileCaptures ?? captures
        self.patterns = patterns
        self.ownRepository = ownRepository
        self.applyEndPatternLast = applyEndPatternLast
    }

    /// The pattern searched for to enter this rule, or nil when there is
    /// nothing to search for.
    var entryPattern: String? {
        switch kind {
        case .match(let pattern): return pattern
        case .beginEnd(let begin, _): return begin
        case .beginWhile(let begin, _): return begin
        case .include, .group: return nil
        }
    }
}

extension GrammarRule {
    /// Parses a `patterns` array, dropping the entries it cannot read.
    static func parse(list raw: Any?) -> [GrammarRule] {
        guard let list = raw as? [Any] else { return [] }
        return list.compactMap { parse($0) }
    }

    /// Parses one rule, or returns nil when the object names nothing this
    /// engine can do.
    static func parse(_ raw: Any) -> GrammarRule? {
        guard let object = raw as? [String: Any] else { return nil }
        if truthy(object["disabled"]) { return nil }

        let captures = GrammarCapture.parse(object["captures"]) ?? [:]
        let begin = object["begin"] as? String

        let kind: Kind
        if let include = object["include"] as? String, !include.isEmpty {
            kind = .include(include)
        } else if let match = object["match"] as? String {
            kind = .match(match)
        } else if let begin {
            if let end = object["end"] as? String {
                kind = .beginEnd(begin: begin, end: end)
            } else if let continuation = object["while"] as? String {
                kind = .beginWhile(begin: begin, continuation: continuation)
            } else {
                return nil
            }
        } else if object["patterns"] is [Any] {
            kind = .group
        } else {
            return nil
        }

        return GrammarRule(
            kind: kind,
            name: object["name"] as? String,
            contentName: object["contentName"] as? String,
            captures: captures,
            beginCaptures: GrammarCapture.parse(object["beginCaptures"]),
            endCaptures: GrammarCapture.parse(object["endCaptures"]),
            whileCaptures: GrammarCapture.parse(object["whileCaptures"]),
            patterns: parse(list: object["patterns"]),
            ownRepository: parse(repository: object["repository"]),
            applyEndPatternLast: truthy(object["applyEndPatternLast"]))
    }

    /// Parses a `repository` object, wherever it appears: a grammar's own
    /// or one a single rule declared.
    static func parse(repository raw: Any?) -> [String: GrammarRule] {
        guard let object = raw as? [String: Any] else { return [:] }
        var result: [String: GrammarRule] = [:]
        for (key, value) in object {
            guard let rule = parse(value) else { continue }
            result[key] = rule
        }
        return result
    }

    /// Points every `include` under `roots` at the repository in force
    /// where it was written.
    ///
    /// A rule may declare a `repository` of its own, and `#key` inside it
    /// then means that rule's key first and the grammar's second. Ruby's
    /// `method_parameters` is the case that made this necessary: `#params`
    /// is a key it declares, so an engine reading only the grammar's
    /// repository dropped the rule — `name` in
    /// `def greet(name, greeting: "hi")` came out unpainted and `greeting`
    /// came out a keyword. HTML declares one for `svg` and one for `math`
    /// the same way, which is what colours an `<svg>` element's attributes.
    ///
    /// Worked out once, here, rather than threaded through the scanner. A
    /// rule is reached from several places and the first path to it settles
    /// which repository it sees — the same first-wins the reference
    /// implementation gets from compiling each rule once.
    static func link(_ roots: [[GrammarRule]], to top: [String: GrammarRule]) {
        var visited: Set<ObjectIdentifier> = []
        for rules in roots {
            link(rules, inherited: nil, top: top, visited: &visited)
        }
    }

    private static func link(
        _ rules: [GrammarRule],
        inherited: [String: GrammarRule]?,
        top: [String: GrammarRule],
        visited: inout Set<ObjectIdentifier>
    ) {
        for rule in rules {
            guard visited.insert(ObjectIdentifier(rule)).inserted else { continue }
            var current = inherited
            if rule.declaresRepository {
                current = (inherited ?? top).merging(rule.ownRepository) { _, nested in nested }
            }
            rule.scopedRepository = current
            link(rule.patterns, inherited: current, top: top, visited: &visited)
            link(Array(rule.ownRepository.values), inherited: current, top: top, visited: &visited)
            for captures in [rule.captures, rule.beginCaptures, rule.endCaptures, rule.whileCaptures] {
                for capture in captures.values {
                    link(capture.patterns, inherited: current, top: top, visited: &visited)
                }
            }
        }
    }

    /// Whether the rule's own `repository` counts.
    ///
    /// Only on a rule that matches nothing itself, which is the one shape
    /// the reference implementation merges a nested repository for. A
    /// `repository` beside a `match` or a `begin` is ignored there, so it
    /// is ignored here.
    private var declaresRepository: Bool {
        guard !ownRepository.isEmpty else { return false }
        switch kind {
        case .group, .include: return true
        case .match, .beginEnd, .beginWhile: return false
        }
    }

    private static func truthy(_ raw: Any?) -> Bool {
        if let flag = raw as? Bool { return flag }
        if let number = raw as? NSNumber { return number.intValue != 0 }
        return false
    }
}

/// One numbered group of a match, and what the grammar wants done with it.
struct GrammarCapture {
    /// The scope pushed over the group. May carry `$1`-style references.
    let name: String?

    /// Rules to run over the group's text. Rare, and bounded: a capture's
    /// patterns are tokenized against the group's bytes alone, so `^`,
    /// lookbehind and `\G` inside them see the group and not the line.
    let patterns: [GrammarRule]
}

extension GrammarCapture {
    /// Parses a `captures` object, or returns nil when the key was absent —
    /// which is how `beginCaptures` knows to fall back to `captures`.
    static func parse(_ raw: Any?) -> [Int: GrammarCapture]? {
        guard let object = raw as? [String: Any] else { return nil }
        var result: [Int: GrammarCapture] = [:]
        for (key, value) in object {
            guard let group = Int(key), group >= 0 else { continue }
            guard let entry = value as? [String: Any] else { continue }
            let name = entry["name"] as? String
            let patterns = GrammarRule.parse(list: entry["patterns"])
            guard name != nil || !patterns.isEmpty else { continue }
            result[group] = GrammarCapture(name: name, patterns: patterns)
        }
        return result
    }
}
