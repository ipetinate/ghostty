import Foundation
@testable import Ghostty
import Testing

/// The engine's own rules, on grammars small enough to read.
///
/// The proof that it colours a real language is `ElixirGrammarTests`. This
/// file is the mechanics underneath: the four rule shapes, the way captures
/// nest, and the four things that are easy to get wrong and silent when
/// they are — byte offsets, `\G`, a backreference in an `end`, and a match
/// that consumes nothing.
struct GrammarTokenizerTests {
    // MARK: - match

    @Test func paintsAMatchRuleAndLeavesTheRestAlone() throws {
        let probe = try #require(GrammarProbe(scope: "source.t", grammars: [
            """
            {
              "scopeName": "source.t",
              "patterns": [{ "name": "keyword.control", "match": "\\\\bif\\\\b" }]
            }
            """,
        ]))

        let line = probe.line("x if y")
        #expect(line.range(at: 2) == 2..<4)
        #expect(line.scopes(at: 2) == ["source.t", "keyword.control"])
        #expect(line.scopes(at: 0) == ["source.t"])
        #expect(line.kind(at: 2) == .keyword)
        #expect(line.kind(at: 0) == .plain)
    }

    /// Offsets are UTF-8 bytes the whole way. The caller converts once, when
    /// it paints; anything here that counted characters would be wrong by
    /// exactly the number of accents above it.
    ///
    /// The same token starts at 14 in UTF-16, which is what an `NSRange`
    /// counts. Four of difference is what a caller that read a byte offset
    /// as a character offset would paint wrong.
    @Test func countsInBytesThroughAccentsAndEmoji() throws {
        let probe = try #require(GrammarProbe(scope: "source.t", grammars: [
            """
            {
              "scopeName": "source.t",
              "patterns": [{ "name": "keyword.control", "match": "fim" }]
            }
            """,
        ]))

        let line = probe.line("acentuação 🎉 fim")
        #expect(line.range(at: 18) == 18..<21)
        #expect(line.text(at: 18) == "fim")
        #expect(line.scope(at: 18) == "keyword.control")
        #expect(("acentuação 🎉 fim" as NSString).range(of: "fim").location == 14)
    }

    @Test func tokenizesABlankLine() throws {
        let probe = try #require(GrammarProbe(scope: "source.t", grammars: [
            """
            {
              "scopeName": "source.t",
              "patterns": [{ "name": "keyword.control", "match": "x" }]
            }
            """,
        ]))

        let line = probe.line("")
        #expect(line.spans.isEmpty)
        #expect(line.state.isInitial)
    }

    // MARK: - begin/end

    @Test func carriesARegionAcrossLines() throws {
        let probe = try #require(GrammarProbe(scope: "source.doc", grammars: [
            """
            {
              "scopeName": "source.doc",
              "patterns": [
                { "name": "meta.doc", "contentName": "comment.block", "begin": "/\\\\*", "end": "\\\\*/" }
              ]
            }
            """,
        ]))

        let lines = probe.lines(of: "a /* b\nc */ d")

        #expect(lines[0].scopes(at: 2) == ["source.doc", "meta.doc"])
        #expect(lines[0].scopes(at: 4) == ["source.doc", "meta.doc", "comment.block"])
        #expect(lines[0].state.depth == 1)
        #expect(lines[0].state.scopes == ["source.doc", "meta.doc", "comment.block"])

        #expect(lines[1].scopes(at: 0) == ["source.doc", "meta.doc", "comment.block"])
        #expect(lines[1].scopes(at: 2) == ["source.doc", "meta.doc"])
        #expect(lines[1].range(at: 2) == 2..<4)
        #expect(lines[1].scopes(at: 5) == ["source.doc"])
        #expect(lines[1].state.isInitial)
    }

    @Test func leavesAnUnclosedRegionOpenAtTheEndOfTheLine() throws {
        let probe = try #require(GrammarProbe(scope: "source.doc", grammars: [
            """
            {
              "scopeName": "source.doc",
              "patterns": [{ "name": "comment.block", "begin": "/\\\\*", "end": "\\\\*/" }]
            }
            """,
        ]))

        let lines = probe.lines(of: "/* open\nstill open\nstill")
        #expect(lines.allSatisfy { $0.state.depth == 1 })
        #expect(lines[2].scopes(at: 0) == ["source.doc", "comment.block"])
    }

    /// The reason the engine needs Oniguruma rather than a table of
    /// languages. Lua's long bracket closes on the run of equals signs its
    /// opener used and on no other, and the only way a grammar can say that
    /// is `\1` in the `end`.
    @Test func recompilesAnEndPatternWithTheBeginMatchSubstituted() throws {
        let probe = try #require(GrammarProbe(scope: "source.lua", grammars: [
            """
            {
              "scopeName": "source.lua",
              "patterns": [
                { "name": "comment.block.lua", "begin": "--\\\\[(=*)\\\\[", "end": "\\\\]\\\\1\\\\]" }
              ]
            }
            """,
        ]))

        let lines = probe.lines(of: "--[==[ still open ]=]\nclosed here ]==] after")

        #expect(lines[0].range(at: 0) == 0..<21)
        #expect(lines[0].scope(at: 0) == "comment.block.lua")
        #expect(lines[0].state.depth == 1)

        #expect(lines[1].range(at: 0) == 0..<16)
        #expect(lines[1].scope(at: 0) == "comment.block.lua")
        #expect(lines[1].scopes(at: 17) == ["source.lua"])
        #expect(lines[1].state.isInitial)
    }

    @Test func closesTheRegionBeforeMatchingInsideIt() throws {
        let probe = try #require(GrammarProbe(scope: "source.t", grammars: [
            """
            {
              "scopeName": "source.t",
              "patterns": [
                {
                  "name": "string.quoted",
                  "begin": "\\"",
                  "end": "\\"",
                  "patterns": [{ "name": "invalid.illegal", "match": "\\"" }]
                }
              ]
            }
            """,
        ]))

        let line = probe.line("\"a\" b")
        #expect(line.range(at: 0) == 0..<3)
        #expect(line.scope(at: 0) == "string.quoted")
        #expect(line.state.isInitial)
    }

    /// Unless the rule asked for the opposite, in which case the child that
    /// matches at the same offset takes it and the region stays open.
    @Test func letsAChildWinTheOffsetWhenTheRuleAsksForIt() throws {
        func probe(applyEndPatternLast: Int) throws -> GrammarProbe {
            try #require(GrammarProbe(scope: "source.last", grammars: [
                """
                {
                  "scopeName": "source.last",
                  "patterns": [
                    {
                      "name": "meta.region",
                      "begin": "\\\\(",
                      "end": "\\\\)",
                      "applyEndPatternLast": \(applyEndPatternLast),
                      "patterns": [{ "name": "keyword.control", "match": "\\\\)\\\\)" }]
                    }
                  ]
                }
                """,
            ]))
        }

        let closed = try probe(applyEndPatternLast: 0).line("a (b)) c")
        #expect(closed.range(at: 2) == 2..<5)
        #expect(closed.scopes(at: 5) == ["source.last"])
        #expect(closed.state.isInitial)

        let open = try probe(applyEndPatternLast: 1).line("a (b)) c")
        #expect(open.range(at: 4) == 4..<6)
        #expect(open.scope(at: 4) == "keyword.control")
        #expect(open.state.depth == 1)
    }

    // MARK: - begin/while

    /// A `while` region continues onto the next line only while its pattern
    /// still matches at the top of it, and `\G` inside it anchors to where
    /// that match stopped. The second `first` on the line is not a keyword,
    /// which is the whole difference between `\G` and `^`.
    @Test func continuesAWhileRegionAndAnchorsTheContinuation() throws {
        let probe = try #require(GrammarProbe(scope: "source.quote", grammars: [
            """
            {
              "scopeName": "source.quote",
              "patterns": [
                {
                  "name": "markup.quote",
                  "begin": "^\\\\s*>\\\\s*",
                  "while": "^\\\\s*>\\\\s*",
                  "patterns": [{ "name": "keyword.control", "match": "\\\\Gfirst" }]
                }
              ]
            }
            """,
        ]))

        let lines = probe.lines(of: "> first word first\n> first again\nplain line")

        #expect(lines[0].range(at: 2) == 2..<7)
        #expect(lines[0].scope(at: 2) == "keyword.control")
        #expect(lines[0].scopes(at: 13) == ["source.quote", "markup.quote"])
        #expect(lines[0].state.depth == 1)

        #expect(lines[1].range(at: 2) == 2..<7)
        #expect(lines[1].scope(at: 2) == "keyword.control")

        #expect(lines[2].state.isInitial)
        #expect(lines[2].scopes(at: 0) == ["source.quote"])
    }

    // MARK: - captures

    /// A group that took part in no match is skipped, not read as an empty
    /// range at zero. Reading `(-1, -1)` as `0..<0` would paint the start of
    /// every line with whichever alternative did not fire.
    @Test func skipsAGroupThatTookPartInNoMatch() throws {
        let probe = try #require(GrammarProbe(scope: "source.alt", grammars: [
            """
            {
              "scopeName": "source.alt",
              "patterns": [
                {
                  "match": "(a)|(b)",
                  "captures": {
                    "1": { "name": "keyword.control" },
                    "2": { "name": "string.quoted" }
                  }
                }
              ]
            }
            """,
        ]))

        let line = probe.line("b a")
        #expect(line.scope(at: 0) == "string.quoted")
        #expect(line.scopes(at: 1) == ["source.alt"])
        #expect(line.scope(at: 2) == "keyword.control")
    }

    @Test func nestsCapturesInsideOneAnother() throws {
        let probe = try #require(GrammarProbe(scope: "source.nest", grammars: [
            """
            {
              "scopeName": "source.nest",
              "patterns": [
                {
                  "match": "((\\\\w+)\\\\.(\\\\w+))\\\\(",
                  "captures": {
                    "1": { "name": "meta.path" },
                    "2": { "name": "entity.name.type" },
                    "3": { "name": "entity.name.function" }
                  }
                }
              ]
            }
            """,
        ]))

        let line = probe.line("IO.puts(x)")
        #expect(line.scopes(at: 0) == ["source.nest", "meta.path", "entity.name.type"])
        #expect(line.scopes(at: 2) == ["source.nest", "meta.path"])
        #expect(line.scopes(at: 3) == ["source.nest", "meta.path", "entity.name.function"])
        #expect(line.range(at: 3) == 3..<7)
        #expect(line.scopes(at: 7) == ["source.nest"])
    }

    @Test func runsACapturesOwnPatternsOverItsText() throws {
        let probe = try #require(GrammarProbe(scope: "source.cap", grammars: [
            """
            {
              "scopeName": "source.cap",
              "patterns": [
                {
                  "match": "key\\\\((.*)\\\\)",
                  "captures": {
                    "1": {
                      "name": "meta.arg",
                      "patterns": [{ "name": "constant.numeric", "match": "\\\\d+" }]
                    }
                  }
                }
              ]
            }
            """,
        ]))

        let line = probe.line("key(a1b22c)")
        #expect(line.scopes(at: 4) == ["source.cap", "meta.arg"])
        #expect(line.scopes(at: 5) == ["source.cap", "meta.arg", "constant.numeric"])
        #expect(line.range(at: 7) == 7..<9)
        #expect(line.kind(at: 7) == .number)
    }

    /// Capture zero is the whole match, and a grammar names it when it wants
    /// the punctuation of a construct coloured separately from the
    /// construct.
    @Test func readsCaptureZeroAsTheWholeMatch() throws {
        let probe = try #require(GrammarProbe(scope: "source.t", grammars: [
            """
            {
              "scopeName": "source.t",
              "patterns": [
                { "match": "#\\\\{", "name": "meta.embedded", "captures": { "0": { "name": "punctuation.section" } } }
              ]
            }
            """,
        ]))

        let line = probe.line("a #{ b")
        #expect(line.scopes(at: 2) == ["source.t", "meta.embedded", "punctuation.section"])
        #expect(line.range(at: 2) == 2..<4)
        #expect(line.kind(at: 2) == .punctuation)
    }

    @Test func fillsAScopeNameFromACapture() throws {
        let probe = try #require(GrammarProbe(scope: "source.tag", grammars: [
            """
            {
              "scopeName": "source.tag",
              "patterns": [{ "name": "entity.name.tag.$1", "match": "<(\\\\w+)>" }]
            }
            """,
        ]))

        #expect(probe.line("<div>").scope(at: 0) == "entity.name.tag.div")
    }

    // MARK: - includes

    @Test func resolvesARepositoryInclude() throws {
        let probe = try #require(GrammarProbe(scope: "source.t", grammars: [
            """
            {
              "scopeName": "source.t",
              "patterns": [{ "include": "#word" }],
              "repository": {
                "word": { "name": "keyword.control", "match": "\\\\bgo\\\\b" }
              }
            }
            """,
        ]))

        #expect(probe.line("go on").scope(at: 0) == "keyword.control")
    }

    @Test func resolvesSelfInsideARegion() throws {
        let probe = try #require(GrammarProbe(scope: "source.t", grammars: [
            """
            {
              "scopeName": "source.t",
              "patterns": [
                { "name": "keyword.control", "match": "\\\\bgo\\\\b" },
                { "name": "meta.group", "begin": "\\\\(", "end": "\\\\)", "patterns": [{ "include": "$self" }] }
              ]
            }
            """,
        ]))

        let line = probe.line("go (go) go")
        #expect(line.scopes(at: 4) == ["source.t", "meta.group", "keyword.control"])
        #expect(line.scopes(at: 8) == ["source.t", "keyword.control"])
    }

    /// An `include` naming a grammar the store does not hold is dropped, and
    /// the rest of the grammar still colours. A grammar commonly reaches for
    /// a scope its author shipped in a second package.
    @Test func dropsAnIncludeItCannotResolve() throws {
        let probe = try #require(GrammarProbe(scope: "source.t", grammars: [
            """
            {
              "scopeName": "source.t",
              "patterns": [
                { "include": "source.nowhere" },
                { "include": "#missing" },
                { "name": "keyword.control", "match": "\\\\bgo\\\\b" }
              ]
            }
            """,
        ]))

        #expect(probe.line("go").scope(at: 0) == "keyword.control")
    }

    @Test func survivesAGrammarThatIncludesItself() throws {
        let probe = try #require(GrammarProbe(scope: "source.t", grammars: [
            """
            {
              "scopeName": "source.t",
              "patterns": [{ "include": "#loop" }],
              "repository": {
                "loop": { "patterns": [{ "include": "#loop" }, { "name": "keyword.control", "match": "x" }] }
              }
            }
            """,
        ]))

        #expect(probe.line("x").scope(at: 0) == "keyword.control")
    }

    // MARK: - across grammars

    /// The proof that a language can embed another one it does not ship:
    /// `source.inner` colours inside `source.outer`'s region, and `$base`
    /// inside the inner grammar reaches back out to the outer one rather
    /// than to itself.
    @Test func includesAnotherGrammarAndResolvesBaseThroughIt() throws {
        let probe = try #require(GrammarProbe(scope: "source.outer", grammars: [
            """
            {
              "scopeName": "source.outer",
              "patterns": [
                { "name": "keyword.control", "match": "\\\\bouter\\\\b" },
                {
                  "name": "meta.block",
                  "begin": "<<",
                  "end": ">>",
                  "patterns": [{ "include": "source.inner" }]
                }
              ]
            }
            """,
            """
            {
              "scopeName": "source.inner",
              "patterns": [
                { "name": "entity.name.function", "match": "\\\\binner\\\\b" },
                { "include": "$base" }
              ]
            }
            """,
        ]))

        let line = probe.line("outer << inner outer >> outer")
        #expect(line.scopes(at: 0) == ["source.outer", "keyword.control"])
        #expect(line.scopes(at: 9) == ["source.outer", "meta.block", "entity.name.function"])
        #expect(line.range(at: 9) == 9..<14)
        #expect(line.scopes(at: 15) == ["source.outer", "meta.block", "keyword.control"])
        #expect(line.scopes(at: 24) == ["source.outer", "keyword.control"])
    }

    @Test func resolvesAnIncludeIntoAnotherGrammarsRepository() throws {
        let probe = try #require(GrammarProbe(scope: "source.outer", grammars: [
            """
            {
              "scopeName": "source.outer",
              "patterns": [{ "include": "source.inner#word" }]
            }
            """,
            """
            {
              "scopeName": "source.inner",
              "repository": { "word": { "name": "keyword.control", "match": "x" } }
            }
            """,
        ]))

        #expect(probe.line("x").scope(at: 0) == "keyword.control")
    }

    // MARK: - injections

    @Test func appliesAnInjectionOverTheMatchedGrammar() throws {
        let probe = try #require(GrammarProbe(scope: "source.host", grammars: [
            """
            {
              "scopeName": "source.host",
              "patterns": [{ "name": "string.quoted.double", "begin": "\\"", "end": "\\"" }],
              "injections": {
                "L:source.host string.quoted": {
                  "patterns": [{ "name": "constant.character.escape", "match": "TODO" }]
                }
              }
            }
            """,
        ]))

        let line = probe.line(#"x "a TODO b" y"#)
        #expect(line.scopes(at: 5) == ["source.host", "string.quoted.double", "constant.character.escape"])
        #expect(line.range(at: 5) == 5..<9)
        #expect(line.scopes(at: 3) == ["source.host", "string.quoted.double"])
    }

    /// An injected `#key` is the repository of the grammar that declared
    /// the injection, not of the document. Both grammars here have a `mark`
    /// entry, the guest injects `#mark`, and the guest's is the one that has
    /// to answer.
    ///
    /// The injection is also only in play where its selector says: inside
    /// the host's own region, and not on the `TODO` after it.
    @Test func resolvesAnInjectionsIncludeInTheGrammarThatDeclaredIt() throws {
        let probe = try #require(GrammarProbe(
            scope: "source.host",
            grammars: [
                """
                {
                  "scopeName": "source.host",
                  "patterns": [{ "name": "meta.block", "begin": "<<", "end": ">>" }],
                  "repository": { "mark": { "name": "invalid.illegal", "match": "TODO" } }
                }
                """,
                """
                {
                  "scopeName": "source.guest",
                  "injectionSelector": "L:meta.block",
                  "patterns": [{ "include": "#mark" }],
                  "repository": { "mark": { "name": "constant.character.escape", "match": "TODO" } }
                }
                """,
            ],
            injectTo: ["source.guest": ["source.host"]]))

        let line = probe.line("<< TODO >> TODO")
        #expect(line.range(at: 3) == 3..<7)
        #expect(line.scopes(at: 3) == ["source.host", "meta.block", "constant.character.escape"])
        #expect(line.scopes(at: 11) == ["source.host"])
    }

    /// A grammar reaches somebody else's document only because a manifest
    /// asked. Without the `injectTo` half, the same two grammars leave the
    /// document alone.
    @Test func leavesAGrammarOutWhenNoManifestAskedForIt() throws {
        let probe = try #require(GrammarProbe(scope: "source.host", grammars: [
            """
            {
              "scopeName": "source.host",
              "patterns": [{ "name": "meta.block", "begin": "<<", "end": ">>" }]
            }
            """,
            """
            {
              "scopeName": "source.guest",
              "injectionSelector": "L:meta.block",
              "patterns": [{ "name": "constant.character.escape", "match": "TODO" }]
            }
            """,
        ]))

        #expect(probe.line("<< TODO >>").scopes(at: 3) == ["source.host", "meta.block"])
    }

    /// Injections are the **root** grammar's, and a grammar reached through
    /// an `include` contributes none of its own.
    ///
    /// The reference implementation reads them once, from the grammar the
    /// document started in, and PHP depends on it: `text.html.php` declares
    /// the rule that enters `<?php`, and `source.php` — which is only ever
    /// the guest — declares nothing. A guest allowed to inject into every
    /// host that includes it would enter a second embedded block inside the
    /// first.
    @Test func takesNoInjectionFromAGrammarItMerelyIncludes() throws {
        let probe = try #require(GrammarProbe(scope: "source.host", grammars: [
            """
            {
              "scopeName": "source.host",
              "patterns": [
                { "name": "meta.block", "begin": "<<", "end": ">>", "patterns": [{ "include": "source.guest" }] }
              ]
            }
            """,
            """
            {
              "scopeName": "source.guest",
              "patterns": [{ "name": "meta.guest", "begin": "\\\\[", "end": "\\\\]" }],
              "injections": {
                "L:meta.block": { "patterns": [{ "name": "constant.character.escape", "match": "TODO" }] }
              }
            }
            """,
        ]))

        #expect(probe.line("<< TODO >>").scopes(at: 3) == ["source.host", "meta.block"])
    }

    /// The shape PHP is coloured by: a selector that lets the injection
    /// into the document's shell and keeps it out of the region it opened
    /// there, so `<?php` cannot be entered twice.
    @Test func withdrawsAnInjectionFromTheRegionItOpened() throws {
        let probe = try #require(GrammarProbe(scope: "text.html.thing", grammars: [
            """
            {
              "scopeName": "text.html.thing",
              "patterns": [{ "name": "entity.name.tag", "match": "html" }],
              "injections": {
                "text.html.thing - meta.embedded": {
                  "patterns": [
                    {
                      "name": "meta.embedded.block.thing",
                      "begin": "<%",
                      "end": "%>",
                      "patterns": [{ "name": "keyword.control", "match": "if" }]
                    }
                  ]
                }
              }
            }
            """,
        ]))

        let line = probe.line("html <% if <% if %>")
        #expect(line.scopes(at: 0) == ["text.html.thing", "entity.name.tag"])
        #expect(line.scopes(at: 8) == ["text.html.thing", "meta.embedded.block.thing", "keyword.control"])
        #expect(line.scopes(at: 11) == ["text.html.thing", "meta.embedded.block.thing"])
        #expect(line.scopes(at: 14) == ["text.html.thing", "meta.embedded.block.thing", "keyword.control"])
    }

    /// `L:` takes a position the host also matches; a bare selector does
    /// not. Both rules match `TODO` at the same offset here, and the prefix
    /// is the whole of the difference.
    @Test func letsOnlyAnLInjectionWinAPositionTheHostAlsoMatched() throws {
        func probe(prefix: String) throws -> GrammarProbe {
            try #require(GrammarProbe(scope: "source.host", grammars: [
                """
                {
                  "scopeName": "source.host",
                  "patterns": [{ "name": "invalid.illegal", "match": "TODO" }],
                  "injections": {
                    "\(prefix)source.host": {
                      "patterns": [{ "name": "constant.character.escape", "match": "TODO" }]
                    }
                  }
                }
                """,
            ]))
        }

        #expect(try probe(prefix: "L:").line("x TODO").scope(at: 2) == "constant.character.escape")
        #expect(try probe(prefix: "").line("x TODO").scope(at: 2) == "invalid.illegal")
        #expect(try probe(prefix: "R:").line("x TODO").scope(at: 2) == "invalid.illegal")
    }

    /// An injection whose selector does not match the stack stays out of it.
    @Test func leavesAnInjectionOutWhenTheSelectorDoesNotMatch() throws {
        let probe = try #require(GrammarProbe(scope: "source.host", grammars: [
            """
            {
              "scopeName": "source.host",
              "patterns": [{ "name": "string.quoted.double", "begin": "\\"", "end": "\\"" }],
              "injections": {
                "L:source.host comment": {
                  "patterns": [{ "name": "constant.character.escape", "match": "TODO" }]
                }
              }
            }
            """,
        ]))

        let line = probe.line(#"x "a TODO b" y"#)
        #expect(line.scopes(at: 5) == ["source.host", "string.quoted.double"])
    }

    // MARK: - the guards

    /// A rule that consumes nothing would be picked again at the same
    /// position for ever. The lookahead here matches an empty span before
    /// `b`; the rule behind it has to get the position instead.
    @Test func doesNotLoopOnAMatchThatConsumesNothing() throws {
        let probe = try #require(GrammarProbe(scope: "source.empty", grammars: [
            """
            {
              "scopeName": "source.empty",
              "patterns": [
                { "name": "invalid.empty", "match": "(?=b)" },
                { "name": "keyword.control", "match": "b" }
              ]
            }
            """,
        ]))

        let line = probe.line("abc")
        #expect(line.scopes(at: 0) == ["source.empty"])
        #expect(line.scope(at: 1) == "keyword.control")
        #expect(line.range(at: 1) == 1..<2)
        #expect(line.scopes(at: 2) == ["source.empty"])
    }

    /// A region whose `begin` and `end` both match nothing opens and closes
    /// at one position without ever moving. The region is abandoned and the
    /// rest of the line comes out under what was around it, rather than the
    /// editor hanging on somebody else's grammar.
    @Test func abandonsARegionThatOpensAndClosesWithoutMoving() throws {
        let probe = try #require(GrammarProbe(scope: "source.spin", grammars: [
            """
            {
              "scopeName": "source.spin",
              "patterns": [{ "name": "meta.spin", "begin": "(?=a)", "end": "(?=a)" }]
            }
            """,
        ]))

        let line = probe.line("aaa")
        #expect(line.spans.map(\.range) == [0..<3])
        #expect(line.scopes(at: 0) == ["source.spin"])
        #expect(line.state.isInitial)
    }

    @Test func stopsPushingRegionsAtTheDepthCeiling() throws {
        let store = GrammarStore()
        let grammar = try #require(Grammar.parse(Data("""
        {
          "scopeName": "source.deep",
          "patterns": [
            { "name": "meta.deep", "begin": "a", "end": "zzzz", "patterns": [{ "include": "$self" }] }
          ]
        }
        """.utf8)))
        store.add(grammar)

        var limits = GrammarTokenizer.Limits.standard
        limits.depth = 4
        let tokenizer = GrammarTokenizer(store: store, grammar: grammar, limits: limits)
        let result = tokenizer.tokenize(String(repeating: "a", count: 40), state: tokenizer.initialState)
        #expect(result.state.depth == 4)
    }

    // MARK: - state

    /// The state is what lets a cache stop early: re-tokenize downwards from
    /// an edit and stop the moment a line's outgoing state equals the one
    /// already stored. That is the whole point of the type being
    /// `Equatable`, so it is worth a test of its own.
    @Test func reportsAnEqualStateForTwoLinesThatEndTheSameWay() throws {
        let probe = try #require(GrammarProbe(scope: "source.doc", grammars: [
            """
            {
              "scopeName": "source.doc",
              "patterns": [{ "name": "comment.block", "begin": "/\\\\*", "end": "\\\\*/" }]
            }
            """,
        ]))

        let lines = probe.lines(of: "/* one\ntwo\nthree */\nfour")
        #expect(lines[0].state == lines[1].state)
        #expect(lines[0].state != lines[2].state)
        #expect(lines[2].state == lines[3].state)
        #expect(lines[3].state == probe.tokenizer.initialState)
    }

    @Test func tellsTwoRegionsOfTheSameRuleApart() throws {
        let probe = try #require(GrammarProbe(scope: "source.lua", grammars: [
            """
            {
              "scopeName": "source.lua",
              "patterns": [{ "name": "comment.block", "begin": "\\\\[(=*)\\\\[", "end": "\\\\]\\\\1\\\\]" }]
            }
            """,
        ]))

        let one = probe.lines(of: "[=[ open")[0].state
        let two = probe.lines(of: "[==[ open")[0].state
        #expect(one != two)
        #expect(one == probe.lines(of: "[=[ also open")[0].state)
    }
}
