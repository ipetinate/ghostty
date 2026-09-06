import Foundation

/// Whether a project carries one of the paths a companion server asked for,
/// and therefore whether that server has anything to say about a file in it.
///
/// The same shape as `TypeScriptToolchain` and for the same reason: which
/// servers serve a file is a fact about its project, and the types that
/// answer "who serves this language" are pure, so the fact is resolved here
/// and handed in as a value.
///
/// **Why gate a companion server at all.** Tailwind's is the measured case:
/// with Tailwind absent it starts, finds no project, and then answers every
/// completion inside every `class` attribute with nothing — while the
/// class-attribute exception in `CodeCompletionTrigger` has already turned
/// off the string suppression that keeps a 1-character trigger out of prose.
/// Routing a companion only where its marker exists is what keeps that
/// exception paid for.
enum ProjectMarker: Equatable, Sendable {
    /// A marker was found at this absolute path — the marker's own, so a
    /// message that mentions it can be specific.
    case found(at: String)

    /// No marker anywhere between the file and the workspace root.
    case absent

    var isPresent: Bool {
        if case .found = self { return true }
        return false
    }

    /// Whether this file's project carries any of `markers`.
    ///
    /// An empty list means "always": a companion server that names no marker
    /// is one whose author says it is useful everywhere its language ids
    /// appear, and inventing a condition for it would be this build deciding
    /// something the manifest declined to.
    ///
    /// **Walks up**, unlike `TypeScriptToolchain.resolve`, and the asymmetry
    /// is deliberate. That one has a useful answer when it finds nothing —
    /// `.native`, which still starts a server — so looking only in the
    /// project's own directory costs nothing. This one's empty answer is *the
    /// server does not run*, and a monorepo hoists `node_modules` to the repo
    /// root, so stopping at the file's own package would silently disable a
    /// companion in exactly the repositories most likely to have it.
    ///
    /// Still cheap enough for the routing path — `LSPCenter.keys(forPath:)`
    /// runs this per debounced change — because each level is one `stat` per
    /// marker and the walk is bounded by the workspace root. A file five
    /// directories deep costs six.
    static func resolve(
        forPath path: String,
        root: String,
        markers: [String],
        fileManager: FileManager = .default
    ) -> ProjectMarker {
        guard !markers.isEmpty else { return .found(at: root) }

        var directory = (path as NSString).deletingLastPathComponent
        let root = (root as NSString).standardizingPath

        while true {
            for marker in markers {
                let candidate = (directory as NSString).appendingPathComponent(marker)
                if fileManager.fileExists(atPath: candidate) { return .found(at: candidate) }
            }

            /// The root is checked and then the walk stops, rather than the
            /// walk stopping when it reaches the root: a file *at* the root
            /// has to be looked at once.
            guard directory != root, directory != "/", !directory.isEmpty else { return .absent }

            let parent = (directory as NSString).deletingLastPathComponent
            guard parent != directory else { return .absent }
            directory = parent
        }
    }
}
