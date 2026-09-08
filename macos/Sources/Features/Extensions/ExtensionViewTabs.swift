import AppKit

/// Opens a file drawn by one of an extension's editor views.
///
/// The identity of the tab is the **file**, so this is the ordinary open
/// with a choice of who draws it: de-duplication, closing, ⌘W and session
/// restore are the app's existing behaviour for a file, and the label is the
/// file's own name.
@MainActor
enum ExtensionViewTabs {
    static func open(_ url: URL, with viewID: String) -> Bool {
        guard let controller = ExtensionDocumentTabs.editorHost() else { return false }
        guard controller.openFileWithView(url, viewID: viewID) else { return false }
        controller.window?.makeKeyAndOrderFront(nil)
        return true
    }
}
