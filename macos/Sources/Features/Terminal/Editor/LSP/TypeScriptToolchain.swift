import Foundation

/// Which TypeScript a workspace has, and therefore which server can serve it.
///
/// TypeScript 7 is the native rewrite and ships **no `tsserver.js`**. Measured
/// against 7.0.2: the whole of `lib/` is `getExePath.js`, `tsc.js`,
/// `version.cjs` and two `.d.ts` files, `bin` declares only `tsc`, and
/// npm's `latest` is 7 — so `npm i typescript` today produces exactly that.
///
/// Two things follow, and together they are the reason this type exists
/// rather than a preference setting:
///
/// - `typescript-language-server` drives `tsserver.js` and bundles no copy of
///   its own. Against a TypeScript 7 install it does not degrade: `initialize`
///   answers `-32603 Could not find a valid TypeScript installation. … Exiting.`
///   and the process leaves.
/// - The native binary speaks LSP itself — `tsc --lsp --stdio` — with no
///   tsdk, no `tsserver.path`, and nothing in between. (`--lsp` alone exits 1;
///   the pair is the invocation.)
///
/// So which server a file gets is a fact about its project, and the whole
/// discriminator is whether one file is on disk.
enum TypeScriptToolchain: Equatable, Sendable {
    /// A `tsserver.js` the wrapper can drive, at this absolute path.
    case tsserver(path: String)

    /// No `tsserver.js` here. The native binary is the only thing that can
    /// serve this project — and, `latest` being 7, usually the only thing
    /// installed.
    case native

    /// Where a project keeps its own TypeScript, relative to the workspace.
    static let localLibPath = "node_modules/typescript/lib"

    /// The file whose presence decides everything above.
    static let tsserverFileName = "tsserver.js"

    /// Where a project keeps its `node_modules`, relative to the workspace.
    static let nodeModulesPath = "node_modules"

    /// What this workspace has.
    ///
    /// **Project-local only, and deliberately one `stat`.** This is on the
    /// hot path — `LSPCenter.keys(forPath:)` runs it for every debounced
    /// change — so it may not read a `package.json`, and it certainly may not
    /// do what `LSPInitializationOptions.globalTypeScriptLib` does and shell
    /// out to `npm root -g`. The version number is not needed to route:
    /// "is there a `tsserver.js`" answers the question by itself, and the
    /// version is read only when there is a message to write.
    ///
    /// A project with no TypeScript of its own resolves to `.native`, which
    /// is the useful default rather than a guess: `tsc` is what a global
    /// install puts on `PATH` today, and if it is absent too the launch
    /// reports `.notInstalled` on its own.
    static func resolve(root: String, fileManager: FileManager = .default) -> TypeScriptToolchain {
        let lib = (root as NSString).appendingPathComponent(localLibPath)
        let tsserver = (lib as NSString).appendingPathComponent(tsserverFileName)
        return fileManager.fileExists(atPath: tsserver) ? .tsserver(path: tsserver) : .native
    }

    /// The directory a named tsserver plugin lives in, when it is installed
    /// for this workspace.
    ///
    /// Absolute, because a plugin's `location` is read through
    /// `URI.file(...)` and a relative path resolves against whatever the
    /// server's working directory happens to be.
    /// The project's copy wins, and a global install is the fallback.
    ///
    /// The fallback is what makes installing the plugin from Settings mean
    /// anything: that install is global, and without this the app would look
    /// only inside the project and load nothing. The asymmetry it removes was
    /// real — the tsdk beside it has had a global fallback all along, so the
    /// same Settings row could supply one half of a pair and not the other.
    ///
    /// Local first because a project pinning its own plugin has a reason to,
    /// and because a global copy at a different version than the project's
    /// own tooling is the mismatch the pinning exists to prevent.
    ///
    /// `plugin` is a package name out of a manifest and is refused unless it
    /// is one — see `isPackageName`. It is joined onto two directories this
    /// app then reads, so a `..` in it would be a manifest choosing which
    /// directory a language server loads code from.
    ///
    /// Safe to shell out here: this runs while resolving a server's launch
    /// options, once per server, not on the typing path.
    static func pluginLocation(
        _ plugin: String,
        root: String,
        searchPath: String = "",
        fileManager: FileManager = .default
    ) -> String? {
        guard isPackageName(plugin) else { return nil }

        let local = (root as NSString)
            .appendingPathComponent(nodeModulesPath)
            .appending("/" + plugin)
        if fileManager.fileExists(atPath: local) { return local }

        guard !searchPath.isEmpty,
              let npm = LSPProcess.locate("npm", searchPath: searchPath),
              let output = ShellCommand.run(npm, ["root", "-g"], timeout: 5)
        else { return nil }

        let root = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else { return nil }

        let global = (root as NSString).appendingPathComponent(plugin)
        return fileManager.fileExists(atPath: global) ? global : nil
    }

    /// Whether a string is an npm package name and nothing else — a scope, a
    /// name, and the characters npm itself allows in one.
    static func isPackageName(_ plugin: String) -> Bool {
        guard !plugin.isEmpty, plugin.count <= 214 else { return false }
        guard !plugin.hasPrefix("/"), !plugin.hasPrefix("."), !plugin.hasSuffix("/") else {
            return false
        }
        guard !plugin.split(separator: "/").contains("..") else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789@/._-")
        return plugin.allSatisfy(allowed.contains)
    }

    /// The version string beside a project's TypeScript, for a message.
    ///
    /// Off the routing path on purpose — this reads and parses a file, and
    /// the only thing it is for is telling somebody *which* TypeScript was
    /// found so the advice can be right. See `unusableReason(root:)`.
    static func localVersion(root: String, fileManager: FileManager = .default) -> String? {
        let manifest = (root as NSString)
            .appendingPathComponent("node_modules/typescript/package.json")
        guard let data = fileManager.contents(atPath: manifest),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String
        else { return nil }
        return version
    }
}
