import SwiftUI

/// What a contributed language's row has to say about itself.
///
/// Assembled here rather than read off the model, because there is no one
/// field that answers it: whether a contribution is in force lives in
/// `LanguageCatalog.Resolution`, whether it may contribute a *server* lives
/// in `LanguageManifest.ServerEligibility`, and whether that server may be
/// launched lives in `LanguageTrust.Verdict`. Three answers from three
/// layers, and a row can only show one — so the order below is the whole
/// content of this type, and it runs most-inert first. A shadowed
/// contribution is not doing anything at all, so saying it is "not
/// approved" would be true and useless.
///
/// The three-layer split is deliberate upstream and worth not flattening:
/// eligibility is decided at parse time and cannot be argued with, trust is
/// a decision the user makes and can revisit, and resolution is about which
/// of several files wins. Collapsing them into one status field on the
/// model would make every future case pick a layer to lie about.
enum ContributedStatus: Equatable {
    /// In force, approved, ready to launch.
    case ready

    /// In force with no server of its own — highlighting, comments and
    /// keywords, and nothing to approve. A perfectly good state, and by far
    /// the most common one for a language pack.
    case noServer

    /// The user said no, and it stuck.
    case refused

    /// The manifest declares a schema this build cannot read, so its server
    /// half was discarded — see `LanguageManifest.ServerEligibility`.
    case needsNewerApp(declared: String)

    /// No usable `id`, so no approval could be recorded for it.
    case unidentified

    /// The command is not a program name, or resolves inside the workspace.
    /// Refused outright rather than asked about.
    case blocked(String)

    /// Parsed and listed, but something ahead of it already claims a file
    /// type it wanted.
    case shadowed(by: String, claim: String)

    @MainActor
    static func of(_ contributed: LanguageCatalog.Contributed) -> ContributedStatus {
        if case .shadowed(let shadow, let claim) = contributed.resolution {
            let owner: String
            switch shadow {
            case .builtIn: owner = "Phantom"
            case .extensionID(let id): owner = id
            }
            return .shadowed(by: owner, claim: claim)
        }

        switch contributed.language.serverRejection {
        case .ineligible(.needsNewerApp(let declared)):
            return .needsNewerApp(declared: declared)
        case .ineligible(.unidentified):
            return .unidentified
        case .unsafeCommand(let command):
            return .blocked(command)
        case .ineligible(.eligible), .missingCommand, .none:
            break
        }

        guard let server = contributed.language.server else { return .noServer }

        /// The command itself as the resolved path, per `trustVerdict`'s own
        /// note: this row is asking "would this be approved", not launching
        /// anything, and looking the binary up on `PATH` from a settings
        /// screen would block the main actor to answer a question the row
        /// does not need answered.
        /// The path the probe found, or nil while it has not answered and
        /// for a program that is not installed. A trust record holds where
        /// the program was when it was approved, so handing this the bare
        /// command name reported "the path changed" every single time.
        guard let verdict = LanguageResolver.shared.trustVerdict(
            for: contributed,
            resolvedPath: LSPCenter.shared.installedPath(forCommand: server.command)
        ) else {
            return .noServer
        }

        switch verdict {
        case .allow:
            return .ready
        case .deny(.refusedByUser):
            return .refused
        case .deny(.commandInsideWorkspace(let path)):
            return .blocked(path)
        case .deny(.unsafeCommand):
            return .blocked(server.command)
        }
    }

    var title: String {
        switch self {
        case .ready: return "Allowed"
        case .noServer: return "No Server"
        case .refused: return "Refused"
        case .needsNewerApp: return "Needs a Newer Phantom"
        case .unidentified: return "Missing Extension ID"
        case .blocked: return "Blocked"
        case .shadowed: return "Shadowed"
        }
    }

    var systemImage: String {
        switch self {
        case .ready: return "checkmark.seal"
        case .noServer: return "text.aligncenter"
        case .refused, .blocked: return "hand.raised"
        case .needsNewerApp: return "arrow.up.circle"
        case .unidentified: return "exclamationmark.triangle"
        case .shadowed: return "square.stack.3d.down.forward"
        }
    }

    /// Red only for a decision that stops something, orange for one waiting
    /// on the reader, grey for a state that is simply how things are — a
    /// language pack with no server is not a problem and should not be
    /// coloured like one.
    var color: Color {
        switch self {
        case .ready: return .green
        case .noServer, .shadowed: return .secondary
        case .needsNewerApp: return .orange
        case .refused, .blocked, .unidentified: return .red
        }
    }

    /// The sentence under the badge. Says what is true *and* what still
    /// works, because the whole point of gating only `Process.run` is that
    /// an unapproved language is not a broken one.
    var explanation: String {
        switch self {
        case .ready:
            return "Installing this extension is what allows its server to run. It starts when you open a file of this kind."
        case .noServer:
            return "This extension contributes highlighting, comments and keywords for this language, and no server. There is nothing to allow."
        case .refused:
            return "You told Phantom not to run this extension's programs, and that answer is kept. Allowing it again below is the only way back — a refusal that expired on its own would be one you eventually clicked past."
        case .needsNewerApp(let declared):
            return "The manifest declares schema version \(declared), which this build cannot read. Its language half still works; its server half was discarded rather than guessed at, because a later schema is free to change what `command` means."
        case .unidentified:
            return "The manifest has no usable id, so there is nowhere for an approval to live — a trust record is keyed by identity precisely so it is not keyed by a path. The language works; the server does not."
        case .blocked(let what):
            return "Phantom will not run \(what), whatever you allow. A command that needs a shell, or one that resolves inside the workspace you opened, is refused outright."
        case .shadowed(let owner, let claim):
            return "\(owner) already claims \(claim), so this contribution is parsed and listed but not in effect. Copying a file into a directory must never change a language you already had."
        }
    }
}

/// One contributed language's own sections inside its extension's form:
/// what state the contribution is in, what it claims, and the one control
/// that can change which of two claimants wins.
///
/// A section rather than a pane, because the reader arrives here by
/// choosing an *extension* — the language is one of possibly several things
/// that extension contributes, and everything the languages share (the
/// extension's identity, the approval covering all of them, the servers)
/// belongs beside them once rather than repeated per language.
struct ContributedLanguageSection: View {
    let contributed: LanguageCatalog.Contributed

    /// Not read by anything in this type, and load-bearing anyway.
    ///
    /// `LanguageTrustStore` writes to `UserDefaults` and publishes nothing,
    /// by design — a security record has no business driving a view's
    /// lifecycle. So forgetting a decision has to reach this section some
    /// other way, and a stored property that *changes* is the way SwiftUI is
    /// told a struct view is not the same value it was: without it the
    /// parent can re-evaluate, find an identical `ContributedLanguageSection`,
    /// and skip re-running this `body` — leaving "Refused" on screen after
    /// the record behind it was dropped.
    let trustRevision: Int

    private var status: ContributedStatus {
        ContributedStatus.of(contributed)
    }

    var body: some View {
        Section {
            LabeledContent("Status") {
                HStack(spacing: 5) {
                    Image(systemName: status.systemImage)
                        .foregroundStyle(status.color)
                    Text(status.title)
                }
            }

            Text(status.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledContent("Language ID") {
                Text(verbatim: contributed.language.languageID)
                    .textSelection(.enabled)
            }

            if !fileTypes.isEmpty {
                LabeledContent("Files") {
                    Text(verbatim: fileTypes)
                        .textSelection(.enabled)
                }
            }
        } header: {
            HStack(spacing: 6) {
                LanguageIconView(icon: contributed.language.iconURL, size: 14)
                /// Every string on this screen that came out of a manifest
                /// goes through `Text(verbatim:)`. The interpolating
                /// initializer treats its argument as a `LocalizedStringKey`,
                /// which is markdown — so a display name of `**Elixir**`
                /// would render bold, and one containing `[x](javascript:…)`
                /// would render as a link. The parser escapes control
                /// scalars; it does not escape markup, because escaping for a
                /// presentation layer is the presentation layer's job.
                Text(verbatim: contributed.language.displayName)
            }
        }

        precedenceSection
    }

    private var fileTypes: String {
        (contributed.language.fileExtensions.map { "." + $0 }
            + contributed.language.fileNames
            + contributed.language.filePatterns.map(\.source))
            .joined(separator: ", ")
    }

    /// The one control `LanguagePromotionStore` and
    /// `LanguageResolver.setPromoted` both say has to exist: precedence is
    /// **user extension > bundled extension**, and the only way past it is a
    /// click here. A manifest cannot ask to be promoted, which is the whole
    /// reason a conflict is *shown* rather than resolved in the file's
    /// favour — so without a button the shadowed state is a dead end and the
    /// design's escape hatch does not exist.
    ///
    /// Shown only when there is something to say. An active, unpromoted
    /// contribution is already winning nothing away from anybody, and
    /// offering to promote it would invite a question the reader does not
    /// have.
    @ViewBuilder
    private var precedenceSection: some View {
        if case .shadowed(let owner, let claim) = status {
            Section {
                Button("Use This Instead of \(owner)") {
                    LanguageResolver.shared.setPromoted(
                        true,
                        extensionID: contributed.provenance.extensionID,
                        languageID: contributed.language.languageID
                    )
                }
                .disabled(contributed.provenance.extensionID.isEmpty)
            } header: {
                Text("Precedence")
            } footer: {
                Text("\(owner) claims \(claim), so this contribution is inert. Promoting it puts this extension ahead — for this language only, and until you say otherwise.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if isPromoted {
            Section {
                Button("Stop Using This") {
                    LanguageResolver.shared.setPromoted(
                        false,
                        extensionID: contributed.provenance.extensionID,
                        languageID: contributed.language.languageID
                    )
                }
            } header: {
                Text("Precedence")
            } footer: {
                Text("You put this extension ahead of what claimed this language before. Turning it back gives the other one its place again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isPromoted: Bool {
        LanguagePromotionStore.isPromoted(
            extensionID: contributed.provenance.extensionID,
            languageID: contributed.language.languageID
        )
    }
}
