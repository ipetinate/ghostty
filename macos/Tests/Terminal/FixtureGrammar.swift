import Foundation
@testable import Ghostty
import Testing

/// A grammar small enough to read, for a test that needs *some* highlighter
/// to prove something else.
///
/// `Fixtures/fixture.tmLanguage.json` has four rules: a `//` line comment, a
/// `/* */` block comment, a double-quoted string with backslash escapes, and
/// seven keywords. It is loaded the way an installed extension's grammar is —
/// parsed from disk into a `GrammarStore` — so a caller of the editor sees
/// here what it sees in the app.
enum FixtureGrammar {
    static let scopeName = "source.fixture"
    static let languageID = "fixture"
    static let fileExtension = "fx"
    static let extensionID = "acme.fixture"

    /// Located from this file rather than the test bundle, so the grammar is
    /// read as it sits in the repository.
    static var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
    }

    static var fileURL: URL {
        fixtures.appendingPathComponent("fixture.tmLanguage.json")
    }

    static func grammar() throws -> Grammar {
        try #require(Grammar.parse(contentsOf: fileURL))
    }

    static func store() throws -> GrammarStore {
        let store = GrammarStore()
        store.add(try grammar(), languageId: languageID)
        return store
    }

    static func highlighter() throws -> GrammarHighlighter {
        let store = try store()
        let grammar = try #require(store.grammar(scope: scopeName))
        return GrammarHighlighter(tokenizer: GrammarTokenizer(store: store, grammar: grammar))
    }

    /// The manifest an extension shipping this grammar would carry, rooted
    /// at the Fixtures directory so the grammar path resolves to the file.
    static let manifestJSON = #"""
    {
      "schemaVersion": 1,
      "id": "acme.fixture",
      "name": "Fixture",
      "version": "1.0.0",
      "publisher": "acme",
      "contributes": {
        "languages": [{
          "languageId": "fixture",
          "name": "Fixture",
          "extensions": ["fx"],
          "lineComment": "//",
          "blockComment": ["/*", "*/"]
        }],
        "grammars": [{
          "scopeName": "source.fixture",
          "path": "fixture.tmLanguage.json",
          "languageId": "fixture"
        }]
      }
    }
    """#

    static func manifest() throws -> LanguageManifest {
        try #require(LanguageManifest.parse(
            data: Data(manifestJSON.utf8),
            url: fixtures.appendingPathComponent(LanguageManifest.fileName),
            root: fixtures,
            scope: .user
        ))
    }

    /// What `LanguageResolver.snapshot` would hold with this extension
    /// installed and nothing else.
    @MainActor
    static func snapshot() throws -> LanguageResolver.Snapshot {
        let catalog = LanguageCatalog.resolve(manifests: [try manifest()], promotions: [])
        return LanguageResolver.Snapshot(
            catalog: catalog,
            grammars: LanguageResolver.buildGrammars(from: catalog)
        )
    }

    /// What `LanguageResolver.snapshot` holds with nothing installed.
    @MainActor
    static func emptySnapshot() -> LanguageResolver.Snapshot {
        LanguageResolver.Snapshot(catalog: .empty, grammars: GrammarStore())
    }
}
