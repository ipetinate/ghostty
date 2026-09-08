import Foundation
@testable import Ghostty
import Testing

/// `IconTheme`'s resolution rules, which decide what every row in the file
/// explorer looks like.
///
/// The rule worth guarding is the extension one: themes key off multi-part
/// extensions (`component.ts`, `spec.ts`, `d.ts`, `tar.gz` are all real
/// entries in the bundled Symbols theme), so a last-dot-only split would
/// silently show plain TypeScript icons for every Angular component in a
/// project and look merely underwhelming rather than broken.
struct IconThemeTests {
    private func theme(
        definitions: [String: String] = ["fallback": "./f.svg"],
        fileExtensions: [String: String] = [:],
        fileNames: [String: String] = [:],
        languageIds: [String: String] = [:],
        folderNames: [String: String] = [:],
        folderNamesExpanded: [String: String] = [:],
        rootFolderNames: [String: String] = [:],
        rootFolderNamesExpanded: [String: String] = [:],
        defaultFile: String? = "fallback",
        defaultFolder: String? = "folder",
        defaultFolderExpanded: String? = nil,
        defaultRootFolder: String? = nil,
        defaultRootFolderExpanded: String? = nil,
        light: IconTheme.Overrides? = nil
    ) -> IconTheme {
        IconTheme(
            name: "test",
            root: URL(fileURLWithPath: "/tmp/theme"),
            definitions: definitions,
            fileExtensions: fileExtensions,
            fileNames: fileNames,
            languageIds: languageIds,
            folderNames: folderNames,
            folderNamesExpanded: folderNamesExpanded,
            rootFolderNames: rootFolderNames,
            rootFolderNamesExpanded: rootFolderNamesExpanded,
            defaultFile: defaultFile,
            defaultFolder: defaultFolder,
            defaultFolderExpanded: defaultFolderExpanded,
            defaultRootFolder: defaultRootFolder,
            defaultRootFolderExpanded: defaultRootFolderExpanded,
            light: light
        )
    }

    // MARK: Extension candidates

    @Test func candidatesAreLongestFirst() {
        #expect(IconTheme.extensionCandidates(for: "my.component.ts") == ["component.ts", "ts"])
    }

    @Test func aSingleExtensionYieldsOneCandidate() {
        #expect(IconTheme.extensionCandidates(for: "main.swift") == ["swift"])
    }

    @Test func aNameWithNoDotYieldsNoCandidates() {
        #expect(IconTheme.extensionCandidates(for: "makefile").isEmpty)
    }

    @Test func aDotfileYieldsTheNameAfterTheDot() {
        #expect(IconTheme.extensionCandidates(for: ".gitignore") == ["gitignore"])
    }

    // MARK: File resolution

    /// The whole reason candidates are ordered: `component.ts` has to win
    /// over the `ts` that also matches.
    @Test func aLongerExtensionBeatsAShorterOne() {
        let subject = theme(fileExtensions: ["ts": "typescript", "component.ts": "angular"])
        #expect(subject.iconID(forFile: "hero.component.ts") == "angular")
        #expect(subject.iconID(forFile: "hero.ts") == "typescript")
    }

    @Test func anExactFileNameBeatsAnyExtension() {
        let subject = theme(
            fileExtensions: ["json": "json"],
            fileNames: ["package.json": "node"]
        )
        #expect(subject.iconID(forFile: "package.json") == "node")
        #expect(subject.iconID(forFile: "tsconfig.json") == "json")
    }

    @Test func lookupIsCaseInsensitive() {
        let subject = theme(
            fileExtensions: ["swift": "swift"],
            fileNames: ["dockerfile": "docker"]
        )
        #expect(subject.iconID(forFile: "Dockerfile") == "docker")
        #expect(subject.iconID(forFile: "Main.SWIFT") == "swift")
    }

    @Test func anUnknownFileFallsBackToTheThemeDefault() {
        #expect(theme().iconID(forFile: "mystery.xyz") == "fallback")
    }

    // MARK: languageIds fallback

    /// The bundled Symbols theme defines a Vue icon but never lists `vue`
    /// under `fileExtensions` — it keys it by language only. Skipping
    /// `languageIds` therefore drew a blank page for every `.vue` file,
    /// which is what this covers.
    @Test func anExtensionThatDoublesAsALanguageIDResolves() {
        let subject = theme(languageIds: ["vue": "vue-icon", "php": "php-icon"])
        #expect(subject.iconID(forFile: "App.vue") == "vue-icon")
        #expect(subject.iconID(forFile: "index.php") == "php-icon")
    }

    @Test func extensionsWhoseLanguageIDDiffersResolveThroughTheTable() {
        let subject = theme(languageIds: ["csharp": "cs-icon", "objective-c": "objc-icon"])
        #expect(subject.iconID(forFile: "Program.cs") == "cs-icon")
        #expect(subject.iconID(forFile: "View.m") == "objc-icon")
    }

    /// Precedence still holds: an explicit extension mapping is more
    /// specific than a language guess and has to win.
    @Test func fileExtensionsStillBeatTheLanguageFallback() {
        let subject = theme(
            fileExtensions: ["vue": "from-extension"],
            languageIds: ["vue": "from-language"]
        )
        #expect(subject.iconID(forFile: "App.vue") == "from-extension")
    }

    @Test func anUnknownLanguageStillFallsBackToTheDefault() {
        let subject = theme(languageIds: ["vue": "vue-icon"])
        #expect(subject.iconID(forFile: "notes.xyz") == "fallback")
    }

    // MARK: Folder resolution

    @Test func folderNamesResolveBeforeTheDefault() {
        let subject = theme(folderNames: ["src": "folder-src"])
        #expect(subject.iconID(forFolder: "src", expanded: false) == "folder-src")
        #expect(subject.iconID(forFolder: "whatever", expanded: false) == "folder")
    }

    @Test func expandedFoldersPreferTheirOwnArtworkWhenTheThemeHasIt() {
        let subject = theme(
            folderNames: ["src": "folder-src"],
            folderNamesExpanded: ["src": "folder-src-open"],
            defaultFolderExpanded: "folder-open"
        )
        #expect(subject.iconID(forFolder: "src", expanded: true) == "folder-src-open")
        #expect(subject.iconID(forFolder: "other", expanded: true) == "folder-open")
    }

    /// The bundled Symbols theme defines no expanded variants at all, so
    /// expanding a folder must not blank its icon.
    @Test func expandingFallsBackToTheClosedIconWhenNoExpandedVariantExists() {
        let subject = theme(folderNames: ["src": "folder-src"])
        #expect(subject.iconID(forFolder: "src", expanded: true) == "folder-src")
        #expect(subject.iconID(forFolder: "other", expanded: true) == "folder")
    }

    @Test func theRootFolderCanHaveItsOwnIcon() {
        let subject = theme(
            folderNames: ["app": "folder-app"],
            rootFolderNames: ["app": "root-app"],
            defaultRootFolder: "root"
        )
        #expect(subject.iconID(forFolder: "app", expanded: false, isRoot: true) == "root-app")
        #expect(subject.iconID(forFolder: "other", expanded: false, isRoot: true) == "root")
        #expect(subject.iconID(forFolder: "app", expanded: false, isRoot: false) == "folder-app")
    }

    // MARK: The light section

    /// Material Icon Theme names 263 of these. The dark artwork on a light
    /// sidebar is the symptom; 54 icon ids reachable no other way is the
    /// cost.
    @Test func aLightOverrideAnswersBeforeTheDarkTable() {
        let subject = theme(
            fileNames: ["readme.md": "readme"],
            light: IconTheme.Overrides(fileNames: ["readme.md": "readme_light"])
        )
        #expect(subject.iconID(forFile: "README.md") == "readme")
        #expect(subject.iconID(forFile: "README.md", on: .light) == "readme_light")
    }

    /// The section is an override, not a replacement: a key it omits still
    /// answers from the table above it.
    @Test func aKeyTheLightSectionOmitsFallsThrough() {
        let subject = theme(
            fileExtensions: ["ts": "typescript"],
            light: IconTheme.Overrides(fileNames: ["readme.md": "readme_light"])
        )
        #expect(subject.iconID(forFile: "main.ts", on: .light) == "typescript")
    }

    /// Per lookup rather than per theme, which is what keeps the order
    /// intact: an exact name beats an extension whichever table answered.
    @Test func precedenceHoldsAcrossTheTwoTables() {
        let subject = theme(
            fileExtensions: ["md": "markdown_light"],
            fileNames: ["readme.md": "readme"],
            light: IconTheme.Overrides(fileExtensions: ["md": "markdown_light"])
        )
        #expect(subject.iconID(forFile: "README.md", on: .light) == "readme")
    }

    @Test func lightFoldersFollowTheSameRule() {
        let subject = theme(
            folderNames: ["src": "folder-src"],
            folderNamesExpanded: ["src": "folder-src-open"],
            light: IconTheme.Overrides(
                folderNames: ["src": "folder-src_light"],
                folderNamesExpanded: ["src": "folder-src-open_light"]
            )
        )
        #expect(subject.iconID(forFolder: "src", expanded: false, on: .light) == "folder-src_light")
        #expect(subject.iconID(forFolder: "src", expanded: true, on: .light) == "folder-src-open_light")
        #expect(subject.iconID(forFolder: "src", expanded: true) == "folder-src-open")
    }

    // MARK: An open root

    /// The root branch used to answer with `defaultRootFolder` before
    /// `expanded` was read at all, so a theme naming an open root could not
    /// use it. Material names `folder-root-open`.
    @Test func anExpandedRootPrefersTheThemesOpenRoot() {
        let subject = theme(
            defaultRootFolder: "folder-root",
            defaultRootFolderExpanded: "folder-root-open"
        )
        #expect(subject.iconID(forFolder: "project", expanded: false, isRoot: true) == "folder-root")
        #expect(subject.iconID(forFolder: "project", expanded: true, isRoot: true) == "folder-root-open")
    }

    @Test func anExpandedRootNamedByTheThemeBeatsBothDefaults() {
        let subject = theme(
            rootFolderNames: ["project": "root-project"],
            rootFolderNamesExpanded: ["project": "root-project-open"],
            defaultRootFolder: "folder-root",
            defaultRootFolderExpanded: "folder-root-open"
        )
        #expect(subject.iconID(forFolder: "project", expanded: true, isRoot: true) == "root-project-open")
        #expect(subject.iconID(forFolder: "project", expanded: false, isRoot: true) == "root-project")
    }

    // MARK: Parsing

    @Test func parsingKeepsOnlySvgBackedDefinitions() {
        let json: [String: Any] = [
            "iconDefinitions": [
                "ts": ["iconPath": "./icons/ts.svg"],
                "seti": ["fontCharacter": "\\E001", "fontColor": "#519aba"],
            ],
            "fileExtensions": ["TS": "ts"],
            "file": "document",
        ]
        let subject = IconTheme.parse(json: json, name: "t", root: URL(fileURLWithPath: "/tmp/t"))

        #expect(subject.definitions == ["ts": "./icons/ts.svg"])
        #expect(subject.iconID(forFile: "a.ts") == "ts")
        #expect(subject.isSupported)
    }

    /// A font-based theme (VS Code's own Seti) parses without error but
    /// can't draw anything — the picker needs that to be visible rather
    /// than showing a column of blanks.
    @Test func aFontOnlyThemeReportsItselfUnsupported() {
        let json: [String: Any] = [
            "iconDefinitions": ["a": ["fontCharacter": "\\E001"]],
            "fonts": [["id": "seti"]],
        ]
        let subject = IconTheme.parse(json: json, name: "seti", root: URL(fileURLWithPath: "/tmp/s"))
        #expect(!subject.isSupported)
    }

    @Test func iconURLsResolveRelativeToTheThemeDirectory() {
        let subject = theme(definitions: ["ts": "./icons/files/ts.svg"])
        #expect(subject.iconURL(for: "ts")?.path == "/tmp/theme/icons/files/ts.svg")
        #expect(subject.iconURL(for: "missing") == nil)
    }
}
