import Foundation

/// One server an extension contributes, whichever half of the manifest it
/// came from.
///
/// `contributes.languages[].server` and `contributes.servers[]` are two
/// declarations of the same thing to a reader configuring it — a binary, its
/// arguments, and the `initializationOptions` it is started with — so the
/// form draws one row shape for both and this is what a row is handed. The
/// difference that survives is ``isCompanion``, because a reader looking at
/// two rows for one language deserves to be told which is which.
struct ExtensionServerSubject: Identifiable {
    let id: String
    let displayName: String
    let command: String
    let arguments: [String]
    let installHint: String
    let documentationURL: URL?

    /// The documents this server is offered for. One id for a language's own
    /// server; several for a companion that attaches across languages.
    let languageIDs: [String]

    /// The launchable value, when there is one, so the row can report what
    /// the process is doing rather than only whether its binary exists.
    ///
    /// Always obtained from the model's own factory, never assembled here: a
    /// definition built by a view is a definition that can be built without
    /// provenance, and provenance is what the trust gate reads.
    let definition: LSPServerDefinition?

    let isCompanion: Bool

    var invocation: String {
        ([command] + arguments).joined(separator: " ")
    }
}

extension ExtensionServerSubject {
    /// The server a contributed language declares as its own, or nil when it
    /// declares none.
    init?(language contributed: LanguageCatalog.Contributed) {
        guard let server = contributed.language.server else { return nil }
        self.init(
            id: contributed.id + "#server",
            displayName: contributed.language.displayName,
            command: server.command,
            arguments: server.arguments,
            installHint: server.installHint,
            documentationURL: server.documentationURL,
            languageIDs: [contributed.language.languageID],
            definition: contributed.serverDefinition,
            isCompanion: false)
    }
}
