import SwiftUI

/// One server's rows inside its extension's form: what it is, whether its
/// binary is there, how to get it, and the three fields that override it.
///
/// The Install button reads ``ExtensionInstallPlan`` and nothing else.
/// `installHint` is beside it as text with a Copy button, and never as a
/// command — the plan is the only path from a manifest to `$SHELL -lic`,
/// and it earns that by checking every command word by word at the parse.
/// A free-text sentence arriving at the shell would turn "run this named
/// binary, once you approve it" into "run this sentence".
struct ExtensionServerSection: View {
    let server: ExtensionServerSubject
    let requirement: ExtensionRequirement?

    @ObservedObject var run: PackageInstallRun
    @Binding var runningCommand: String?
    let onRunFinished: () -> Void

    @ObservedObject private var lsp = LSPCenter.shared
    @State private var showUninstallConfirmation = false

    private var isInstalled: Bool { requirement?.isInstalled ?? false }

    private var install: ExtensionInstallCommand? { requirement?.install }

    private var isRunning: Bool { runningCommand == server.command }

    /// The sections are returned side by side rather than from a `Group`.
    /// A modifier on a `Group` of `Section`s collapses it into one opaque
    /// view, and the `Form` then draws the headers without the controls
    /// under them — which is how the override fields shipped invisible.
    var body: some View {
        section
            .confirmationDialog(
                "Uninstall \(server.displayName)?",
                isPresented: $showUninstallConfirmation,
                titleVisibility: .visible
            ) {
                Button("Uninstall", role: .destructive) {
                    guard let command = install?.uninstall else { return }
                    start(command)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(verbatim: "Runs \(install?.uninstall ?? "") in a terminal with your login environment.")
            }

        ServerOverrideFields(
            defaultCommand: server.command,
            defaultArguments: server.arguments
        )
    }

    private var section: some View {
        Section {
            LabeledContent("Status") { statusBadge }

            CopyableValueRow(title: "Default Command", value: server.invocation)

            LabeledContent(server.languageIDs.count == 1 ? "Language" : "Languages") {
                Text(verbatim: server.languageIDs.joined(separator: ", "))
                    .textSelection(.enabled)
            }

            if let path = requirement?.resolvedPath {
                LabeledContent("Found at") {
                    Text(verbatim: path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            if !server.installHint.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("How to Install")
                            .font(.headline)
                        Text(verbatim: server.installHint)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    CopyButton(text: server.installHint, label: "Copy")
                }
            }

            if let url = server.documentationURL {
                Link(destination: url) {
                    Label("Documentation", systemImage: "book.closed")
                }
                .buttonStyle(.link)
            }

            installControls
        } header: {
            HStack(spacing: 6) {
                Text(verbatim: server.displayName)
                if server.isCompanion {
                    Text("Companion")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: String {
        server.isCompanion
            ? "A companion server runs beside the server of each language it claims, not instead of it."
            : "This language's own server. It starts when you open a file of this kind, once the extension is approved."
    }

    /// The runtime answer when there is a launchable definition, and the
    /// answer about the file on disk when there is not — a shadowed
    /// contribution has no definition, and "is the binary there" is still
    /// worth saying about it.
    @ViewBuilder
    private var statusBadge: some View {
        if let definition = server.definition {
            LSPStatusBadge(status: lsp.status(for: definition), detailed: true)
        } else if isInstalled {
            Label("Installed", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Label("Not installed", systemImage: "circle.dashed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var installControls: some View {
        if isRunning {
            progress
        } else {
            HStack(spacing: 8) {
                if !isInstalled, let install {
                    Button("Install") { start(install.command) }
                        .disabled(run.isRunning)
                        .help("Runs \(install.command) in a terminal with your login environment")
                }
                if isInstalled, install?.uninstall != nil {
                    Button("Uninstall", role: .destructive) {
                        showUninstallConfirmation = true
                    }
                    .disabled(run.isRunning)
                }
                if !isInstalled, install == nil {
                    Text(verbatim: unavailableReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if runningCommand == nil, let failure = run.failure {
                Text(verbatim: failure)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var unavailableReason: String {
        server.documentationURL == nil
            ? "This extension says nothing about how to install it."
            : "No package manager this extension offers is installed here."
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let fraction = run.progress {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 140)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text("Working…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(run.recentOutput, id: \.self) { line in
                Text(verbatim: line)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func start(_ command: String) {
        guard !run.isRunning else { return }
        runningCommand = server.command
        run.run(command) { _ in
            runningCommand = nil
            onRunFinished()
        }
    }
}
