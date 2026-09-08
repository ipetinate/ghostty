import Foundation

extension ExtensionServerSubject {
    /// The companion servers one extension contributes — the entries of
    /// `contributes.servers`, which attach beside a language's own server
    /// rather than instead of it.
    ///
    /// The single point where the settings form reads that half of the
    /// catalog. Everything above it works in ``ExtensionServerSubject``, so
    /// a change to the catalog's own names lands here and nowhere else.
    static func companions(
        ofExtension extensionID: String,
        in catalog: LanguageCatalog
    ) -> [ExtensionServerSubject] {
        catalog.servers
            .filter { $0.provenance.extensionID == extensionID }
            .map { contributed in
                let server = contributed.server
                return ExtensionServerSubject(
                    id: contributed.id,
                    displayName: server.displayName,
                    command: server.command,
                    arguments: server.arguments,
                    installHint: server.installHint,
                    documentationURL: server.documentationURL,
                    languageIDs: server.languageIDs,
                    /// One definition stands for the row even though the
                    /// contribution produces one per language id: they differ
                    /// only in the id announced at `didOpen`, and the row is
                    /// asking about the binary and the process, which every
                    /// one of them shares. Nil when the contribution is not
                    /// in force, which is `serverDefinitions` refusing rather
                    /// than this view deciding.
                    definition: contributed.serverDefinitions.first,
                    isCompanion: true)
            }
    }
}
