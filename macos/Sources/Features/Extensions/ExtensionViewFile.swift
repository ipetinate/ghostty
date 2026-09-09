import Foundation

/// The file a contributed editor view is drawing, as the page is told about
/// it.
///
/// A view's tab is a file tab, so the page has to be told which file — the
/// equivalent of the document a custom editor is handed. It is the app
/// telling the page what its own tab is bound to, not data another page
/// sent: the only way a path gets here is a file the reader opened.
///
/// Relative to the scope's root and never absolute, for the reason
/// `ExtensionViewBridge.relativePath` refuses an absolute path on the way
/// in: a page that is handed one learns where the reader's disk is laid out,
/// and it has no use for that — every method it can call takes a relative
/// path anyway.
struct ExtensionViewFile: Equatable, Sendable {
    let root: ExtensionViewFileScope.Root
    let path: String

    /// The file `url` is, named the way this page may name it, or nil when
    /// it is outside the scope.
    ///
    /// Nil is a real answer and the page is told nothing: a claimed file
    /// opened from outside the workspace — the Finder, a recent-files list —
    /// is a file this view has no way to read, so a page told its path would
    /// only fail on the next call.
    static func inside(_ scope: ExtensionViewFileScope, url: URL) -> ExtensionViewFile? {
        for root in ExtensionViewFileScope.Root.allCases {
            guard let base = try? scope.url(for: root, path: nil) else { continue }
            guard let relative = relative(of: url, under: base) else { continue }
            return ExtensionViewFile(root: root, path: relative)
        }
        return nil
    }

    static func relative(of url: URL, under base: URL) -> String? {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath().path
        let root = base.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard resolved.hasPrefix(prefix) else { return nil }
        let relative = String(resolved.dropFirst(prefix.count))
        return relative.isEmpty ? nil : relative
    }

    var payload: [String: Any] {
        ["root": root.rawValue, "path": path]
    }
}
