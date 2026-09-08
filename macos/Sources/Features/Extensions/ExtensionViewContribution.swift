import Foundation

/// One `contributes.views[]` entry: an interactive page an extension draws
/// inside Phantom.
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
    let placements: Set<Placement>
    let permissions: Set<ExtensionViewMethod>

    /// Where the icon that opens this view appears.
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
            placements: placements(json["placements"]),
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

    /// Both placements when the file names none: an author who contributes a
    /// view wants it reachable, and picking one of the two bars is the
    /// narrower wish.
    static func placements(_ value: Any?) -> Set<Placement> {
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
