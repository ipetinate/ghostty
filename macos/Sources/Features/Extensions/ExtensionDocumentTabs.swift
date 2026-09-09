import AppKit

@MainActor
enum ExtensionDocumentTabs {
    static func open(_ entry: ExtensionIndex.Entry) {
        open(ExtensionDocument(entry: entry))
    }

    static func open(installed: InstalledExtension) {
        open(ExtensionDocument(installed: installed))
    }

    static func open(_ document: ExtensionDocument) {
        guard let controller = editorHost() else { return }
        controller.openExtensionInEditor(document)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    static func openInSettings(id: String) {
        SettingsNavigation.shared.target = SettingsNavigation.Target(
            section: .extensions,
            row: SettingsNavigation.extensionRow(id)
        )
        _ = NSApp.sendAction(#selector(AppDelegate.openConfig(_:)), to: nil, from: nil)
    }

    /// The window a page opens into: the one in front, or a new one when
    /// there is none. Shared with `ExtensionViewTabs`, so an extension's
    /// page and an extension's view reach the editor by the same route.
    static func editorHost() -> TerminalController? {
        if let controller = TerminalController.preferredParent { return controller }
        guard let ghostty = (NSApp.delegate as? AppDelegate)?.ghostty else { return nil }
        return TerminalController.newWindow(ghostty)
    }
}
