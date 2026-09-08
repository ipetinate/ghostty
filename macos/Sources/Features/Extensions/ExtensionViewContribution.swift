import Foundation

/// One `contributes.views[]` entry: an interactive page an extension draws
/// inside Phantom.
///
/// An entry names the **surface** it renders on. A `sidebar` entry is a
/// panel of the sidebar, selected by its button in the rail or the top bar,
/// the way Files and Git are. An `editor` entry is a tab.
///
/// An `editor` entry claims file names, and that is what its tab is
/// identified by: the file. Opening a claimed file from the sidebar tree,
/// the file explorer, a search hit or the quick opener all reach the same
/// tab, and re-opening, closing and session restore need nothing of their
/// own because the app already does those for a file.
///
/// An interactive extension usually contributes both: a tree on the
/// sidebar, and the editor that a row of that tree opens. Neither surface is
/// the other's fallback — see `ExtensionViewSurface`.
///
/// The page is a bundled ES module and, when it ships one, a stylesheet.
/// Nothing else of it is loaded: no second script, no remote font, no
/// stylesheet off a CDN, because the page is served under a
/// `default-src 'none'` policy that permits only the two files staged beside
/// it. See `ExtensionViewHostBundle`.
///
/// The page reaches nothing by itself — no filesystem, no process, no
/// socket. Each of those is a method it asks the app to perform, and the app
/// refuses every method this entry did not name in `permissions`. That is
/// why the list is of method names rather than of capability groups: what an
/// author declares and what the app checks are the same string.
struct ExtensionViewContribution: Identifiable, Equatable, Sendable {
    /// Spelled `viewId` in the file, the way `languageId` and `agentId` are.
    let viewID: String

    let title: String

    /// Artwork shipped in the package, never an SF Symbol name.
    ///
    /// A symbol the running macOS does not resolve makes SwiftUI drop the
    /// whole row out of a `List` with nothing logged, so a name a third
    /// party chose is the one thing this must not accept. A file either
    /// decodes or visibly does not.
    let icon: URL

    let entry: URL
    let style: URL?

    /// Where this entry's page is drawn.
    let surface: Surface

    /// The file names an `editor` entry claims, as globs.
    ///
    /// Empty for a `sidebar` entry, and for an `editor` entry that is only
    /// ever opened without a file behind it. The dialect is
    /// `GlobPattern.fileNamePattern`, the same one
    /// `contributes.languages[].fileNamePatterns` uses, so a pattern may
    /// not carry a separator: an editor claims a name, never a location.
    let filenamePatterns: [GlobPattern]

    /// Whether a claimed file opens in this view or merely offers to.
    let priority: Priority
    /// Which of the sidebar's two switcher bars carries this panel's
    /// button.
    ///
    /// **Empty for an `editor` entry, always.** An editor view is reached by
    /// opening a file it claims, never by a button: a button that opened a
    /// blank editor tab would be a button whose meaning depends on what the
    /// extension does next. Only a `sidebar` entry has one, and for a
    /// `sidebar` entry that names none the answer is both bars — a panel
    /// with no button cannot be selected at all.
    let placements: Set<Placement>

    let permissions: Set<ExtensionViewMethod>

    /// What a claim on a file name is worth.
    enum Priority: String, CaseIterable, Equatable, Sendable {
        /// The text editor still opens the file, and this view is offered
        /// beside it — "Open with …" on the tab.
        ///
        /// The default, and the right default: a claimed file is still a
        /// text file the reader may want to read as text, and a view that
        /// took the file over would be a third party deciding that for them.
        case option

        /// This view opens the file, and the text editor is offered beside
        /// it.
        case `default`
    }

    /// The two places a view's page can be drawn.
    enum Surface: String, CaseIterable, Equatable, Sendable {
        /// A panel of the sidebar, selected by this entry's own button.
        case sidebar

        /// A tab of the editor, opened through `views.open`.
        case editor
    }

    /// Where the button that opens this view appears.
    enum Placement: String, CaseIterable, Equatable, Sendable {
        /// The column of icons down the side of the sidebar.
        case sidebar

        /// The row of tabs across the top of the sidebar.
        case topBar
    }

    var id: String { viewID }

    static let maxViews = 8
    static let maxTitleLength = 64
    static let maxPermissions = 16

    /// Suffixes an entry and a stylesheet may carry.
    ///
    /// Checked because the host page loads them as a module and as a
    /// stylesheet: a path this list does not name is a file the page would
    /// ask the engine to interpret as something it is not.
    static let entrySuffixes: Set<String> = ["js", "mjs"]
    static let styleSuffixes: Set<String> = ["css"]

    static func parse(json: [String: Any], root: URL) -> ExtensionViewContribution? {
        guard let viewID = LanguageContribution.validLanguageID(json["viewId"]),
              let title = LanguageManifest.displayString(json["title"]),
              title.count <= maxTitleLength,
              let icon = artwork(json["icon"], root: root),
              let entry = file(json["entry"], root: root, suffixes: entrySuffixes)
        else { return nil }

        return ExtensionViewContribution(
            viewID: viewID,
            title: title,
            icon: icon,
            entry: entry,
            style: file(json["style"], root: root, suffixes: styleSuffixes),
            surface: surface(json["surface"]),
            filenamePatterns: LanguageContribution.filePatterns(from: json["filenamePatterns"]),
            priority: priority(json["priority"]),
            placements: placements(json["placements"], surface: surface(json["surface"])),
            permissions: permissions(json["permissions"])
        )
    }

    /// An image inside the package, or nil.
    ///
    /// The containment check is `LanguageContribution.containedURL`'s, so a
    /// `../` or an absolute path costs the whole view rather than reading a
    /// file outside the extension.
    static func artwork(_ value: Any?, root: URL) -> URL? {
        guard let url = LanguageContribution.containedURL(value, root: root),
              ExtensionMediaGate.kind(ofPath: url.lastPathComponent) == .image
        else { return nil }
        return url
    }

    static func file(_ value: Any?, root: URL, suffixes: Set<String>) -> URL? {
        guard let url = LanguageContribution.containedURL(value, root: root),
              suffixes.contains(url.pathExtension.lowercased())
        else { return nil }
        return url
    }

    /// The sidebar when the file names no surface.
    ///
    /// An entry with no surface is one written before this field existed,
    /// and the sidebar is where such an entry was drawn.
    static func surface(_ value: Any?) -> Surface {
        guard let raw = LanguageManifest.string(value) else { return .sidebar }
        return Surface(rawValue: raw) ?? .sidebar
    }

    /// The reader's text editor keeps the file when the manifest says
    /// nothing, because taking a file over is the larger claim.
    static func priority(_ value: Any?) -> Priority {
        guard let raw = LanguageManifest.string(value) else { return .option }
        return Priority(rawValue: raw) ?? .option
    }

    /// Whether this entry claims a file by that name.
    ///
    /// Only an `editor` entry ever claims one. A `sidebar` panel is not
    /// something a file opens into, so a pattern on one is ignored rather
    /// than honoured — the validator refuses it at publish time.
    func claims(fileName: String) -> Bool {
        guard surface == .editor, !filenamePatterns.isEmpty else { return false }
        let name = fileName.lowercased()
        return filenamePatterns.contains { $0.matches(name) }
    }

    /// The bars this entry's button appears in.
    ///
    /// Nothing for an `editor` entry, whatever the manifest says. An editor
    /// view is opened by a file, and giving it a button put a **second**
    /// Bruno mark in the rail beside the panel's — two icons for one
    /// extension, one of which opened an empty page.
    ///
    /// Both bars for a `sidebar` entry that names none: an author who
    /// contributes a panel wants it reachable, and picking one of the two
    /// bars is the narrower wish. Absent cannot mean "no button" here,
    /// because a panel with no button is a panel with no way in.
    static func placements(_ value: Any?, surface: Surface) -> Set<Placement> {
        guard surface == .sidebar else { return [] }
        let raw = (value as? [Any]) ?? []
        let named = Set(raw.compactMap { LanguageManifest.string($0).flatMap(Placement.init(rawValue:)) })
        return named.isEmpty ? Set(Placement.allCases) : named
    }

    /// Methods this view may call. A name this build does not know is
    /// dropped rather than refused, the same way an unrecognised
    /// `contributes` key is: a manifest written for a later Phantom keeps
    /// the half this one understands.
    static func permissions(_ value: Any?) -> Set<ExtensionViewMethod> {
        let raw = (value as? [Any]) ?? []
        return Set(
            raw
                .prefix(maxPermissions)
                .compactMap { LanguageManifest.string($0).flatMap(ExtensionViewMethod.init(rawValue:)) }
        )
    }
}
