import Foundation
@testable import Ghostty
import Testing

/// Which TypeScript a project has, decided by one file.
///
/// TypeScript 7 is the native rewrite and ships no `tsserver.js`, so a
/// wrapper that drives that file — and bundles no copy of its own — cannot
/// serve a TS 7 project at all. Measured: `initialize` answers `-32603 Could
/// not find a valid TypeScript installation` and the process exits. The
/// native binary speaks LSP itself instead. So the question "which server"
/// is a fact about the project, and this is where it is answered.
///
/// Which server an extension then *declares* for that project is the
/// manifest's business, not this build's — see `LanguageCompanionTests`.
struct TypeScriptToolchainTests {
    /// A `FileManager` that answers for a fixed set of paths, so the routing
    /// can be exercised without laying out real `node_modules` trees.
    private final class FakeFileManager: FileManager, @unchecked Sendable {
        var present: Set<String> = []
        var files: [String: Data] = [:]

        override func fileExists(atPath path: String) -> Bool {
            present.contains(path) || files[path] != nil
        }

        override func contents(atPath path: String) -> Data? { files[path] }
    }

    private let root = "/Users/x/project"

    private var tsserverPath: String {
        root + "/node_modules/typescript/lib/tsserver.js"
    }

    @Test func aProjectWithATsserverGetsTheWrapper() {
        let fileManager = FakeFileManager()
        fileManager.present = [tsserverPath]

        #expect(
            TypeScriptToolchain.resolve(root: root, fileManager: fileManager)
                == .tsserver(path: tsserverPath)
        )
    }

    /// The TypeScript 7 shape: a `typescript` package is installed, and the
    /// one file the wrapper needs is simply not in it.
    @Test func aProjectWhoseTypeScriptHasNoTsserverGetsTheNativeServer() {
        let fileManager = FakeFileManager()
        fileManager.present = [
            root + "/node_modules/typescript/lib/tsc.js",
            root + "/node_modules/typescript/lib/getExePath.js",
        ]

        #expect(TypeScriptToolchain.resolve(root: root, fileManager: fileManager) == .native)
    }

    /// No TypeScript of its own resolves to the native server too — the
    /// useful default rather than a guess, since that is what a global
    /// install puts on `PATH` today. If it is missing as well, the launch
    /// reports `notInstalled` on its own.
    @Test func aProjectWithNoTypeScriptAtAllGetsTheNativeServer() {
        #expect(TypeScriptToolchain.resolve(root: root, fileManager: FakeFileManager()) == .native)
    }

    @Test func thePluginLocationIsAbsoluteAndOnlyWhenInstalled() {
        let fileManager = FakeFileManager()
        let plugin = "@vue/typescript-plugin"
        #expect(
            TypeScriptToolchain.pluginLocation(plugin, root: root, fileManager: fileManager) == nil
        )

        let location = root + "/node_modules/" + plugin
        fileManager.present = [location]
        #expect(
            TypeScriptToolchain.pluginLocation(plugin, root: root, fileManager: fileManager)
                == location
        )
        #expect(location.hasPrefix("/"), "the plugin resolves location through URI.file")
    }

    /// The plugin name comes out of a manifest and is joined onto two
    /// directories this app then reads, so a name that is not a package name
    /// is refused rather than walked.
    @Test func aPluginNameThatIsNotAPackageNameResolvesNowhere() {
        let fileManager = FakeFileManager()
        fileManager.present = [root + "/node_modules/../../../etc/evil"]

        for plugin in ["../../../etc/evil", "/etc/evil", "./evil", ""] {
            #expect(
                TypeScriptToolchain.pluginLocation(plugin, root: root, fileManager: fileManager) == nil,
                "\(plugin) was accepted as a package name"
            )
        }
    }

    @Test func theVersionIsReadOnlyWhenThereIsAMessageToWrite() {
        let fileManager = FakeFileManager()
        #expect(TypeScriptToolchain.localVersion(root: root, fileManager: fileManager) == nil)

        fileManager.files[root + "/node_modules/typescript/package.json"] =
            Data(#"{"name":"typescript","version":"7.0.2"}"#.utf8)
        #expect(TypeScriptToolchain.localVersion(root: root, fileManager: fileManager) == "7.0.2")
    }
}

/// Which files a binary may be handed at all — the one guard that outlived
/// the server table, because it is a fact about a program's behaviour rather
/// than a claim about which servers exist.
struct LSPCommandCompatibilityTests {
    /// **The native TypeScript server is never handed a file it does not
    /// recognise, and the reason is that it dies rather than declines.**
    ///
    /// Measured, one `didOpen` per process: `.vue`, `.svelte`, `.astro`,
    /// `.mdx`, `.css` and a file with no extension each end in
    /// `panic: ScriptKind must be specified when parsing source file`, inside
    /// `parser.(*Parser).initializeState`. The process leaves, and everything
    /// else it was serving leaves with it.
    ///
    /// So this is an allowlist, and writing it as "everything except `.vue`"
    /// is the mistake it exists to catch — `.vue` was only the first one
    /// anybody tried.
    ///
    /// It has to be keyed on the command because nothing in this build
    /// declares `tsc`: the two ways that command reaches a process are a user
    /// override repointing some language at it, and a contributed manifest
    /// naming it. Neither definition is written here, so neither could carry
    /// a field saying what it accepts.
    @Test func theBinaryIsRefusedTheFileWhoeverPointedAtIt() {
        for path in ["/p/App.vue", "/p/a.svelte", "/p/main.css", "/p/Makefile", "/p/x.ex"] {
            #expect(
                !LSPCommandCompatibility.accepts(
                    command: LSPCommandCompatibility.nativeTypeScriptCommand,
                    path: path
                ),
                "\(path) would have been handed to the native server, which panics on it"
            )
        }

        for path in ["/p/a.ts", "/p/a.TSX", "/p/a.js", "/p/tsconfig.json"] {
            #expect(
                LSPCommandCompatibility.accepts(
                    command: LSPCommandCompatibility.nativeTypeScriptCommand,
                    path: path
                ),
                "\(path) is in the measured allowlist and was refused"
            )
        }
    }

    /// The allowlist is the thing under test, so it is read rather than
    /// restated: every extension in it is accepted, and the six measured
    /// killers are not.
    @Test func theAllowlistIsWhatDecides() {
        for ext in LSPCommandCompatibility.nativeTypeScriptExtensions {
            #expect(
                LSPCommandCompatibility.accepts(
                    command: LSPCommandCompatibility.nativeTypeScriptCommand,
                    path: "/p/f.\(ext)"
                ),
                ".\(ext) is in the allowlist and was refused"
            )
        }

        for ext in ["vue", "svelte", "astro", "mdx", "css"] {
            #expect(
                !LSPCommandCompatibility.nativeTypeScriptExtensions.contains(ext),
                ".\(ext) was measured killing the process and is in the allowlist"
            )
        }
    }

    /// Every other binary is unaffected. The rule is about one command that
    /// dies on unknown input, not a general permission system — a server that
    /// declines a document politely needs no protection from us.
    @Test func noOtherBinaryIsConstrained() {
        for command in ["typescript-language-server", "vue-language-server", "gopls", "elixir-ls"] {
            for path in ["/p/App.vue", "/p/main.css", "/p/a.ts", "/p/Makefile"] {
                #expect(LSPCommandCompatibility.accepts(command: command, path: path), "\(command) \(path)")
            }
        }
    }
}

/// The options a tsserver hosting a plugin is started with, and the sentence
/// a reader gets when it cannot be.
struct PluginHostOptionsTests {
    private static let plugin = "@vue/typescript-plugin"

    private func value() -> LSPValue {
        LSPInitializationOptions.pluginHostValue(
            tsserverPath: "/p/node_modules/typescript/lib/tsserver.js",
            pluginLocation: "/p/node_modules/" + Self.plugin,
            plugin: Self.plugin,
            languages: ["vue"]
        )
    }

    /// `tsserver.path` is not optional: without it `initialize` answers
    /// "Could not find a valid TypeScript installation" and the process
    /// exits.
    @Test func theOptionsNameTheTsserverAndThePlugin() {
        let options = value()
        #expect(
            options["tsserver"]?["path"]?.stringValue
                == "/p/node_modules/typescript/lib/tsserver.js"
        )

        let plugin = options["plugins"]?.arrayValue?.first
        #expect(plugin?["name"]?.stringValue == Self.plugin)
        #expect(plugin?["location"]?.stringValue == "/p/node_modules/" + Self.plugin)
    }

    /// `languages` becomes tsserver's `modeIds`, which is the thing that
    /// registers the server for the language at all. Without it the server
    /// refuses the document outright.
    @Test func theLanguagesArrayIsWhatRegistersTheServerForTheLanguage() {
        let plugin = value()["plugins"]?.arrayValue?.first
        #expect(plugin?["languages"]?.arrayValue?.compactMap(\.stringValue) == ["vue"])
    }

    @Test func theLocationIsAbsolute() {
        let location = value()["plugins"]?.arrayValue?.first?["location"]?.stringValue
        #expect(location?.hasPrefix("/") == true, "location is read through URI.file")
    }

    /// **The refusal reaches the reader rather than being pruned.**
    ///
    /// Pruning the second server out of the routing was the first shape of
    /// this and it produced exactly the silence the feature exists to remove:
    /// a server that is never routed is never launched, so the sentence
    /// explaining why the `<script>` block is dead — which lives here, in the
    /// options resolution — never runs either. The reader got a working
    /// template, an empty script, and nothing to read.
    @Test func aProjectThatCannotHostThePluginGetsASentenceAndNotSilence() {
        let outcome = LSPInitializationOptions.typeScriptPluginHost(
            plugin: Self.plugin,
            languages: ["vue"],
            root: "/p/definitely-not-a-real-project-\(UUID().uuidString)"
        )

        guard case .failure(let reason) = outcome else {
            Issue.record("a project with no TypeScript resolved plugin options")
            return
        }
        #expect(reason.contains("will not start"))
        #expect(reason.contains(Self.plugin))
        #expect(reason.contains("6"))
    }

    /// The two failures pull in opposite directions, so they cannot share a
    /// sentence: with no TypeScript the answer is "install one", with
    /// TypeScript 7 it is "install an older one" — which nobody guesses.
    @Test func theTwoFailuresGiveOppositeAdvice() {
        let seven = LSPInitializationOptions.missingPluginHostMessage(
            plugin: Self.plugin, foundVersion: "7.0.2")
        #expect(seven.contains("7.0.2"))
        #expect(seven.contains("6.x"))

        let none = LSPInitializationOptions.missingPluginHostMessage(
            plugin: Self.plugin, foundVersion: nil)
        #expect(none.contains("no TypeScript of its own"))
        #expect(!none.contains("7.0.2"))
    }

    /// Silence and refusal look identical on screen. A reader who thinks it
    /// was attempted goes hunting for a failure that never happened, so the
    /// message has to say Phantom will not try — and it names the plugin,
    /// because the advice is "install this one" and the plugin is now
    /// whatever a manifest declared.
    @Test func theMessageSaysItWillNotTryAndNamesThePlugin() {
        let message = LSPInitializationOptions.missingPluginHostMessage(
            plugin: "typescript-svelte-plugin", foundVersion: "7.0.2")
        #expect(message.contains("will not start"))
        #expect(message.contains("typescript-svelte-plugin"))
    }

    /// The project has a tsserver but not the plugin — a different failure
    /// with different advice, and one a shared sentence would have hidden.
    @Test func aMissingPluginIsItsOwnSentence() {
        let message = LSPInitializationOptions.missingPluginMessage(plugin: Self.plugin)
        #expect(message.contains(Self.plugin))
        #expect(!message.contains("6.x"))
    }
}
