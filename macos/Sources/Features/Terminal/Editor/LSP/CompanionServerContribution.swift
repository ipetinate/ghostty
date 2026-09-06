import Foundation

/// One entry of `contributes.servers` — a server that attaches *alongside*
/// a language's own server rather than instead of it.
///
/// Tailwind IntelliSense is the shape this exists for: it completes the
/// inside of a `class` attribute in five different languages, none of which
/// it is *the* server for. The Vue extension's second process is the other
/// shape — the `<script>` block of a `.vue` is served by tsserver loading a
/// plugin, while the Vue server keeps the template and the styles.
///
/// It is appended **after** the language's own server, because everything
/// that merges answers from several servers reads primary-first: the
/// language's own server is the one whose hover and diagnostics should win.
struct CompanionServerContribution: Equatable, Sendable, Identifiable {
    /// More than this in one extension is not a language pack, and each one
    /// is a process per language id per workspace.
    static let maxServers = 16

    static let maxLanguageIDs = 32

    static let maxProjectMarkers = 16

    static let maxMarkerLength = 256

    /// Stable within the extension, and the key one companion server
    /// shadows another on.
    let id: String

    let displayName: String

    /// Resolved on the login shell's `PATH` and launched directly, never
    /// through a shell — the same contract `LanguageServerContribution`
    /// has.
    let command: String

    let arguments: [String]

    /// The documents this server is offered for. One `LSPServerDefinition`
    /// is built per id, because `didOpen` announces the id and the server
    /// picks how to read the document from it — a document arriving as
    /// anything else is a document it has no rule for.
    let languageIDs: [String]

    /// Relative paths, any one of which starting the server when it is
    /// found walking up from the file's directory to the workspace root.
    /// Empty means always.
    let projectMarkers: [String]

    /// **Display and copy only.** This sentence never reaches a shell. A
    /// manifest that wants a button says so in `installPlan`, whose commands
    /// are checked word by word; this is the text beside it.
    let installHint: String

    let installPlan: ExtensionInstallPlan?

    let documentationURL: URL?

    /// `initializationOptions` re-encoded as JSON text, the same way a
    /// language's own server carries them.
    let initializationOptionsJSON: String?

    /// The glue this server needs that no JSON literal can express. See
    /// `LSPInitializationOptionsKind`.
    let resolver: LSPInitializationOptionsKind

    let category: LSPServerCategory

    let maximumJavaFeatureVersion: Int?

    /// The launchable definition for one of the language ids this server was
    /// declared for, or nil for any other.
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

    /// Nil when the entry has no usable id, no launchable command, or claims
    /// no language at all — each of which is a server nothing could ever
    /// start, and none of which costs the manifest anything else.
    static func parse(json: [String: Any]) -> CompanionServerContribution? {
        guard let id = LanguageManifest.validID(json["id"]) else { return nil }
        guard let command = LanguageManifest.string(json["command"]),
              LanguageServerContribution.isLaunchable(command)
        else { return nil }

        let languageIDs = self.languageIDs(from: json["languageIds"])
        guard !languageIDs.isEmpty else { return nil }

        return CompanionServerContribution(
            id: id,
            displayName: LanguageManifest.displayString(json["name"]) ?? id,
            command: command,
            arguments: LanguageServerContribution.arguments(from: json["args"]),
            languageIDs: languageIDs,
            projectMarkers: projectMarkers(from: json["projectMarkers"]),
            installHint: LanguageServerContribution.installHint(json["installHint"]),
            installPlan: ExtensionInstallPlan.parse(json["install"]),
            documentationURL: LanguageServerContribution.documentationURL(json["documentationURL"]),
            initializationOptionsJSON: LanguageServerContribution
                .initializationOptionsJSON(json["initializationOptions"]),
            resolver: LanguageServerContribution.resolver(json["resolver"]),
            category: LSPServerCategory(rawValue: LanguageManifest.string(json["category"]) ?? "")
                ?? .script,
            maximumJavaFeatureVersion: LanguageServerContribution
                .maximumJavaFeatureVersion(json["maximumJavaFeatureVersion"])
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

    /// Marker paths, refused unless they are relative and stay relative.
    ///
    /// An absolute marker would let a manifest decide the server runs by
    /// pointing at something outside the project entirely, and `..` would
    /// let it climb out of the directory the walk is standing in — which is
    /// the same walk that is already bounded by the workspace root, and
    /// pointless to bound if a marker can step over it.
    static func projectMarkers(from value: Any?) -> [String] {
        let raw = (value as? [Any])?.compactMap { $0 as? String } ?? []
        var seen: Set<String> = []
        return raw.compactMap { candidate -> String? in
            let text = candidate.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, text.count <= maxMarkerLength else { return nil }
            guard !text.hasPrefix("/"), !text.hasPrefix("~") else { return nil }
            guard !text.split(separator: "/").contains("..") else { return nil }
            guard !text.unicodeScalars.contains(where: LanguageContribution.isUnsafeScalar)
            else { return nil }
            return seen.insert(text).inserted ? text : nil
        }
        .prefix(maxProjectMarkers)
        .map { $0 }
    }
}
