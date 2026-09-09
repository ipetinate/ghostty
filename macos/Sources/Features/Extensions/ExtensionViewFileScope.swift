import Foundation

/// The two folders a contributed view may read and write, and the only way
/// it reaches them.
///
/// A page never opens a file. It names a relative path, the app resolves it
/// against one of these folders, proves the result is still inside that
/// folder, and hands back the bytes. The proof is made twice against the
/// same resolved base — once on the path and once through
/// `resolvingSymlinksInPath` — so that neither a `../` nor a symlink planted
/// inside the workspace reaches out of it.
///
/// The two write methods go through the same `url(for:path:)` and therefore
/// the same proof. What they add is refusal: neither creates a folder,
/// `create` refuses a path that exists, and `replace` refuses one that does
/// not and refuses the extension's own directory outright.
struct ExtensionViewFileScope: Equatable, Sendable {
    /// Which folder a path is resolved against.
    enum Root: String, CaseIterable, Equatable, Sendable {
        case workspace

        /// The extension's own installed directory. Spelled `extension` in
        /// the call because that is what an author calls it.
        case package = "extension"
    }

    /// Which of the two write methods is asking.
    ///
    /// A value rather than two functions, because everything except the one
    /// refusal each is named for is shared, and a second copy of the
    /// containment proof is the last thing this type needs.
    enum WriteMode: String, CaseIterable, Equatable, Sendable {
        /// `workspace.create`: the path must not exist.
        case create

        /// `workspace.replace`: the path must exist, and must be a regular
        /// file in the workspace.
        case replace

        var method: ExtensionViewMethod {
            switch self {
            case .create: return .workspaceCreate
            case .replace: return .workspaceReplace
            }
        }
    }

    struct Entry: Equatable, Sendable {
        let path: String
        let name: String
        let isDirectory: Bool
        let bytes: Int
    }

    enum Failure: Error, Equatable, Sendable {
        case noWorkspace
        case outOfScope(String)
        case missing(String)
        case notAFile(String)
        case notADirectory(String)
        case tooLarge(String, bytes: Int)
        case notText(String)
        case exists(String)
        case absent(String)
        case noParent(String)
        case immutableRoot(Root)
        case unwritable(String, String)

        var rejection: ExtensionViewRejection {
            switch self {
            case .noWorkspace:
                return .unreadable("This view was opened with no workspace folder.")
            case .outOfScope(let path):
                return .outOfScope(path)
            case .missing(let path):
                return .unreadable("\(path) does not exist.")
            case .notAFile(let path):
                return .unreadable("\(path) is not a regular file.")
            case .notADirectory(let path):
                return .unreadable("\(path) is not a folder.")
            case .tooLarge(let path, let bytes):
                return .unreadable("\(path) is \(bytes) bytes; the limit is \(ExtensionViewFileScope.maxFileBytes).")
            case .notText(let path):
                return .unreadable("\(path) is not UTF-8 text.")
            case .exists(let path):
                return .exists(path)
            case .absent(let path):
                return .absent(path)
            case .noParent(let path):
                return .unwritable(
                    "\(path) needs a folder that already exists; this method creates none.")
            case .immutableRoot(let root):
                return .unwritable(
                    "workspace.replace does not write to \"\(root.rawValue)\". "
                        + "The manifest in that directory is what grants this view its permissions.")
            case .unwritable(let path, let detail):
                return .unwritable("\(path) could not be written: \(detail)")
            }
        }
    }

    let workspace: URL?
    let package: URL

    static let maxFileBytes = 2 * 1024 * 1024
    static let maxEntries = 2048

    /// How large a file either write method may leave on disk. The bridge
    /// refuses a longer `text` before this is reached; the check is made
    /// twice because the bound belongs to the filesystem side as much as to
    /// the parameter.
    static let maxWriteBytes = ExtensionViewBridge.maxWriteBytes

    /// Folder names a walk never enters.
    ///
    /// Not a security rule — everything here is inside the workspace the
    /// reader opened. It is a cost rule: a page asking for the tree of a
    /// JavaScript project would otherwise be handed a hundred thousand
    /// names it has no use for, and `maxEntries` would cut the walk before
    /// it reached the files the author was looking for.
    static let skippedDirectories: Set<String> = [
        "node_modules", ".git", ".svn", ".hg", "vendor", "target",
        "dist", "build", ".next", ".venv", "__pycache__",
    ]

    func url(for root: Root, path: String?) throws -> URL {
        let base: URL
        switch root {
        case .workspace:
            guard let workspace else { throw Failure.noWorkspace }
            base = workspace
        case .package:
            base = package
        }

        guard let path, !path.isEmpty else { return base.standardizedFileURL.resolvingSymlinksInPath() }
        guard let resolved = Self.contained(path, in: base) else { throw Failure.outOfScope(path) }
        return resolved
    }

    /// The same containment rule `LanguageContribution.containedURL` applies
    /// to a manifest's paths, over a base this type owns.
    static func contained(_ path: String, in base: URL) -> URL? {
        let root = base.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = root.appendingPathComponent(path).standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(prefix),
              candidate.resolvingSymlinksInPath().path.hasPrefix(prefix)
        else { return nil }
        return candidate
    }

    /// An existing regular file inside the scope, as a URL.
    ///
    /// The same containment proof `read` makes, without reading the bytes.
    /// For `views.open`, which hands a path to the app to open rather than
    /// to the page to read: a page may only open a file it could already
    /// have read, so the check is the read side's and not a weaker one.
    func file(root: Root, path: String) throws -> URL {
        let url = try url(for: root, path: path)
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        guard let values else { throw Failure.missing(path) }
        guard values.isRegularFile == true else { throw Failure.notAFile(path) }
        return url
    }

    func read(root: Root, path: String) throws -> String {
        let url = try url(for: root, path: path)
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard let values else { throw Failure.missing(path) }
        guard values.isRegularFile == true else { throw Failure.notAFile(path) }
        guard let bytes = values.fileSize, bytes <= Self.maxFileBytes else {
            throw Failure.tooLarge(path, bytes: values.fileSize ?? 0)
        }
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            throw Failure.notText(path)
        }
        return text
    }

    /// Writes one file, and answers how many bytes went into it.
    ///
    /// Every refusal, in the order it is made. The spelling of the path is
    /// checked before any of this, by `ExtensionViewBridge.writablePath` —
    /// an absolute path, a `~`, a `\`, a `..` and a dot-prefixed part are
    /// all gone by the time this runs, and so is a `text` over the bound.
    ///
    /// 1. `.replace` refuses `.package` outright. The `extension.json` in
    ///    that directory is what tells the app which methods this very page
    ///    may call, and `ExtensionStore.refresh()` reads it again without a
    ///    restart — so a page able to write over it could grant itself every
    ///    method there is. That is not a bound that can be put back after
    ///    the fact, so the method does not reach the directory at all.
    ///    `.create` still does: it adds files, and every file the app reads
    ///    from a package by manifest or by convention is already there,
    ///    which is exactly what `.create` refuses to touch.
    /// 2. The path has to resolve inside the folder `root` names, proved the
    ///    two ways `url(for:path:)` proves it. A symlink planted mid-path
    ///    that leaves the folder fails the second proof, and a `.workspace`
    ///    root with no folder open fails the first.
    /// 3. The folder the file goes in has to exist already. **Neither
    ///    method creates a folder, at any depth.** A page that could would
    ///    be a page that can lay out a tree of its own choosing inside
    ///    somebody's repository, and nothing either method is for needs
    ///    that.
    /// 4. `.create` refuses a path that exists; `.replace` refuses one that
    ///    does not, and one that is not a regular file. `.create` checks
    ///    with `fileExists` for the sake of the message and then again in
    ///    the write itself, through `withoutOverwriting`: between a check
    ///    and a write there is a window, and what is at stake is somebody's
    ///    work.
    /// 5. The bytes have to fit `maxWriteBytes`.
    ///
    /// `.replace` writes atomically, so a failure halfway leaves the file as
    /// it was rather than truncated. There is **no method that deletes a
    /// file, empties one or renames one**, and neither of these can be made
    /// into one.
    @discardableResult
    func write(root: Root, path: String, text: String, mode: WriteMode) throws -> Int {
        if mode == .replace, root == .package { throw Failure.immutableRoot(root) }

        let url = try url(for: root, path: path)
        guard Self.isDirectory(url.deletingLastPathComponent()) else {
            throw Failure.noParent(path)
        }

        let present = try? url.resourceValues(forKeys: [.isRegularFileKey])
        switch mode {
        case .create:
            guard present == nil else { throw Failure.exists(path) }
        case .replace:
            guard let present else { throw Failure.absent(path) }
            guard present.isRegularFile == true else { throw Failure.notAFile(path) }
        }

        let data = Data(text.utf8)
        guard data.count <= Self.maxWriteBytes else {
            throw Failure.unwritable(
                path, "it is \(data.count) bytes, and one write may carry \(Self.maxWriteBytes).")
        }

        do {
            try data.write(to: url, options: mode == .create ? [.withoutOverwriting] : [.atomic])
        } catch let error as NSError where error.code == NSFileWriteFileExistsError {
            throw Failure.exists(path)
        } catch {
            throw Failure.unwritable(path, error.localizedDescription)
        }
        return data.count
    }

    func list(root: Root, path: String?, depth: Int) throws -> [Entry] {
        let base = try url(for: root, path: path)
        guard Self.isDirectory(base) else { throw Failure.notADirectory(path ?? ".") }
        let prefix = path.map { $0.isEmpty ? "" : $0 + "/" } ?? ""
        return Self.walk(base, prefix: prefix, remaining: depth)
    }

    static func walk(_ directory: URL, prefix: String, remaining: Int) -> [Entry] {
        guard remaining > 0 else { return [] }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []

        var entries: [Entry] = []
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard entries.count < maxEntries else { break }
            let name = child.lastPathComponent
            guard !name.unicodeScalars.contains(where: LanguageContribution.isUnsafeScalar) else { continue }
            let values = try? child.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory == true
            guard isDirectory || values?.isRegularFile == true else { continue }
            entries.append(Entry(
                path: prefix + name,
                name: name,
                isDirectory: isDirectory,
                bytes: isDirectory ? 0 : (values?.fileSize ?? 0)))
            guard isDirectory, !skippedDirectories.contains(name) else { continue }
            entries += walk(child, prefix: prefix + name + "/", remaining: remaining - 1)
        }
        return Array(entries.prefix(maxEntries))
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    /// The folder a view opened over a terminal's directory works in: the
    /// repository that contains it, or the directory itself.
    ///
    /// `LSPCenter.workspaceRoot(for:)` answers the same question for a
    /// *file* and drops the last component before it starts, which is one
    /// folder too many for a directory that is already the root.
    static func workspaceRoot(forDirectory path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        var directory = (path as NSString).standardizingPath
        guard ExtensionViewFileScope.isDirectory(URL(fileURLWithPath: directory)) else { return nil }
        let start = directory
        while directory != "/", !directory.isEmpty {
            if FileManager.default.fileExists(atPath: directory + "/.git") {
                return URL(fileURLWithPath: directory, isDirectory: true)
            }
            directory = (directory as NSString).deletingLastPathComponent
        }
        return URL(fileURLWithPath: start, isDirectory: true)
    }
}
