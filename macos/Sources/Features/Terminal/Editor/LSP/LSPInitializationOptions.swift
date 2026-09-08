import Foundation

/// A named capability this build implements for a server that asked for it,
/// when a user override doesn't already supply `initializationOptions`.
///
/// Everything a server needs that is *data* travels as literal JSON in its
/// manifest. These two are what is left: glue that has to read the project
/// on disk before it knows what to send, which no literal can express. A
/// manifest asks for one by name, in its server block:
///
/// ```jsonc
/// "resolver": { "kind": "typescriptSDKArgument" }
/// "resolver": { "kind": "typescriptPluginHost",
///               "plugin": "@vue/typescript-plugin", "languages": ["vue"] }
/// ```
///
/// `LSPServerDefinition` stays a plain, `Hashable` value — a closure there
/// would give every definition its own identity. A tag plus a resolver that
/// switches on it keeps the data pure and the resolution (which touches the
/// filesystem, and for one case a subprocess) in one place that can be
/// tested on its own.
enum LSPInitializationOptionsKind: Hashable, Sendable {
    case none

    /// The server drives TypeScript but cannot find it the way an editor
    /// that already indexed the project would. Phantom resolves the
    /// project's TypeScript library directory and appends `--tsdk=<dir>` to
    /// the arguments — spelled `typescriptSDKArgument` in a manifest.
    case typeScriptSDKArgument

    /// The server *is* tsserver, and the thing that teaches it a language it
    /// does not otherwise know is a TypeScript plugin. Phantom resolves the
    /// project's `tsserver.js` and the named plugin's directory, and builds
    /// the `initializationOptions` that load one into the other — spelled
    /// `typescriptPluginHost` in a manifest.
    ///
    /// `languages` becomes tsserver's `modeIds`, which is what registers the
    /// server for those ids at all. Without it the server refuses the
    /// document outright (`Unexpected resource …`).
    case typeScriptPluginHost(plugin: String, languages: [String])
}

/// Which of the three sources supplies one launch's `initializationOptions`.
///
/// The decision on its own, before any of the three has been read: an
/// override is text in `UserDefaults`, a resolver is a walk of the project's
/// `node_modules` and sometimes an `npm` subprocess, and a manifest's literal
/// is text off disk. Separating the choice from the work is what lets the
/// choice be read — and asserted — without any of it.
///
/// See `LSPCenter.initializationOptionsSource(for:override:)` for the order
/// and why it is that order.
enum LSPInitializationOptionsSource: Equatable {
    /// The reader's own override, as the raw JSON text they typed.
    case override(String)

    /// A value this app works out from the project, named by the manifest.
    ///
    /// The kind travels whole rather than narrowed to the two that resolve
    /// to something, so a launch reads exactly what the definition holds.
    /// `LSPCenter.initializationOptionsSource(for:override:)` never answers
    /// `.resolver(.none)` — a manifest that named no resolver is `manifest`
    /// or `none` — and a launch handed one sends nothing, the same as `none`.
    case resolver(LSPInitializationOptionsKind)

    /// The JSON the manifest wrote out literally.
    case manifest(String)

    /// Nothing to send, which is the answer for most servers.
    case none
}

enum LSPInitializationOptions {
    /// The concrete alternative to silence: shown when neither a
    /// project-local nor a global TypeScript can be found.
    static let missingTypeScriptMessage = """
    This language server needs TypeScript, and none was found in this \
    project or globally. Install it with "npm i -D typescript" in the \
    project, or "npm i -g typescript".
    """

    /// Where a server should look for TypeScript: the project's own copy
    /// first, so a workspace pinning a version is checked against that
    /// version rather than whatever else happens to be on the machine.
    ///
    /// The global lookup shells out to `npm`, so this belongs off the main
    /// actor — see the call in `LSPCenter.server(for:)`.
    static func typeScriptSDK(
        root: String,
        searchPath: String,
        fileManager: FileManager = .default
    ) -> LSPOutcome<String> {
        let local = (root as NSString).appendingPathComponent("node_modules/typescript/lib")
        if fileManager.fileExists(atPath: local) { return .success(local) }

        if let global = globalTypeScriptLib(searchPath: searchPath, fileManager: fileManager) {
            return .success(global)
        }
        return .failure(missingTypeScriptMessage)
    }

    /// `npm root -g` rather than guessing at Homebrew/nvm/volta layouts:
    /// npm already knows exactly where it put things, and a guess would be
    /// wrong for exactly the setups a guess is hardest to get right for.
    private static func globalTypeScriptLib(searchPath: String, fileManager: FileManager) -> String? {
        guard let npm = LSPProcess.locate("npm", searchPath: searchPath) else { return nil }
        guard let output = ShellCommand.run(npm, ["root", "-g"], timeout: 5) else { return nil }

        let root = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else { return nil }

        let candidate = (root as NSString).appendingPathComponent("typescript/lib")
        return fileManager.fileExists(atPath: candidate) ? candidate : nil
    }

    /// The file a server loads out of a `tsdk`, whichever way it was told
    /// where the directory is.
    static let tsdkEntryPoint = "typescript.js"

    /// The reason a directory that exists is still not a usable `tsdk`.
    ///
    /// Names TypeScript 7 because that is what it is, on every machine this
    /// fires on today: `npm i -g typescript` installs the native rewrite,
    /// whose `lib` holds `tsc.js` and a version file and nothing a language
    /// server can load. See `TypeScriptToolchain`.
    static let unloadableTypeScriptMessage = """
    The TypeScript found for this project has no library for a language \
    server to load — TypeScript 7 is the native rewrite and ships none. \
    Install one this server can use with "npm i -D typescript@6" in the \
    project.
    """

    /// The `tsdk` a server can actually load, or the reason there is none.
    ///
    /// The extra check exists because the path became a **launch argument**.
    /// A directory that is there but empty of `typescript.js` used to make
    /// the server report its own failure during `initialize`; a server that
    /// resolves the file while it is still starting is killed by the same
    /// directory before it says anything at all. Answering here keeps the
    /// sentence the reader needs.
    static func loadableTypeScriptSDK(
        root: String,
        searchPath: String,
        fileManager: FileManager = .default
    ) -> LSPOutcome<String> {
        switch typeScriptSDK(root: root, searchPath: searchPath, fileManager: fileManager) {
        case .failure(let reason):
            return .failure(reason)
        case .success(let tsdk):
            let entry = (tsdk as NSString).appendingPathComponent(tsdkEntryPoint)
            guard fileManager.fileExists(atPath: entry) else {
                return .failure(unloadableTypeScriptMessage)
            }
            return .success(tsdk)
        }
    }

    /// The value to send as `initializationOptions`, for a resolved `tsdk`.
    static func sdkValue(tsdk: String) -> LSPValue {
        ["typescript": ["tsdk": .string(tsdk)]]
    }

    /// The same `tsdk`, on the command line, because some servers read it
    /// **only** from there.
    ///
    /// Measured against `@vue/language-server` 3.3.10 and 3.3.11: its entry
    /// point scans `process.argv` for `--tsdk=`, and falls back to
    /// `require('typescript')` when there is none. That fallback resolves to
    /// the peer copy npm installs beside the server, which today is
    /// TypeScript 7 — the native rewrite, which has no `tsserver` for the
    /// server to drive. The result is not an error: `initialize` answers
    /// normally, and then every request hangs unanswered, because the server
    /// never gets as far as asking `tsserver` which project the file belongs
    /// to. Sending `initializationOptions.typescript.tsdk`, which version 2
    /// read, changes nothing there — version 3 never looks at it.
    ///
    /// Both are sent. The option is what the older server reads and the
    /// argument is what the newer one reads, and a machine can have either
    /// installed.
    static func tsdkArgument(tsdk: String) -> String {
        "--tsdk=\(tsdk)"
    }

    /// Shown when a document is opened in a project whose TypeScript cannot
    /// host the plugin its server needs.
    ///
    /// It names the version it found, because the advice depends on it and
    /// the two cases pull in opposite directions: with no TypeScript at all
    /// the answer is "install one", and with TypeScript 7 the answer is
    /// "install an older one", which nobody guesses.
    ///
    /// It also says Phantom **will not try**. That is the part a shorter
    /// message loses: silence and refusal look identical on screen, and a
    /// reader who thinks it was attempted goes looking for the failure.
    static func missingPluginHostMessage(plugin: String, foundVersion: String?) -> String {
        let found = foundVersion.map {
            "This project has TypeScript \($0), which ships no tsserver for the plugin to load."
        } ?? "This project has no TypeScript of its own."

        return """
        \(found) \(plugin) needs TypeScript 6.x here, and Phantom will not \
        start a server for it until there is one. Install it with \
        "npm i -D typescript@6 \(plugin)" in the project.
        """
    }

    /// Shown when the project has a tsserver but not the plugin itself.
    static func missingPluginMessage(plugin: String) -> String {
        """
        This server loads \(plugin), and it is not installed in this \
        project. Install it with "npm i -D \(plugin)".
        """
    }

    /// `initializationOptions` for a tsserver hosting one plugin.
    ///
    /// `location` is absolute because the plugin resolves it through
    /// `URI.file(...)`, which has nothing to resolve a relative path against
    /// but the server's working directory.
    static func pluginHostValue(
        tsserverPath: String,
        pluginLocation: String,
        plugin: String,
        languages: [String]
    ) -> LSPValue {
        [
            "tsserver": ["path": .string(tsserverPath)],
            "plugins": [
                [
                    "name": .string(plugin),
                    "location": .string(pluginLocation),
                    "languages": .array(languages.map { .string($0) }),
                ],
            ],
        ]
    }

    /// The plugin options for a workspace, or the reason there are none.
    static func typeScriptPluginHost(
        plugin: String,
        languages: [String],
        root: String,
        searchPath: String = "",
        fileManager: FileManager = .default
    ) -> LSPOutcome<LSPValue> {
        guard case .tsserver(let tsserverPath) = TypeScriptToolchain.resolve(
            root: root,
            fileManager: fileManager
        ) else {
            return .failure(missingPluginHostMessage(
                plugin: plugin,
                foundVersion: TypeScriptToolchain.localVersion(root: root, fileManager: fileManager)
            ))
        }

        guard let location = TypeScriptToolchain.pluginLocation(
            plugin,
            root: root,
            searchPath: searchPath,
            fileManager: fileManager
        ) else {
            return .failure(missingPluginMessage(plugin: plugin))
        }

        return .success(pluginHostValue(
            tsserverPath: tsserverPath,
            pluginLocation: location,
            plugin: plugin,
            languages: languages
        ))
    }
}
