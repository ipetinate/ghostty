import Foundation
@testable import Ghostty
import Testing

/// The tokenizer state kept at the start of every coloured line, and what
/// an edit does to it.
///
/// Three lines, twenty-one UTF-16 units: `/* open` at 0, `middle` at 8 and
/// `let x` at 15. The comment opened on the first line is never closed, so
/// the third line is a comment only if the state made it that far.
struct LineTokenizationCacheTests {
    private static let source = "/* open\nmiddle\nlet x\n" as NSString
    private static let thirdLine = NSRange(location: 15, length: 6)

    private func cache(for highlighter: GrammarHighlighter) throws -> LineTokenizationCache {
        LineTokenizationCache(initialState: try #require(highlighter.initialState))
    }

    private func kind(_ tokens: [GrammarHighlighter.Token], at location: Int) -> TokenKind? {
        tokens.first { NSLocationInRange(location, $0.range) }?.kind
    }

    @Test func aBlockCommentOpenedAboveTheRangeIsStillOpen() throws {
        let highlighter = try FixtureGrammar.highlighter()
        let cache = try cache(for: highlighter)

        let tokens = cache.tokens(in: Self.source, range: Self.thirdLine, highlighter: highlighter)

        #expect(!tokens.isEmpty)
        #expect(tokens.allSatisfy { $0.kind == .comment })
        #expect(kind(tokens, at: 15) == .comment)
        #expect(cache.lineCount == 3)
    }

    @Test func linesAreFoundByBisection() throws {
        let highlighter = try FixtureGrammar.highlighter()
        let cache = try cache(for: highlighter)
        _ = cache.tokens(
            in: Self.source,
            range: NSRange(location: 0, length: Self.source.length),
            highlighter: highlighter
        )

        #expect(cache.lineIndex(containing: 0) == 0)
        #expect(cache.lineIndex(containing: 7) == 0)
        #expect(cache.lineIndex(containing: 8) == 1)
        #expect(cache.lineIndex(containing: 14) == 1)
        #expect(cache.lineIndex(containing: 15) == 2)
        #expect(cache.lineIndex(containing: 100) == 2)
    }

    @Test func anEditForgetsTheLinesBelowItAndKeepsTheOnesAbove() throws {
        let highlighter = try FixtureGrammar.highlighter()
        let cache = try cache(for: highlighter)
        _ = cache.tokens(
            in: Self.source,
            range: NSRange(location: 0, length: Self.source.length),
            highlighter: highlighter
        )
        #expect(cache.lineCount == 3)

        cache.invalidate(from: 8)

        #expect(cache.lineCount == 2)
        #expect(cache.lineIndex(containing: 8) == 1)
        #expect(cache.lineIndex(containing: 20) == 1)

        let edited = "/* open\n*/ mid\nlet x\n" as NSString
        let tokens = cache.tokens(in: edited, range: Self.thirdLine, highlighter: highlighter)

        #expect(tokens.map(\.kind) == [.keyword])
        #expect(tokens.first?.range == NSRange(location: 15, length: 3))
        #expect(cache.lineCount == 3)
    }

    /// The line holding the edit keeps the state it *started* in, because
    /// nothing above it changed. A caller that edits line one and invalidates
    /// from line two is therefore left with line two's old start state,
    /// which is the contract and the reason the caller passes the edit's own
    /// location.
    @Test func theEditedLineKeepsItsStartState() throws {
        let highlighter = try FixtureGrammar.highlighter()
        let cache = try cache(for: highlighter)
        _ = cache.tokens(
            in: Self.source,
            range: NSRange(location: 0, length: Self.source.length),
            highlighter: highlighter
        )

        let noLongerOpen = "// open\nmiddle\nlet x\n" as NSString

        cache.invalidate(from: 8)
        let stale = cache.tokens(in: noLongerOpen, range: Self.thirdLine, highlighter: highlighter)
        #expect(kind(stale, at: 15) == .comment)

        cache.invalidate(from: 0)
        let fresh = cache.tokens(in: noLongerOpen, range: Self.thirdLine, highlighter: highlighter)
        #expect(fresh.map(\.kind) == [.keyword])
    }

    @Test func invalidatingBeyondTheCachedPrefixChangesNothing() throws {
        let highlighter = try FixtureGrammar.highlighter()
        let cache = try cache(for: highlighter)
        _ = cache.tokens(in: Self.source, range: NSRange(location: 0, length: 8), highlighter: highlighter)
        #expect(cache.lineCount == 2)

        cache.invalidate(from: 500)

        #expect(cache.lineCount == 2)
    }

    /// Seeding is for a document too large to walk from the top: the first
    /// visible line starts from the initial state, so the comment opened
    /// above the viewport is not seen — and nothing is learned about the
    /// lines that were skipped.
    @Test func seedingBehindTheCacheStartsTheVisibleLineClean() throws {
        let highlighter = try FixtureGrammar.highlighter()

        let seeded = try cache(for: highlighter)
        let tokens = seeded.tokens(
            in: Self.source,
            range: Self.thirdLine,
            highlighter: highlighter,
            seedWhenBehind: true
        )
        #expect(tokens.map(\.kind) == [.keyword])
        #expect(tokens.first?.range == NSRange(location: 15, length: 3))
        #expect(seeded.lineCount == 1)

        let walked = try cache(for: highlighter)
        let carried = walked.tokens(in: Self.source, range: Self.thirdLine, highlighter: highlighter)
        #expect(carried.allSatisfy { $0.kind == .comment })
        #expect(walked.lineCount == 3)
    }

    /// Seeding only applies when the range starts *past* what the cache
    /// knows. A range inside the cached prefix is answered from the prefix.
    @Test func seedingDoesNotApplyInsideTheCachedPrefix() throws {
        let highlighter = try FixtureGrammar.highlighter()
        let cache = try cache(for: highlighter)
        _ = cache.tokens(
            in: Self.source,
            range: NSRange(location: 0, length: Self.source.length),
            highlighter: highlighter
        )

        let tokens = cache.tokens(
            in: Self.source,
            range: Self.thirdLine,
            highlighter: highlighter,
            seedWhenBehind: true
        )

        #expect(tokens.allSatisfy { $0.kind == .comment })
    }

    @Test func aPlainHighlighterProducesNoTokens() throws {
        let cache = try cache(for: try FixtureGrammar.highlighter())

        let tokens = cache.tokens(
            in: Self.source,
            range: NSRange(location: 0, length: Self.source.length),
            highlighter: .plain
        )

        #expect(tokens.isEmpty)
    }

    @Test func aResetForgetsEveryLine() throws {
        let highlighter = try FixtureGrammar.highlighter()
        let cache = try cache(for: highlighter)
        _ = cache.tokens(
            in: Self.source,
            range: NSRange(location: 0, length: Self.source.length),
            highlighter: highlighter
        )
        #expect(cache.lineCount == 3)

        cache.reset(initialState: try #require(highlighter.initialState))

        #expect(cache.lineCount == 1)
    }
}
