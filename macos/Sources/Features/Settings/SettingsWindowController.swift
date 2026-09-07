import AppKit
import SwiftUI

/// The settings window: a single shared instance reused across opens,
/// shown in place of opening the raw config file in an editor.
@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private var ghostty: Ghostty.App?

    private init() {
        /// No `.fullSizeContentView`, and no transparent titlebar.
        ///
        /// `NavigationSplitView` hosted here installs a real window toolbar
        /// and puts the pane's `navigationTitle` in it, plus the sidebar
        /// toggle and — once a pane pushes a detail — the back button. With
        /// the content view running the full height and the titlebar told to
        /// draw nothing, that band had no background and the scroll had no
        /// floor: in Extensions the `Version` row and the paragraph below it
        /// drew straight through `‹ PHP`, and the same happened on every
        /// other pane, where a section header crossed the pane's own title.
        /// Panes tried to answer it with `.toolbarBackground(.visible, for:
        /// .windowToolbar)`, which cannot win — `titlebarAppearsTransparent`
        /// suppresses that background in AppKit, below anything SwiftUI asks
        /// for. Leaving both flags off gives the toolbar its own background
        /// and clips the content under it, which is what the modifier was
        /// reaching for.
        ///
        /// It costs one ellipsis: AppKit draws the title in the titlebar's
        /// leading region rather than across the detail column, and
        /// "Keyboard Shortcuts" runs about eight points past it. The name is
        /// in the selected sidebar row directly below, and `.expanded` — the
        /// toolbar style that gives the title a row of its own — spends
        /// another 40 points of chrome and strands the sidebar toggle on a
        /// line by itself.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.title = "Settings"

        /// The window opens at its own floor, so it can be enlarged but never
        /// shrunk. Deliberate: the widest pane is the shortcut table, which
        /// wraps into unreadability below this. This is the *only* place the
        /// minimum is declared — the panes used to repeat it as SwiftUI
        /// `.frame(minWidth:minHeight:)`, one matching and one smaller and
        /// therefore dead, which read as three different answers.
        window.contentMinSize = NSSize(width: 960, height: 600)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("GhosttySettings")
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(ghostty: Ghostty.App) {
        if self.ghostty !== ghostty || window?.contentView == nil {
            self.ghostty = ghostty
            window?.contentView = NSHostingView(rootView: SettingsRootView(ghostty: ghostty).themedChrome())
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
