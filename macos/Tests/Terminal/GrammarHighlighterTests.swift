import Foundation
@testable import Ghostty
import Testing

/// The seam where the tokenizer's UTF-8 bytes become the editor's UTF-16
/// ranges and its scope names become the theme's kinds.
struct GrammarHighlighterTests {
    private func tokens(_ text: String, highlighter: GrammarHighlighter) -> [GrammarHighlighter.Token] {
        highlighter.tokens(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    private func kind(_ tokens: [GrammarHighlighter.Token], at location: Int) -> TokenKind? {
        tokens.first { NSLocationInRange(location, $0.range) }?.kind
    }

    // MARK: - Bytes become UTF-16 units

    /// The emoji is four bytes and two UTF-16 units. A range that carried the
    /// byte offset would paint two characters to the right of the keyword.
    @Test func aKeywordAfterAnEmojiLandsAtItsUTF16Index() throws {
        let highlighter = try FixtureGrammar.highlighter()
        let text = "🎉 let x"

        let found = tokens(text, highlighter: highlighter)

        #expect(found.map(\.kind) == [.keyword])
        #expect(found.first?.range == NSRange(location: 3, length: 3))
        #expect((text as NSString).range(of: "let").location == 3)
        #expect(Array("🎉 ".utf8).count == 5)
    }

    @Test func utf16OffsetsCountUnitsAndNotBytes() {
        var offsets = UTF16Offsets(bytes: Array("é🎉x".utf8))

        #expect(offsets.units(before: 0) == 0)
        #expect(offsets.units(before: 2) == 1)
        #expect(offsets.units(before: 6) == 3)
        #expect(offsets.units(before: 7) == 4)
        #expect("é🎉x".utf16.count == 4)
    }

    @Test func utf16OffsetsClampAndRestartWhenAskedBackwards() {
        var offsets = UTF16Offsets(bytes: Array("é🎉x".utf8))

        #expect(offsets.units(before: 99) == 4)
        #expect(offsets.units(before: -1) == 0)
        #expect(offsets.units(before: 6) == 3)
        #expect(offsets.units(before: 2) == 1)
    }

    @Test func aLineTokenizedAloneIsPlacedAtItsOffset() throws {
        let highlighter = try FixtureGrammar.highlighter()
        let state = try #require(highlighter.initialState)

        let closed = highlighter.tokens(inLine: Array("let x\n".utf8), at: 100, state: state)
        #expect(closed.tokens.map(\.range) == [NSRange(location: 100, length: 3)])
        #expect(closed.tokens.map(\.kind) == [.keyword])
        #expect(closed.state == state)

        let opened = highlighter.tokens(inLine: Array("/* open\n".utf8), at: 0, state: state)
        #expect(opened.state.depth == 1)
        #expect(opened.state != state)
    }

    // MARK: - Scopes become kinds

    @Test func eachRuleOfTheFixtureComesOutAsItsKind() throws {
        let highlighter = try FixtureGrammar.highlighter()
        let text = #"let s = "a\"b" // note"#

        let found = tokens(text, highlighter: highlighter)

        #expect(kind(found, at: 0) == .keyword)
        #expect(kind(found, at: 4) == nil)
        #expect(kind(found, at: 8) == .string)
        #expect(kind(found, at: 10) == .string)
        #expect(kind(found, at: 13) == .string)
        #expect(kind(found, at: 15) == .comment)
        #expect(kind(found, at: 21) == .comment)
    }

    @Test func plainSpansAreNotEmitted() throws {
        let highlighter = try FixtureGrammar.highlighter()

        let found = tokens("alpha beta", highlighter: highlighter)

        #expect(found.isEmpty)
    }

    // MARK: - The range

    /// The whole text is tokenized from the top so a construct opened above
    /// the range is known to be open. Only the tokens in the range come back.
    @Test func aRangeIsColouredWithWhatOpenedAboveIt() throws {
        let highlighter = try FixtureGrammar.highlighter()
        let text = "/* a\nb\nc */ let x"
        let lastLine = NSRange(location: 7, length: 10)

        let found = highlighter.tokens(in: text, range: lastLine)

        #expect(kind(found, at: 7) == .comment)
        #expect(kind(found, at: 10) == .comment)
        #expect(kind(found, at: 12) == .keyword)
        #expect(kind(found, at: 16) == nil)
        #expect(found.allSatisfy { NSIntersectionRange($0.range, lastLine) == $0.range })
    }

    @Test func tokensAreClippedToTheRangeAsked() throws {
        let highlighter = try FixtureGrammar.highlighter()
        let middle = NSRange(location: 3, length: 3)

        let found = highlighter.tokens(in: "/* abc */", range: middle)

        #expect(!found.isEmpty)
        #expect(found.allSatisfy { $0.kind == .comment })
        #expect(found.allSatisfy { NSIntersectionRange($0.range, middle) == $0.range })
    }

    @Test func aRangePastTheEndYieldsNothing() throws {
        let highlighter = try FixtureGrammar.highlighter()

        #expect(highlighter.tokens(in: "let x", range: NSRange(location: 10, length: 5)).isEmpty)
        #expect(highlighter.tokens(in: "let x", range: NSRange(location: 0, length: 0)).isEmpty)
        #expect(highlighter.tokens(in: "", range: NSRange(location: 0, length: 5)).isEmpty)
    }

    // MARK: - Plain

    @Test func thePlainHighlighterColoursNothingAndSaysSo() throws {
        let plain = GrammarHighlighter.plain

        #expect(plain.isPlain)
        #expect(plain.initialState == nil)
        #expect(tokens("let x // y", highlighter: plain).isEmpty)
        #expect(!(try FixtureGrammar.highlighter()).isPlain)
    }
}
