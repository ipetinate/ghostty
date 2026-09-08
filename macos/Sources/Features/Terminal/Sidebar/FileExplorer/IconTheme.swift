import Foundation

/// A VS Code file-icon theme: the `icon-theme.json` mapping plus the SVG
/// files it points at.
///
/// Only the SVG half of the format is supported. The other half is
/// font-based — VS Code's own default (Seti) ships a `.woff` and keys icons
/// by `fontCharacter` — and macOS can't register a WOFF without
/// decompressing it first, which would be an entire second rendering path
/// for one theme. Font-based themes parse to an empty `definitions` and are
/// reported as unsupported rather than half-working.
///
/// Parsing is deliberately lenient everywhere else: a theme that omits a
/// key, or names an icon that isn't on disk, falls through to the next rule
/// in the chain instead of failing to load. These are third-party files we
/// don't control.
struct IconTheme: Equatable {
    /// Display name — the containing directory's name.
    let name: String

    /// The directory holding `icon-theme.json`. Every `iconPath` in the
    /// file is relative to this.
    let root: URL

    /// Icon id → path relative to `root`.
    let definitions: [String: String]

    let fileExtensions: [String: String]
    let fileNames: [String: String]
    let languageIds: [String: String]
    let folderNames: [String: String]
    let folderNamesExpanded: [String: String]
    let rootFolderNames: [String: String]
    let rootFolderNamesExpanded: [String: String]

    let defaultFile: String?
    let defaultFolder: String?
    let defaultFolderExpanded: String?
    let defaultRootFolder: String?
    let defaultRootFolderExpanded: String?

    /// The theme's `light` section: the same tables again, consulted first
    /// when the icons are being drawn on a light background.
    ///
    /// **An override, not a replacement.** A key the section omits falls
    /// through to the table above it, per lookup rather than per theme —
    /// which is what keeps the precedence intact: an exact file name still
    /// beats an extension, whichever of the two tables answered. Material
    /// Icon Theme 5.38.1 names 263 overrides this way and 54 icon ids that
    /// appear nowhere else, so without it those files draw the dark artwork
    /// and those 54 drawings are unreachable.
    let light: Overrides?

    /// One `light` section, or the absence of one.
    struct Overrides: Equatable {
        var fileExtensions: [String: String] = [:]
        var fileNames: [String: String] = [:]
        var languageIds: [String: String] = [:]
        var folderNames: [String: String] = [:]
        var folderNamesExpanded: [String: String] = [:]
        var rootFolderNames: [String: String] = [:]
        var rootFolderNamesExpanded: [String: String] = [:]

        var isEmpty: Bool {
            fileExtensions.isEmpty && fileNames.isEmpty && languageIds.isEmpty
                && folderNames.isEmpty && folderNamesExpanded.isEmpty
                && rootFolderNames.isEmpty && rootFolderNamesExpanded.isEmpty
        }
    }

    /// Which background the icons are about to be drawn on.
    ///
    /// Not the system appearance: the explorer is painted by the terminal's
    /// own theme, and a reader on a light theme inside a dark system is
    /// looking at a light sidebar. `ThemePalette.background.isLightColor` is
    /// the same answer the extension viewer already asks for.
    enum Background: Equatable {
        case dark
        case light
    }

    var contributedBy: String?

    /// The artwork of the extension that carries this theme, for a theme
    /// that names none of its own. Set by `FileIconProvider` after the
    /// load, because it is a fact about the extension rather than about
    /// the `icon-theme.json` this type parses.
    var contributedArtwork: URL?

    /// Whether this theme resolved any SVG at all. A font-based theme
    /// parses cleanly but can't draw anything, and the picker needs to say
    /// so rather than silently showing blank rows.
    var isSupported: Bool { !definitions.isEmpty }

    /// What to call the theme on screen.
    ///
    /// A contributed theme is named by its manifest, which already spells
    /// the name the way its author wants it read — capitalizing it would
    /// turn `VSCode Icons` into `Vscode Icons`. A theme found as a
    /// directory has only that directory's name, `symbols`, so that one is
    /// capitalized.
    var displayName: String { contributedBy == nil ? name.capitalized : name }

    /// `name`, folded for comparison.
    ///
    /// Two themes whose names differ only in case are one theme to the
    /// reader — `symbols` in the app bundle and `Symbols` contributed by
    /// an extension are the same pack — so every comparison of a theme
    /// name goes through this: the deduplication that keeps one of them
    /// out of the picker, and the match that resolves the persisted
    /// selection back to a theme.
    static func folded(_ name: String) -> String { name.lowercased() }

    var foldedName: String { Self.folded(name) }

    /// Artwork that stands for the whole pack in a picker.
    ///
    /// The pack's own plain file and folder icons come first: they are
    /// what every row in the explorer falls back to, so they are the most
    /// honest preview of what picking the pack does. A pack that names
    /// neither — a starter theme with eight definitions and no `file` key
    /// — has only the artwork of the extension carrying it.
    ///
    /// The file has to be there, not merely named: themes name ids they
    /// never shipped, and a picker drawing nothing for the first candidate
    /// would never reach the second.
    var artworkURL: URL? {
        let manager = FileManager.default
        for id in [defaultFile, defaultFolder, defaultRootFolder].compactMap({ $0 }) {
            guard let url = iconURL(for: id), manager.fileExists(atPath: url.path) else { continue }
            return url
        }
        return contributedArtwork
    }

    // MARK: Resolution

    /// The icon id for a file, in VS Code's own precedence order: an exact
    /// filename match beats an extension match, and a longer extension
    /// beats a shorter one — `foo.component.ts` is an Angular component
    /// before it is TypeScript.
    ///
    /// `languageIds` is consulted last, and only through a guess at the
    /// language, because resolving it properly needs a language service to
    /// say "this file is `typescriptreact`" and a terminal has no such
    /// thing. Skipping it entirely was the first cut and it showed: the
    /// bundled theme defines a Vue icon but never lists `vue` under
    /// `fileExtensions`, so every `.vue` file drew a blank page. Most of
    /// that gap closes by trying the extension *as* a language id — which
    /// is exactly right for `vue`, `php` and `razor` — and the rest by the
    /// small table below.
    /// `rejecting` withholds one framework's artwork from a project that is
    /// not built with it, and it has to be checked **inside** the walk over
    /// candidates rather than after it. `user.service.ts` matches
    /// `service.ts` before it matches `ts`: refusing the first answer is
    /// only useful if the second one is still reachable, which is what
    /// carrying on through the loop buys.
    func iconID(
        forFile fileName: String,
        on background: Background = .dark,
        rejecting rejected: Set<WorkspaceFramework> = []
    ) -> String? {
        let overrides = background == .light ? light : nil
        let lowered = fileName.lowercased()
        if let id = overrides?.fileNames[lowered] ?? fileNames[lowered],
           allows(id, rejecting: rejected) {
            return id
        }

        let candidates = Self.extensionCandidates(for: lowered)
        for candidate in candidates {
            if let id = overrides?.fileExtensions[candidate] ?? fileExtensions[candidate],
               allows(id, rejecting: rejected) {
                return id
            }
        }
        for candidate in candidates {
            if let id = overrides?.languageIds[candidate] ?? languageIds[candidate],
               allows(id, rejecting: rejected) {
                return id
            }
            if let language = Self.languageIDsByExtension[candidate],
               let id = overrides?.languageIds[language] ?? languageIds[language],
               allows(id, rejecting: rejected) {
                return id
            }
        }
        return defaultFile
    }

    /// Whether this icon may be drawn for this project.
    private func allows(_ id: String, rejecting rejected: Set<WorkspaceFramework>) -> Bool {
        guard let brand = WorkspaceFramework.brands(iconID: id) else { return true }
        return !rejected.contains(brand)
    }

    /// Extensions whose VS Code language id isn't just the extension.
    ///
    /// Only needed for themes that key an icon by language and never by
    /// extension. Deliberately short: it covers the languages that actually
    /// turn up and is not trying to be a complete registry.
    static let languageIDsByExtension: [String: String] = [
        "clj": "clojure", "cljs": "clojure", "cljc": "clojure",
        "cr": "crystal",
        "cs": "csharp",
        "erl": "erlang", "hrl": "erlang",
        "ex": "elixir", "exs": "elixir",
        "feature": "gherkin",
        "fs": "fsharp", "fsx": "fsharp",
        "gd": "gdscript",
        "groovy": "groovy",
        "hbs": "handlebars",
        "hs": "haskell",
        "ipynb": "jupyter",
        "jl": "julia",
        "m": "objective-c", "mm": "objective-cpp",
        "pl": "perl", "pm": "perl",
        "tex": "latex", "sty": "latex",
    ]

    /// The icon id for a directory. `isRoot` picks the theme's root-folder
    /// icon when it defines one, which is how themes mark the workspace
    /// root differently from the folders inside it.
    ///
    /// **Open before closed, at every step.** The root branch used to
    /// answer with `defaultRootFolder` before `expanded` was ever read, so
    /// a theme naming an open root — Material names `folder-root-open` —
    /// could not use it: the closed icon stayed on an expanded root. Reading
    /// the key was not enough to fix that; the order had to change.
    func iconID(
        forFolder folderName: String,
        expanded: Bool,
        isRoot: Bool = false,
        on background: Background = .dark
    ) -> String? {
        let overrides = background == .light ? light : nil
        let lowered = folderName.lowercased()

        if isRoot {
            if expanded, let id = overrides?.rootFolderNamesExpanded[lowered] ?? rootFolderNamesExpanded[lowered] {
                return id
            }
            if let id = overrides?.rootFolderNames[lowered] ?? rootFolderNames[lowered] { return id }
            if expanded, let id = defaultRootFolderExpanded { return id }
            if let id = defaultRootFolder { return id }
        }

        if expanded, let id = overrides?.folderNamesExpanded[lowered] ?? folderNamesExpanded[lowered] {
            return id
        }
        if let id = overrides?.folderNames[lowered] ?? folderNames[lowered] { return id }

        if expanded, let id = defaultFolderExpanded { return id }
        return defaultFolder
    }

    /// Where an icon id's artwork lives, or nil when the theme names an id
    /// it never defined.
    ///
    /// Built by appending rather than with `URL(fileURLWithPath:relativeTo:)`:
    /// that initializer resolves against the *parent* when the base URL
    /// carries no trailing slash, which silently drops the theme's own
    /// directory and points every icon one level too high.
    func iconURL(for id: String) -> URL? {
        guard let relative = definitions[id] else { return nil }
        guard !relative.hasPrefix("/") else { return URL(fileURLWithPath: relative) }

        let trimmed = relative.hasPrefix("./") ? String(relative.dropFirst(2)) : relative
        return root.appendingPathComponent(trimmed).standardizedFileURL
    }

    /// Every extension a filename could match, longest first.
    ///
    /// `my.component.ts` yields `component.ts` then `ts`. VS Code treats
    /// every dot as a possible extension boundary, and themes rely on it —
    /// `spec.ts`, `d.ts` and `tar.gz` are all real keys in the bundled
    /// theme and would never match a last-dot-only split.
    static func extensionCandidates(for lowercasedName: String) -> [String] {
        let parts = lowercasedName.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count > 1 else { return [] }
        return (1..<parts.count).map { parts[$0...].joined(separator: ".") }
    }

    // MARK: Parsing

    /// Reads `icon-theme.json` (or the first `*icon-theme.json`) out of a
    /// theme directory. Returns nil only when there's no readable theme
    /// file at all.
    static func load(
        directory: URL,
        name: String? = nil,
        contributedBy: String? = nil
    ) -> IconTheme? {
        let fm = FileManager.default
        var jsonURL = directory.appendingPathComponent("icon-theme.json")

        if !fm.fileExists(atPath: jsonURL.path) {
            let entries = (try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            guard let match = entries.first(where: {
                $0.lastPathComponent.hasSuffix("icon-theme.json")
            }) else { return nil }
            jsonURL = match
        }

        guard let data = try? Data(contentsOf: jsonURL),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        return parse(
            json: json,
            name: name ?? directory.lastPathComponent,
            root: directory,
            contributedBy: contributedBy
        )
    }

    static func parse(
        json: [String: Any],
        name: String,
        root: URL,
        contributedBy: String? = nil
    ) -> IconTheme {
        var definitions: [String: String] = [:]
        if let raw = json["iconDefinitions"] as? [String: Any] {
            for (id, value) in raw {
                guard let entry = value as? [String: Any],
                      let path = entry["iconPath"] as? String
                else { continue }
                definitions[id] = path
            }
        }

        return IconTheme(
            name: name,
            root: root,
            definitions: definitions,
            fileExtensions: lowercasedKeys(json["fileExtensions"]),
            fileNames: lowercasedKeys(json["fileNames"]),
            languageIds: lowercasedKeys(json["languageIds"]),
            folderNames: lowercasedKeys(json["folderNames"]),
            folderNamesExpanded: lowercasedKeys(json["folderNamesExpanded"]),
            rootFolderNames: lowercasedKeys(json["rootFolderNames"]),
            rootFolderNamesExpanded: lowercasedKeys(json["rootFolderNamesExpanded"]),
            defaultFile: json["file"] as? String,
            defaultFolder: json["folder"] as? String,
            defaultFolderExpanded: json["folderExpanded"] as? String,
            defaultRootFolder: json["rootFolder"] as? String,
            defaultRootFolderExpanded: json["rootFolderExpanded"] as? String,
            light: overrides(json["light"]),
            contributedBy: contributedBy
        )
    }

    /// The `light` section, or nil when the theme has none worth carrying.
    ///
    /// An empty section reads as absent so the lookups can skip it with one
    /// comparison instead of seven. Material Icon Theme's `highContrast`
    /// section is exactly that shape in 5.38.1 — both of its tables are
    /// empty — which is why nothing here reads it: there is a key, and
    /// there is nothing in it.
    private static func overrides(_ value: Any?) -> Overrides? {
        guard let json = value as? [String: Any] else { return nil }
        let parsed = Overrides(
            fileExtensions: lowercasedKeys(json["fileExtensions"]),
            fileNames: lowercasedKeys(json["fileNames"]),
            languageIds: lowercasedKeys(json["languageIds"]),
            folderNames: lowercasedKeys(json["folderNames"]),
            folderNamesExpanded: lowercasedKeys(json["folderNamesExpanded"]),
            rootFolderNames: lowercasedKeys(json["rootFolderNames"]),
            rootFolderNamesExpanded: lowercasedKeys(json["rootFolderNamesExpanded"])
        )
        return parsed.isEmpty ? nil : parsed
    }

    /// Lookups are all done on lowercased names, so the tables are folded
    /// once here rather than at every hit — themes are inconsistent about
    /// case (`Dockerfile` vs `dockerfile`) and a miss is silent.
    private static func lowercasedKeys(_ value: Any?) -> [String: String] {
        guard let dict = value as? [String: String] else { return [:] }
        return Dictionary(
            dict.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
