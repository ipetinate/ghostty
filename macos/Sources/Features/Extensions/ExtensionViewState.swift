import CryptoKit
import Foundation

/// The small store a contributed view remembers things in, per workspace.
///
/// A view that asked the reader where their collection is must not ask again,
/// and there is nowhere it could write that answer itself: the workspace is
/// the reader's repository and does not want a dotfile, and the extension's
/// own directory is the package as installed — `workspace.replace` refuses it
/// outright, because the manifest in there is what grants the view its
/// methods.
///
/// So the app keeps it. One JSON object per extension per workspace, in
/// Phantom's own support directory, reachable only through `state.read` and
/// `state.write` and never as a path.
struct ExtensionViewState: Equatable, Sendable {
    let extensionID: String

    /// The workspace this state belongs to, or nil for the state an
    /// extension keeps regardless of where the reader is working.
    let workspace: URL?

    /// How large one object may be, as JSON.
    ///
    /// A path, an id, a choice — not a cache. A view with more than this to
    /// remember is a view that wants a file, and it has `workspace.create`
    /// for that.
    static let maxBytes = 8 * 1024

    static let directoryName = "view-state"

    /// The prefix on a key the **app** owns.
    ///
    /// `state.write` refuses a key that starts with it, so the page can
    /// neither forge nor clobber one. There is one such key today —
    /// `chosenWorkspaceKey` — and it has to be app-owned: a folder the
    /// reader picked is what bounds the view's filesystem methods, so a page
    /// able to write it would be a page able to move its own scope.
    static let reservedPrefix = "$"

    /// Where the reader last pointed this view, when they pointed it
    /// somewhere.
    static let chosenWorkspaceKey = "$workspace"

    /// `<caches>/view-state/<extension id>/<workspace digest>.json`.
    ///
    /// The workspace is a digest and not its path: a path holds separators
    /// and characters a file name may not, and the digest is the same length
    /// for every checkout. It is SHA-256 of the resolved path, so two
    /// windows on one repository read the same state and two checkouts of it
    /// do not.
    func file(cachesDir: URL) -> URL? {
        guard LanguageManifest.validID(extensionID) == extensionID else { return nil }
        return cachesDir
            .appendingPathComponent(Self.directoryName, isDirectory: true)
            .appendingPathComponent(extensionID, isDirectory: true)
            .appendingPathComponent(Self.key(for: workspace) + ".json")
    }

    static func key(for workspace: URL?) -> String {
        guard let workspace else { return "any" }
        let path = workspace.standardizedFileURL.resolvingSymlinksInPath().path
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// What the page may read: everything except the keys the app owns.
    func readForPage(cachesDir: URL) -> [String: Any] {
        read(cachesDir: cachesDir).filter { !$0.key.hasPrefix(Self.reservedPrefix) }
    }

    /// What the extension last wrote, or an empty object.
    ///
    /// An unreadable or unparseable file answers empty rather than throwing:
    /// the state is a convenience, and a view that cannot read it asks the
    /// reader again — which is the behaviour it has on first run anyway.
    func read(cachesDir: URL) -> [String: Any] {
        guard let file = file(cachesDir: cachesDir),
              let data = try? Data(contentsOf: file),
              data.count <= Self.maxBytes,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { return [:] }
        return dictionary
    }

    enum Failure: Error, Equatable, Sendable {
        case tooLarge(bytes: Int)
        case notAnObject
        case reservedKey
        case unwritable(String)
    }

    /// The folder the reader picked for this view, if it is still there.
    ///
    /// Probed rather than trusted. A remembered folder can be renamed,
    /// deleted or on a volume that is not mounted, and a scope based at one
    /// that is gone refuses every call with a message about containment
    /// rather than about the folder. Nil sends the view back to the
    /// terminal's folder, and its page back to the state that offers to
    /// pick one.
    ///
    /// A stale value is **left on disk**. A volume that is not mounted today
    /// is mounted tomorrow, and forgetting on the first miss would make the
    /// reader point at the same folder every morning.
    func chosenWorkspace(cachesDir: URL) -> URL? {
        guard let path = read(cachesDir: cachesDir)[Self.chosenWorkspaceKey] as? String,
              !path.isEmpty,
              ExtensionViewFileScope.isDirectory(URL(fileURLWithPath: path))
        else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Remembers the folder, keeping whatever the page has stored.
    func setChosenWorkspace(_ url: URL, cachesDir: URL) {
        var object = read(cachesDir: cachesDir)
        object[Self.chosenWorkspaceKey] = url.standardizedFileURL.path
        try? write(object, cachesDir: cachesDir, allowingReservedKeys: true)
    }

    /// Replaces the object. Writing an empty object is how a view forgets.
    ///
    /// - Parameter allowingReservedKeys: only the app passes true. A page's
    ///   `state.write` arrives with it false, so a reserved key is refused
    ///   before anything is written.
    @discardableResult
    func write(
        _ object: [String: Any],
        cachesDir: URL,
        allowingReservedKeys: Bool = false
    ) throws -> Int {
        if !allowingReservedKeys {
            guard !object.keys.contains(where: { $0.hasPrefix(Self.reservedPrefix) }) else {
                throw Failure.reservedKey
            }
        }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else { throw Failure.notAnObject }
        guard data.count <= Self.maxBytes else { throw Failure.tooLarge(bytes: data.count) }
        guard let file = file(cachesDir: cachesDir) else { throw Failure.notAnObject }

        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: [.atomic])
        } catch {
            throw Failure.unwritable(error.localizedDescription)
        }
        return data.count
    }
}

extension ExtensionViewState.Failure {
    var rejection: ExtensionViewRejection {
        switch self {
        case .tooLarge(let bytes):
            return .badParameters(
                "'state' is \(bytes) bytes; the limit is \(ExtensionViewState.maxBytes).")
        case .notAnObject:
            return .badParameters("'state' must be a JSON object.")
        case .reservedKey:
            return .badParameters(
                "A key starting with \"\(ExtensionViewState.reservedPrefix)\" belongs to Phantom.")
        case .unwritable(let detail):
            return .unwritable("This view's state could not be written: \(detail)")
        }
    }
}
