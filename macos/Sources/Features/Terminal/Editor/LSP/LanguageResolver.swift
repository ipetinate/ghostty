import Combine
import Foundation

/// The one place that answers "what language is this file, and what starts
/// for it" — the compiled-in registry plus whatever is installed.
///
/// A façade rather than a change to `LSPServerRegistry`, which stays what it
/// has always been: pure data, no filesystem, no app state, answerable in a
/// test with nothing around it. Everything that has to know about disk lives
/// on this side of the seam, and callers that used to reach for the registry
/// reach for this instead.
///
/// Ownership of the precedence rule lives here too, in one method each, so
/// that "the registry wins unless the user promoted this contribution" is
/// stated once rather than re-derived at every call site.
@MainActor
final class LanguageResolver: ObservableObject {
    static let shared = LanguageResolver()

    @Published private(set) var catalog: LanguageCatalog = .empty

    /// Every grammar the installed extensions ship, built once per reload and
    /// handed out by reference. Readers off the main actor take the reference
    /// and keep it for the duration of one job; a reload builds a new store
    /// rather than mutating this one under them.
    private(set) var grammars = GrammarStore()

    /// The catalog and grammars as of the last reload, readable from any
    /// thread. A diff pane lexes off the main actor and a markdown renderer
    /// is a plain struct; both take this rather than the actor.
    final class Snapshot: @unchecked Sendable {
        let catalog: LanguageCatalog
        let grammars: GrammarStore

        init(catalog: LanguageCatalog, grammars: GrammarStore) {
            self.catalog = catalog
            self.grammars = grammars
        }
    }

    private static let snapshotLock = NSLock()
    nonisolated(unsafe) private static var latestSnapshot = Snapshot(catalog: .empty, grammars: GrammarStore())

    nonisolated static var snapshot: Snapshot {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return latestSnapshot
    }

    private init() {
        reload()
    }

    /// The directory inside the app bundle holding extensions we ship,
    /// mirroring `FileIconProvider.bundledThemesDir`.
    ///
    /// Nothing ships there yet. The path is read anyway so that shipping one
    /// later is a resource change and not a code change.
    static var bundledExtensionsDir: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("extensions", isDirectory: true)
    }

    func reload() {
        catalog = LanguageCatalog.load(
            bundled: Self.bundledExtensionsDir,
            user: GuiConfigStore.shared.extensionsDirURL,
            promotions: LanguagePromotionStore.all
        )
        grammars = Self.buildGrammars(from: catalog)
        let snapshot = Snapshot(catalog: catalog, grammars: grammars)
        Self.snapshotLock.lock()
        Self.latestSnapshot = snapshot
        Self.snapshotLock.unlock()
        AgentRegistry.shared.setExtensionAgents(catalog.activeAgentDescriptors)
    }

    nonisolated static func buildGrammars(from catalog: LanguageCatalog) -> GrammarStore {
        let store = GrammarStore()
        for contributed in catalog.grammars {
            guard let size = (try? contributed.grammar.fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
                  size <= GrammarContribution.maxBytes,
                  let grammar = Grammar.parse(contentsOf: contributed.grammar.fileURL)
            else { continue }
            store.add(grammar, languageId: contributed.grammar.languageID)
        }
        return store
    }

    /// The highlighter for a file, which is plain text when no installed
    /// extension claims the file or the one that does ships no grammar.
    func highlighter(forFileName fileName: String) -> GrammarHighlighter {
        Self.highlighter(forFileName: fileName, in: Self.snapshot)
    }

    func highlighter(forLanguageID languageID: String?) -> GrammarHighlighter {
        Self.highlighter(forLanguageID: languageID, in: Self.snapshot)
    }

    func highlighter(forFenceLabel label: String?) -> GrammarHighlighter {
        Self.highlighter(forFenceLabel: label, in: Self.snapshot)
    }

    /// The language id an installed extension gives a file name, or nil.
    func languageID(forFileName fileName: String) -> String? {
        catalog.contribution(forFileName: fileName)?.language.languageID
    }

    /// The comment markers the extension claiming a file declared.
    func commentMarkers(forFileName fileName: String) -> CommentMarkers {
        Self.commentMarkers(forFileName: fileName, in: Self.snapshot)
    }

    nonisolated static func highlighter(forFileName fileName: String, in snapshot: Snapshot) -> GrammarHighlighter {
        let languageID = snapshot.catalog.contribution(forFileName: fileName)?.language.languageID
        return highlighter(forLanguageID: languageID, in: snapshot)
    }

    nonisolated static func highlighter(forLanguageID languageID: String?, in snapshot: Snapshot) -> GrammarHighlighter {
        guard let languageID, let grammar = snapshot.grammars.grammar(language: languageID) else { return .plain }
        return GrammarHighlighter(tokenizer: GrammarTokenizer(store: snapshot.grammars, grammar: grammar))
    }

    /// The highlighter for a fenced code block, whose label is whatever the
    /// author typed: a language id, a file extension, a nickname like `golang`
    /// or `console`, or a word naming no source language at all — `text`,
    /// `diff`, `mermaid` — for which the answer is plain, not a guess.
    nonisolated static func highlighter(forFenceLabel label: String?, in snapshot: Snapshot) -> GrammarHighlighter {
        guard let label else { return .plain }
        let trimmed = label.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return .plain }
        let name = fenceAliases[trimmed] ?? trimmed
        let store = snapshot.grammars
        if let grammar = store.grammar(language: name) ?? store.grammar(fileType: name) {
            return GrammarHighlighter(tokenizer: GrammarTokenizer(store: store, grammar: grammar))
        }
        return highlighter(forFileName: "fence." + name, in: snapshot)
    }

    nonisolated static func commentMarkers(forFileName fileName: String, in snapshot: Snapshot) -> CommentMarkers {
        guard let language = snapshot.catalog.contribution(forFileName: fileName)?.language else { return .none }
        return CommentMarkers(line: language.lineComment, block: language.blockComment)
    }

    /// The names authors write on a fence that no language id or file
    /// extension is spelled as. A convention of markdown, not a fact about
    /// any language, which is why it lives here and not in an extension.
    nonisolated static let fenceAliases: [String: String] = [
        "js": "javascript", "node": "javascript", "mjs": "javascript", "cjs": "javascript",
        "ts": "typescript", "golang": "go", "rs": "rust", "py": "python", "rb": "ruby",
        "sh": "shellscript", "bash": "shellscript", "zsh": "shellscript", "shell": "shellscript",
        "fish": "shellscript", "console": "shellscript", "terminal": "shellscript",
        "dockerfile": "shellscript", "make": "shellscript",
        "yml": "yaml", "md": "markdown", "mdx": "markdown",
        "postgres": "sql", "postgresql": "sql", "mysql": "sql",
        "c++": "cpp", "objc": "objective-c", "objective-c": "objective-c",
        "tf": "terraform", "hcl": "terraform", "kt": "kotlin", "kts": "kotlin",
        "jsonc": "json", "json5": "json", "vue-html": "html",
    ]

    // MARK: Resolution

    /// The LSP language id for a path, or nil when nothing claims it.
    func languageID(forPath path: String) -> String? {
        let name = (path as NSString).lastPathComponent
        if let contributed = catalog.contribution(forFileName: name) {
            return contributed.language.languageID
        }
        return LSPServerRegistry.languageID(forPath: path)
    }

    /// What to launch for a path.
    ///
    /// A contributed definition carries its own `origin`, which is what the
    /// trust gate reads. A registry definition carries `.builtIn` by
    /// default, so the gate lets it through without a lookup and without a
    /// chance to forget one.
    ///
    /// A contribution that claims the file but ships no server still *owns*
    /// the file, and the answer is nothing rather than the registry's:
    /// falling through would start a server for a language the user has
    /// replaced.
    func serverDefinition(forPath path: String) -> LSPServerDefinition? {
        let name = (path as NSString).lastPathComponent
        if let contributed = catalog.contribution(forFileName: name),
           let definition = contributed.serverDefinition {
            return definition
        }
        if catalog.contribution(forFileName: name) != nil { return nil }
        return LSPServerRegistry.server(forPath: path)
    }

    /// Every server that should be started for a file, in the order they are
    /// to be consulted — primary first.
    ///
    /// Plural because one language id is not one server, and two things make
    /// that concrete today. Since Volar 2 a `.vue` file is served by the Vue
    /// server for its template and by `typescript-language-server` — loading
    /// `@vue/typescript-plugin` — for its `<script>`; one server per language
    /// id is the Volar 1.x model and has been wrong since. And a file in a
    /// Tailwind project gets the Tailwind server alongside whichever server
    /// completes the language itself, which is what fills in a `class`
    /// attribute.
    ///
    /// This is also the seam where facts about disk are resolved: the registry
    /// is pure and takes both of them as values.
    func serverDefinitions(forPath path: String) -> [LSPServerDefinition] {
        let name = (path as NSString).lastPathComponent
        if let contributed = catalog.contribution(forFileName: name) {
            return contributed.serverDefinition.map { [$0] } ?? []
        }

        let root = LSPCenter.workspaceRoot(for: path)
        return LSPServerRegistry.servers(
            forPath: path,
            toolchain: TypeScriptToolchain.resolve(root: root),
            tailwind: TailwindProject.resolve(forPath: path, root: root)
        )
    }

    func serverDefinition(forLanguage languageID: String) -> LSPServerDefinition? {
        if let contributed = catalog.contribution(forLanguageID: languageID),
           let definition = contributed.serverDefinition {
            return definition
        }
        if catalog.contribution(forLanguageID: languageID) != nil { return nil }
        return LSPServerRegistry.server(forLanguage: languageID)
    }

    func formatter(forFileNamed name: String) -> ExternalFormatter? {
        Self.formatter(forFileNamed: name, catalog: catalog)
    }

    nonisolated static func formatter(
        forFileNamed name: String,
        catalog: LanguageCatalog
    ) -> ExternalFormatter? {
        catalog.formatter(forFileName: name)?.externalFormatter
    }

    /// `initializationOptions` a contribution supplied, as JSON text — the
    /// same shape a user's own override is stored in, so it can travel the
    /// same parse.
    func initializationOptionsJSON(forLanguage languageID: String) -> String? {
        catalog.contribution(forLanguageID: languageID)?
            .language.server?.initializationOptionsJSON
    }

    // MARK: User decisions

    /// Moves a contribution ahead of the compiled-in registry, or back.
    ///
    /// The gesture is the user's — a button in Settings. A manifest cannot
    /// ask for this, which is the whole reason the conflict is *shown*
    /// rather than resolved in the file's favour.
    func setPromoted(_ promoted: Bool, extensionID: String, languageID: String) {
        LanguagePromotionStore.setPromoted(
            promoted,
            extensionID: extensionID,
            languageID: languageID
        )
        reload()
        Self.noteResolutionChanged()
    }

    /// Forgets a trust decision, which is how a refusal is undone.
    func forgetTrust(extensionID: String) {
        LanguageTrustStore.forget(extensionID)
        Self.noteResolutionChanged()
    }

    /// Tells the open documents to introduce themselves again.
    ///
    /// Without it, undoing a refusal is a setting that appears to do
    /// nothing: `LSPCenter` asked the gate once, was told no, and has no
    /// reason to ask a second time — the file would have to be closed and
    /// reopened for the answer to be taken. The generation counter is the
    /// mechanism that already exists for "a server that could not run before
    /// can run now", and a decision reversed in Settings is exactly that.
    ///
    /// **The dependency only points this way.** `LSPCenter` reads this
    /// resolver, including from its own initializer, so anything here that
    /// reached for `LSPCenter.shared` *eagerly* would re-enter a singleton
    /// still being constructed. Reaching for it from a user's gesture, long
    /// after both exist, is safe; reaching for it from `reload()` — which
    /// runs during `init` — would not be.
    private static func noteResolutionChanged() {
        LSPCenter.shared.noteAvailabilityChanged()
    }

    /// The verdict for a contributed language, for a Settings row that wants
    /// to show what would happen without making it happen.
    ///
    /// `resolvedPath` and `workspaceRoot` are the caller's to supply; a row
    /// that only wants to say "not approved yet" can pass the command itself
    /// and no root.
    func trustVerdict(
        for contributed: LanguageCatalog.Contributed,
        resolvedPath: String,
        workspaceRoot: String? = nil
    ) -> LanguageTrust.Verdict? {
        guard let server = contributed.language.server else { return nil }
        let subject = LanguageTrust.Subject(
            origin: .manifest(contributed.provenance),
            digest: contributed.provenance.digest,
            command: server.command,
            resolvedPath: resolvedPath,
            workspaceRoot: workspaceRoot
        )
        return LanguageTrust.verdict(
            for: subject,
            record: LanguageTrustStore.record(for: contributed.provenance.extensionID)
        )
    }
}
