import Foundation

/// Where a server definition, or an external formatter, came from — and
/// therefore whether the reader's own refusal can apply to it.
///
/// This travels *on the definition* rather than in a table beside it. A
/// field that rides along cannot be forgotten; a side table looked up by
/// language id can, and one missed lookup is not a bug in a UI — it is the
/// gate not running.
enum LSPServerOrigin: Hashable, Sendable {
    /// Compiled into this build. No language server is any more — every one
    /// of them comes from a manifest — but a formatter and an agent still
    /// can be, and the gate has to have a case that no refusal can key
    /// against, because there is no extension to refuse.
    case builtIn

    /// From an `extension.json`, with the identity an approval is keyed by.
    case manifest(ExtensionProvenance)
}

/// The identity of the extension a definition came from.
///
/// Keyed by `extensionID` + `digest` and **never** by directory: a store
/// will one day want to verify these bytes with a signature instead of a
/// hash, and that has to be possible without invalidating a format people
/// have already published. Identity that is a path is identity that changes
/// when somebody reorganizes a folder.
struct ExtensionProvenance: Hashable, Sendable {
    let extensionID: String

    /// SHA-256 of the manifest's raw bytes. See `LanguageManifest.digest`.
    let digest: String

    let manifestPath: String

    let scope: LanguageManifest.Scope
}

/// What a user decided about one extension's server, as persisted.
///
/// Deliberately **not** stored in the config directory. A trust decision
/// kept next to the manifest is a trust decision the manifest's author can
/// write, and the whole point of the record is that it says something the
/// extension does not get to say about itself.
struct LanguageTrustRecord: Codable, Equatable, Sendable {
    enum Decision: String, Codable, Equatable, Sendable {
        case allowed
        case refused
    }

    /// The shape of this record.
    ///
    /// A record this build cannot decode is treated as **absent**, which is
    /// the same as no decision: the extension runs, because installing it
    /// was the consent. A future field that changes what a refusal covers
    /// must therefore come with a bump, or an old build would keep running
    /// something the reader had refused.
    var recordVersion: Int

    /// The manifest bytes this decision was made about.
    var digest: String

    /// The command as the manifest wrote it.
    var command: String

    /// Where that command resolved on `PATH` when the decision was taken.
    ///
    /// Kept for the record rather than compared against: what the reader
    /// refused is the extension, not one path it happened to resolve to, so
    /// a refusal survives a `brew upgrade` moving the binary.
    var resolvedPath: String

    /// Where the manifest was when the decision was made. Recorded so a
    /// reader can see what they answered about; a refusal follows the
    /// extension by id, not by path.
    var manifestPath: String

    var decision: Decision

    var decidedAt: Date

}

/// Whether a server may be launched — the entire trust model, as one pure
/// function.
///
/// It gates **exactly one thing: `Process.run`.** Everything else an
/// extension contributes works whatever the answer is, and that is what
/// makes a refusal a usable answer instead of a broken editor: a refused
/// `.ex` file still highlights, still toggles comments, still completes
/// from the words in the buffer and the keywords in the manifest. Only the
/// process stays down.
///
/// Pure so the tests that cover it never go near a `Process`, a
/// `UserDefaults`, or a window. Everything it needs — including the path
/// `PATH` resolution landed on — arrives as a value that somebody else
/// looked up.
enum LanguageTrust {
    /// What is being judged.
    ///
    /// Wider than `(origin, record)` because the two hardenings judge
    /// something that is not in the manifest's identity: the command as
    /// written, and where it resolved relative to the workspace it would run
    /// in. Passing them in keeps the comparison here, where it is tested,
    /// instead of at each call site.
    struct Subject: Equatable, Sendable {
        let origin: LSPServerOrigin

        /// The digest of the manifest **as it is now**, carried into the
        /// record a refusal writes.
        let digest: String

        let command: String

        /// The absolute path `LSPProcess.locate` returned. The caller
        /// resolves first: a command that cannot be found has nothing to
        /// approve, and "not installed" is not a trust answer.
        /// Where the program is on this machine right now.
        ///
        /// **Nil means "not known", never "not there".** A caller that has
        /// not resolved the command cannot claim its path changed, so a nil
        /// skips the path comparison and leaves the rest of the checks to
        /// speak. Passing the bare command name instead of nil is what made
        /// every approved extension read as out of date.
        let resolvedPath: String?

        /// The workspace the file being edited belongs to, when known.
        let workspaceRoot: String?
    }

    enum Verdict: Equatable, Sendable {
        /// Launch it.
        case allow

        /// Do not launch it.
        case deny(Denial)
    }

    enum Denial: Equatable, Sendable {
        /// The user said no. Remembered, and reversible only from Settings:
        /// a refusal that expires when the next `.ex` file opens is a
        /// refusal the user will eventually click past.
        case refusedByUser(at: Date)

        /// The command resolved to something inside the workspace.
        ///
        /// Plenty of shells put `./node_modules/.bin` on `PATH`, so a
        /// manifest can name a perfectly innocent-looking command and rely
        /// on a freshly-cloned repository to supply it. Approving the name
        /// would then approve whatever the repo shipped.
        case commandInsideWorkspace(path: String)

        /// The command is not a program name. Already refused at parse time;
        /// checked again here because this is the last point before a
        /// process, and a defence that exists at only one layer is a
        /// defence one refactor from being gone.
        case unsafeCommand
    }

    /// Whether this launch may go ahead.
    ///
    /// **Installing the extension is the consent.** Nothing here asks: a
    /// reader who fetched an extension from the store, or put one in their
    /// extensions directory by hand, has already said they want what it
    /// contributes, and a dialog raised the first time a `.php` file is
    /// opened only teaches them to click past dialogs. What used to be four
    /// re-ask rules — a changed manifest, a changed command, a moved
    /// manifest, a command that resolved somewhere new — are all the same
    /// answer now, and it is yes.
    ///
    /// The two hardenings above stay, because neither is a question. They
    /// are checked before any remembered answer, since no approval makes
    /// them safe.
    ///
    /// A refusal is the reader's own, taken in Settings, and it is the one
    /// thing here that can say no. It is never expired by a change to the
    /// extension: a refusal that lifts itself when the manifest is rewritten
    /// is not a refusal.
    static func verdict(for subject: Subject, record: LanguageTrustRecord?) -> Verdict {
        guard case .manifest = subject.origin else { return .allow }

        if !LanguageServerContribution.isLaunchable(subject.command) {
            return .deny(.unsafeCommand)
        }
        if let root = subject.workspaceRoot, let path = subject.resolvedPath,
           isInside(path, root: root) {
            return .deny(.commandInsideWorkspace(path: path))
        }

        guard let record, record.decision == .refused else { return .allow }
        return .deny(.refusedByUser(at: record.decidedAt))
    }

    /// Path containment, compared on standardized paths so `.` and `..`
    /// cannot make an inside path look outside.
    ///
    /// A workspace of `/` counts as no workspace: it is not a repository
    /// that could have shipped a binary, and treating it as one would deny
    /// every server for any file opened outside a project.
    static func isInside(_ path: String, root: String) -> Bool {
        let standardizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        guard standardizedRoot != "/", !standardizedRoot.isEmpty else { return false }
        let prefix = standardizedRoot.hasSuffix("/") ? standardizedRoot : standardizedRoot + "/"
        return standardizedPath.hasPrefix(prefix)
    }
}
