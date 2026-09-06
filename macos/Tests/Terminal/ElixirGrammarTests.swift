import Foundation
@testable import Ghostty
import Testing

/// The test the grammar engine exists for.
///
/// Elixir has no support anywhere in this binary: no lexer, no keyword
/// table, no entry in any enum, no `.ex` in any list. Everything asserted
/// here comes out of a `.tmLanguage.json` file read from disk, which is
/// exactly what an extension from the store will hand over. If this passes,
/// a language nobody compiled in colours like one that was.
///
/// The grammars are third-party and their licence travels with them; see
/// `Fixtures/README.md` and `Fixtures/LICENSE-elixir`.
struct ElixirGrammarTests {
    private static let source = """
    defmodule Meu.Modulo do
      @moduledoc \"\"\"
      Documentação do módulo.
      \"\"\"

      @palavras ~w[um dois três]

      def saudar(nome) do
        IO.puts("Olá, #{nome}! 🎉")
        {:ok, nome}
      end
    end
    """

    /// Located from this file rather than the test bundle, so the grammars
    /// are read as they sit in the repository.
    private static var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
    }

    /// The store as an extension would leave it: two grammars read from
    /// JSON, one of which embeds the other.
    private func store() throws -> GrammarStore {
        let store = GrammarStore()
        let elixir = try #require(
            Grammar.parse(contentsOf: Self.fixtures.appendingPathComponent("elixir.tmLanguage.json")))
        let eex = try #require(
            Grammar.parse(contentsOf: Self.fixtures.appendingPathComponent("eex.tmLanguage.json")))
        store.add(elixir, languageId: "elixir")
        store.add(eex, languageId: "eex")
        return store
    }

    private func probe() throws -> GrammarProbe {
        try #require(GrammarProbe(store: try store(), scope: "source.elixir"))
    }

    private func lines() throws -> [GrammarProbe.Line] {
        try probe().lines(of: Self.source)
    }

    // MARK: - the grammar itself

    @Test func readsTheGrammarFromDisk() throws {
        let store = try store()
        let elixir = try #require(store.grammar(scope: "source.elixir"))
        #expect(elixir.name == "Elixir")
        #expect(elixir.fileTypes == ["ex", "exs"])
        #expect(elixir.firstLineMatch == "^#!/.*\\belixir")
        #expect(elixir.patterns.count > 100)
        #expect(elixir.repository["interpolated_elixir"] != nil)
        #expect(store.grammar(language: "elixir") === elixir)
        #expect(store.grammar(fileType: ".exs") === elixir)
    }

    // MARK: - the five spans

    /// A module declaration. `defmodule` is the keyword and the dotted name
    /// after it is a type, both from named captures on one `match` rule.
    @Test func coloursAModuleDeclaration() throws {
        let line = try lines()[0]

        #expect(line.range(at: 0) == 0..<9)
        #expect(line.scopes(at: 0) == [
            "source.elixir", "meta.module.elixir", "keyword.control.module.elixir",
        ])
        #expect(line.kind(at: 0) == .keyword)

        #expect(line.range(at: 10) == 10..<20)
        #expect(line.text(at: 10) == "Meu.Modulo")
        #expect(line.scope(at: 10) == "entity.name.type.module.elixir")
        #expect(line.kind(at: 10) == .type)

        #expect(line.range(at: 21) == 21..<23)
        #expect(line.scope(at: 21) == "keyword.control.elixir")
    }

    /// A docstring heredoc, which is a region that opens on one line and
    /// closes on another. Nothing about this works without state carried
    /// across the line boundary.
    @Test func carriesADocstringHeredocAcrossLines() throws {
        let lines = try lines()
        let scope = "comment.documentation.heredoc.elixir"

        #expect(lines[1].range(at: 2) == 2..<16)
        #expect(lines[1].text(at: 2) == "@moduledoc \"\"\"")
        #expect(lines[1].scope(at: 2) == scope)
        #expect(lines[1].state.depth == 1)
        #expect(lines[1].state.scopes == ["source.elixir", scope])

        #expect(lines[2].range(at: 0) == 0..<28)
        #expect(lines[2].scope(at: 0) == scope)
        #expect(lines[2].kind(at: 0) == .comment)
        #expect(lines[2].state.depth == 1)

        #expect(lines[3].range(at: 0) == 0..<5)
        #expect(lines[3].scope(at: 0) == scope)
        #expect(lines[3].state.isInitial)

        #expect(lines[4].spans.isEmpty)
        #expect(lines[4].state.isInitial)
    }

    /// A word-list sigil. The delimiters are punctuation and the body is a
    /// string, and the `três` inside it is why the offsets are bytes: the
    /// body is 12 characters and 13 bytes.
    @Test func coloursAWordListSigil() throws {
        let line = try lines()[5]

        #expect(line.range(at: 12) == 12..<15)
        #expect(line.text(at: 12) == "~w[")
        #expect(line.scope(at: 12) == "punctuation.section.list.begin.elixir")

        #expect(line.range(at: 15) == 15..<28)
        #expect(line.text(at: 15) == "um dois três")
        #expect(line.scope(at: 15) == "string.quoted.double.interpolated.elixir")
        #expect(line.kind(at: 15) == .string)

        #expect(line.range(at: 28) == 28..<29)
        #expect(line.scope(at: 28) == "punctuation.section.list.end.elixir")
    }

    /// An interpolation inside a string, which is the grammar re-entering
    /// its own top level through `$self` while a string region is still
    /// open. The stack proves it: the variable is inside `meta.embedded`
    /// inside `string.quoted.double`.
    ///
    /// The emoji after the interpolation is four bytes of the six the last
    /// run of string covers, and the quote after it still closes where it
    /// should.
    @Test func coloursAnInterpolationInsideAString() throws {
        let line = try lines()[8]

        #expect(line.range(at: 12) == 12..<13)
        #expect(line.scope(at: 12) == "punctuation.definition.string.begin.elixir")

        #expect(line.range(at: 13) == 13..<19)
        #expect(line.text(at: 13) == "Olá, ")
        #expect(line.scope(at: 13) == "string.quoted.double.elixir")

        #expect(line.range(at: 19) == 19..<21)
        #expect(line.text(at: 19) == "#{")
        #expect(line.scopes(at: 19) == [
            "source.elixir",
            "string.quoted.double.elixir",
            "meta.embedded.line.elixir",
            "punctuation.section.embedded.elixir",
        ])

        #expect(line.range(at: 21) == 21..<25)
        #expect(line.text(at: 21) == "nome")
        #expect(line.scopes(at: 21) == [
            "source.elixir",
            "string.quoted.double.elixir",
            "meta.embedded.line.elixir",
            "variable.other.readwrite.elixir",
        ])

        #expect(line.range(at: 25) == 25..<26)
        #expect(line.scope(at: 25) == "punctuation.section.embedded.elixir")

        #expect(line.range(at: 26) == 26..<32)
        #expect(line.text(at: 26) == "! 🎉")
        #expect(line.range(at: 32) == 32..<33)
        #expect(line.scope(at: 32) == "punctuation.definition.string.end.elixir")
        #expect(line.state.isInitial)
    }

    /// An atom. The colon is punctuation and the name under it is the
    /// symbol, which the theme collapses to a keyword through
    /// `constant.language`.
    @Test func coloursAnAtom() throws {
        let line = try lines()[9]

        #expect(line.range(at: 5) == 5..<6)
        #expect(line.scopes(at: 5) == [
            "source.elixir", "constant.language.symbol.elixir", "punctuation.definition.constant.elixir",
        ])

        #expect(line.range(at: 6) == 6..<8)
        #expect(line.text(at: 6) == "ok")
        #expect(line.scopes(at: 6) == ["source.elixir", "constant.language.symbol.elixir"])
        #expect(line.kind(at: 6) == .keyword)
    }

    // MARK: - the rest of the file

    @Test func coloursAFunctionDefinition() throws {
        let line = try lines()[7]
        #expect(line.range(at: 2) == 2..<5)
        #expect(line.scope(at: 2) == "keyword.control.elixir")
        #expect(line.range(at: 6) == 6..<12)
        #expect(line.text(at: 6) == "saudar")
        #expect(line.scope(at: 6) == "entity.name.function.elixir")
        #expect(line.kind(at: 6) == .function)
    }

    @Test func coversEveryByteOfEveryLine() throws {
        for line in try lines() {
            var cursor = 0
            for span in line.spans {
                #expect(span.range.lowerBound == cursor)
                cursor = span.range.upperBound
            }
            #expect(cursor == line.bytes.count)
        }
    }

    @Test func endsTheFileWithNothingOpen() throws {
        let lines = try lines()
        #expect(lines[11].scope(at: 0) == "keyword.control.elixir")
        #expect(lines[11].state.isInitial)
    }

    // MARK: - one grammar inside another

    /// EEx is a second grammar whose only interesting rule includes
    /// `source.elixir` by scope name. Elixir colours inside the `<%= %>`
    /// tag, which is the whole of what `SFCRegions` does today in code.
    @Test func coloursElixirEmbeddedInAnEexTemplate() throws {
        let probe = try #require(GrammarProbe(store: try store(), scope: "text.elixir"))
        let line = probe.line("<h1><%= @titulo %></h1>")

        #expect(line.scopes(at: 0) == ["text.elixir"])
        #expect(line.range(at: 0) == 0..<4)

        #expect(line.range(at: 4) == 4..<7)
        #expect(line.text(at: 4) == "<%=")
        #expect(line.scopes(at: 4) == [
            "text.elixir", "meta.embedded.line.elixir", "punctuation.section.embedded.elixir",
        ])

        #expect(line.range(at: 8) == 8..<9)
        #expect(line.scopes(at: 8) == [
            "text.elixir",
            "meta.embedded.line.elixir",
            "variable.other.constant.elixir",
            "punctuation.definition.variable.elixir",
        ])

        #expect(line.range(at: 9) == 9..<15)
        #expect(line.text(at: 9) == "titulo")
        #expect(line.scopes(at: 9) == [
            "text.elixir", "meta.embedded.line.elixir", "variable.other.constant.elixir",
        ])

        #expect(line.range(at: 16) == 16..<18)
        #expect(line.text(at: 16) == "%>")
        #expect(line.scopes(at: 18) == ["text.elixir"])
        #expect(line.state.isInitial)
    }

    @Test func coloursAnEexComment() throws {
        let probe = try #require(GrammarProbe(store: try store(), scope: "text.elixir"))
        let line = probe.line("<%# comentário %>")

        #expect(line.range(at: 0) == 0..<3)
        #expect(line.scopes(at: 0) == [
            "text.elixir", "comment.block.eex", "punctuation.definition.comment.eex",
        ])
        #expect(line.range(at: 3) == 3..<16)
        #expect(line.text(at: 3) == " comentário ")
        #expect(line.kind(at: 3) == .comment)
        #expect(line.state.isInitial)
    }
}
