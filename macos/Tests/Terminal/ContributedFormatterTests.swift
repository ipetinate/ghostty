import Foundation
@testable import Ghostty
import Testing

struct ContributedFormatterTests {
    private func manifest(
        directory: String,
        id: String,
        scope: LanguageManifest.Scope = .user,
        formatters: String
    ) -> LanguageManifest {
        let root = URL(fileURLWithPath: "/tmp/phantom-formatters").appendingPathComponent(directory)
        let json = #"""
        {
          "schemaVersion": 1,
          "id": "\#(id)",
          "name": "\#(id)",
          "version": "1.0.0",
          "publisher": "acme",
          "contributes": { "formatters": [\#(formatters)] }
        }
        """#
        return LanguageManifest.parse(
            data: Data(json.utf8),
            url: root.appendingPathComponent(LanguageManifest.fileName),
            root: root,
            scope: scope
        )!
    }

    private static let zigfmt = #"""
    { "id": "zigfmt", "name": "zig fmt", "command": "zig", "args": ["fmt", "--stdin"], "extensions": ["zig", "zon"] }
    """#

    private static let stylua = #"""
    { "id": "stylua", "name": "StyLua", "command": "stylua", "args": ["-"], "extensions": ["lua"] }
    """#

    /// The same two tools as they would actually be shipped: each asking for
    /// the file's name, and each spelling the option its own way.
    private static let ruffNamingTheFile = #"""
    { "id": "ruff", "name": "Ruff", "command": "ruff",
      "args": ["format", "--stdin-filename", "$FILE", "-"], "extensions": ["py"] }
    """#

    private static let styluaNamingTheFile = #"""
    { "id": "stylua", "name": "StyLua", "command": "stylua",
      "args": ["--stdin-filepath", "$FILE", "-"], "extensions": ["lua"] }
    """#

    // MARK: The catalog

    @Test func aFormatterForFilesNobodyClaimsIsActive() throws {
        let catalog = LanguageCatalog.resolve(
            manifests: [manifest(directory: "acme.zig", id: "acme.zig", formatters: Self.zigfmt)],
            promotions: []
        )

        let contributed = try #require(catalog.formatters.first)
        #expect(contributed.isActive)
        #expect(contributed.id == "acme.zig#formatter:zigfmt")
        #expect(catalog.formatter(forFileName: "main.zig")?.id == contributed.id)
        #expect(catalog.formatter(forFileName: "build.zig.zon")?.id == contributed.id)
        #expect(catalog.formatter(forFileName: "main.rs") == nil)

        let external = try #require(contributed.externalFormatter)
        #expect(external.id == contributed.id)
        #expect(external.command == "zig")
        #expect(external.arguments == ["fmt", "--stdin"])
        #expect(external.extensions == ["zig", "zon"])
        #expect(external.displayName == "zig fmt")
        #expect(external.provenance == contributed.provenance)
        #expect(external.origin == .manifest(contributed.provenance))
    }

    /// Shadowing is all-or-nothing across a formatter's extensions. Only
    /// `zig` is contested here; `py` is the extension nobody else wants, and
    /// it goes down with it — half a formatter, running on one file type and
    /// not the one beside it, is not something a reader could work out.
    @Test func aFormatterIsShadowedWholeWhenOneExtensionIsTaken() {
        let catalog = LanguageCatalog.resolve(
            manifests: [
                manifest(directory: "aaa.zig", id: "aaa.zig", formatters: Self.zigfmt),
                manifest(
                    directory: "zzz.mixed",
                    id: "zzz.mixed",
                    formatters: #"{ "id": "t", "name": "T", "command": "t", "extensions": ["zig", "py"] }"#
                ),
            ],
            promotions: []
        )
        #expect(catalog.formatters.last?.resolution
            == .shadowed(by: .extensionID("aaa.zig"), claim: "ext:zig"))
        #expect(catalog.formatter(forFileName: "main.py") == nil)
    }

    @Test func twoExtensionsClaimingTheSameFilesResolveLexicographically() throws {
        let catalog = LanguageCatalog.resolve(
            manifests: [
                manifest(directory: "zeta.zig", id: "zeta.zig", formatters: Self.zigfmt),
                manifest(directory: "alpha.zig", id: "alpha.zig", formatters: Self.zigfmt),
            ],
            promotions: []
        )

        #expect(catalog.formatters.count == 2)
        let winner = try #require(catalog.formatters.first)
        let loser = try #require(catalog.formatters.last)
        #expect(winner.provenance.extensionID == "alpha.zig")
        #expect(winner.isActive)
        #expect(loser.provenance.extensionID == "zeta.zig")
        #expect(loser.resolution == .shadowed(by: .extensionID("alpha.zig"), claim: "ext:zig"))
        #expect(catalog.formatter(forFileName: "main.zig")?.provenance.extensionID == "alpha.zig")
    }

    @Test func aUserExtensionOutranksABundledOne() throws {
        let catalog = LanguageCatalog.resolve(
            manifests: [
                manifest(directory: "alpha.zig", id: "alpha.zig", scope: .bundled, formatters: Self.zigfmt),
                manifest(directory: "zeta.zig", id: "zeta.zig", scope: .user, formatters: Self.zigfmt),
            ],
            promotions: []
        )
        #expect(catalog.formatters.first?.provenance.extensionID == "zeta.zig")
        #expect(catalog.formatters.first?.isActive == true)
        #expect(catalog.formatters.last?.isActive == false)
    }

    /// The flag that tells a tool which file it is formatting is manifest
    /// data, and it has to survive to the command line spelled exactly as the
    /// manifest spelled it.
    ///
    /// It is not one flag. `ruff` reads `--stdin-filename` and `stylua` reads
    /// `--stdin-filepath`, and neither answers to the other's — so this build
    /// cannot supply the name itself, and nothing here may know which tool is
    /// which. Getting it wrong is silent: the tool formats with its defaults
    /// instead of with the `pyproject.toml` or `stylua.toml` above the file,
    /// and the reader sees a diff they did not ask for rather than an error.
    @Test func theFileFlagAManifestDeclaresReachesTheCommandLine() throws {
        let catalog = LanguageCatalog.resolve(
            manifests: [manifest(
                directory: "acme.tools",
                id: "acme.tools",
                formatters: [Self.ruffNamingTheFile, Self.styluaNamingTheFile, Self.zigfmt]
                    .joined(separator: ",")
            )],
            promotions: []
        )

        let ruff = try #require(LanguageResolver.formatter(forFileNamed: "main.py", catalog: catalog))
        #expect(ruff.arguments == ["format", "--stdin-filename", ExternalFormatter.filePlaceholder, "-"])
        #expect(ruff.invocation == "ruff format --stdin-filename $FILE -")
        #expect(ruff.arguments(for: "/repo/app/main.py")
            == ["format", "--stdin-filename", "/repo/app/main.py", "-"])

        let stylua = try #require(LanguageResolver.formatter(forFileNamed: "init.lua", catalog: catalog))
        #expect(stylua.arguments == ["--stdin-filepath", ExternalFormatter.filePlaceholder, "-"])
        #expect(stylua.arguments(for: "/repo/init.lua") == ["--stdin-filepath", "/repo/init.lua", "-"])
        #expect(!stylua.invocation.contains("--stdin-filename"))

        /// A tool that never asked for the name is handed nothing extra:
        /// the substitution replaces a placeholder, it does not append one.
        let zig = try #require(LanguageResolver.formatter(forFileNamed: "main.zig", catalog: catalog))
        #expect(zig.arguments(for: "/repo/main.zig") == ["fmt", "--stdin"])
    }

    @Test func theEmptyCatalogHasNoFormatters() {
        #expect(LanguageCatalog.empty.formatters.isEmpty)
        #expect(LanguageCatalog.empty.formatter(forFileName: "main.zig") == nil)
    }

    // MARK: Resolution order

    /// The resolver answers out of the installed extensions and out of
    /// nothing else. A file no manifest claims has no formatter, which is the
    /// normal case rather than a gap.
    @Test func theResolverAnswersOnlyFromWhatIsInstalled() throws {
        let catalog = LanguageCatalog.resolve(
            manifests: [manifest(
                directory: "acme.pack",
                id: "acme.pack",
                formatters: Self.zigfmt + "," + Self.stylua
            )],
            promotions: []
        )

        let lua = try #require(LanguageResolver.formatter(forFileNamed: "init.lua", catalog: catalog))
        #expect(lua.id == "acme.pack#formatter:stylua")
        #expect(lua.provenance?.extensionID == "acme.pack")
        #expect(lua.origin == .manifest(try #require(lua.provenance)))

        let zig = try #require(LanguageResolver.formatter(forFileNamed: "main.zig", catalog: catalog))
        #expect(zig.id == "acme.pack#formatter:zigfmt")
        #expect(zig.provenance?.extensionID == "acme.pack")

        #expect(LanguageResolver.formatter(forFileNamed: "main.rs", catalog: catalog) == nil)
        #expect(LanguageResolver.formatter(forFileNamed: "Makefile", catalog: catalog) == nil)
        #expect(LanguageResolver.formatter(forFileNamed: "init.lua", catalog: .empty) == nil)
    }

    @Test func theReadersSettingsKeepTheProvenance() throws {
        let catalog = LanguageCatalog.resolve(
            manifests: [manifest(directory: "acme.zig", id: "acme.zig", formatters: Self.zigfmt)],
            promotions: []
        )
        let external = try #require(catalog.formatters.first?.externalFormatter)

        var setting = ExternalFormatterSetting()
        setting.command = "/opt/zig/zig"
        let effective = try #require(ExternalFormatterStore.effective(external, setting: setting))
        #expect(effective.command == "/opt/zig/zig")
        #expect(effective.provenance == external.provenance)
    }

    // MARK: Trust across two programs

    private static let provenance = ExtensionProvenance(
        extensionID: "acme.lua",
        digest: "aa11",
        manifestPath: "/Users/x/.config/phantom/extensions/acme.lua/extension.json",
        scope: .user
    )

    private func subject(
        command: String,
        resolvedPath: String,
        digest: String = "aa11"
    ) -> LanguageTrust.Subject {
        LanguageTrust.Subject(
            origin: .manifest(Self.provenance),
            digest: digest,
            command: command,
            resolvedPath: resolvedPath,
            workspaceRoot: "/Users/x/project"
        )
    }

    private var server: LanguageTrust.Subject {
        subject(command: "lua-language-server", resolvedPath: "/opt/homebrew/bin/lua-language-server")
    }

    private var formatter: LanguageTrust.Subject {
        subject(command: "stylua", resolvedPath: "/opt/homebrew/bin/stylua")
    }

    @Test func aSecondProgramFromAnApprovedExtensionIsAskedAboutAndNamesTheFirst() {
        let record = LanguageTrust.record(for: server, decision: .allowed)
        #expect(LanguageTrust.verdict(for: server, record: record) == .allow)
        #expect(
            LanguageTrust.verdict(for: formatter, record: record)
                == .ask(.commandChanged(previous: "lua-language-server"))
        )
    }

    @Test func approvingTheSecondProgramKeepsTheFirstApproved() {
        let first = LanguageTrust.record(for: server, decision: .allowed)
        let both = LanguageTrust.record(for: formatter, decision: .allowed, extending: first)

        #expect(both.command == "stylua")
        #expect(both.approvedPrograms.map(\.command) == ["stylua", "lua-language-server"])
        #expect(LanguageTrust.verdict(for: server, record: both) == .allow)
        #expect(LanguageTrust.verdict(for: formatter, record: both) == .allow)
    }

    @Test func aReApprovalOfTheSameProgramDoesNotDuplicateIt() {
        let first = LanguageTrust.record(for: server, decision: .allowed)
        let again = LanguageTrust.record(for: server, decision: .allowed, extending: first)
        #expect(again.approvedPrograms.count == 1)
        #expect(again.programs == nil)
    }

    @Test func aMovedBinaryInvalidatesOnlyItsOwnProgram() {
        let first = LanguageTrust.record(for: server, decision: .allowed)
        let both = LanguageTrust.record(for: formatter, decision: .allowed, extending: first)
        let moved = subject(command: "stylua", resolvedPath: "/usr/local/bin/stylua")

        #expect(
            LanguageTrust.verdict(for: moved, record: both)
                == .ask(.commandPathChanged(previous: "/opt/homebrew/bin/stylua"))
        )
        #expect(LanguageTrust.verdict(for: server, record: both) == .allow)
    }

    @Test func aRefusalReplacesEveryEarlierApproval() {
        let approved = LanguageTrust.record(for: server, decision: .allowed)
        let refused = LanguageTrust.record(for: formatter, decision: .refused, extending: approved)

        #expect(refused.programs == nil)
        #expect(refused.decision == .refused)
        #expect(
            LanguageTrust.verdict(for: server, record: refused)
                == .deny(.refusedByUser(at: refused.decidedAt))
        )
    }

    @Test func anApprovalDoesNotExtendARefusalOrADifferentManifest() {
        let refused = LanguageTrust.record(for: server, decision: .refused)
        let afterRefusal = LanguageTrust.record(for: formatter, decision: .allowed, extending: refused)
        #expect(afterRefusal.approvedPrograms.map(\.command) == ["stylua"])

        let approved = LanguageTrust.record(for: server, decision: .allowed)
        let edited = subject(command: "stylua", resolvedPath: "/opt/homebrew/bin/stylua", digest: "bb22")
        let afterEdit = LanguageTrust.record(for: edited, decision: .allowed, extending: approved)
        #expect(afterEdit.approvedPrograms.map(\.command) == ["stylua"])
        #expect(afterEdit.digest == "bb22")
    }

    @Test func aRecordWrittenBeforeProgramsExistedStillDecodes() throws {
        let legacy = Data(#"""
        {"recordVersion":1,"digest":"aa11","command":"lua-language-server",
         "resolvedPath":"/opt/homebrew/bin/lua-language-server",
         "manifestPath":"/Users/x/.config/phantom/extensions/acme.lua/extension.json",
         "decision":"allowed","decidedAt":700000000}
        """#.utf8)
        let record = try JSONDecoder().decode(LanguageTrustRecord.self, from: legacy)

        #expect(record.programs == nil)
        #expect(record.approvedPrograms.map(\.command) == ["lua-language-server"])
        #expect(LanguageTrust.verdict(for: server, record: record) == .allow)
    }

    @Test func rememberingMergesIntoTheStoredRecord() {
        withCleanTrustDefaults {
            LanguageTrustStore.remember(.allowed, for: server)
            LanguageTrustStore.remember(.allowed, for: formatter)

            let stored = LanguageTrustStore.record(for: "acme.lua")
            #expect(stored?.approvedPrograms.map(\.command) == ["stylua", "lua-language-server"])
            #expect(LanguageTrust.verdict(for: server, record: stored) == .allow)
            #expect(LanguageTrust.verdict(for: formatter, record: stored) == .allow)
        }
    }

    private func withCleanTrustDefaults(_ body: () -> Void) {
        let key = LanguageTrustStore.defaultsKey
        let stored = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer {
            if let stored {
                UserDefaults.standard.set(stored, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        body()
    }

    // MARK: The prompt

    private func prompt(role: LanguageTrustAlert.Request.Role) -> LanguageTrustAlert.Request {
        LanguageTrustAlert.Request(
            extensionName: "Lua",
            extensionID: "acme.lua",
            publisher: "acme",
            extensionVersion: "1.0.0",
            languageName: ".lua",
            command: "stylua",
            arguments: ["-"],
            resolvedPath: "/opt/homebrew/bin/stylua",
            manifestPath: "/Users/x/.config/phantom/extensions/acme.lua/extension.json",
            change: .firstRun,
            role: role
        )
    }

    @Test func thePromptNamesAFormatterAsOne() {
        let request = prompt(role: .formatter(tool: "StyLua"))

        #expect(LanguageTrustAlert.messageText(for: request) == "Run a Formatter from \u{201c}Lua\u{201d}?")
        #expect(LanguageTrustAlert.confirmButtonTitle(for: request) == "Run Formatter")

        let text = LanguageTrustAlert.informativeText(for: request)
        #expect(text.contains("wants to run StyLua to format .lua files"))
        #expect(!text.contains("language server for"))
        #expect(text.contains("runs as you"))
    }

    @Test func thePromptStillNamesAServerAsOneByDefault() {
        let request = prompt(role: .languageServer)

        #expect(LanguageTrustAlert.messageText(for: request) == "Run a Language Server from \u{201c}Lua\u{201d}?")
        #expect(LanguageTrustAlert.confirmButtonTitle(for: request) == "Run Language Server")
        #expect(LanguageTrustAlert.informativeText(for: request).contains("start a language server for .lua"))
    }

    @Test func aToolNameOutOfAManifestIsEscapedInTheProse() {
        let request = prompt(role: .formatter(tool: "Sty\u{202E}Lua"))
        let text = LanguageTrustAlert.informativeText(for: request)
        #expect(!text.unicodeScalars.contains("\u{202E}"))
        #expect(text.contains("\\u{202E}"))
    }
}
