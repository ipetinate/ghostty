import Foundation
@testable import Ghostty
import Testing

/// `contributes.servers`: a server that attaches beside a language's own.
///
/// The shape is the Tailwind one — a binary that completes inside `class`
/// attributes in languages it does not own, and only in a project that has
/// Tailwind installed — and the parse is the `languages[].server` parse with
/// two fields beside it: which language ids it attaches to, and what the
/// project has to show first.
struct CompanionServerContributionTests {
    private static let tailwind = #"""
    {
      "name": "Tailwind CSS",
      "command": "tailwindcss-language-server",
      "args": ["--stdio"],
      "languageIds": ["html", "vue", "typescriptreact", "javascriptreact", "javascript"],
      "projectMarkers": ["node_modules/tailwindcss"],
      "category": "styles",
      "installHint": "npm i -g @tailwindcss/language-server",
      "documentationURL": "https://github.com/tailwindlabs/tailwindcss-intellisense",
      "install": {
        "commands": [
          {
            "manager": "npm",
            "command": "npm install -g @tailwindcss/language-server",
            "uninstall": "npm uninstall -g @tailwindcss/language-server"
          }
        ]
      }
    }
    """#

    private func manifest(
        id: String = "acme.tailwind",
        schemaVersion: Int = 1,
        servers: String
    ) -> LanguageManifest {
        let root = URL(fileURLWithPath: "/tmp/phantom-servers").appendingPathComponent(id)
        let json = #"""
        {
          "schemaVersion": \#(schemaVersion),
          "id": "\#(id)",
          "name": "Tailwind",
          "version": "1.0.0",
          "publisher": "acme",
          "contributes": { "servers": [\#(servers)] }
        }
        """#
        return LanguageManifest.parse(
            data: Data(json.utf8),
            url: root.appendingPathComponent(LanguageManifest.fileName),
            root: root,
            scope: .user
        )!
    }

    @Test func theTailwindShapeParsesWhole() throws {
        let manifest = manifest(servers: Self.tailwind)
        let server = try #require(manifest.servers.first)

        #expect(server.displayName == "Tailwind CSS")
        #expect(server.command == "tailwindcss-language-server")
        #expect(server.arguments == ["--stdio"])
        #expect(server.languageIDs == ["html", "vue", "typescriptreact", "javascriptreact", "javascript"])
        #expect(server.projectRules.markers == [.file("node_modules/tailwindcss")])
        #expect(server.projectRules.declaresAdoption)
        #expect(server.category == .styles)
        #expect(server.installHint == "npm i -g @tailwindcss/language-server")
        #expect(server.documentationURL?.host == "github.com")
        #expect(server.installPlan?.commands.first?.manager == .npm)
        #expect(server.installPlan?.commands.first?.uninstall
            == "npm uninstall -g @tailwindcss/language-server")
        #expect(server.resolver == .none)
        #expect(server.maximumJavaFeatureVersion == nil)
    }

    @Test func aServerIsAContributionOnItsOwn() {
        let manifest = manifest(servers: Self.tailwind)

        #expect(manifest.isUsable)
        #expect(manifest.languages.isEmpty)
        #expect(!manifest.unrecognizedFields.contains("contributes.servers"))
    }

    /// A server with nothing to attach to would never start, so the entry is
    /// dropped rather than listed.
    @Test func anEntryWithNoLanguageIsRefused() {
        let missing = manifest(servers: #"{ "command": "tailwindcss-language-server" }"#)
        #expect(missing.servers.isEmpty)

        let empty = manifest(servers: #"{ "command": "x-ls", "languageIds": [] }"#)
        #expect(empty.servers.isEmpty)
    }

    /// The same refusal the language half applies: a command that only means
    /// what it says to a shell is not a command.
    @Test func anUnsafeCommandIsRefused() {
        let manifest = manifest(
            servers: #"{ "command": "tailwindcss-language-server; rm -rf ~", "languageIds": ["html"] }"#
        )
        #expect(manifest.servers.isEmpty)
    }

    /// A program is a program whichever key declares it, so the schema rule
    /// that discards the server half of a manifest this build cannot read
    /// discards these too.
    @Test func aLaterSchemaKeepsNoServers() {
        let manifest = manifest(schemaVersion: 99, servers: Self.tailwind)
        #expect(manifest.servers.isEmpty)
        #expect(manifest.eligibility == .needsNewerApp(declared: "99"))
    }

    @Test func languageIDsAreLoweredDedupedAndValidated() {
        let manifest = manifest(
            servers: #"{ "command": "x-ls", "languageIds": ["HTML", "html", "bad/id", "vue"] }"#
        )
        #expect(manifest.servers.first?.languageIDs == ["html", "vue"])
    }

    @Test func theNameFallsBackToTheCommandAndTheCategoryToScript() throws {
        let manifest = manifest(servers: #"{ "command": "x-ls", "languageIds": ["html"] }"#)
        let server = try #require(manifest.servers.first)

        #expect(server.displayName == "x-ls")
        #expect(server.category == .script)
        #expect(!server.projectRules.declaresAdoption)
    }

    @Test func oneCommandIsKeptOncePerManifest() {
        let manifest = manifest(servers: """
        { "command": "x-ls", "languageIds": ["html"] },
        { "command": "x-ls", "languageIds": ["vue"] }
        """)

        #expect(manifest.servers.count == 1)
        #expect(manifest.servers.first?.languageIDs == ["html"])
    }

    // MARK: The fields any server block may carry

    /// A resolver names a capability the binary implements. The plugin and
    /// the languages it registers for come from the manifest, so the same
    /// code serves an extension this build has never seen.
    @Test func aPluginHostResolverCarriesItsPluginAndLanguages() {
        let manifest = manifest(servers: #"""
        {
          "command": "typescript-language-server",
          "languageIds": ["vue"],
          "resolver": {
            "kind": "typescriptPluginHost",
            "plugin": "@vue/typescript-plugin",
            "languages": ["vue"]
          }
        }
        """#)

        #expect(manifest.servers.first?.resolver
            == .typeScriptPluginHost(plugin: "@vue/typescript-plugin", languages: ["vue"]))
    }

    @Test func theSDKArgumentResolverNeedsNothingBesideItsKind() {
        let manifest = manifest(servers: #"""
        { "command": "vue-language-server", "languageIds": ["vue"],
          "resolver": { "kind": "typescriptSDKArgument" } }
        """#)

        #expect(manifest.servers.first?.resolver == .typeScriptSDKArgument)
    }

    /// A kind this build does not implement reads as no resolver, the same
    /// way an unknown `contributes` key does: the server still starts,
    /// without the glue.
    @Test func anUnknownResolverKindIsNoResolver() {
        let manifest = manifest(
            servers: #"{ "command": "x-ls", "languageIds": ["html"], "resolver": { "kind": "future" } }"#
        )
        #expect(manifest.servers.first?.resolver == LSPInitializationOptionsKind.none)
    }

    /// The plugin name is joined onto two directories this app then reads,
    /// so a path escape in it is a manifest choosing which code a language
    /// server loads.
    @Test func aPluginThatIsNotAPackageNameIsRefused() {
        for plugin in ["../../evil", "/etc/passwd", ".hidden", "Upper/Case"] {
            let manifest = manifest(servers: #"""
            { "command": "x-ls", "languageIds": ["html"],
              "resolver": { "kind": "typescriptPluginHost", "plugin": "\#(plugin)",
                            "languages": ["html"] } }
            """#)
            #expect(manifest.servers.first?.resolver == LSPInitializationOptionsKind.none, "\(plugin)")
        }
    }

    @Test func aPluginHostWithNoLanguagesIsNoResolver() {
        let manifest = manifest(servers: #"""
        { "command": "x-ls", "languageIds": ["html"],
          "resolver": { "kind": "typescriptPluginHost", "plugin": "some-plugin" } }
        """#)
        #expect(manifest.servers.first?.resolver == LSPInitializationOptionsKind.none)
    }

    @Test func literalInitializationOptionsSurviveAsSortedJSON() {
        let manifest = manifest(servers: #"""
        { "command": "x-ls", "languageIds": ["json"],
          "initializationOptions": { "provideFormatter": true } }
        """#)

        #expect(manifest.servers.first?.initializationOptionsJSON == #"{"provideFormatter":true}"#)
    }

    /// `true` bridges to `Int` as 1, so a ceiling has to reject a boolean
    /// rather than read it as Java 1.
    @Test func aJavaCeilingIsAnIntegerAndNothingElse() {
        let good = manifest(
            servers: #"{ "command": "jdtls", "languageIds": ["java"], "maximumJavaFeatureVersion": 21 }"#
        )
        #expect(good.servers.first?.maximumJavaFeatureVersion == 21)

        for bad in ["true", "\"21\"", "0", "21.5"] {
            let manifest = manifest(
                servers: #"{ "command": "jdtls", "languageIds": ["java"], "maximumJavaFeatureVersion": \#(bad) }"#
            )
            #expect(manifest.servers.first?.maximumJavaFeatureVersion == nil, "\(bad)")
        }
    }

    /// `${HOME}` is left alone at the parse and expanded at launch, because
    /// only the launch knows whose home it is.
    @Test func homeInAnArgumentSurvivesTheParseAndExpandsAtLaunch() throws {
        let manifest = manifest(servers: #"""
        { "command": "jdtls", "languageIds": ["java"],
          "args": ["-data", "${HOME}/.cache/jdtls-workspace"] }
        """#)
        let server = try #require(manifest.servers.first)

        #expect(server.arguments == ["-data", "${HOME}/.cache/jdtls-workspace"])
        #expect(LSPProcess.expandingHome("${HOME}/.cache/jdtls-workspace")
            == NSHomeDirectory() + "/.cache/jdtls-workspace")
        #expect(LSPProcess.expandingHome("--stdio") == "--stdio")
    }
}
