import Foundation

/// One entry of `contributes.servers`: a server that runs **beside** the
/// server of a language it does not own, for the files of the languages it
/// names, and only in a project that shows it is wanted.
///
/// Tailwind is the shape this was written against. Its server completes the
/// inside of a `class` attribute in HTML, Vue and JSX, none of which is its
/// language, and it has nothing to say in a project without
/// `node_modules/tailwindcss`. The other shape is a tsserver hosting a
/// plugin: the `<script>` block of a `.vue` is served by that process while
/// the Vue server keeps the template and the styles.
///
/// A companion is appended **after** the language's own server, because
/// everything that merges answers from several servers reads primary-first:
/// the language's own server is the one whose hover and diagnostics win.
///
/// The server half is spelled exactly as `languages[].server` is, and parsed
/// by the same code, so an author who has written one has written the other.
struct CompanionServerContribution: Equatable, Sendable {
    /// More than this in one extension is not a language pack, and each one
    /// is a process per language id per workspace.
    static let maxServers = 16

    static let maxLanguageIDs = 32

    /// What to call it in a list and in the approval prompt.
    let displayName: String

    let server: LanguageServerContribution

    /// The language ids this server attaches to, lower-cased. `didOpen`
    /// announces the file's own language id, so one process runs per
    /// language id per workspace — the arithmetic every other server already
    /// pays.
    let languageIDs: [String]

    /// What the project has to show before this server starts, read from
    /// `projectMarkers` — the same key, the same parser and the same walk a
    /// formatter uses to ask whether a project adopted it. Empty rules
    /// attach the server to every file of those languages.
    ///
    /// **Only the markers are read here.** A formatter block also carries
    /// `localBinary` and `workingDirectory`, and neither means anything to a
    /// server: the launch resolves its command on the login `PATH` and runs
    /// it in the workspace root. Parsing them would let a manifest write a
    /// key that decides nothing.
    let projectRules: FormatterProjectRules

    /// Which section of the Settings list this server belongs to.
    let category: LSPServerCategory

    /// The binary, which is this server's identity: two extensions attaching
    /// the same command to one language would run the same process twice for
    /// one file, so the catalog keeps one of them.
    var command: String { server.command }

    var arguments: [String] { server.arguments }

    var installHint: String { server.installHint }

    var installPlan: ExtensionInstallPlan? { server.installPlan }

    var documentationURL: URL? { server.documentationURL }

    var initializationOptionsJSON: String? { server.initializationOptionsJSON }

    /// The glue this server needs that no JSON literal can express. See
    /// `LSPInitializationOptionsKind`.
    var resolver: LSPInitializationOptionsKind { server.resolver }

    var maximumJavaFeatureVersion: Int? { server.maximumJavaFeatureVersion }

    /// The launchable definition for one of the language ids this server was
    /// declared for, or nil for any other.
    ///
    /// Keyed by the **file's** language id, not by anything of the
    /// companion's own: `didOpen` announces `definition.languageID`, and the
    /// server picks how to read the document from it. It also keeps the
    /// companion on its own `LSPCenter.Key` — same language, same root,
    /// different command — instead of colliding with the primary.
    ///
    /// That is load-bearing for a tsserver plugin host. The plugin's
    /// `languages` array becomes tsserver's `modeIds`, which is what
    /// registers the process for `vue` at all, and the document has to
    /// arrive announced as `vue` to match it.
    ///
    /// `provenance` is required rather than defaulted: the definition is
    /// what reaches the trust gate, and a companion server is a program from
    /// a file this app did not write exactly as much as a language's own
    /// server is.
    func definition(
        forLanguage languageID: String,
        provenance: ExtensionProvenance
    ) -> LSPServerDefinition? {
        guard languageIDs.contains(languageID) else { return nil }
        return LSPServerDefinition(
            languageID: languageID,
            displayName: displayName,
            command: command,
            arguments: arguments,
            installHint: installHint,
            initializationOptionsKind: resolver,
            initializationOptionsJSON: initializationOptionsJSON,
            origin: .manifest(provenance),
            category: category,
            documentationURL: documentationURL,
            maximumJavaFeatureVersion: maximumJavaFeatureVersion
        )
    }

    // MARK: Parsing

    /// Nil for an entry with no launchable command or no language to attach
    /// to — each of those is a server nothing could ever start. Every other
    /// defect costs the field, not the entry.
    static func parse(json: [String: Any]) -> CompanionServerContribution? {
        guard case (let server?, nil) = LanguageServerContribution.parse(json: json) else {
            return nil
        }
        let languageIDs = self.languageIDs(from: json["languageIds"])
        guard !languageIDs.isEmpty else { return nil }

        return CompanionServerContribution(
            displayName: LanguageManifest.displayString(json["name"]) ?? server.command,
            server: server,
            languageIDs: languageIDs,
            projectRules: FormatterProjectRules(
                markers: FormatterContribution.markers(from: json["projectMarkers"])
            ),
            category: LSPServerCategory(rawValue: LanguageManifest.string(json["category"]) ?? "")
                ?? .script
        )
    }

    static func languageIDs(from value: Any?) -> [String] {
        let raw = (value as? [Any]) ?? []
        var seen: Set<String> = []
        return raw
            .compactMap(LanguageContribution.validLanguageID)
            .filter { seen.insert($0).inserted }
            .prefix(maxLanguageIDs)
            .map { $0 }
    }
}
