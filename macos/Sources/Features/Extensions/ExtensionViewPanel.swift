import AppKit
import SwiftUI

/// A contributed view, in the sidebar pane it was opened into.
///
/// Stages the extension's bundle off the main thread, then hands the page to
/// `ExtensionViewHost`. A view whose bundle cannot be staged says so in
/// words rather than showing an empty pane, because the two things that put
/// it there — an entry the author did not build, and a bundle over the size
/// limit — are both the author's to fix and neither logs anywhere the reader
/// can see.
struct ExtensionViewPanel: View {
    let descriptor: ExtensionViewDescriptor

    /// The folder the view's filesystem methods are bounded to, or nil when
    /// the terminal the sidebar follows is not in one. Nil is a real answer:
    /// `workspace.read` then refuses rather than reading from somewhere
    /// arbitrary.
    let workspace: URL?

    @ObservedObject private var palette: ThemePalette = .shared
    @ObservedObject private var store: ExtensionStore = .shared

    @State private var staged: URL?
    @State private var failure: String?

    private var scope: ExtensionViewFileScope {
        ExtensionViewFileScope(workspace: workspace, package: descriptor.root)
    }

    /// What a restage has to be keyed on: the view, the extension's version
    /// on disk, and the folder the methods are bounded to.
    private var identity: String {
        [descriptor.id, descriptor.root.path, workspace?.path ?? ""].joined(separator: "\u{1}")
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    permissions: descriptor.contribution.permissions
                ),
                theme: ExtensionViewerTheme.current()
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
