import SwiftUI

/// A contributed `editor` view, in the tab it is drawing.
///
/// The descriptor is resolved from the registry on every draw rather than
/// carried in the tab, so an extension removed while its tab is open says as
/// much instead of drawing a page from a directory that is gone.
struct ExtensionViewPaneView: View {
    /// `ExtensionViewDescriptor.id`.
    let viewID: String

    /// Where this pane's terminal is. See ``EditorTerminalDirectory``.
    let terminalDirectory: String?

    /// The file this view is drawing.
    let file: URL

    /// Rises by one on every ⌘S the reader presses on this tab.
    let saveTicket: Int

    /// What the page says about its unsaved work.
    let onDirty: (Bool) -> Void

    @ObservedObject private var registry: ExtensionViewRegistry = .shared

    private var descriptor: ExtensionViewDescriptor? {
        registry.descriptor(id: viewID)
    }

    var body: some View {
        if let descriptor, descriptor.contribution.surface == .editor {
            ExtensionViewSurface(
                descriptor: descriptor,
                workspace: workspace,
                file: file,
                saveTicket: saveTicket,
                onDirty: onDirty
            )
        } else {
            MediaUnreadableView(message: "This extension is no longer installed.")
        }
    }

    /// The folder the view's filesystem methods are bounded to.
    ///
    /// The file's own repository when there is a file, so a claimed file
    /// opened from outside the terminal's folder is still readable by the
    /// page drawing it. The terminal's folder otherwise, which is all a
    /// transient page has.
    private var workspace: URL? {
        let directory = file.deletingLastPathComponent().path
        if let root = ExtensionViewFileScope.workspaceRoot(forDirectory: directory) { return root }
        return ExtensionViewFileScope.workspaceRoot(forDirectory: terminalDirectory)
    }
}
