import Foundation

/// A file whose presence says a project adopted a formatter.
///
/// A tool that carries its own configuration file leaves the plain form
/// behind; a tool declared inside a manifest somebody else owns leaves the
/// second one, because the manifest is there in every project of that
/// ecosystem and only the key means anything.
enum FormatterMarker: Equatable, Hashable, Sendable {
    /// A path relative to each directory the walk visits. Existence is the
    /// whole test — the contents are the tool's business, not ours.
    case file(String)

    /// A top-level key inside a manifest, `package.json` and `package.yaml`
    /// being the pair this was written against.
    case key(named: String, inFile: String)

    /// The file this marker looks for, relative to a directory on the walk.
    var fileName: String {
        switch self {
        case .file(let name): return name
        case .key(_, let file): return file
        }
    }
}

/// Where a formatter is run from.
///
/// It decides which configuration the tool finds, so it is a statement about
/// the tool and belongs beside the rest of them rather than in the runner.
enum FormatterWorkingDirectory: String, Equatable, Hashable, Sendable, CaseIterable {
    /// Beside the marker that was found. A `plugins` entry in a configuration
    /// is resolved relative to that configuration, and a monorepo package
    /// that formats differently from its root would otherwise run from the
    /// wrong place.
    case marker

    /// Beside the file being formatted, which is what a tool that reads a
    /// configuration from the file's own directory upwards wants.
    case file

    /// The enclosing repository, for a tool whose configuration is only ever
    /// at the top.
    case workspace
}

/// What a formatter declares about the projects it serves.
///
/// Empty by default, and an empty value is the tool that simply formats: no
/// project has to say anything for it to run, and it runs beside the file.
/// Every field here comes from a manifest, so nothing in this type may name a
/// tool.
struct FormatterProjectRules: Equatable, Hashable, Sendable {
    /// In the order the manifest wrote them, which is the order they are
    /// preferred in — the first one found is the one reported.
    var markers: [FormatterMarker] = []

    /// The tool installed into the project, as a path relative to a directory
    /// on the walk. Preferred over the `PATH` lookup when it is found.
    var localBinary: String?

    var workingDirectory: FormatterWorkingDirectory = .file

    /// Whether anything here is a claim about the project adopting the tool.
    var declaresAdoption: Bool { !markers.isEmpty || localBinary != nil }

    /// Whether answering any of this needs the walk at all. A tool that
    /// declares none of it costs no `stat` calls.
    var needsWalk: Bool { declaresAdoption || workingDirectory != .file }
}

/// What the walk up from a file found: whether the project adopted this
/// formatter, which copy of it to run, and where to run it.
///
/// The four questions a formatter asks about a project, answered from the
/// three keys a manifest declares. Nothing here knows which tool it is
/// answering for.
struct FormatterProject: Equatable, Sendable {
    /// How much the project said about this tool.
    enum Adoption: Equatable, Sendable {
        /// The project declared it: a marker was found, or the tool is
        /// installed into the project. Its answer beats the language
        /// server's, because the project already made that choice.
        case adopted

        /// The tool asks projects to declare it, and this one did not. It may
        /// still be run by hand, and must not run on a save — running one
        /// project's globally installed tool over a repository that formats
        /// with something else rewrites files against the house style.
        case unadopted

        /// The tool asks for nothing. It is the only formatter its language
        /// has here, which is where the language server's own formatter
        /// stands, so it runs whenever the server has no answer.
        case undeclared
    }

    let rules: FormatterProjectRules

    /// The directory holding the file being formatted. The fallback for every
    /// working directory that could not be resolved: running a formatter from
    /// wherever the app happens to be is never the better answer.
    let fileDirectory: String

    /// The nearest marker found on the walk, if any. Only its existence is
    /// meaningful, and the directory holding it.
    let markerPath: String?

    /// The nearest copy of the tool installed into the project, if any.
    let localBinaryPath: String?

    /// Where the walk stopped: the enclosing repository, or the home
    /// directory. Nil when neither was reached before the depth limit.
    let rootPath: String?

    var adoption: Adoption {
        guard rules.declaresAdoption else { return .undeclared }
        return markerPath != nil || localBinaryPath != nil ? .adopted : .unadopted
    }

    /// The directory to run the tool in.
    var workingDirectory: String {
        switch rules.workingDirectory {
        case .file:
            return fileDirectory
        case .marker:
            guard let markerPath else { return rootPath ?? fileDirectory }
            return (markerPath as NSString).deletingLastPathComponent
        case .workspace:
            return rootPath ?? fileDirectory
        }
    }
}

extension FormatterProject {
    // MARK: The walk

    /// Walks up from a file collecting everything the rules ask about.
    ///
    /// Every declared signal is collected on one pass, and the walk continues
    /// past the first hit for the *other* one — a monorepo package holds the
    /// configuration while the hoisted binary lives at the repository root,
    /// and finding only the nearer of the two would make the decision depend
    /// on which came first.
    ///
    /// ## Where it stops
    ///
    /// At the enclosing repository, or at the user's home directory,
    /// whichever comes first — never at `/`. Two reasons, and the second is
    /// the one that matters:
    ///
    /// - A configuration outside the repository is not this project's. Its
    ///   author did not write it for a file they have never seen.
    /// - The directories above `~` are shared, and on a work machine not
    ///   always the user's. Reading `/.somethingrc` to decide how to rewrite
    ///   someone's buffer is a decision taken by whoever can write to `/`.
    ///
    /// `.git` is tested for *existence*, not for being a directory: in a
    /// worktree or a submodule it is a file holding a `gitdir:` pointer, and
    /// those are exactly the checkouts people do parallel work in.
    ///
    /// ## Cost
    ///
    /// A tool that declares nothing costs nothing: the walk is skipped
    /// outright. Otherwise, per directory, one `stat` per marker that misses,
    /// one for the local binary, one for `.git`, and — only where a manifest
    /// marker's file exists — one small read. Cheap enough to run per save;
    /// not so cheap that it should run per keystroke.
    ///
    /// - Parameter maximumDepth: a walk that cannot run away. The path is
    ///   arbitrary user input.
    static func discover(
        forFile path: String,
        rules: FormatterProjectRules,
        fileManager: FileManager = .default,
        homeDirectory: String? = nil,
        maximumDepth: Int = 64
    ) -> FormatterProject {
        let fileDirectory = (path as NSString).deletingLastPathComponent

        guard rules.needsWalk else {
            return FormatterProject(
                rules: rules,
                fileDirectory: fileDirectory,
                markerPath: nil,
                localBinaryPath: nil,
                rootPath: nil
            )
        }

        let home = homeDirectory ?? fileManager.homeDirectoryForCurrentUser.path
        var directory = URL(fileURLWithPath: path).deletingLastPathComponent()

        var markerPath: String?
        var localBinaryPath: String?
        var rootPath: String?

        for _ in 0..<maximumDepth {
            /// The root itself is never inspected. Everyone's files are under
            /// it, so a marker there would claim every project at once.
            guard directory.path != "/", !directory.path.isEmpty else { break }

            if markerPath == nil {
                markerPath = marker(in: directory, rules: rules, fileManager: fileManager)
            }
            if localBinaryPath == nil {
                localBinaryPath = localBinary(in: directory, rules: rules, fileManager: fileManager)
            }

            let isRepositoryRoot = fileManager.fileExists(
                atPath: directory.appendingPathComponent(".git").path
            )
            if isRepositoryRoot || directory.path == home {
                rootPath = directory.path
                break
            }

            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { break }
            directory = parent
        }

        return FormatterProject(
            rules: rules,
            fileDirectory: fileDirectory,
            markerPath: markerPath,
            localBinaryPath: localBinaryPath,
            rootPath: rootPath
        )
    }

    /// The first marker present in one directory, in the order declared.
    static func marker(
        in directory: URL,
        rules: FormatterProjectRules,
        fileManager: FileManager = .default
    ) -> String? {
        for marker in rules.markers {
            let candidate = directory.appendingPathComponent(marker.fileName).path
            switch marker {
            case .file:
                if fileManager.fileExists(atPath: candidate) { return candidate }
            case .key(let name, _):
                if declares(name, inFileAt: candidate, fileManager: fileManager) { return candidate }
            }
        }
        return nil
    }

    /// The tool installed into one directory.
    ///
    /// Executable, not merely present: a path that is there and cannot be run
    /// is a broken or half-installed tree, not an installation.
    static func localBinary(
        in directory: URL,
        rules: FormatterProjectRules,
        fileManager: FileManager = .default
    ) -> String? {
        guard let relative = rules.localBinary else { return nil }
        let candidate = directory.appendingPathComponent(relative).path
        return fileManager.isExecutableFile(atPath: candidate) ? candidate : nil
    }
}

extension FormatterProject {
    // MARK: Reading a key out of a manifest

    /// Whether a manifest declares a key at its top level.
    ///
    /// The value is never inspected. It is legally an object *or* a string
    /// naming another file, and either way the only thing being asked is
    /// whether the author declared the tool here.
    ///
    /// Only JSON and YAML are read. A manifest in a format this cannot parse
    /// answers "no", which leaves the file alone instead of having something
    /// else reformat it.
    static func declares(
        _ key: String,
        inFileAt path: String,
        fileManager: FileManager = .default
    ) -> Bool {
        guard fileManager.fileExists(atPath: path) else { return false }

        switch (path as NSString).pathExtension.lowercased() {
        case "json": return jsonDeclares(key, at: path)
        case "yaml", "yml": return yamlDeclares(key, at: path)
        default: return false
        }
    }

    /// A malformed manifest reads as "no". It is a file somebody is probably
    /// mid-edit on, and guessing at a broken one is how a formatter starts
    /// running where it was not wanted.
    static func jsonDeclares(_ key: String, at path: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }

        return object[key] != nil
    }

    /// **A line scan, not a parser.** Foundation ships no YAML, and the whole
    /// question is whether one key exists at the top level of a manifest —
    /// which in a package manifest is written in block style, one key per
    /// line at column zero. Pulling in a YAML dependency to answer that would
    /// be a larger decision than the feature deserves, and would put a parser
    /// on the path that decides whether to reformat somebody's file.
    ///
    /// The limit, stated rather than discovered later: a manifest written as
    /// a single flow mapping — `{tool: {...}}` on one line — reads as "no".
    /// Nothing writes a package manifest that way, and the failure is the
    /// safe direction: the tool is not claimed, so the file is left alone
    /// instead of being reformatted by something else.
    static func yamlDeclares(_ key: String, at path: String) -> Bool {
        guard let text = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        else { return false }

        return text.split(separator: "\n", omittingEmptySubsequences: false).contains { line in
            declaresTopLevelKey(key, in: line)
        }
    }

    /// A top-level `key:`, quoted or not.
    ///
    /// Indentation is what makes it top-level, so a leading space disqualifies
    /// the line — otherwise `dependencies:` followed by an indented
    /// `<key>: ^3.6.0` would read as a configuration, and a dev dependency is
    /// not a declaration that this project is configured here. That is the
    /// same distinction `jsonDeclares` gets for free from JSON.
    static func declaresTopLevelKey(_ key: String, in line: some StringProtocol) -> Bool {
        guard let first = line.first, first != " ", first != "\t" else { return false }

        var rest = line[line.startIndex...]
        for quote in ["\"", "'"] where rest.hasPrefix(quote) {
            rest = rest.dropFirst()
            guard rest.hasPrefix(key + quote) else { return false }
            rest = rest.dropFirst((key + quote).count)
            return rest.drop(while: { $0 == " " }).hasPrefix(":")
        }

        guard rest.hasPrefix(key) else { return false }
        return rest.dropFirst(key.count).drop(while: { $0 == " " }).hasPrefix(":")
    }
}
