import Foundation
@testable import Ghostty
import Testing

/// What the parser accepts, and what it quietly ignores.
///
/// The bargain is stated in ``Grammar``: strict about the shape it needs,
/// lenient about everything else. A grammar written for another editor
/// carries folding markers, comments and hints this engine has no use for,
/// and refusing the file over one of them would mean refusing most of the
/// grammars that exist.
struct GrammarParsingTests {
    private func grammar(_ json: String) -> Grammar? {
        Grammar.parse(Data(json.utf8))
    }

    // MARK: - the document

    @Test func readsTheKeysItNeeds() throws {
        let parsed = try #require(grammar("""
        {
          "name": "Thing",
          "scopeName": "source.thing",
          "fileTypes": ["th", ".THX"],
          "firstLineMatch": "^#!/.*thing",
          "patterns": [{ "name": "keyword.control", "match": "x" }],
          "repository": { "word": { "name": "string.quoted", "match": "y" } }
        }
        """))

        #expect(parsed.scopeName == "source.thing")
        #expect(parsed.name == "Thing")
        #expect(parsed.fileTypes == ["th", "thx"])
        #expect(parsed.firstLineMatch == "^#!/.*thing")
        #expect(parsed.patterns.count == 1)
        #expect(parsed.repository.count == 1)
    }

    @Test func refusesADocumentWithNoScopeName() {
        #expect(grammar(#"{ "patterns": [] }"#) == nil)
        #expect(grammar(#"{ "scopeName": "" }"#) == nil)
        #expect(grammar("[]") == nil)
        #expect(grammar("not json") == nil)
    }

    @Test func acceptsAGrammarWithNoPatterns() throws {
        let parsed = try #require(grammar(#"{ "scopeName": "source.empty" }"#))
        #expect(parsed.patterns.isEmpty)
        #expect(parsed.repository.isEmpty)
        #expect(parsed.injections.isEmpty)
    }

    @Test func ignoresKeysItDoesNotKnow() throws {
        let parsed = try #require(grammar("""
        {
          "scopeName": "source.thing",
          "foldingStartMarker": "\\\\{\\\\s*$",
          "foldingStopMarker": "^\\\\s*\\\\}",
          "uuid": "0F0B9AA7",
          "comment": "written for a different editor",
          "patterns": [
            { "name": "keyword.control", "match": "x", "comment": "a note", "hidden": true }
          ]
        }
        """))

        #expect(parsed.patterns.count == 1)
        #expect(parsed.patterns[0].name == "keyword.control")
    }

    // MARK: - the rules

    @Test func readsTheFourRuleShapes() throws {
        let parsed = try #require(grammar("""
        {
          "scopeName": "source.thing",
          "patterns": [
            { "match": "a" },
            { "begin": "b", "end": "c" },
            { "begin": "d", "while": "e" },
            { "include": "#f" },
            { "patterns": [{ "match": "g" }] }
          ]
        }
        """))

        #expect(parsed.patterns.count == 5)
        if case .match(let pattern) = parsed.patterns[0].kind {
            #expect(pattern == "a")
        } else {
            Issue.record("expected a match rule")
        }
        if case .beginEnd(let begin, let end) = parsed.patterns[1].kind {
            #expect(begin == "b")
            #expect(end == "c")
        } else {
            Issue.record("expected a begin/end rule")
        }
        if case .beginWhile(let begin, let continuation) = parsed.patterns[2].kind {
            #expect(begin == "d")
            #expect(continuation == "e")
        } else {
            Issue.record("expected a begin/while rule")
        }
        if case .include(let reference) = parsed.patterns[3].kind {
            #expect(reference == "#f")
        } else {
            Issue.record("expected an include rule")
        }
        if case .group = parsed.patterns[4].kind {
            #expect(parsed.patterns[4].patterns.count == 1)
        } else {
            Issue.record("expected a container rule")
        }
    }

    /// A malformed rule goes on its own. The grammar around it still
    /// colours, which is the difference between one broken pattern and a
    /// language that does not work.
    @Test func dropsAMalformedRuleAndKeepsTheRest() throws {
        let parsed = try #require(grammar("""
        {
          "scopeName": "source.thing",
          "patterns": [
            { "begin": "no end and no while" },
            { "name": "nothing to match" },
            "a string where a rule should be",
            { "include": "" },
            { "name": "keyword.control", "match": "x" }
          ]
        }
        """))

        #expect(parsed.patterns.count == 1)
        #expect(parsed.patterns[0].name == "keyword.control")
    }

    @Test func skipsADisabledRule() throws {
        let parsed = try #require(grammar("""
        {
          "scopeName": "source.thing",
          "patterns": [
            { "match": "a", "disabled": 1 },
            { "match": "b", "disabled": true },
            { "match": "c", "disabled": 0 }
          ]
        }
        """))

        #expect(parsed.patterns.count == 1)
        if case .match(let pattern) = parsed.patterns[0].kind {
            #expect(pattern == "c")
        } else {
            Issue.record("expected a match rule")
        }
    }

    /// `captures` on a `begin`/`end` rule means both ends of it, which is
    /// how most grammars colour a delimiter pair with one key.
    @Test func readsCapturesOnBothEndsOfARegion() throws {
        let parsed = try #require(grammar("""
        {
          "scopeName": "source.thing",
          "patterns": [
            { "begin": "a", "end": "b", "captures": { "0": { "name": "punctuation.section" } } },
            {
              "begin": "c",
              "end": "d",
              "captures": { "0": { "name": "shared" } },
              "endCaptures": { "0": { "name": "own" } }
            }
          ]
        }
        """))

        #expect(parsed.patterns[0].beginCaptures[0]?.name == "punctuation.section")
        #expect(parsed.patterns[0].endCaptures[0]?.name == "punctuation.section")
        #expect(parsed.patterns[1].beginCaptures[0]?.name == "shared")
        #expect(parsed.patterns[1].endCaptures[0]?.name == "own")
    }

    @Test func dropsACaptureThatAsksForNothing() throws {
        let parsed = try #require(grammar("""
        {
          "scopeName": "source.thing",
          "patterns": [
            {
              "match": "(a)(b)(c)",
              "captures": {
                "1": { "name": "keyword.control" },
                "2": {},
                "three": { "name": "string.quoted" }
              }
            }
          ]
        }
        """))

        #expect(parsed.patterns[0].captures.count == 1)
        #expect(parsed.patterns[0].captures[1]?.name == "keyword.control")
    }

    @Test func readsApplyEndPatternLast() throws {
        let parsed = try #require(grammar("""
        {
          "scopeName": "source.thing",
          "patterns": [
            { "begin": "a", "end": "b", "applyEndPatternLast": 1 },
            { "begin": "c", "end": "d" }
          ]
        }
        """))

        #expect(parsed.patterns[0].applyEndPatternLast)
        #expect(!parsed.patterns[1].applyEndPatternLast)
    }

    /// A rule that matches nothing itself may declare a `repository`, and
    /// the rules under it then see those keys ahead of the grammar's.
    ///
    /// The shadowing is what makes it worth reading: HTML's `svg` key
    /// declares its own `attribute`, and the grammar has one under that
    /// name too.
    @Test func readsARepositoryARuleDeclaredForItself() throws {
        let parsed = try #require(grammar("""
        {
          "scopeName": "source.thing",
          "patterns": [{ "include": "#outer" }],
          "repository": {
            "attribute": { "name": "keyword.control", "match": "a" },
            "outer": {
              "patterns": [{ "include": "#attribute" }],
              "repository": {
                "attribute": { "name": "string.quoted", "match": "b" }
              }
            }
          }
        }
        """))

        let outer = try #require(parsed.repository["outer"])
        #expect(outer.ownRepository["attribute"]?.name == "string.quoted")
        #expect(outer.scopedRepository?["attribute"]?.name == "string.quoted")
        #expect(outer.patterns[0].scopedRepository?["attribute"]?.name == "string.quoted")

        let shared = try #require(parsed.repository["attribute"])
        #expect(shared.ownRepository.isEmpty)
        #expect(shared.scopedRepository == nil)
    }

    // MARK: - injections

    @Test func readsAnInjectionAndItsPriority() throws {
        let parsed = try #require(grammar("""
        {
          "scopeName": "source.thing",
          "injections": {
            "L:source.thing string": { "patterns": [{ "match": "a" }] },
            "R:source.thing comment": { "patterns": [{ "match": "b" }] },
            "source.thing meta": { "patterns": [{ "match": "c" }] }
          }
        }
        """))

        #expect(parsed.injections.count == 3)
        #expect(parsed.injections.map(\.selector.priority) == [.before, .normal, .after])
    }

    @Test func dropsAnInjectionWithNoPatterns() throws {
        let parsed = try #require(grammar("""
        {
          "scopeName": "source.thing",
          "injections": { "source.thing": { "patterns": [] } }
        }
        """))

        #expect(parsed.injections.isEmpty)
    }

    /// One key may name several alternatives, and each carries its own
    /// priority. PHP's is written that way and reading it as one selector
    /// with one priority is what left a `.php` file unpainted.
    @Test func readsEveryAlternativeOfOneInjectionKey() throws {
        let parsed = try #require(grammar("""
        {
          "scopeName": "text.html.thing",
          "injections": {
            "text.html.thing - (meta.embedded | meta.tag), L:(source.js - meta.embedded)": {
              "patterns": [{ "match": "a" }]
            }
          }
        }
        """))

        #expect(parsed.injections.count == 2)
        #expect(parsed.injections.map(\.selector.priority) == [.before, .normal])
        #expect(parsed.injections[0].rule === parsed.injections[1].rule)
    }

    /// A grammar that injects itself into somebody else's document says
    /// *where* with a top-level `injectionSelector`, and the manifest says
    /// *which* documents.
    @Test func readsTheSelectorAGrammarInjectsItselfBy() throws {
        let parsed = try #require(grammar("""
        {
          "scopeName": "thing.directives",
          "injectionSelector": "L:meta.tag -meta.attribute, L:meta.element",
          "patterns": [{ "match": "a" }]
        }
        """))

        #expect(parsed.injectionSelectors.count == 2)
        #expect(parsed.injectionSelectors.allSatisfy { $0.priority == .before })
        #expect(parsed.injectedRule.patterns.count == 1)
    }

    @Test func readsNoInjectionSelectorWhenTheGrammarWroteNone() throws {
        let parsed = try #require(grammar(#"{ "scopeName": "source.thing" }"#))

        #expect(parsed.injectionSelectors.isEmpty)
    }
}
