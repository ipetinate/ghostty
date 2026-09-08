import Foundation
@testable import Ghostty
import Testing

/// Which contributed servers attach beside a language's own, and the two
/// shapes that takes: a companion the project asked for by a marker, and a
/// tsserver hosting a plugin for a language it does not otherwise know.
struct LanguageCompanionTests {
    private func manifest(
        directory: String,
        id: String,
        languages: String = "",
        servers: String = ""
    ) -> LanguageManifest {
        let root = URL(fileURLWithPath: "/tmp/phantom-companions").appendingPathComponent(directory)
        let json = #"""
        {
          "schemaVersion": 1,
          "id": "\#(id)",
          "name": "\#(id)",
          "version": "2.0.0",
          "publisher": "acme",
          "contributes": { "languages": [\#(languages)], "servers": [\#(servers)] }
        }
        """#
        return LanguageManifest.parse(
            data: Data(json.utf8),
            url: root.appendingPathComponent(LanguageManifest.fileName),
            root: root,
            scope: .user
        )!
    }

    private static let tailwind = #"""
    {
      "name": "Tailwind CSS",
      "command": "tailwindcss-language-server",
      "args": ["--stdio"],
      "languageIds": ["html", "vue", "typescriptreact", "javascriptreact", "javascript"],
      "projectMarkers": ["node_modules/tailwindcss"]
    }
    """#

    // MARK: companionServers(forLanguageID:)

    @Test func aCompanionAttachesToTheLanguagesItNamesAndNoOther() {
        let catalog = LanguageCatalog.resolve(
            manifests: [manifest(directory: "acme.tailwind", id: "acme.tailwind", servers: Self.tailwind)],
            promotions: []
        )

        #expect(catalog.companionServers(forLanguageID: "html").map(\.server.displayName) == ["Tailwind CSS"])
        #expect(catalog.companionServers(forLanguageID: "HTML").count == 1)
        #expect(catalog.companionServers(forLanguageID: "javascript").count == 1)
        #expect(catalog.companionServers(forLanguageID: "typescript").isEmpty)
        #expect(catalog.companionServers(forLanguageID: "css").isEmpty)
    }

    /// The definition is keyed by the **file's** language id: `didOpen`
    /// announces it, and the server picks how to read the document from it.
    @Test func theDefinitionCarriesTheFilesLanguageAndTheExtensionsProvenance() throws {
        let catalog = LanguageCatalog.resolve(
            manifests: [manifest(directory: "acme.tailwind", id: "acme.tailwind", servers: Self.tailwind)],
            promotions: []
        )
        let companion = try #require(catalog.servers.first)

        let definition = try #require(companion.serverDefinition(forLanguage: "typescriptreact"))
        #expect(definition.languageID == "typescriptreact")
        #expect(definition.command == "tailwindcss-language-server")
        #expect(definition.arguments == ["--stdio"])
        #expect(definition.displayName == "Tailwind CSS")
        #expect(definition.origin == .manifest(companion.provenance))
        #expect(definition.initializationOptionsKind == .none)

        #expect(companion.serverDefinition(forLanguage: "typescript") == nil)
    }

    /// Two extensions attaching one binary would run it twice for one file,
    /// so the second is shadowed — by directory name, like everything else.
    @Test func oneBinaryAttachesOnceAcrossExtensions() throws {
        let catalog = LanguageCatalog.resolve(
            manifests: [
                manifest(directory: "zeta.tailwind", id: "zeta.tailwind", servers: Self.tailwind),
                manifest(directory: "alpha.tailwind", id: "alpha.tailwind", servers: Self.tailwind),
            ],
            promotions: []
        )

        #expect(catalog.servers.count == 2)
        #expect(catalog.servers.first?.provenance.extensionID == "alpha.tailwind")
        #expect(catalog.servers.first?.isActive == true)
        #expect(catalog.servers.last?.resolution
            == .shadowed(by: .extensionID("alpha.tailwind"), claim: "server:tailwindcss-language-server"))
        #expect(catalog.companionServers(forLanguageID: "html").count == 1)
    }

    @Test func twoDifferentBinariesBothAttach() {
        let emmet = #"{ "command": "emmet-ls", "languageIds": ["html"] }"#
        let catalog = LanguageCatalog.resolve(
            manifests: [
                manifest(directory: "acme.tailwind", id: "acme.tailwind", servers: Self.tailwind),
                manifest(directory: "acme.emmet", id: "acme.emmet", servers: emmet),
            ],
            promotions: []
        )

        #expect(catalog.companionServers(forLanguageID: "html").map(\.server.command)
            == ["emmet-ls", "tailwindcss-language-server"])
    }

    // MARK: attaches(toFile:)

    private func inRepository(
        _ directories: [String],
        _ body: (String) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("phantom-companion-\(UUID().uuidString)")
        for directory in directories + [".git"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(directory),
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root.path)
    }

    private func tailwindCompanion() throws -> LanguageCatalog.ContributedServer {
        let catalog = LanguageCatalog.resolve(
            manifests: [manifest(directory: "acme.tailwind", id: "acme.tailwind", servers: Self.tailwind)],
            promotions: []
        )
        return try #require(catalog.servers.first)
    }

    @Test func attachesWhereTheMarkerIsBesideTheFile() throws {
        let companion = try tailwindCompanion()
        try inRepository(["src", "node_modules/tailwindcss"]) { root in
            #expect(companion.attaches(toFile: root + "/src/App.tsx"))
        }
    }

    /// A monorepo hoists `node_modules` to the repository root, which is
    /// where the walk up from the file finds it.
    @Test func attachesWhereTheMarkerIsHoistedToTheRepositoryRoot() throws {
        let companion = try tailwindCompanion()
        try inRepository(["apps/web/src", "node_modules/tailwindcss"]) { root in
            #expect(companion.attaches(toFile: root + "/apps/web/src/App.tsx"))
        }
    }

    @Test func doesNotAttachWithoutTheMarker() throws {
        let companion = try tailwindCompanion()
        try inRepository(["src", "node_modules/react"]) { root in
            #expect(!companion.attaches(toFile: root + "/src/App.tsx"))
        }
    }

    /// Rules that declare nothing are the tool that attaches everywhere.
    @Test func attachesEverywhereWhenNoMarkerIsDeclared() throws {
        let catalog = LanguageCatalog.resolve(
            manifests: [manifest(
                directory: "acme.emmet",
                id: "acme.emmet",
                servers: #"{ "command": "emmet-ls", "languageIds": ["html"] }"#
            )],
            promotions: []
        )
        let companion = try #require(catalog.servers.first)
        try inRepository(["src"]) { root in
            #expect(companion.attaches(toFile: root + "/src/index.html"))
        }
    }

    // MARK: The TypeScript half of a .vue

    /// The second process a `.vue` needs is a companion like any other: the
    /// extension declares it, names the plugin, and names the languages the
    /// plugin registers for. Nothing in the binary knows what Vue is.
    private static let vueTypeScriptPeer = #"""
    {
      "name": "TypeScript (Vue)",
      "command": "typescript-language-server",
      "args": ["--stdio"],
      "languageIds": ["vue"],
      "resolver": {
        "kind": "typescriptPluginHost",
        "plugin": "@vue/typescript-plugin",
        "languages": ["vue"]
      }
    }
    """#

    /// Announced as `vue`, not as `typescript`. The plugin's `languages`
    /// array becomes tsserver's `modeIds`, which is what registers the
    /// process for `vue` at all, and the document has to arrive announced as
    /// `vue` to match it. It also keeps the process on its own
    /// `LSPCenter.Key` — same language, same root, different command.
    @Test func thePluginHostIsAnnouncedAsTheLanguageItWasDeclaredFor() throws {
        let catalog = LanguageCatalog.resolve(
            manifests: [manifest(directory: "acme.vue", id: "acme.vue", servers: Self.vueTypeScriptPeer)],
            promotions: []
        )
        let companion = try #require(catalog.servers.first)

        let peer = try #require(companion.serverDefinition(forLanguage: "vue"))
        #expect(peer.languageID == "vue")
        #expect(peer.command == "typescript-language-server")
        #expect(peer.arguments == ["--stdio"])
        #expect(peer.origin == .manifest(companion.provenance))
        #expect(peer.initializationOptionsKind
            == .typeScriptPluginHost(plugin: "@vue/typescript-plugin", languages: ["vue"]))

        #expect(companion.serverDefinition(forLanguage: "typescript") == nil)
    }

    /// The resolver carries the plugin and its languages from the manifest,
    /// so the same capability serves an extension nobody has written yet.
    @Test func aPluginHostForSomeOtherFrameworkResolvesTheSameWay() throws {
        let catalog = LanguageCatalog.resolve(
            manifests: [manifest(directory: "acme.svelte", id: "acme.svelte", servers: #"""
            {
              "command": "typescript-language-server",
              "args": ["--stdio"],
              "languageIds": ["svelte"],
              "resolver": {
                "kind": "typescriptPluginHost",
                "plugin": "typescript-svelte-plugin",
                "languages": ["svelte"]
              }
            }
            """#)],
            promotions: []
        )
        let peer = try #require(catalog.servers.first?.serverDefinition(forLanguage: "svelte"))
        #expect(peer.initializationOptionsKind
            == .typeScriptPluginHost(plugin: "typescript-svelte-plugin", languages: ["svelte"]))
    }

    /// With no extension declaring one, there is no peer — and the binary
    /// has nothing to fall back on, which is the point.
    @Test func withoutADeclaredPluginHostThereIsNoPeer() {
        let catalog = LanguageCatalog.resolve(
            manifests: [manifest(directory: "acme.tailwind", id: "acme.tailwind", servers: Self.tailwind)],
            promotions: []
        )
        #expect(catalog.companionServers(forLanguageID: "vue").allSatisfy {
            $0.server.resolver == LSPInitializationOptionsKind.none
        })
        #expect(LanguageCatalog.empty.companionServers(forLanguageID: "vue").isEmpty)
    }
}
