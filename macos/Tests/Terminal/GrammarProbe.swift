import Foundation
@testable import Ghostty

/// Drives ``GrammarTokenizer`` over a whole source string so a test can ask
/// what colour a byte came out.
///
/// The tokenizer's contract is one line at a time with the state carried
/// across, which is exactly right for an editor and tiresome to write by
/// hand in every test. This walks the lines, keeps the state, and answers
/// questions by byte offset.
struct GrammarProbe {
    struct Line {
        let text: String
        let bytes: [UInt8]
        let spans: [GrammarTokenizer.Span]
        let state: TokenizerState

        /// The span covering a byte offset, or nil when nothing does.
        func span(at offset: Int) -> GrammarTokenizer.Span? {
            spans.first { $0.range.contains(offset) }
        }

        func range(at offset: Int) -> Range<Int>? {
            span(at: offset)?.range
        }

        /// The whole scope stack over a byte offset, outermost first.
        func scopes(at offset: Int) -> [String] {
            span(at: offset)?.scopes ?? []
        }

        /// The innermost scope over a byte offset.
        func scope(at offset: Int) -> String? {
            span(at: offset)?.scopes.last
        }

        func kind(at offset: Int) -> TokenKind {
            ScopeTheme.standard.kind(for: scopes(at: offset))
        }

        func text(at offset: Int) -> String? {
            guard let range = range(at: offset) else { return nil }
            return String(bytes: bytes[range], encoding: .utf8)
        }

        /// Every span carrying a scope, innermost or not.
        func spans(under scope: String) -> [GrammarTokenizer.Span] {
            spans.filter { $0.scopes.contains(scope) }
        }

        /// The byte offset the given text starts at, which keeps a test
        /// from counting UTF-8 bytes by hand.
        func offset(of needle: String) -> Int? {
            let target = Array(needle.utf8)
            guard !target.isEmpty, bytes.count >= target.count else { return nil }
            let starts = 0...(bytes.count - target.count)
            return starts.first { Array(bytes[$0..<($0 + target.count)]) == target }
        }
    }

    let tokenizer: GrammarTokenizer

    init(tokenizer: GrammarTokenizer) {
        self.tokenizer = tokenizer
    }

    /// A probe over grammars given as JSON text, which is how the engine
    /// receives them from an extension.
    init?(scope: String, grammars: [String]) {
        let store = GrammarStore()
        for text in grammars {
            guard let grammar = Grammar.parse(Data(text.utf8)) else { return nil }
            store.add(grammar)
        }
        guard let tokenizer = GrammarTokenizer(store: store, scopeName: scope) else { return nil }
        self.tokenizer = tokenizer
    }

    init?(store: GrammarStore, scope: String) {
        guard let tokenizer = GrammarTokenizer(store: store, scopeName: scope) else { return nil }
        self.tokenizer = tokenizer
    }

    func lines(of source: String) -> [Line] {
        var state = tokenizer.initialState
        var result: [Line] = []
        for text in source.components(separatedBy: "\n") {
            let outcome = tokenizer.tokenize(text, state: state)
            state = outcome.state
            result.append(Line(text: text, bytes: Array(text.utf8), spans: outcome.spans, state: state))
        }
        return result
    }

    /// One line, tokenized from the document's initial state.
    func line(_ source: String) -> Line {
        lines(of: source)[0]
    }
}
