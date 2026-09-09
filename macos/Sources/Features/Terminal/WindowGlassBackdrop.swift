import AppKit
import SwiftUI

/// The single material the whole window sits on.
///
/// Both panes keep painting their own coat of the theme colour over it, so the
/// two halves stay identical and `background-opacity` keeps meaning what it
/// means. What changes is what that coat sits on: a material that paints from
/// the first layout, rather than a window that paints nothing until the Metal
/// surface draws.
///
/// Installed once, behind the content view. The per-pane glass in
/// `TerminalViewContainer` is what made the boundary between sidebar and
/// terminal show, and it never reaches a window with the sidebar on: that
/// lookup finds the container among the split view's arranged subviews, and
/// with the sidebar the terminal lives inside the editor grid instead.
enum WindowGlassBackdrop {
    static func make(config: Ghostty.Config) -> NSView? {
        let variant: BackportGlass
        switch config.backgroundBlur {
        case .macosGlassRegular: variant = .regular
        case .macosGlassClear: variant = .clear
        default: return nil
        }

#if compiler(>=6.2)
        guard #available(macOS 26.0, *) else { return nil }
        let view = NSHostingView(rootView: Surface(glass: variant.official))
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
#else
        _ = variant
        return nil
#endif
    }

    /// Wraps `content` so the material sits behind it, or hands `content` back
    /// untouched when this window is not on glass.
    static func install(behind content: NSView, config: Ghostty.Config) -> NSView {
        guard let backdrop = make(config: config) else { return content }

        let container = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(backdrop)
        container.addSubview(content)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: container.topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            backdrop.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        return container
    }
}

#if compiler(>=6.2)
@available(macOS 26.0, *)
private struct Surface: View {
    let glass: Glass

    var body: some View {
        Color.clear.glassEffect(glass, in: Rectangle())
    }
}
#endif
