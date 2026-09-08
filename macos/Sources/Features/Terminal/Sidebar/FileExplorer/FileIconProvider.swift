import AppKit
import Combine
import SwiftUI

/// What to draw next to a row in the file explorer.
enum FileIcon: Equatable {
    /// Artwork from an icon theme, already carrying its own brand colors —
    /// draw it as-is, never as a template.
    case image(NSImage)

    /// The built-in fallback: an SF Symbol plus the tint it should take.
    case symbol(name: String, color: Color)
}

/// Resolves a filename to an icon, and owns the set of installed icon
/// themes.
///
/// Themes come from three places, mirroring how `ThemeCatalog` handles color
/// themes: the app bundle, anything the user drops in
/// `~/.config/phantom/icon-themes/<name>/`, and the directories installed
/// extensions contribute. Any SVG-based VS Code icon theme works — copy the
/// extension's folder in, no install step.
///
/// **The bundle ships none of them.** A fresh install therefore has no theme
/// to select and draws SF Symbols, and every pack is an extension the reader
/// asks for — in the welcome window's `WelcomeIconPacks` or in Settings. The
/// app used to bundle one, which cost 2.3 MB in every download and made the
/// registry offer an Install button for a pack already in use.
///
/// With no theme selected the explorer still looks like an explorer: the
/// `symbolFallback` table below maps the common extensions onto SF Symbols
/// so a fresh install isn't a wall of identical page icons.
@MainActor
final class FileIconProvider: ObservableObject {
    static let shared = FileIconProvider()

    /// Persisted by name rather than index so reordering or removing a
    /// theme can't silently switch the user to a different one.
    static let selectionKey = "FileExplorerIconTheme"

    /// The value stored in `selectionKey` for "no theme, use SF Symbols".
    static let symbolsOnly = ""

    @Published private(set) var themes: [IconTheme] = []
    @Published private(set) var active: IconTheme?

    /// Keyed by icon id, cleared whenever the active theme changes. SVG
    /// decoding is not free and the same handful of ids repeat down every
    /// directory listing.
    private var imageCache: [String: NSImage] = [:]

    /// Keyed by folded theme name, cleared on every reload. Holds the
    /// misses too, so a theme that draws nothing is not read off disk
    /// again every time the menu opens.
    private var artworkCache: [String: NSImage?] = [:]

    private var catalogObservation: AnyCancellable?

    private init() {
        reload()
        catalogObservation = LanguageResolver.shared.$catalog
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
    }

    // MARK: Catalog

    /// The directory inside the app bundle holding themes we ship, mirroring
    /// `LanguageResolver.bundledExtensionsDir`.
    ///
    /// Nothing ships there. The path is read anyway so that shipping a pack
    /// later is a resource change and not a code change.
    static var bundledThemesDir: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("icon-themes", isDirectory: true)
    }

    func reload() {
        themes = Self.themes(
            inDirectories: [Self.bundledThemesDir, GuiConfigStore.shared.iconThemesDirURL].compactMap { $0 },
            contributed: LanguageResolver.shared.catalog.iconThemes
        )
        artworkCache.removeAll()
        applySelection()
    }

    /// Every installed theme, at most one per name, in display order.
    ///
    /// One name, one entry, folded — and the deduplication has to span all
    /// three sources rather than only the contributed one. The theme the app
    /// bundle used to hold was a directory called `symbols`; the extension
    /// that packages that same theme declares it as `Symbols`. Compared raw,
    /// those are two names, so the picker listed the pack twice under one
    /// label and which of the two the persisted selection resolved to was
    /// decided by nothing the reader could see. The bundled copy is gone and
    /// that pair cannot collide again, but any two packs can — a reader's own
    /// directory against an extension's — so the fold stays.
    ///
    /// The nearest source wins: the app bundle, then the reader's own
    /// directory, then the extensions. Directory listings arrive in no
    /// particular order, so they are sorted before the walk — otherwise
    /// which of two directories differing only in case survives changes
    /// between launches.
    nonisolated static func themes(
        inDirectories directories: [URL],
        contributed: [LanguageCatalog.ContributedIconTheme]
    ) -> [IconTheme] {
        var found: [IconTheme] = []
        var claimed: Set<String> = []

        for dir in directories {
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                      let theme = IconTheme.load(directory: entry),
                      claimed.insert(theme.foldedName).inserted
                else { continue }
                found.append(theme)
            }
        }

        found += contributedThemes(contributed, excluding: claimed)

        return found.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// `taken` holds folded names — `IconTheme.folded` — not raw ones.
    nonisolated static func contributedThemes(
        _ contributed: [LanguageCatalog.ContributedIconTheme],
        excluding taken: Set<String>
    ) -> [IconTheme] {
        var seen = Set(taken.map(IconTheme.folded))
        return contributed.compactMap { entry in
            guard seen.insert(IconTheme.folded(entry.iconTheme.name)).inserted,
                  var theme = IconTheme.load(
                      directory: entry.iconTheme.directoryURL,
                      name: entry.iconTheme.name,
                      contributedBy: entry.extensionName
                  )
            else { return nil }
            theme.contributedArtwork = ExtensionStore.artworkURL(in: entry.extensionRoot)
            return theme
        }
    }

    /// The side a picker draws a pack's artwork at, in points.
    static let artworkSize: CGFloat = 16

    /// The pack's own artwork at picker size, or nil when it has none.
    func artwork(for theme: IconTheme) -> NSImage? {
        if let cached = artworkCache[theme.foldedName] { return cached }
        let image = theme.artworkURL
            .flatMap { NSImage(contentsOf: $0) }
            .map(Self.sizedForPicker)
        artworkCache[theme.foldedName] = image
        return image
    }

    /// A menu draws an image at whatever size the image declares, and a
    /// pack's own artwork declares its own — the SVGs are 24 points, the
    /// packaged PNGs 128 — so the size is set here rather than left to the
    /// row. `isTemplate` is cleared for the reason `FileIcon.image` gives:
    /// this is artwork carrying its own brand colors, not a glyph to tint.
    private static func sizedForPicker(_ image: NSImage) -> NSImage {
        let sized = image.copy() as? NSImage ?? image
        sized.size = NSSize(width: artworkSize, height: artworkSize)
        sized.isTemplate = false
        return sized
    }

    /// Selects a theme by name, or `symbolsOnly` to fall back to SF Symbols.
    func select(_ name: String) {
        UserDefaults.standard.set(name, forKey: Self.selectionKey)
        applySelection()
    }

    var selectedName: String {
        UserDefaults.standard.string(forKey: Self.selectionKey) ?? Self.defaultThemeName
    }

    /// The selection under the name the installed theme goes by, which is
    /// what a picker has to tag its rows with.
    ///
    /// The two differ whenever the stored spelling and the installed pack's
    /// own differ in case, which is what a reader who selected the bundled
    /// `symbols` and later installed the extension's `Symbols` has.
    /// Answering with the stored spelling would leave the picker showing no
    /// selection at all, for a theme that is installed and active.
    var selectedThemeName: String {
        let folded = IconTheme.folded(selectedName)
        return themes.first { $0.foldedName == folded }?.name ?? selectedName
    }

    /// No pack, because the bundle ships none: a fresh install draws the
    /// `symbolFallback` table until the reader asks for a pack.
    ///
    /// A reader who selected the bundled `symbols` before it was removed
    /// still has that name stored, and `applySelection` drops it for want of
    /// a theme by that name — so they see SF Symbols too, and the picker in
    /// Settings keeps a row saying the pack is not installed. Installing
    /// `phantom.symbols-icons` gives the icons back under the selection they
    /// already have, because `Symbols` folds onto `symbols`.
    static let defaultThemeName = symbolsOnly

    private func applySelection() {
        let name = IconTheme.folded(selectedName)
        let next = name == Self.symbolsOnly
            ? nil
            : themes.first { $0.foldedName == name && $0.isSupported }

        guard next != active else { return }
        active = next
        imageCache.removeAll()
    }

    // MARK: Icon resolution

    /// `path` is optional because five of the seven callers hold only a
    /// name — a git status line, a search hit. It buys the two answers a
    /// theme cannot reach on its own, both of them from the project's own
    /// dependencies: a `.tsx` in a Solid project wearing Solid's icon, and
    /// a `user.service.ts` in a NestJS project *not* wearing Angular's. See
    /// `WorkspaceFramework`.
    func icon(forFile fileName: String, at path: String? = nil) -> FileIcon {
        guard let theme = active else { return Self.symbolFallback(forFile: fileName) }
        let framework = path.flatMap { WorkspaceFramework.of(path: $0) }

        /// The framework's own icon, when the file's suffix is one a
        /// framework may speak for and the theme has artwork by that name.
        /// The theme's tables are not consulted here, so nothing in this
        /// type knows what any particular theme calls React's icon.
        if WorkspaceFramework.claims(fileName: fileName), let framework,
           theme.definitions[framework.iconID] != nil,
           let image = image(for: framework.iconID, in: theme) {
            return .image(image)
        }

        if let id = theme.iconID(
            forFile: fileName,
            on: background,
            rejecting: path == nil ? [] : WorkspaceFramework.rejected(by: framework)
        ), let image = image(for: id, in: theme) {
            return .image(image)
        }
        return Self.symbolFallback(forFile: fileName)
    }

    func icon(forFolder folderName: String, expanded: Bool, isRoot: Bool = false) -> FileIcon {
        if let theme = active,
           let id = theme.iconID(forFolder: folderName, expanded: expanded, isRoot: isRoot, on: background),
           let image = image(for: id, in: theme) {
            return .image(image)
        }
        return .symbol(name: expanded ? "folder.fill" : "folder", color: .secondary)
    }

    /// Which set of the theme's tables to read, asked per lookup.
    ///
    /// The terminal's own background, not the system appearance: the
    /// explorer is painted by the theme, so a light theme inside a dark
    /// system is a light sidebar and wants the light artwork. This is the
    /// same question `ExtensionViewerTheme` asks to tell its page which
    /// scheme it is in.
    ///
    /// Nothing is cached against it. A light override names a *different*
    /// icon id — Material's are suffixed `_light` — and `imageCache` is
    /// keyed by id, so a theme change needs no eviction here.
    private var background: IconTheme.Background {
        ThemePalette.shared.background?.isLightColor == true ? .light : .dark
    }

    private func image(for id: String, in theme: IconTheme) -> NSImage? {
        if let cached = imageCache[id] { return cached }
        guard let url = theme.iconURL(for: id),
              let image = NSImage(contentsOf: url)
        else { return nil }
        imageCache[id] = image
        return image
    }

    // MARK: SF Symbols fallback

    /// Extension → SF Symbol, for when no icon theme is active or the theme
    /// has no artwork for this file. Grouped by what the file *is* rather
    /// than by language, since SF Symbols has no per-language glyphs.
    private static let symbolsByExtension: [String: (String, Color)] = {
        var map: [String: (String, Color)] = [:]

        func put(_ symbol: String, _ color: Color, _ extensions: [String]) {
            for ext in extensions { map[ext] = (symbol, color) }
        }

        put("curlybraces", .orange, [
            "swift", "zig", "rs", "go", "c", "h", "cpp", "cc", "hpp", "m", "mm",
            "java", "kt", "kts", "rb", "py", "php", "cs", "scala", "dart", "lua",
            "ex", "exs", "erl", "hs", "clj", "vue", "svelte",
        ])
        put("chevron.left.forwardslash.chevron.right", .blue, [
            "ts", "tsx", "js", "jsx", "mjs", "cjs", "html", "htm", "xml",
        ])
        put("paintbrush", .pink, ["css", "scss", "sass", "less", "styl"])
        put("list.bullet.rectangle", .yellow, [
            "json", "yml", "yaml", "toml", "ini", "conf", "cfg", "plist", "env",
        ])
        put("doc.text", .secondary, ["md", "markdown", "txt", "rst", "adoc", "org"])
        put("photo", .purple, [
            "png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "ico", "tiff", "heic",
        ])
        put("film", .purple, ["mp4", "mov", "avi", "mkv", "webm"])
        put("waveform", .purple, ["mp3", "wav", "flac", "aac", "ogg", "m4a"])
        put("terminal", .green, ["sh", "bash", "zsh", "fish", "bat", "ps1"])
        put("shippingbox", .brown, ["zip", "tar", "gz", "bz2", "xz", "7z", "rar", "dmg"])
        put("lock", .gray, ["lock", "pem", "key", "crt", "cer"])
        put("cylinder.split.1x2", .cyan, ["sql", "db", "sqlite", "sqlite3"])
        put("doc.richtext", .red, ["pdf"])
        put("textformat", .secondary, ["ttf", "otf", "woff", "woff2", "eot"])

        return map
    }()

    /// Filenames that read better by name than by extension.
    ///
    /// Where most of the dot-names live, and they have to: `.eslintrc` and
    /// `.zshrc` have no extension in any useful sense — the whole name is
    /// the meaning — so without an entry here each one falls through to the
    /// blank page icon. The ones that do carry a real suffix (`.env`,
    /// `.prettierrc.json`) still resolve by extension and are left out.
    private static let symbolsByName: [String: (String, Color)] = [
        "dockerfile": ("shippingbox", .blue),
        "makefile": ("hammer", .orange),
        "license": ("scroll", .secondary),
        "readme.md": ("book", .blue),
        ".gitignore": ("arrow.triangle.branch", .orange),
        ".gitattributes": ("arrow.triangle.branch", .orange),
        ".gitmodules": ("arrow.triangle.branch", .orange),
        ".gitkeep": ("arrow.triangle.branch", .orange),
        ".dockerignore": ("shippingbox", .blue),
        ".editorconfig": ("list.bullet.rectangle", .yellow),
        ".npmrc": ("list.bullet.rectangle", .yellow),
        ".nvmrc": ("list.bullet.rectangle", .yellow),
        ".yarnrc": ("list.bullet.rectangle", .yellow),
        ".eslintrc": ("list.bullet.rectangle", .yellow),
        ".prettierrc": ("list.bullet.rectangle", .yellow),
        ".babelrc": ("list.bullet.rectangle", .yellow),
        ".zshrc": ("terminal", .green),
        ".zprofile": ("terminal", .green),
        ".bashrc": ("terminal", .green),
        ".bash_profile": ("terminal", .green),
        ".profile": ("terminal", .green),
        "package.json": ("shippingbox", .red),
    ]

    static func symbolFallback(forFile fileName: String) -> FileIcon {
        let lowered = fileName.lowercased()

        if let match = symbolsByName[lowered] {
            return .symbol(name: match.0, color: match.1)
        }

        for candidate in IconTheme.extensionCandidates(for: lowered) {
            if let match = symbolsByExtension[candidate] {
                return .symbol(name: match.0, color: match.1)
            }
        }

        return .symbol(name: "doc", color: .secondary)
    }
}

/// Draws whichever kind of icon the provider returned at a consistent size.
struct FileIconView: View {
    let icon: FileIcon
    var size: CGFloat = 14

    var body: some View {
        switch icon {
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        case .symbol(let name, let color):
            Image(systemName: name)
                .font(.system(size: size - 2))
                .foregroundStyle(color)
                .frame(width: size, height: size)
        }
    }
}
