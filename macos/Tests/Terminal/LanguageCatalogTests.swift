import Foundation
@testable import Ghostty
import Testing

/// Precedence, and what happens when two extensions want the same file type.
///
/// The rule under test is **user extension > bundled extension**, with
/// promotion — a click in Settings, never something a file can ask for — as
/// the only way past it. This build ships no language table of its own any
/// more, so the third rank the order used to start with is gone; what is
/// left is still the thing the extension design rests on, because installing
/// one manifest must not silently take a file type from another.
///
/// The second rule is duller and matters as much: ties are broken by
/// directory name, lexicographically. Which manifest wins is nearly
/// arbitrary; that it is the *same* one on every machine is not. Resolution
/// that depended on `contentsOfDirectory` order would be a bug that
/// reproduces for one person and not the next.
struct LanguageCatalogTests {
    private func manifest(
        directory: String,
        id: String,
        scope: LanguageManifest.Scope = .user,
        languages: String
    ) -> LanguageManifest {
        let root = URL(fileURLWithPath: "/tmp/phantom-catalog").appendingPathComponent(directory)
        let json = #"""
        {
          "schemaVersion": 1,
          "id": "\#(id)",
          "name": "\#(id)",
          "version": "1.0.0",
          "publisher": "acme",
          "contributes": { "languages": [\#(languages)] }
        }
        """#
        return LanguageManifest.parse(
            data: Data(json.utf8),
            url: root.appendingPathComponent(LanguageManifest.fileName),
            root: root,
            scope: scope
        )!
    }

    private static let elixir = #"""
    {
      "languageId": "elixir",
      "name": "Elixir",
      "extensions": ["ex", "exs"],
      "fileNames": ["mix.lock"],
      "keywords": ["def", "end"],
      "lineComment": "#",
      "server": { "command": "elixir-ls" }
    }
    """#

    // MARK: One extension claims what another already has

    /// File names are compared case-insensitively, so a manifest spelling it
    /// `makefile` has to count the claim of the one that spelled it
    /// `Makefile` as taken.
    @Test func aClaimedFileNameIsOwnedRegardlessOfCase() {
        let catalog = LanguageCatalog.resolve(
            manifests: [
                manifest(
                    directory: "a.make",
                    id: "a.make",
                    languages: #"{ "languageId": "mymake", "fileNames": ["Makefile"] }"#
                ),
                manifest(
                    directory: "b.make",
                    id: "b.make",
                    languages: #"{ "languageId": "yourmake", "fileNames": ["makefile"] }"#
                ),
            ],
            promotions: []
        )
        #expect(catalog.contributed.first?.isActive == true)
        #expect(catalog.contributed.last?.resolution
            == .shadowed(by: .extensionID("a.make"), claim: "name:makefile"))
    }

    /// A language id another extension already has is taken even when the
    /// file extensions differ: the id is what a `didOpen` carries and what
    /// the per-language settings are keyed by.
    @Test func aClaimedLanguageIDIsOwned() {
        let catalog = LanguageCatalog.resolve(
            manifests: [
                manifest(
                    directory: "a.kotlin",
                    id: "a.kotlin",
                    languages: #"{ "languageId": "kotlin", "extensions": ["kt"] }"#
                ),
                manifest(
                    directory: "b.kotlin",
                    id: "b.kotlin",
                    languages: #"{ "languageId": "kotlin", "extensions": ["ktx"] }"#
                ),
            ],
            promotions: []
        )
        #expect(catalog.contributed.last?.resolution
            == .shadowed(by: .extensionID("a.kotlin"), claim: "lang:kotlin"))
    }

    // MARK: A language nobody had

    @Test func aLanguageNothingElseClaimsIsActive() throws {
        let catalog = LanguageCatalog.resolve(
            manifests: [manifest(
                directory: "acme.elixir",
                id: "acme.elixir",
                languages: Self.elixir
            )],
            promotions: []
        )

        let contributed = try #require(catalog.contributed.first)
        #expect(contributed.isActive)
        #expect(catalog.contribution(forFileName: "app.ex")?.id == contributed.id)
        #expect(catalog.contribution(forFileName: "app.exs")?.id == contributed.id)
        #expect(catalog.contribution(forFileName: "mix.lock")?.id == contributed.id)
        #expect(catalog.contribution(forFileName: "app.ts") == nil)

        let definition = try #require(contributed.serverDefinition)
        #expect(definition.command == "elixir-ls")
        #expect(definition.languageID == "elixir")
        #expect(definition.origin == .manifest(contributed.provenance))
    }

    /// A name is a more specific statement than an extension — `go.mod` is
    /// Go, and `.mod` is a Fortran module as often as it is anything else.
    @Test func aFileNameBeatsAnExtension() throws {
        let catalog = LanguageCatalog.resolve(
            manifests: [
                manifest(
                    directory: "a.byname",
                    id: "a.byname",
                    languages: #"{ "languageId": "lockfile", "fileNames": ["mix.lock"] }"#
                ),
                manifest(
                    directory: "b.byext",
                    id: "b.byext",
                    languages: #"{ "languageId": "locky", "extensions": ["lock"] }"#
                ),
            ],
            promotions: []
        )
        #expect(catalog.contribution(forFileName: "mix.lock")?.language.languageID == "lockfile")
        #expect(catalog.contribution(forFileName: "other.lock")?.language.languageID == "locky")
    }

    // MARK: Two extensions, one file type

    /// The manifests are handed over in the order that would win if
    /// discovery order decided anything, which is the point.
    @Test func twoExtensionsClaimingTheSameTypeResolveLexicographically() throws {
        let catalog = LanguageCatalog.resolve(
            manifests: [
                manifest(directory: "zeta.elixir", id: "zeta.elixir", languages: Self.elixir),
                manifest(directory: "alpha.elixir", id: "alpha.elixir", languages: Self.elixir),
            ],
            promotions: []
        )

        #expect(catalog.contributed.count == 2)
        let winner = try #require(catalog.contributed.first)
        let loser = try #require(catalog.contributed.last)

        #expect(winner.provenance.extensionID == "alpha.elixir")
        #expect(winner.isActive)
        #expect(loser.provenance.extensionID == "zeta.elixir")
        #expect(loser.resolution == .shadowed(by: .extensionID("alpha.elixir"), claim: "lang:elixir"))
        #expect(catalog.contribution(forFileName: "app.ex")?.provenance.extensionID
            == "alpha.elixir")
    }

    /// The user's directory outranks the bundle, whatever the names are.
    @Test func aUserExtensionOutranksABundledOne() throws {
        let catalog = LanguageCatalog.resolve(
            manifests: [
                manifest(
                    directory: "aaa.elixir",
                    id: "aaa.elixir",
                    scope: .bundled,
                    languages: Self.elixir
                ),
                manifest(
                    directory: "zzz.elixir",
                    id: "zzz.elixir",
                    scope: .user,
                    languages: Self.elixir
                ),
            ],
            promotions: []
        )
        #expect(catalog.contributed.first?.provenance.extensionID == "zzz.elixir")
        #expect(catalog.contributed.first?.isActive == true)
        #expect(catalog.contributed.last?.resolution
            == .shadowed(by: .extensionID("zzz.elixir"), claim: "lang:elixir"))
    }

    /// Shadowing is all-or-nothing across a contribution's claims. Half a
    /// language — one extension claimed, its neighbour not — is not something
    /// a user could be expected to work out. Only `taken` is contested here;
    /// `neverseen` is the claim nobody else wants, and it goes down with it.
    @Test func aContributionIsShadowedWholeRatherThanPerClaim() {
        let catalog = LanguageCatalog.resolve(
            manifests: [
                manifest(
                    directory: "a.owner",
                    id: "a.owner",
                    languages: #"{ "languageId": "owned", "extensions": ["taken"] }"#
                ),
                manifest(
                    directory: "b.mixed",
                    id: "b.mixed",
                    languages: #"{ "languageId": "mixed", "extensions": ["neverseen", "taken"] }"#
                ),
            ],
            promotions: []
        )
        #expect(catalog.contributed.last?.isActive == false)
        #expect(catalog.contribution(forFileName: "a.neverseen") == nil)
    }

    // MARK: Promotion

    /// Promotion is what a user clicks when the extension they want lost the
    /// tie. It moves one contribution ahead of every unpromoted one, so the
    /// loser of a lexicographic tie becomes the winner.
    @Test func promotionMovesAContributionAheadOfAnUnpromotedOne() {
        let manifests = [
            manifest(
                directory: "alpha.ts",
                id: "alpha.ts",
                languages: #"{ "languageId": "alphats", "extensions": ["ts"] }"#
            ),
            manifest(
                directory: "zeta.ts",
                id: "zeta.ts",
                languages: #"{ "languageId": "zetats", "extensions": ["ts"] }"#
            ),
        ]

        let before = LanguageCatalog.resolve(manifests: manifests, promotions: [])
        #expect(before.contribution(forFileName: "main.ts")?.language.languageID == "alphats")

        let after = LanguageCatalog.resolve(
            manifests: manifests,
            promotions: [LanguagePromotionStore.key(
                extensionID: "zeta.ts",
                languageID: "zetats"
            )]
        )
        #expect(after.contribution(forFileName: "main.ts")?.language.languageID == "zetats")
        #expect(after.contributed.first?.resolution == .active)
    }

    /// A promotion outranks the scope rule as well: a bundled extension the
    /// user promoted beats a user one they did not.
    @Test func aPromotedBundledExtensionOutranksAnUnpromotedUserOne() {
        let catalog = LanguageCatalog.resolve(
            manifests: [
                manifest(
                    directory: "aaa.elixir",
                    id: "aaa.elixir",
                    scope: .bundled,
                    languages: Self.elixir
                ),
                manifest(
                    directory: "zzz.elixir",
                    id: "zzz.elixir",
                    scope: .user,
                    languages: Self.elixir
                ),
            ],
            promotions: [LanguagePromotionStore.key(
                extensionID: "aaa.elixir",
                languageID: "elixir"
            )]
        )
        #expect(catalog.contribution(forFileName: "app.ex")?.provenance.extensionID == "aaa.elixir")
    }

    /// A promotion covers one language of one extension — promoting the
    /// TypeScript half of a pack does not promote whatever else it claimed.
    @Test func promotionIsPerLanguageAndNotPerExtension() {
        let catalog = LanguageCatalog.resolve(
            manifests: [
                manifest(
                    directory: "acme.pack",
                    id: "acme.pack",
                    languages: #"""
                    { "languageId": "packts", "extensions": ["ts"] },
                    { "languageId": "packgo", "extensions": ["go"] }
                    """#
                ),
                manifest(
                    directory: "aaa.rival",
                    id: "aaa.rival",
                    languages: #"""
                    { "languageId": "rivalts", "extensions": ["ts"] },
                    { "languageId": "rivalgo", "extensions": ["go"] }
                    """#
                ),
            ],
            promotions: [LanguagePromotionStore.key(
                extensionID: "acme.pack",
                languageID: "packts"
            )]
        )

        let byID = Dictionary(
            uniqueKeysWithValues: catalog.contributed.map { ($0.language.languageID, $0) }
        )
        #expect(byID["packts"]?.isActive == true)
        #expect(byID["rivalts"]?.isActive == false)
        #expect(byID["packgo"]?.isActive == false)
        #expect(byID["rivalgo"]?.isActive == true)
    }

    // MARK: Scanning

    /// A directory with no manifest, and a loose file beside the extension
    /// directories, are both skipped rather than counted.
    @Test func scanningADirectoryReadsEveryExtensionInIt() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("phantom-catalog-" + UUID().uuidString)
        let user = base.appendingPathComponent("user")
        let bundled = base.appendingPathComponent("bundled")
        defer { try? FileManager.default.removeItem(at: base) }

        func write(_ id: String, in directory: URL) throws {
            let root = directory.appendingPathComponent(id)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let json = #"""
            {
              "id": "\#(id)",
              "contributes": {
                "languages": [{ "languageId": "\#(id.replacingOccurrences(of: ".", with: "-"))" }]
              }
            }
            """#
            try Data(json.utf8).write(to: root.appendingPathComponent(LanguageManifest.fileName))
        }

        try write("acme.one", in: user)
        try write("acme.two", in: user)
        try write("phantom.bundled", in: bundled)

        try FileManager.default.createDirectory(
            at: user.appendingPathComponent("empty"),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: user.appendingPathComponent("stray.json"))

        let catalog = LanguageCatalog.load(bundled: bundled, user: user, promotions: [])

        #expect(catalog.entries.map(\.id) == ["acme.one", "acme.two", "phantom.bundled"])
        #expect(catalog.contributed.count == 3)
        /// Computed outside the macro: `allSatisfy` is `rethrows`, and inside
        /// `#expect`'s expansion Swift cannot prove the closure does not
        /// throw, so the call reads as throwing in a test that is not.
        let allActive = catalog.contributed.allSatisfy(\.isActive)
        #expect(allActive)
    }

    @Test func aMissingDirectoryIsNotAnError() {
        let missing = URL(fileURLWithPath: "/tmp/phantom-does-not-exist-" + UUID().uuidString)
        let catalog = LanguageCatalog.load(bundled: nil, user: missing, promotions: [])
        #expect(catalog == .empty)
    }
}
