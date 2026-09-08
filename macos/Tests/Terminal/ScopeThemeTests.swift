import Foundation
@testable import Ghostty
import Testing

/// Nine colours out of an open-ended vocabulary.
struct ScopeThemeTests {
    private let theme = ScopeTheme.standard

    @Test func mapsAScopeByItsLongestPrefix() {
        #expect(theme.kind(forScope: "comment.line.number-sign.elixir") == .comment)
        #expect(theme.kind(forScope: "string.quoted.double.elixir") == .string)
        #expect(theme.kind(forScope: "constant.numeric.integer.elixir") == .number)
        #expect(theme.kind(forScope: "keyword.control.elixir") == .keyword)
        #expect(theme.kind(forScope: "storage.type.function") == .keyword)
        #expect(theme.kind(forScope: "entity.name.type.module.elixir") == .type)
        #expect(theme.kind(forScope: "entity.name.function.elixir") == .function)
        #expect(theme.kind(forScope: "entity.other.attribute-name.html") == .attribute)
        #expect(theme.kind(forScope: "punctuation.definition.string.begin") == .punctuation)
    }

    /// `constant.language` and `constant.numeric` disagree, and the longer
    /// of the two prefixes that matches is the one that decides.
    @Test func prefersTheLongerOfTwoPrefixesThatBothMatch() {
        #expect(theme.kind(forScope: "constant.language.symbol.elixir") == .keyword)
        #expect(theme.kind(forScope: "constant.numeric.float") == .number)
        #expect(theme.kind(forScope: "constant.character.escape.elixir") == .string)
        #expect(theme.kind(forScope: "constant.other.symbol") == nil)
    }

    @Test func claimsNothingItDoesNotRecognise() {
        #expect(theme.kind(forScope: "meta.module.elixir") == nil)
        #expect(theme.kind(forScope: "variable.other.readwrite") == nil)
        #expect(theme.kind(forScope: "commentary.note") == nil)
    }

    /// Innermost first. A function name inside a string is a function name;
    /// only when nothing inside is recognised does the search move outwards.
    @Test func readsTheStackFromTheInsideOut() {
        #expect(theme.kind(for: ["source.elixir", "string.quoted", "entity.name.function"]) == .function)
        #expect(theme.kind(for: ["source.elixir", "string.quoted", "meta.embedded"]) == .string)
        #expect(theme.kind(for: ["source.elixir", "meta.module.elixir"]) == .plain)
        #expect(theme.kind(for: []) == .plain)
    }

    @Test func honoursACustomTable() {
        let custom = ScopeTheme(rules: [
            .init(prefix: "meta", kind: .attribute),
            .init(prefix: "meta.module", kind: .type),
        ])
        #expect(custom.kind(forScope: "meta.module.elixir") == .type)
        #expect(custom.kind(forScope: "meta.function.elixir") == .attribute)
        #expect(custom.kind(forScope: "keyword.control") == nil)
    }
}
