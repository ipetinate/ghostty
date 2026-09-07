import Foundation

/// The gate: store and verdict in one call, so the two places that create a
/// process from a manifest's command — the language-server start and the
/// external-formatter run — have one line to add rather than a policy to
/// reimplement.
///
/// It gates `Process.run` and nothing else. A refusal here costs the file
/// its server or its formatter; it keeps its highlighting, its comment
/// toggling, its keywords and its buffer-word completion, because none of
/// those needed a process.
///
/// **Nothing here asks.** Installing the extension is the consent, and the
/// only answer that can stop a launch is a refusal the reader took in
/// Settings, plus the two hardenings `LanguageTrust.verdict` applies to
/// every launch. This used to raise a sheet on first run and on every
/// change to the manifest, the command or its resolved path.
enum LanguageTrustGate {
    /// Whether this definition may be launched.
    ///
    /// `resolvedPath` is the caller's: it has already located the command to
    /// decide whether the server is installed at all, and resolving twice
    /// could resolve differently.
    static func allowsLaunch(
        of definition: LSPServerDefinition,
        resolvedPath: String,
        workspaceRoot: String?
    ) -> Bool {
        guard case .manifest(let provenance) = definition.origin else { return true }

        return allows(
            LanguageTrust.Subject(
                origin: definition.origin,
                digest: provenance.digest,
                command: definition.command,
                resolvedPath: resolvedPath,
                workspaceRoot: workspaceRoot
            ),
            extensionID: provenance.extensionID
        )
    }

    static func allowsRun(
        of formatter: ExternalFormatter,
        resolvedPath: String,
        workspaceRoot: String?
    ) -> Bool {
        guard case .manifest(let provenance) = formatter.origin else { return true }

        return allows(
            LanguageTrust.Subject(
                origin: formatter.origin,
                digest: provenance.digest,
                command: formatter.command,
                resolvedPath: resolvedPath,
                workspaceRoot: workspaceRoot
            ),
            extensionID: provenance.extensionID
        )
    }

    private static func allows(_ subject: LanguageTrust.Subject, extensionID: String) -> Bool {
        LanguageTrust.verdict(
            for: subject,
            record: LanguageTrustStore.record(for: extensionID)
        ) == .allow
    }
}
