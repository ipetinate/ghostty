import Foundation
@testable import Ghostty
import Testing

struct ContributedIconThemeTests {
    private static let iconThemeJSON = #"""
    {
      "iconDefinitions": { "lua": { "iconPath": "./lua.svg" }, "folder": { "iconPath": "./folder.svg" } },
      "fileExtensions": { "lua": "lua" },
      "folder": "folder"
    }
    """#

    private func makeRoot(directory: String, iconThemes: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("phantom-icon-themes-" + UUID().uuidString)
            .appendingPathComponent(directory)
        for name in iconThemes {
            let dir = root.appendingPathComponent("icons/" + name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Self.iconThemeJSON.write(
                to: dir.appendingPathComponent("icon-theme.json"),
                atomically: true,
                encoding: .utf8
            )
            try "<svg/>".write(to: dir.appendingPathComponent("lua.svg"), atomically: true, encoding: .utf8)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func manifest(
        root: URL,
        id: String,
        name: String,
        scope: LanguageManifest.Scope = .user,
        iconThemes: String
    ) -> LanguageManifest {
        let json = #"""
        {
          "schemaVersion": 1,
          "id": "\#(id)",
          "name": "\#(name)",
          "version": "1.0.0",
          "publisher": "acme",
          "contributes": { "iconThemes": [\#(iconThemes)] }
        }
        """#
        return LanguageManifest.parse(
            data: Data(json.utf8),
            url: root.appendingPathComponent(LanguageManifest.fileName),
            root: root,
            scope: scope
        )!
    }

    // MARK: The catalog

    @Test func contributedIconThemesAreAggregatedWithTheirExtensionsName() throws {
        let root = try makeRoot(directory: "acme.lua", iconThemes: ["set"])
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let catalog = LanguageCatalog.resolve(
            manifests: [manifest(
                root: root,
                id: "acme.lua",
                name: "Lua",
                iconThemes: #"{ "name": "Lua Icons", "path": "icons/set" }"#
            )],
            promotions: []
        )

        let entry = try #require(catalog.iconThemes.first)
        #expect(entry.extensionName == "Lua")
        #expect(entry.listIdentity == "acme.lua")
        #expect(entry.id == "acme.lua#iconTheme:Lua Icons")
        #expect(entry.iconTheme.name == "Lua Icons")
        #expect(entry.iconTheme.directoryURL.lastPathComponent == "set")
    }

    @Test func twoExtensionsContributingTheSameNameResolveLexicographically() throws {
        let zeta = try makeRoot(directory: "zeta.pack", iconThemes: ["set"])
        let alpha = try makeRoot(directory: "alpha.pack", iconThemes: ["set"])
        defer {
            try? FileManager.default.removeItem(at: zeta.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: alpha.deletingLastPathComponent())
        }
        let entry = #"{ "name": "Shared Icons", "path": "icons/set" }"#

        let catalog = LanguageCatalog.resolve(
            manifests: [
                manifest(root: zeta, id: "zeta.pack", name: "Zeta", iconThemes: entry),
                manifest(root: alpha, id: "alpha.pack", name: "Alpha", scope: .bundled, iconThemes: entry),
            ],
            promotions: []
        )

        #expect(catalog.iconThemes.map(\.listIdentity) == ["zeta.pack"])
    }

    @Test func theEmptyCatalogHasNoIconThemes() {
        #expect(LanguageCatalog.empty.iconThemes.isEmpty)
    }

    // MARK: The provider's view of it

    @Test func aContributedDirectoryLoadsUnderTheManifestsName() throws {
        let root = try makeRoot(directory: "acme.lua", iconThemes: ["set"])
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let catalog = LanguageCatalog.resolve(
            manifests: [manifest(
                root: root,
                id: "acme.lua",
                name: "Lua",
                iconThemes: #"{ "name": "Lua Icons", "path": "icons/set" }"#
            )],
            promotions: []
        )

        let themes = FileIconProvider.contributedThemes(catalog.iconThemes, excluding: [])
        let theme = try #require(themes.first)
        #expect(theme.name == "Lua Icons")
        #expect(theme.contributedBy == "Lua")
        #expect(theme.isSupported)
        #expect(theme.iconID(forFile: "init.lua") == "lua")
        #expect(theme.iconURL(for: "lua")?.lastPathComponent == "lua.svg")
    }

    @Test func aNameAlreadyInstalledIsNotTakenByAnExtension() throws {
        let root = try makeRoot(directory: "acme.lua", iconThemes: ["set", "other"])
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let catalog = LanguageCatalog.resolve(
            manifests: [manifest(
                root: root,
                id: "acme.lua",
                name: "Lua",
                iconThemes: #"""
                { "name": "symbols", "path": "icons/set" },
                { "name": "Lua Icons", "path": "icons/other" }
                """#
            )],
            promotions: []
        )

        let themes = FileIconProvider.contributedThemes(catalog.iconThemes, excluding: ["symbols"])
        #expect(themes.map(\.name) == ["Lua Icons"])
    }

    @Test func aDirectoryOnDiskStillLoadsUnderItsOwnName() throws {
        let root = try makeRoot(directory: "acme.lua", iconThemes: ["set"])
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let theme = try #require(IconTheme.load(directory: root.appendingPathComponent("icons/set")))
        #expect(theme.name == "set")
        #expect(theme.contributedBy == nil)
    }

    // MARK: One name, one entry

    @Test func aNameAlreadyInstalledIsNotTakenWhateverTheCase() throws {
        let root = try makeRoot(directory: "acme.lua", iconThemes: ["set"])
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let catalog = LanguageCatalog.resolve(
            manifests: [manifest(
                root: root,
                id: "acme.lua",
                name: "Lua",
                iconThemes: #"{ "name": "Symbols", "path": "icons/set" }"#
            )],
            promotions: []
        )

        #expect(FileIconProvider.contributedThemes(catalog.iconThemes, excluding: ["symbols"]).isEmpty)
    }

    @Test func aDirectoryAndAnExtensionNamingOneThemeAreListedOnce() throws {
        let bundled = try makeThemeDirectories(["symbols"])
        let root = try makeRoot(directory: "acme.icons", iconThemes: ["set"])
        defer {
            try? FileManager.default.removeItem(at: bundled)
            try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        }

        let catalog = LanguageCatalog.resolve(
            manifests: [manifest(
                root: root,
                id: "acme.icons",
                name: "Symbols Icons",
                iconThemes: #"{ "name": "Symbols", "path": "icons/set" }"#
            )],
            promotions: []
        )

        let themes = FileIconProvider.themes(inDirectories: [bundled], contributed: catalog.iconThemes)
        #expect(themes.map(\.name) == ["symbols"])
        #expect(themes.first?.contributedBy == nil)
    }

    @Test func twoDirectoriesNamingOneThemeAreListedOnceUnderTheNearestOne() throws {
        let bundled = try makeThemeDirectories(["symbols"])
        let user = try makeThemeDirectories(["Symbols"])
        defer {
            try? FileManager.default.removeItem(at: bundled)
            try? FileManager.default.removeItem(at: user)
        }

        let themes = FileIconProvider.themes(inDirectories: [bundled, user], contributed: [])
        #expect(themes.map(\.name) == ["symbols"])
    }

    @Test func twoThemesWithDifferentNamesAreBothListed() throws {
        let bundled = try makeThemeDirectories(["symbols"])
        let root = try makeRoot(directory: "acme.icons", iconThemes: ["set"])
        defer {
            try? FileManager.default.removeItem(at: bundled)
            try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        }

        let catalog = LanguageCatalog.resolve(
            manifests: [manifest(
                root: root,
                id: "acme.icons",
                name: "Symbols Starter",
                iconThemes: #"{ "name": "Symbols Starter", "path": "icons/set" }"#
            )],
            promotions: []
        )

        let themes = FileIconProvider.themes(inDirectories: [bundled], contributed: catalog.iconThemes)
        #expect(themes.map(\.displayName) == ["Symbols", "Symbols Starter"])
    }

    // MARK: What a pack looks like in a picker

    @Test func aPacksArtworkIsItsOwnPlainFileIcon() throws {
        let container = try makeThemeDirectories(
            ["pack"],
            json: #"{ "iconDefinitions": { "doc": { "iconPath": "./doc.svg" }, "dir": { "iconPath": "./dir.svg" } }, "file": "doc", "folder": "dir" }"#,
            icons: ["doc.svg", "dir.svg"]
        )
        defer { try? FileManager.default.removeItem(at: container) }

        let theme = try #require(IconTheme.load(directory: container.appendingPathComponent("pack")))
        #expect(theme.artworkURL?.lastPathComponent == "doc.svg")
    }

    @Test func aPackNamingNoPlainFileFallsBackToItsFolderIcon() throws {
        let container = try makeThemeDirectories(
            ["pack"],
            json: #"{ "iconDefinitions": { "dir": { "iconPath": "./dir.svg" } }, "folder": "dir" }"#,
            icons: ["dir.svg"]
        )
        defer { try? FileManager.default.removeItem(at: container) }

        let theme = try #require(IconTheme.load(directory: container.appendingPathComponent("pack")))
        #expect(theme.artworkURL?.lastPathComponent == "dir.svg")
    }

    @Test func artworkTheThemeNamesButNeverShippedIsSkipped() throws {
        let container = try makeThemeDirectories(
            ["pack"],
            json: #"{ "iconDefinitions": { "doc": { "iconPath": "./doc.svg" }, "dir": { "iconPath": "./dir.svg" } }, "file": "doc", "folder": "dir" }"#,
            icons: ["dir.svg"]
        )
        defer { try? FileManager.default.removeItem(at: container) }

        let theme = try #require(IconTheme.load(directory: container.appendingPathComponent("pack")))
        #expect(theme.artworkURL?.lastPathComponent == "dir.svg")
    }

    @Test func aPackWithNoArtworkOfItsOwnWearsTheExtensionsIcon() throws {
        let root = try makeRoot(directory: "acme.icons", iconThemes: ["set"])
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let media = root.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try Data([0]).write(to: media.appendingPathComponent("icon.png"))

        let catalog = LanguageCatalog.resolve(
            manifests: [manifest(
                root: root,
                id: "acme.icons",
                name: "Acme Icons",
                iconThemes: #"{ "name": "Acme", "path": "icons/set" }"#
            )],
            promotions: []
        )

        let theme = try #require(FileIconProvider.contributedThemes(catalog.iconThemes, excluding: []).first)
        #expect(theme.artworkURL == media.appendingPathComponent("icon.png"))
    }

    @Test func aPackWithNeitherHasNoArtwork() throws {
        let container = try makeThemeDirectories(
            ["pack"],
            json: #"{ "iconDefinitions": { "doc": { "iconPath": "./doc.svg" } } }"#,
            icons: ["doc.svg"]
        )
        defer { try? FileManager.default.removeItem(at: container) }

        let theme = try #require(IconTheme.load(directory: container.appendingPathComponent("pack")))
        #expect(theme.artworkURL == nil)
    }

    // MARK: Fixtures

    /// One container holding a theme directory per name, the shape the app
    /// bundle and the reader's own `icon-themes` directory both have.
    private func makeThemeDirectories(
        _ names: [String],
        json: String = #"{ "iconDefinitions": { "doc": { "iconPath": "./doc.svg" } }, "file": "doc" }"#,
        icons: [String] = ["doc.svg"]
    ) throws -> URL {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("phantom-icon-theme-dirs-" + UUID().uuidString)
        for name in names {
            let dir = container.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try json.write(
                to: dir.appendingPathComponent("icon-theme.json"),
                atomically: true,
                encoding: .utf8
            )
            for icon in icons {
                try "<svg/>".write(to: dir.appendingPathComponent(icon), atomically: true, encoding: .utf8)
            }
        }
        return container
    }
}
