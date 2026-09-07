import Foundation

/// A scope stack, outermost first, shared between the spans that live under
/// it.
///
/// A persistent list rather than an array. Every span a tokenizer emits
/// carries the whole stack it was found under — that is what a theme reads
/// — and a line of ordinary code produces hundreds of spans that differ in
/// their innermost scope only. Pushing a scope allocates one node and every
/// span beneath it shares the tail, so the cost is one node per region
/// entered rather than one array per span.
final class ScopeStack {
    let scope: String
    let parent: ScopeStack?
    let depth: Int

    /// The stack as an array, outermost first.
    ///
    /// Built when the node is, and then shared. Two spans found under the
    /// same stack get the same array, so carrying it costs a retain rather
    /// than a copy — and building it up front rather than on first use
    /// keeps a state that has crossed to another thread from racing on it.
    /// A node is made once per region entered, not once per span, so the
    /// work is small either way.
    let names: [String]

    init(root: String) {
        self.scope = root
        self.parent = nil
        self.depth = 1
        self.names = [root]
    }

    private init(scope: String, parent: ScopeStack) {
        self.scope = scope
        self.parent = parent
        self.depth = parent.depth + 1
        self.names = parent.names + [scope]
    }

    /// The stack with the rule's scopes on top, or this stack unchanged
    /// when the rule named none.
    ///
    /// A `name` may hold **several scopes, separated by spaces**, and each
    /// one goes on the stack. TextMate grammars use it to say two things at
    /// once, and the second thing is usually the one a theme reads:
    /// TypeScript names a function `"meta.definition.function.ts
    /// entity.name.function.ts"`, JSON names an object key
    /// `"string.quoted.double.json support.type.property-name.json"`, and
    /// Kotlin, Swift and PHP write most of their declarations that way.
    /// Pushed whole, the string matches no prefix a theme knows and the span
    /// came out unpainted — which is why function names, PHP keywords and
    /// YAML keys were plain text.
    func pushing(_ scope: String?) -> ScopeStack {
        guard let scope, !scope.isEmpty else { return self }
        guard scope.contains(where: { $0.isWhitespace }) else {
            return ScopeStack(scope: scope, parent: self)
        }
        var stack = self
        for part in scope.split(whereSeparator: { $0.isWhitespace }) {
            stack = ScopeStack(scope: String(part), parent: stack)
        }
        return stack
    }
}

extension ScopeStack: Equatable {
    static func == (lhs: ScopeStack, rhs: ScopeStack) -> Bool {
        if lhs === rhs { return true }
        guard lhs.depth == rhs.depth, lhs.scope == rhs.scope else { return false }
        switch (lhs.parent, rhs.parent) {
        case (nil, nil): return true
        case (let left?, let right?): return left == right
        default: return false
        }
    }
}

/// Where a line left the tokenizer, and therefore where the next line
/// starts.
///
/// This is the whole reason the engine is per line. The old highlighter had
/// no state, so an edit had to guess how far below it the colouring could
/// have changed and repaint a padded window. With a state per line the
/// answer stops being a guess: re-tokenize downwards from the edited line
/// and stop as soon as a line's outgoing state equals the one already
/// stored, because from there nothing below can differ.
///
/// That is what ``Equatable`` is for here. It is not a convenience.
struct TokenizerState {
    /// One open region: the rule that opened it, the grammar that rule
    /// belongs to, and the scopes in force inside it.
    struct Frame {
        let rule: GrammarRule
        let grammar: Grammar

        /// The `end` or `while` pattern, with any backreference to the
        /// `begin` match already substituted. Held as text because the
        /// substitution makes it particular to this region.
        let closing: String?

        /// Whether `closing` is a `while` pattern, which is tested at the
        /// start of every later line rather than searched for within one.
        let isWhile: Bool

        /// The scopes after the rule's `name`, which the `begin` and `end`
        /// matches are coloured under.
        let nameScopes: ScopeStack

        /// The scopes after the rule's `contentName` as well, which the
        /// region's body is coloured under.
        let contentScopes: ScopeStack

        /// False on the line the region opened, true on every line after.
        /// A `while` pattern is only tested once the region has survived a
        /// line boundary.
        var carried: Bool

        /// The byte offset a **zero-width** `begin` match opened this region
        /// at, and -1 for a `begin` that consumed something or for a region
        /// that has been carried to another line.
        ///
        /// Kept so the scanner can recognise the one region it must refuse:
        /// the one whose `begin` and `end` are both zero-width at one
        /// offset, which would push and pop there for as long as anybody let
        /// it. A `begin` that consumed text cannot do that, however empty
        /// its `end` match is, so it is not recorded here — see
        /// `closeRegion`.
        var emptyEntry: Int
    }

    /// The document's own scope, under everything.
    let root: ScopeStack

    /// Open regions, outermost first.
    var frames: [Frame]

    static func initial(scopeName: String) -> TokenizerState {
        TokenizerState(root: ScopeStack(root: scopeName), frames: [])
    }

    /// The scopes a span at the current position would carry.
    var scopes: [String] {
        (frames.last?.contentScopes ?? root).names
    }

    /// How many regions are open. Zero means the line ended at the top
    /// level of the document.
    var depth: Int { frames.count }

    var isInitial: Bool { frames.isEmpty }
}

extension TokenizerState.Frame: Equatable {
    static func == (lhs: TokenizerState.Frame, rhs: TokenizerState.Frame) -> Bool {
        lhs.rule === rhs.rule
            && lhs.grammar === rhs.grammar
            && lhs.closing == rhs.closing
            && lhs.isWhile == rhs.isWhile
            && lhs.contentScopes == rhs.contentScopes
            && lhs.nameScopes == rhs.nameScopes
    }
}

extension TokenizerState: Equatable {
    /// `carried` and `emptyEntry` are deliberately not compared. They say
    /// where on a line the frame was opened, not what the frame is, and a
    /// state handed to the next line has both of them settled — so two
    /// states that differ only in them cannot exist at a line boundary.
    static func == (lhs: TokenizerState, rhs: TokenizerState) -> Bool {
        lhs.root == rhs.root && lhs.frames == rhs.frames
    }
}
