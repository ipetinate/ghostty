import Foundation
@testable import Ghostty
import Testing

/// `contributes.grammars[]`, parsed the way a file we did not write has to
/// be parsed, and the road from there to a highlighter.
struct GrammarContributionTests {
    private static let root = URL(fileURLWithPath: "/tmp/phantom-tests/acme.lua")

    private func parse(_ json: String, root: URL = root, scope: LanguageManifest.Scope = .user) -> LanguageManifest? {
        LanguageManifest.parse(
            data: Data(json.utf8),
            url: root.appendingPathComponent(LanguageManifest.fileName),
            root: root,
            scope: scope
        )
    }

    private func parseGrammar(_ body: String) -> GrammarContribution? {
        parse(#"""
        { "id": "acme.lua", "contributes": { "grammars": [{ \#(body) }] } }
        """#)?.grammars.first
    }

    private func manifest(directory: String, scope: LanguageManifest.Scope = .user, grammars: String) throws -> LanguageManifest {
        let root = URL(fileURLWithPath: "/tmp/phantom-grammars").appendingPathComponent(directory)
        return try #require(parse(#"""
        { "id": "\#(directory)", "contributes": { "grammars": [\#(grammars)] } }
        """#, root: root, scope: scope))
    }

    // MARK: The manifest shape

    @Test func aGrammarParsesWhole() throws {
        let grammar = try #require(parseGrammar(#"""
        "scopeName": "source.lua",
        "path": "./syntaxes/lua.tmLanguage.json",
        "languageId": "lua",
        "embeddedLanguages": { "meta.embedded.block.html": "html", "Not A Scope": "js", "source.js": 7 },
        "injectTo": ["text.html.markdown", "Markdown", 3]
        """#))

        #expect(grammar.scopeName == "source.lua")
        #expect(grammar.fileURL.path.hasSuffix("/acme.lua/syntaxes/lua.tmLanguage.json"))
        #expect(grammar.fileURL.path.hasPrefix(Self.root.standardizedFileURL.resolvingSymlinksInPath().path))
        #expect(grammar.languageID == "lua")
        #expect(grammar.embeddedLanguages == ["meta.embedded.block.html": "html"])
        #expect(grammar.injectTo == ["text.html.markdown"])
    }

    /// A grammar included by others and colouring no whole language of its
    /// own has no `languageId`, and that is not a defect.
    @Test func aGrammarMayColourNoLanguageOfItsOwn() throws {
        let grammar = try #require(parseGrammar(#""scopeName": "source.lua.inner", "path": "inner.json""#))

        #expect(grammar.languageID == nil)
        #expect(grammar.embeddedLanguages.isEmpty)
        #expect(grammar.injectTo.isEmpty)
    }

    @Test func aLanguageIDThatIsNotOneIsDroppedAlone() throws {
        let grammar = try #require(parseGrammar(#""scopeName": "source.lua", "path": "lua.json", "languageId": "a/b""#))

        #expect(grammar.languageID == nil)
        #expect(grammar.scopeName == "source.lua")
    }

    // MARK: What is refused

    @Test func aGrammarWhoseFileIsOutsideTheExtensionIsDropped() {
        #expect(parseGrammar(#""scopeName": "source.lua", "path": "../outside.tmLanguage.json""#) == nil)
        #expect(parseGrammar(#""scopeName": "source.lua", "path": "syntaxes/../../lua.json""#) == nil)
        #expect(parseGrammar(#""scopeName": "source.lua", "path": "/etc/lua.json""#) == nil)
        #expect(parseGrammar(#""scopeName": "source.lua", "path": "~/lua.json""#) == nil)
    }

    @Test func aGrammarThatIsNotJSONIsDropped() {
        #expect(parseGrammar(#""scopeName": "source.lua", "path": "syntaxes/lua.tmLanguage""#) == nil)
        #expect(parseGrammar(#""scopeName": "source.lua", "path": "syntaxes/lua.tmLanguage.plist""#) == nil)
        #expect(parseGrammar(#""scopeName": "source.lua", "path": "syntaxes/lua.JSON""#) != nil)
    }

    @Test func aGrammarNeedsAScopeNameAndAPath() {
        #expect(parseGrammar(#""path": "syntaxes/lua.tmLanguage.json""#) == nil)
        #expect(parseGrammar(#""scopeName": "Lua", "path": "syntaxes/lua.tmLanguage.json""#) == nil)
        #expect(parseGrammar(#""scopeName": "source.lua""#) == nil)
    }

    @Test func scopeNamesAreDottedWords() {
        #expect(GrammarContribution.isScopeName("source.lua"))
        #expect(GrammarContribution.isScopeName("text.html.basic"))
        #expect(GrammarContribution.isScopeName("source.c++"))
        #expect(GrammarContribution.isScopeName("source.objective-c"))

        #expect(!GrammarContribution.isScopeName("Lua"))
        #expect(!GrammarContribution.isScopeName(""))
        #expect(!GrammarContribution.isScopeName("source."))
        #expect(!GrammarContribution.isScopeName(".lua"))
        #expect(!GrammarContribution.isScopeName("source..lua"))
        #expect(!GrammarContribution.isScopeName("source lua"))
        #expect(!GrammarContribution.isScopeName("source/lua"))
        #expect(!GrammarContribution.isScopeName("source.lua\u{202E}"))
        #expect(!GrammarContribution.isScopeName(String(repeating: "a.", count: 70)))
    }

    // MARK: The envelope

    @Test func grammarsMakeAManifestUsableAndAreNotCountedAsUnrecognized() throws {
        let manifest = try #require(parse(#"""
        { "id": "acme.lua", "contributes": { "grammars": [{ "scopeName": "source.lua", "path": "lua.json" }] } }
        """#))

        #expect(manifest.isUsable)
        #expect(manifest.unrecognizedFields.isEmpty)
        #expect(manifest.grammars.count == 1)
    }

    @Test func theSameScopeTwiceInOneManifestKeepsTheFirst() throws {
        let manifest = try #require(parse(#"""
        {
          "id": "acme.lua",
          "contributes": {
            "grammars": [
              { "scopeName": "source.lua", "path": "first.json" },
              { "scopeName": "source.lua", "path": "second.json" },
              { "scopeName": "source.lua.inner", "path": "inner.json" }
            ]
          }
        }
        """#))

        #expect(manifest.grammars.map(\.scopeName) == ["source.lua", "source.lua.inner"])
        #expect(manifest.grammars.first?.fileURL.lastPathComponent == "first.json")
    }

    /// The server half is what an unreadable schema switches off. A grammar
    /// is data the same way a language is, so it stays.
    @Test func aNewerSchemaKeepsTheGrammar() throws {
        let manifest = try #require(parse(#"""
        { "schemaVersion": 2, "id": "acme.lua", "contributes": { "grammars": [{ "scopeName": "source.lua", "path": "lua.json" }] } }
        """#))

        #expect(manifest.eligibility == .needsNewerApp(declared: "2"))
        #expect(manifest.grammars.count == 1)
    }

    // MARK: The catalog

    @Test func theCatalogKeepsOneGrammarPerScope() throws {
        let lua = #"{ "scopeName": "source.lua", "path": "lua.json", "languageId": "lua" }"#
        let catalog = LanguageCatalog.resolve(
            manifests: [
                try manifest(directory: "zeta.lua", grammars: lua),
                try manifest(directory: "alpha.lua", grammars: lua),
            ],
            promotions: []
        )

        #expect(catalog.grammars.count == 1)
        #expect(catalog.grammars.first?.listIdentity == "alpha.lua")
        #expect(catalog.grammars.first?.id == "alpha.lua#grammar:source.lua")
    }

    @Test func aUserGrammarOutranksABundledOne() throws {
        let lua = #"{ "scopeName": "source.lua", "path": "lua.json" }"#
        let catalog = LanguageCatalog.resolve(
            manifests: [
                try manifest(directory: "alpha.lua", scope: .bundled, grammars: lua),
                try manifest(directory: "zeta.lua", scope: .user, grammars: lua),
            ],
            promotions: []
        )

        #expect(catalog.grammars.map(\.listIdentity) == ["zeta.lua"])
    }

    // MARK: The road to a highlighter

    @MainActor
    @Test func aContributedGrammarReachesTheHighlighterThroughTheSnapshot() throws {
        let snapshot = try FixtureGrammar.snapshot()

        #expect(snapshot.grammars.grammar(scope: FixtureGrammar.scopeName) != nil)
        #expect(snapshot.grammars.grammar(language: FixtureGrammar.languageID) != nil)
        #expect(!LanguageResolver.highlighter(forFileName: "main.fx", in: snapshot).isPlain)
        #expect(!LanguageResolver.highlighter(forFileName: "MAIN.FX", in: snapshot).isPlain)
        #expect(!LanguageResolver.highlighter(forLanguageID: "fixture", in: snapshot).isPlain)
        #expect(
            LanguageResolver.commentMarkers(forFileName: "main.fx", in: snapshot)
                == CommentMarkers(line: "//", block: BlockComment(open: "/*", close: "*/"))
        )
    }

    @MainActor
    @Test func aFileNobodyClaimsIsPlain() throws {
        let snapshot = try FixtureGrammar.snapshot()

        #expect(LanguageResolver.highlighter(forFileName: "main.rs", in: snapshot).isPlain)
        #expect(LanguageResolver.highlighter(forFileName: "Makefile", in: snapshot).isPlain)
        #expect(LanguageResolver.highlighter(forLanguageID: nil, in: snapshot).isPlain)
        #expect(LanguageResolver.highlighter(forLanguageID: "rust", in: snapshot).isPlain)
        #expect(LanguageResolver.commentMarkers(forFileName: "main.rs", in: snapshot) == .none)
    }

    @MainActor
    @Test func anEmptySnapshotColoursNothing() {
        let snapshot = FixtureGrammar.emptySnapshot()

        #expect(LanguageResolver.highlighter(forFileName: "main.fx", in: snapshot).isPlain)
        #expect(LanguageResolver.highlighter(forLanguageID: "fixture", in: snapshot).isPlain)
    }

    /// A grammar file that is missing, or that is not a grammar, costs the
    /// extension that grammar and nothing else.
    @Test func aGrammarThatCannotBeReadCostsOnlyItself() throws {
        let manifest = try #require(parse(#"""
        {
          "id": "acme.fixture",
          "contributes": {
            "grammars": [
              { "scopeName": "source.fixture", "path": "fixture.tmLanguage.json", "languageId": "fixture" },
              { "scopeName": "source.missing", "path": "missing.tmLanguage.json", "languageId": "missing" },
              { "scopeName": "source.eex.wrong", "path": "README.md", "languageId": "readme" }
            ]
          }
        }
        """#, root: FixtureGrammar.fixtures))
        #expect(manifest.grammars.count == 2)

        let catalog = LanguageCatalog.resolve(manifests: [manifest], promotions: [])
        let store = LanguageResolver.buildGrammars(from: catalog)

        #expect(store.grammar(scope: "source.fixture") != nil)
        #expect(store.grammar(language: "fixture") != nil)
        #expect(store.grammar(scope: "source.missing") == nil)
        #expect(store.grammar(language: "missing") == nil)
        #expect(Set(store.scopeNames) == ["source.fixture"])
    }
}
