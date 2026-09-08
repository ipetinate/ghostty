import Foundation
@testable import Ghostty
import Testing

/// How the store joins the two halves of an injection.
///
/// A grammar's own `injections` arrive in the grammar file. A grammar that
/// wants its rules in somebody else's document needs both halves: the
/// selector it wrote at its top level, and its extension naming the target
/// in `contributes.grammars[].injectTo`. Neither half does anything alone,
/// and this is the only place they meet.
struct GrammarStoreTests {
    private func grammar(_ json: String) throws -> Grammar {
        try #require(Grammar.parse(Data(json.utf8)))
    }

    private let host = """
    {
      "scopeName": "text.html.thing",
      "injections": {
        "R:text.html.thing - comment": { "patterns": [{ "match": "a" }] }
      },
      "patterns": [{ "match": "b" }]
    }
    """

    private let guest = """
    {
      "scopeName": "thing.directives",
      "injectionSelector": "L:meta.tag, L:meta.element",
      "patterns": [{ "match": "c" }]
    }
    """

    @Test func readsTheRootGrammarsOwnInjections() throws {
        let store = GrammarStore()
        store.add(try grammar(host))

        let injections = store.injections(forRootScope: "text.html.thing")
        #expect(injections.count == 1)
        #expect(injections[0].selector.priority == .after)
        #expect(injections[0].grammar.scopeName == "text.html.thing")
    }

    @Test func joinsAGrammarToTheScopeItsManifestNamed() throws {
        let store = GrammarStore()
        store.add(try grammar(host))
        store.add(try grammar(guest), injectTo: ["text.html.thing"])

        let injections = store.injections(forRootScope: "text.html.thing")
        #expect(injections.count == 3)
        #expect(injections.map(\.selector.priority) == [.before, .before, .after])
        #expect(injections.filter { $0.grammar.scopeName == "thing.directives" }.count == 2)
    }

    /// The selector alone does nothing. A grammar cannot volunteer itself
    /// into a document — its extension has to ask.
    @Test func leavesAGrammarOutUntilAManifestAsks() throws {
        let store = GrammarStore()
        store.add(try grammar(host))
        store.add(try grammar(guest))

        #expect(store.injections(forRootScope: "text.html.thing").count == 1)
    }

    /// And the ask alone does nothing either: a grammar with no
    /// `injectionSelector` says nothing about *where* it applies, so there
    /// is no injection to make.
    @Test func leavesAGrammarOutWhenItNamedNoSelector() throws {
        let store = GrammarStore()
        store.add(try grammar(#"{ "scopeName": "text.html.thing" }"#))
        store.add(
            try grammar(#"{ "scopeName": "thing.plain", "patterns": [{ "match": "c" }] }"#),
            injectTo: ["text.html.thing"])

        #expect(store.injections(forRootScope: "text.html.thing").isEmpty)
    }

    @Test func injectsIntoEveryScopeTheManifestNamed() throws {
        let store = GrammarStore()
        store.add(try grammar(#"{ "scopeName": "text.html.thing" }"#))
        store.add(try grammar(#"{ "scopeName": "text.pug.thing" }"#))
        store.add(try grammar(guest), injectTo: ["text.html.thing", "text.pug.thing"])

        #expect(store.injections(forRootScope: "text.html.thing").count == 2)
        #expect(store.injections(forRootScope: "text.pug.thing").count == 2)
        #expect(store.injections(forRootScope: "text.other.thing").isEmpty)
    }

    /// The rules a cross-grammar injection offers are the whole of the
    /// grammar's own `patterns`, and they are offered through one rule so
    /// the tokenizer expands them once.
    @Test func offersTheWholeGrammarThroughOneRule() throws {
        let store = GrammarStore()
        store.add(try grammar(#"{ "scopeName": "text.html.thing" }"#))
        store.add(try grammar(guest), injectTo: ["text.html.thing"])

        let injections = store.injections(forRootScope: "text.html.thing")
        #expect(injections.count == 2)
        #expect(injections[0].rule === injections[1].rule)
        #expect(injections[0].rule.patterns.count == 1)
    }

    @Test func answersNothingForAScopeItDoesNotHold() throws {
        let store = GrammarStore()
        store.add(try grammar(host))

        #expect(store.injections(forRootScope: "source.absent").isEmpty)
    }
}
