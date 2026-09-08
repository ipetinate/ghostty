import AppKit
import Combine
import SwiftUI

/// One contributed view, paired with the extension that ships it.
///
/// The contribution alone is not enough to open a page: the app has to know
/// which extension's directory the entry is inside, so it can stage the
/// files and bound the filesystem methods to that directory.
struct ExtensionViewDescriptor: Identifiable, Equatable, Sendable {
    let extensionID: String
    let extensionName: String
    let root: URL
    let contribution: ExtensionViewContribution

    /// `<extension id>/<view id>` — unique because an extension id is
    /// unique in the folder and a view id is unique within its manifest.
    var id: String { extensionID + "/" + contribution.viewID }

    var title: String { contribution.title }
    var icon: URL { contribution.icon }
}

/// Every contributed view the installed extensions offer.
///
/// Derived from `ExtensionStore.installed` rather than scanning on its own,
/// so a view appears the moment an extension is installed and disappears
/// when it is removed, with no second reader of the folder.
@MainActor
final class ExtensionViewRegistry: ObservableObject {
    static let shared = ExtensionViewRegistry()

    @Published private(set) var views: [ExtensionViewDescriptor] = []

    /// How many contributed views may reach the two bars at once.
    ///
    /// A rail of forty icons is not a rail. The manifest already caps a
    /// single extension at `ExtensionViewContribution.maxViews`; this is the
    /// cap across all of them.
    static let maxViews = 24

    private var subscription: AnyCancellable?

    init(store: ExtensionStore = .shared) {
        views = Self.descriptors(in: store.installed)
        subscription = store.$installed
            .map(Self.descriptors(in:))
            .removeDuplicates()
            .sink { [weak self] descriptors in
                MainActor.assumeIsolated { self?.publish(descriptors) }
            }
    }

    func descriptor(id: String) -> ExtensionViewDescriptor? {
        views.first { $0.id == id }
    }

    func views(at placement: ExtensionViewContribution.Placement) -> [ExtensionViewDescriptor] {
        views.filter { $0.contribution.placements.contains(placement) }
    }

    /// The editor view that claims this file name, or nil.
    ///
    /// First claim in registry order wins, and the order is the installed
    /// set's — alphabetical by name. Two extensions claiming `*.bru` is an
    /// arbitrary winner, and it is arbitrary in a stable way rather than by
    /// whichever was scanned first; the reader still reaches the other
    /// through "Open with" on the tab.
    func editorView(claiming fileName: String) -> ExtensionViewDescriptor? {
        views.first { $0.contribution.claims(fileName: fileName) }
    }

    /// Every editor view that claims this file name, for the tab's menu.
    func editorViews(claiming fileName: String) -> [ExtensionViewDescriptor] {
        views.filter { $0.contribution.claims(fileName: fileName) }
    }

    private func publish(_ descriptors: [ExtensionViewDescriptor]) {
        guard descriptors != views else { return }
        views = descriptors
    }

    nonisolated static func descriptors(in installed: [InstalledExtension]) -> [ExtensionViewDescriptor] {
        installed
            .flatMap { extensionPackage in
                extensionPackage.views.map {
                    ExtensionViewDescriptor(
                        extensionID: extensionPackage.id,
                        extensionName: extensionPackage.name,
                        root: extensionPackage.root,
                        contribution: $0
                    )
                }
            }
            .prefix(maxViews)
            .map { $0 }
    }
}

/// Artwork a package ships, drawn from the file and remembered by URL.
///
/// **Never an SF Symbol.** A symbol name the running macOS does not resolve
/// makes SwiftUI drop the whole row out of a `List` with nothing logged, and
/// the name would come from a third party. A file that does not decode draws
/// the fallback below, which is this app's own symbol and is known to
/// resolve.
struct ExtensionArtwork: View {
    let url: URL
    var size: CGFloat = 16

    static let fallbackSymbol = "puzzlepiece"

    var body: some View {
        if let image = ExtensionArtworkFiles.shared.image(at: url) {
            Image(nsImage: image)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: Self.fallbackSymbol)
                .font(.system(size: size - 2, weight: .medium))
        }
    }
}

@MainActor
final class ExtensionArtworkFiles {
    static let shared = ExtensionArtworkFiles()

    private var loaded: [URL: NSImage] = [:]
    private var missing: Set<URL> = []

    func image(at url: URL) -> NSImage? {
        let key = url.standardizedFileURL
        if let cached = loaded[key] { return cached }
        guard !missing.contains(key) else { return nil }
        guard let image = NSImage(contentsOf: key), image.size.width > 0, image.size.height > 0 else {
            missing.insert(key)
            return nil
        }
        loaded[key] = image
        return image
    }

    func forget() {
        loaded.removeAll()
        missing.removeAll()
    }
}
