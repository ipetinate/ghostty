import Foundation

/// Which views a page may open, and the whole reason it cannot open
/// somebody else's.
///
/// A page names a view the way its author wrote it in their own manifest —
/// `"http"`, not `"ipetinate.bruno/http"`. The descriptor id is built here,
/// from an `extensionID` this value was constructed with, so a page that
/// sends another extension's id gets a lookup for a view of its **own**
/// extension by that name, and there is no spelling of the parameter that
/// reaches across the boundary. A validated view id holds no `/`, so it
/// cannot smuggle one either.
///
/// Only editor-surface views are listed. A sidebar panel is not something a
/// page opens: the reader selects it from the rail.
struct ExtensionViewOpener: Equatable, Sendable {
    let extensionID: String

    /// The view ids this extension declares on the editor surface.
    let editorViews: Set<String>

    static let none = ExtensionViewOpener(extensionID: "", editorViews: [])

    init(extensionID: String, editorViews: Set<String>) {
        self.extensionID = extensionID
        self.editorViews = editorViews
    }

    /// Every editor view the extension that ships `descriptor` declares.
    ///
    /// Read off the registry rather than off the one contribution, because
    /// the sidebar entry and the editor entry are separate entries of the
    /// same manifest and the caller only holds one of them.
    @MainActor
    init(for descriptor: ExtensionViewDescriptor, registry: ExtensionViewRegistry = .shared) {
        self.init(
            extensionID: descriptor.extensionID,
            editorViews: Set(
                registry.views
                    .filter { $0.extensionID == descriptor.extensionID }
                    .filter { $0.contribution.surface == .editor }
                    .map(\.contribution.viewID)))
    }

    /// The `ExtensionViewDescriptor.id` a page's `viewId` names, or nil.
    func target(_ viewID: String) -> String? {
        guard editorViews.contains(viewID) else { return nil }
        return extensionID + "/" + viewID
    }
}
