import AppKit
import SwiftUI

/// One installed extension's configuration: everything about it that a
/// reader can change, in one form.
///
/// This is where the Languages pane went. That pane listed servers, and a
/// server is no longer a thing this app knows about on its own — every one
/// of them arrives inside an extension, so the extension is the only
/// identity a form can be keyed on. What used to be "the row for
/// `elixir-ls`" is now a section inside the form for the extension that
/// ships `elixir-ls`, next to the languages it contributes and the one
/// approval that covers all of them.
struct ExtensionSettingsForm: View {
    let extensionID: String

    @ObservedObject private var store = ExtensionStore.shared
    @ObservedObject private var languages = LanguageResolver.shared
    @ObservedObject private var lsp = LSPCenter.shared
    @StateObject private var requirements = ExtensionRequirementsModel()
    @StateObject private var run = PackageInstallRun()

    /// Bumped whenever something writes a record this form reads back.
    ///
    /// `LanguageTrustStore` writes to `UserDefaults` and publishes nothing,
    /// correctly — a security record has no business driving a view's
    /// lifecycle. So the write tells the form, and the sections re-read.
    @State private var defaultsRevision = 0

    @State private var runningCommand: String?

    private var installed: InstalledExtension? {
        store.installed.first { $0.id == extensionID }
    }

    private var contributedLanguages: [LanguageCatalog.Contributed] {
        languages.catalog.contributed
            .filter { $0.provenance.extensionID == extensionID }
            .sorted {
                $0.language.displayName.localizedStandardCompare($1.language.displayName)
                    == .orderedAscending
            }
    }

    /// A language's own server first, then the companions, which is the
    /// order they are consulted in — see `CompanionServerContribution`.
    private var servers: [ExtensionServerSubject] {
        contributedLanguages.compactMap(ExtensionServerSubject.init(language:))
            + ExtensionServerSubject.companions(
                ofExtension: extensionID,
                in: languages.catalog)
    }

    var body: some View {
        Form {
            identitySection
            trustSection

            ForEach(contributedLanguages) { contributed in
                ContributedLanguageSection(
                    contributed: contributed,
                    trustRevision: defaultsRevision)
            }

            ForEach(servers) { server in
                ExtensionServerSection(
                    server: server,
                    requirement: requirement(for: server.command),
                    run: run,
                    runningCommand: $runningCommand,
                    onRunFinished: reprobe)
            }

            if contributedLanguages.isEmpty, servers.isEmpty {
                Section {
                    Text("This extension contributes nothing that is configured here. Themes, icon packs and grammars work as soon as they are installed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .scrollIndicators(.hidden)
        .navigationTitle(title)
        .task {
            lsp.refreshInstalledCommands()
            requirements.load(directory: store.manifestDirectory(for: extensionID))
        }
        .onReceive(NotificationCenter.default.publisher(for: LanguageTrustStore.didChangeNotification)) { _ in
            defaultsRevision += 1
        }
    }

    private var title: String {
        installed?.name
            ?? contributedLanguages.first?.extensionName
            ?? contributedServers.first?.extensionName
            ?? extensionID
    }

    private func requirement(for command: String) -> ExtensionRequirement? {
        requirements.requirements.first { $0.program == command }
    }

    private func reprobe() {
        requirements.noteAvailabilityChanged()
        lsp.noteAvailabilityChanged()
        Task { await store.refreshRequirements(id: extensionID) }
    }

    // MARK: Identity

    private var identitySection: some View {
        Section {
            HStack(alignment: .center, spacing: 10) {
                ExtensionIconView(source: iconSource, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    /// `verbatim` for every manifest string on this screen:
                    /// the interpolating initializer treats its argument as a
                    /// `LocalizedStringKey`, which is markdown, so a name of
                    /// `**Elixir**` would render bold and one containing
                    /// `[x](javascript:…)` would render as a link.
                    Text(verbatim: title)
                        .font(.title3.weight(.semibold))
                    if !publisher.isEmpty {
                        Text(verbatim: publisher)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            LabeledContent("Identifier") {
                Text(verbatim: extensionID)
                    .textSelection(.enabled)
            }
            .background(alignment: .top) { OverlayScrollers() }

            if !version.isEmpty {
                LabeledContent("Version") {
                    Text(verbatim: version)
                        .textSelection(.enabled)
                }
            }

            if let manifestURL {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Origin")
                            .font(.headline)
                        Text(verbatim: manifestURL.path)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(3)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    /// Reveals rather than opens: this hands the file to the
                    /// Finder with it selected, which is a navigation.
                    /// Opening it would be Launch Services deciding what
                    /// application runs for a path an extension chose.
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([manifestURL])
                    }
                }
            }

            Button("Open in the Store") {
                if let installed {
                    ExtensionDocumentTabs.open(installed: installed)
                } else if let entry = store.index?.extensions.first(where: { $0.id == extensionID }) {
                    ExtensionDocumentTabs.open(entry)
                }
            }
        } header: {
            Text("Extension")
        } footer: {
            Text(scopeFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var publisher: String {
        installed?.publisher
            ?? contributedLanguages.first?.publisher
            ?? contributedServers.first?.publisher
            ?? ""
    }

    private var version: String {
        installed?.version
            ?? contributedLanguages.first?.extensionVersion
            ?? contributedServers.first?.extensionVersion
            ?? ""
    }

    /// An extension that contributes only companion servers has no
    /// contributed *language*, so neither the path nor the scope below can
    /// be read off one. Both fall through to the servers, which carry the
    /// same provenance.
    private var manifestURL: URL? {
        contributedLanguages.first?.manifestURL ?? contributedServers.first?.manifestURL
    }

    private var scope: LanguageManifest.Scope? {
        contributedLanguages.first?.provenance.scope
            ?? contributedServers.first?.provenance.scope
    }

    private var contributedServers: [LanguageCatalog.ContributedServer] {
        languages.catalog.servers.filter { $0.provenance.extensionID == extensionID }
    }

    private var iconSource: ExtensionIconSource? {
        store.iconSource(forExtension: extensionID)
    }

    private var scopeFooter: String {
        switch scope {
        case .bundled:
            return "Shipped inside Phantom. Bundled extensions are trusted by origin, which assumes the app's own resources are not writable — true of an installed app, and not of a local build."
        case .user, .none:
            return "Found in your extensions directory. Anything that can write there can change what this says, which is why the approval below is kept in your preferences and not beside the file."
        }
    }

    // MARK: Trust

    /// One approval per extension, not per language.
    ///
    /// The record is keyed by extension id — see `LanguageTrustStore` — so
    /// an extension contributing five languages has one decision behind all
    /// five, and drawing it once is the only way to say that truthfully.
    @ViewBuilder
    private var trustSection: some View {
        Section {
            Toggle("Run This Extension's Programs", isOn: Binding(
                get: { LanguageTrustStore.record(for: extensionID)?.decision != .refused },
                set: { setRunsPrograms($0) }
            ))

            if let record = LanguageTrustStore.record(for: extensionID) {
                LabeledContent("Refused") {
                    Text(record.decidedAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Trust")
        } footer: {
            Text("On by default, because installing an extension is what allows it to run: asking again the first time you open a file is a dialog that teaches you to click past dialogs. Turning it off stops exactly one thing — starting a server or a formatter process. Everything else this extension contributes, highlighting, comments and keywords, works either way.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .id(defaultsRevision)
    }

    /// Writes a refusal, or takes one back by forgetting it.
    ///
    /// Allowed is the *absence* of a record rather than a record saying yes.
    /// A stored yes would have to name what it covers — a digest, a command,
    /// a path — and then go stale the moment any of them changed, which is
    /// the re-asking this switch exists instead of.
    private func setRunsPrograms(_ runs: Bool) {
        defer { defaultsRevision += 1 }
        guard !runs else {
            LanguageResolver.shared.forgetTrust(extensionID: extensionID)
            return
        }
        LanguageResolver.shared.refuseTrust(
            extensionID: extensionID,
            digest: digest ?? "",
            manifestPath: manifestURL?.path ?? ""
        )
    }

    private var digest: String? {
        contributedLanguages.first?.provenance.digest
            ?? contributedServers.first?.provenance.digest
    }
}
