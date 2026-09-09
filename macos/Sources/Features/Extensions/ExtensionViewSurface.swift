import AppKit
import SwiftUI

/// One contributed view, staged and drawn.
///
/// Shared by the two surfaces, because staging a bundle and hosting a page
/// is the same work whether the page ends up in the sidebar or in a tab —
/// see `ExtensionViewPanel` and `ExtensionViewPaneView`, which differ only in
/// where the descriptor and the workspace come from.
///
/// A view whose bundle cannot be staged says so in words rather than showing
/// an empty pane, because the two things that put it there — an entry the
/// author did not build, and a bundle over the size limit — are both the
/// author's to fix and neither logs anywhere the reader can see.
struct ExtensionViewSurface: View {
    let descriptor: ExtensionViewDescriptor

    /// The folder the view's filesystem methods are bounded to, or nil when
    /// there is none. Nil is a real answer: the methods refuse rather than
    /// reaching somewhere arbitrary, and the page is expected to offer
    /// `workspace.choose`.
    let workspace: URL?

    /// The file this editor view is drawing. Nil for a sidebar panel.
    var file: URL?

    /// Rises by one on every ⌘S the reader presses on this tab. Zero for a
    /// sidebar panel, which has no save gesture of its own.
    var saveTicket: Int = 0

    /// What the page said about its unsaved work, for the tab's dirty mark.
    var onDirty: (Bool) -> Void = { _ in }

    @ObservedObject private var palette: ThemePalette = .shared
    @ObservedObject private var store: ExtensionStore = .shared

    @State private var staged: URL?
    @State private var failure: String?
    @State private var chosen: URL?

    /// The chosen folder wins while it is set, so a page that asked the
    /// reader for one keeps working in it even after the terminal moves —
    /// and, because it is remembered, after a restart.
    private var effectiveWorkspace: URL? { chosen ?? workspace }

    /// Where a chosen folder is remembered: one record per extension per
    /// workspace, keyed on the folder the terminal is in.
    ///
    /// Keyed on the *terminal's* folder rather than on the chosen one,
    /// because the question it answers is "where does this reader want this
    /// view to work when they are in this project", and the chosen folder is
    /// the answer.
    private var record: ExtensionViewState {
        ExtensionViewState(extensionID: descriptor.extensionID, workspace: workspace)
    }

    private func remember(_ url: URL) {
        chosen = url
        record.setChosenWorkspace(url, cachesDir: store.cachesDir)
    }

    /// The folder the reader picked last time, if it is still there.
    private func restoreChoice() {
        guard chosen == nil else { return }
        chosen = record.chosenWorkspace(cachesDir: store.cachesDir)
    }

    private var scope: ExtensionViewFileScope {
        ExtensionViewFileScope(workspace: effectiveWorkspace, package: descriptor.root)
    }

    /// What a restage has to be keyed on: the view, the extension's version
    /// on disk, and the folder the methods are bounded to.
    private var identity: String {
        [descriptor.id, descriptor.root.path, effectiveWorkspace?.path ?? "", file?.path ?? ""]
            .joined(separator: "\u{1}")
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear(perform: restoreChoice)
            .task(id: identity) { await prepare() }
    }

    @ViewBuilder
    private var content: some View {
        if let failure {
            message(failure)
        } else if let staged {
            ExtensionViewHost(
                request: ExtensionViewHost.Request(
                    host: staged,
                    base: staged.deletingLastPathComponent(),
                    scope: scope,
                    permissions: descriptor.contribution.permissions,
                    opener: ExtensionViewOpener(for: descriptor),
                    file: file.flatMap { ExtensionViewFile.inside(scope, url: $0) },
                    state: ExtensionViewState(
                        extensionID: descriptor.extensionID, workspace: effectiveWorkspace),
                    cachesDir: store.cachesDir,
                    saveTicket: saveTicket
                ),
                theme: ExtensionViewerTheme.current(),
                onChoose: remember,
                onDirty: onDirty
            )
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func message(_ text: String) -> some View {
        VStack(spacing: 6) {
            ExtensionArtwork(url: descriptor.icon, size: 28)
            Text(descriptor.title)
                .font(palette.font(size: 12, weight: .semibold))
            Text(text)
                .font(palette.font(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func prepare() async {
        let root = ExtensionViewHostBundle.root(cachesDir: store.cachesDir)
        let descriptor = descriptor
        let outcome = await Task.detached(priority: .userInitiated) {
            Result { try ExtensionViewHostBundle.stage(descriptor, root: root) }
        }.value

        switch outcome {
        case .success(let host):
            staged = host
            failure = nil
        case .failure(let error):
            staged = nil
            failure = Self.message(for: error)
        }
    }

    static func message(for error: Error) -> String {
        switch error {
        case let failure as ExtensionViewHostBundle.Failure: return failure.message
        default: return error.localizedDescription
        }
    }
}
