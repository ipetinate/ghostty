import Foundation
@testable import Ghostty
import Testing

/// What a scope selector accepts, in the shapes real grammars write.
///
/// Every string here is taken from an installed grammar or is one step
/// removed from one. A selector is the only thing standing between a
/// grammar's injected rules and the whole document, so an alternative read
/// too loosely paints a file that should be plain and one read too strictly
/// leaves PHP unpainted.
struct ScopeSelectorTests {
    private func one(_ text: String) throws -> ScopeSelector {
        let parsed = ScopeSelector.parse(text)
        #expect(parsed.count == 1)
        return try #require(parsed.first)
    }

    // MARK: - identifiers

    @Test func matchesAScopeOnDottedBoundaries() {
        #expect(ScopeSelector.scope("source.js", hasPrefix: "source"))
        #expect(ScopeSelector.scope("source", hasPrefix: "source"))
        #expect(!ScopeSelector.scope("sourcemap.js", hasPrefix: "source"))
        #expect(!ScopeSelector.scope("sourc", hasPrefix: "source"))
    }

    @Test func matchesADescendantPathInOrder() throws {
        let selector = try one("text.html source.js string")

        #expect(selector.matches(["text.html.basic", "source.js.embedded", "string.quoted.double.js"]))
        #expect(selector.matches(["text.html.basic", "meta.tag", "source.js", "meta.x", "string.quoted"]))
        #expect(!selector.matches(["source.js.embedded", "text.html.basic", "string.quoted"]))
        #expect(!selector.matches(["text.html.basic", "source.js.embedded"]))
    }

    @Test func readsAHyphenInsideAnIdentifier() throws {
        let selector = try one("entity.other.attribute-name")

        #expect(selector.matches(["entity.other.attribute-name.html"]))
        #expect(!selector.matches(["entity.other.attribute"]))
    }

    // MARK: - alternatives and priority

    @Test func readsEachAlternativeSeparately() {
        let parsed = ScopeSelector.parse("source.js, source.ts")

        #expect(parsed.count == 2)
        #expect(parsed[0].matches(["source.js"]))
        #expect(!parsed[0].matches(["source.ts"]))
        #expect(parsed[1].matches(["source.ts"]))
    }

    /// A prefix belongs to the alternative it precedes. PHP writes one
    /// selector where the first alternative goes behind HTML's own rules
    /// and the next three ask to go in front of them.
    @Test func givesEachAlternativeItsOwnPriority() {
        let parsed = ScopeSelector.parse("text.html.php - (meta.embedded), L:(source.js), R:source.css")

        #expect(parsed.map(\.priority) == [.normal, .before, .after])
    }

    @Test func matchesEverythingWhenTheAlternativeStatesNoCondition() throws {
        let selector = try one("L:*")

        #expect(selector.priority == .before)
        #expect(selector.matches(["anything"]))
        #expect(selector.matches([]))
    }

    @Test func readsNothingFromAnEmptySelector() {
        #expect(ScopeSelector.parse("").isEmpty)
        #expect(ScopeSelector.parse("   ").isEmpty)
    }

    // MARK: - exclusion

    @Test func excludesABareIdentifier() throws {
        let selector = try one("source.css -comment")

        #expect(selector.matches(["source.css"]))
        #expect(!selector.matches(["source.css", "comment.block.css"]))
    }

    @Test func excludesEveryIdentifierItIsGiven() throws {
        let selector = try one("L:meta.tag -meta.attribute -meta.ng-binding -source.tsx")

        #expect(selector.matches(["text.html.vue", "meta.tag.any.html"]))
        #expect(!selector.matches(["text.html.vue", "meta.tag", "meta.attribute.class"]))
        #expect(!selector.matches(["text.html.vue", "meta.tag", "source.tsx"]))
    }

    @Test func excludesAGroupOfAlternatives() throws {
        let selector = try one("text.html.php - (meta.embedded | meta.tag)")

        #expect(selector.matches(["text.html.php"]))
        #expect(!selector.matches(["text.html.php", "meta.embedded.block.php"]))
        #expect(!selector.matches(["text.html.php", "meta.tag.any.html"]))
    }

    /// Inside parentheses a comma reads as `|`, which is how HTML writes
    /// the list of things its own injection stays out of.
    @Test func readsACommaInsideAGroupAsAnAlternation() throws {
        let selector = try one("R:text.html - (comment.block, text.html meta.embedded)")

        #expect(selector.priority == .after)
        #expect(selector.matches(["text.html.basic"]))
        #expect(!selector.matches(["text.html.basic", "comment.block.html"]))
        #expect(!selector.matches(["text.html.basic", "meta.embedded.block"]))
    }

    // MARK: - the selector PHP is unpainted without

    /// The whole of PHP's `injections` key, and the four answers it has to
    /// give. Reading any one of them wrong is 227 characters of a `.php`
    /// file coming out the wrong colour, which is how this was found.
    @Test func readsThePHPInjectionSelector() {
        let parsed = ScopeSelector.parse("""
        text.html.php - (meta.embedded | meta.tag), \
        L:((text.html.php meta.tag) - (meta.embedded.block.php | meta.embedded.line.php)), \
        L:(source.js - (meta.embedded.block.php | meta.embedded.line.php)), \
        L:(source.css - (meta.embedded.block.php | meta.embedded.line.php))
        """)

        #expect(parsed.count == 4)
        #expect(parsed.map(\.priority) == [.normal, .before, .before, .before])

        let shell = ["text.html.php"]
        let inTag = ["text.html.php", "meta.tag.any.html"]
        let inPHP = ["text.html.php", "meta.embedded.block.php", "source.php"]
        let inScript = ["text.html.php", "source.js"]

        #expect(parsed.contains { $0.matches(shell) })
        #expect(parsed.contains { $0.matches(inTag) })
        #expect(parsed.contains { $0.matches(inScript) })
        #expect(!parsed.contains { $0.matches(inPHP) })
    }

    /// `*` is not part of the selector language. The reference
    /// implementation skips it, which leaves `meta.tag.*.*.html` as
    /// identifiers no real scope answers to — so HTML's exclusion list
    /// excludes nothing by way of them, and honouring the wildcard would
    /// have kept the injection out of every tag.
    @Test func matchesNoRealScopeThroughAWildcard() throws {
        let selector = try one("meta.tag.*.*.html")

        #expect(!selector.matches(["meta.tag.any.thing.html"]))
        #expect(!selector.matches(["meta.tag"]))
    }

    // MARK: - ordering

    /// `L:` first, `R:` last, and the order they arrived in among those of
    /// equal priority — which decides which of two injections wins a
    /// position they both match, so it may not be left to an unstable sort.
    @Test func ordersInjectionsBeforeFirstAndKeepsTheRestInPlace() {
        let priorities: [ScopeSelector.Priority] = [.after, .normal, .before, .normal, .after, .before]
        let ordered = ScopeSelector.ordered(priorities.indices.map { ($0, priorities[$0]) }) { $0.1 }

        #expect(ordered.map { $0.1 } == [.before, .before, .normal, .normal, .after, .after])
        #expect(ordered.map { $0.0 } == [2, 5, 1, 3, 0, 4])
    }
}
