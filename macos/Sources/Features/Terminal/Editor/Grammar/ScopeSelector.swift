import Foundation

/// One alternative of a TextMate scope selector: which scope stacks a set of
/// injected rules applies to, and whether those rules are tried before or
/// after the host document's own.
///
/// **One selector is one alternative.** The text a grammar writes is a
/// comma-separated list of them, each carrying its own `L:`/`R:` prefix, so
/// ``parse(_:)`` answers with a list rather than with one value. PHP's is a
/// single string holding four alternatives of which three ask to go first:
///
/// ```text
/// text.html.php - (meta.embedded | meta.tag),
/// L:((text.html.php meta.tag) - (meta.embedded.block.php | meta.embedded.line.php)),
/// L:(source.js - (…)), L:(source.css - (…))
/// ```
///
/// Reading that as one selector with one priority is how an engine ends up
/// putting the whole of PHP behind HTML's own rules, or ahead of them.
///
/// **The grammar of a selector**, and all of it that is implemented:
///
/// - a comma-separated list of alternatives, each with an optional `L:` or
///   `R:` prefix
/// - a space-separated **descendant path** — `text.html.php meta.tag`
///   matches a stack where `text.html.php` appears before `meta.tag`, not
///   necessarily next to it
/// - parentheses, `|` alternation inside them, and `,` reading as `|` there
/// - `-` exclusion, of a group or of a bare identifier
/// - prefix matching on dotted boundaries, the same rule ``ScopeTheme``
///   uses: `meta.embedded` matches `meta.embedded.block.php`
///
/// `>` for a direct child and the `:` pseudo-classes are **not**
/// implemented; no installed grammar writes either. A character the grammar
/// of a selector has no place for — `*`, most often, in
/// `meta.tag.*.*.html` — is skipped rather than refused, which leaves an
/// identifier that matches no real scope. That is what the reference
/// implementation does with it, and matching those wildcards where it does
/// not would inject rules into every HTML tag.
struct ScopeSelector {
    /// Where the injected rules sit relative to the host's own rules.
    ///
    /// `before` is `L:` — first refusal, so the injection wins a position
    /// the host also matches. `after` is `R:`, and a bare alternative is
    /// `normal`; both sit behind the host, and can only win by matching
    /// earlier in the line.
    enum Priority: Int {
        case before = 1
        case normal = 0
        case after = -1
    }

    let priority: Priority

    private let matcher: Matcher

    init(priority: Priority, matcher: Matcher) {
        self.priority = priority
        self.matcher = matcher
    }

    /// Whether this alternative applies to a scope stack, outermost first.
    func matches(_ scopes: [String]) -> Bool {
        matcher.matches(scopes)
    }

    /// Every alternative of a selector, in the order it was written.
    static func parse(_ text: String) -> [ScopeSelector] {
        var parser = Parser(text: text)
        return parser.selectors()
    }

    /// A scope name matches a selector identifier when it is that
    /// identifier or a dotted descendant of it. `source.js` matches
    /// `source`, and `sourcemap.x` does not.
    static func scope(_ scope: String, hasPrefix identifier: String) -> Bool {
        if scope == identifier { return true }
        guard scope.count > identifier.count, scope.hasPrefix(identifier) else { return false }
        return scope[scope.index(scope.startIndex, offsetBy: identifier.count)] == "."
    }

    /// Injections ordered `L:` first and `R:` last, keeping the order they
    /// arrived in among those of equal priority.
    ///
    /// A stable sort, written out because Swift's is not one. Two injections
    /// of equal priority that match at the same offset are settled by their
    /// place in this list, so an unstable sort would let one document
    /// colour two ways.
    static func ordered<Item>(_ items: [Item], by priority: (Item) -> Priority) -> [Item] {
        items.enumerated()
            .sorted { lhs, rhs in
                let left = priority(lhs.element).rawValue
                let right = priority(rhs.element).rawValue
                return left == right ? lhs.offset < rhs.offset : left > right
            }
            .map(\.element)
    }
}

extension ScopeSelector {
    /// One parsed alternative, as a tree.
    ///
    /// **`all` of nothing matches everything, and `any` of nothing matches
    /// nothing.** Neither is an oversight. It is how `L:*` comes to mean
    /// every stack: `*` is not part of the selector language, so once the
    /// prefix is read there is nothing left of the alternative, and an
    /// alternative that states no condition places none.
    indirect enum Matcher {
        /// A descendant path, outermost identifier first.
        case path([String])
        case negated(Matcher)
        case all([Matcher])
        case any([Matcher])

        func matches(_ scopes: [String]) -> Bool {
            switch self {
            case .path(let identifiers):
                return Self.path(identifiers, matches: scopes)
            case .negated(let inner):
                return !inner.matches(scopes)
            case .all(let matchers):
                return matchers.allSatisfy { $0.matches(scopes) }
            case .any(let matchers):
                return matchers.contains { $0.matches(scopes) }
            }
        }

        private static func path(_ identifiers: [String], matches scopes: [String]) -> Bool {
            guard identifiers.count <= scopes.count else { return false }
            var next = 0
            for identifier in identifiers {
                guard let hit = scopes[next...].firstIndex(where: {
                    ScopeSelector.scope($0, hasPrefix: identifier)
                }) else { return false }
                next = hit + 1
            }
            return true
        }
    }
}

private extension ScopeSelector {
    enum Token: Equatable {
        case priority(Priority)
        case identifier(String)
        case comma
        case pipe
        case minus
        case open
        case close
    }

    /// Recursive descent over the tokens, one alternative at a time.
    ///
    /// The shape is the reference implementation's, because the corners are
    /// where the two could differ and the corners are what real grammars
    /// land on: an empty conjunction, a `,` reading as `|` inside
    /// parentheses, a `-` that takes a group or a bare identifier, and a
    /// prefix that belongs to the alternative it precedes rather than to
    /// the selector.
    struct Parser {
        private let tokens: [Token]
        private var index = 0
        private var token: Token?

        init(text: String) {
            tokens = Self.scan(text)
            advance()
        }

        mutating func selectors() -> [ScopeSelector] {
            var result: [ScopeSelector] = []
            while let current = token {
                var priority = Priority.normal
                if case .priority(let given) = current {
                    priority = given
                    advance()
                }
                result.append(ScopeSelector(priority: priority, matcher: conjunction()))
                guard token == .comma else { break }
                advance()
            }
            return result
        }

        private mutating func advance() {
            token = index < tokens.count ? tokens[index] : nil
            index += 1
        }

        /// Everything an alternative demands at once, so a path and the
        /// exclusions after it are read as one condition.
        private mutating func conjunction() -> Matcher {
            var matchers: [Matcher] = []
            while let operand = operand() {
                matchers.append(operand)
            }
            return .all(matchers)
        }

        /// One path, one negation, or one parenthesised group.
        private mutating func operand() -> Matcher? {
            switch token {
            case .minus:
                advance()
                guard let inner = operand() else { return .any([]) }
                return .negated(inner)
            case .open:
                advance()
                let inner = inner()
                if token == .close { advance() }
                return inner
            case .identifier:
                var identifiers: [String] = []
                while case .identifier(let name) = token {
                    identifiers.append(name)
                    advance()
                }
                return .path(identifiers)
            default:
                return nil
            }
        }

        /// The body of a group: conjunctions separated by `|` or by `,`,
        /// any one of which is enough.
        private mutating func inner() -> Matcher {
            var matchers: [Matcher] = []
            while true {
                matchers.append(conjunction())
                guard token == .pipe || token == .comma else { break }
                while token == .pipe || token == .comma { advance() }
            }
            return .any(matchers)
        }

        /// Splits a selector into tokens, skipping anything the language has
        /// no place for.
        static func scan(_ text: String) -> [Token] {
            var result: [Token] = []
            let characters = Array(text)
            var cursor = 0
            while cursor < characters.count {
                if cursor + 1 < characters.count, characters[cursor + 1] == ":" {
                    if characters[cursor] == "L" {
                        result.append(.priority(.before))
                        cursor += 2
                        continue
                    }
                    if characters[cursor] == "R" {
                        result.append(.priority(.after))
                        cursor += 2
                        continue
                    }
                }

                let character = characters[cursor]
                if isIdentifierStart(character) {
                    var name = ""
                    while cursor < characters.count, isIdentifierBody(characters[cursor]) {
                        name.append(characters[cursor])
                        cursor += 1
                    }
                    result.append(.identifier(name))
                    continue
                }

                cursor += 1
                switch character {
                case ",": result.append(.comma)
                case "|": result.append(.pipe)
                case "-": result.append(.minus)
                case "(": result.append(.open)
                case ")": result.append(.close)
                default: continue
                }
            }
            return result
        }

        private static func isIdentifierStart(_ character: Character) -> Bool {
            character == "." || character == ":" || isWord(character)
        }

        private static func isIdentifierBody(_ character: Character) -> Bool {
            character == "-" || isIdentifierStart(character)
        }

        private static func isWord(_ character: Character) -> Bool {
            character == "_" || (character.isASCII && (character.isLetter || character.isNumber))
        }
    }
}
