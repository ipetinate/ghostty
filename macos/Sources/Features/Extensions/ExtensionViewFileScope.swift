import Foundation

/// The two folders a contributed view may read, and the only way it reads
/// them.
///
/// A page never opens a file. It names a relative path, the app resolves it
/// against one of these folders, proves the result is still inside that
/// folder, and hands back the bytes. The proof is made twice against the
/// same resolved base — once on the path and once through
/// `resolvingSymlinksInPath` — so that neither a `../` nor a symlink planted
/// inside the workspace reaches out of it.
struct ExtensionViewFileScope: Equatable, Sendable {
    /// Which folder a path is resolved against.
    enum Root: String, CaseIterable, Equatable, Sendable {
        case workspace

        /// The extension's own installed directory. Spelled `extension` in
        /// the call because that is what an author calls it.
        case package = "extension"
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
            }
        }
    }

    let workspace: URL?
    let package: URL

    static let maxFileBytes = 2 * 1024 * 1024
    static let maxEntries = 2048

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
            guard !name.unicodeScalars.contains(where: LanguageManifest.isUnsafeScalar) else { continue }
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
