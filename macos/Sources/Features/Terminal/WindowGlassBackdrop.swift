import AppKit

/// The single material the whole window sits on.
///
/// Both panes keep painting their own coat of the theme colour over it, so the
/// two halves stay identical and `background-opacity` keeps meaning what it
/// means. What changes is what that coat sits on: a view that paints from the
/// first layout, rather than a window that paints nothing until the Metal
/// surface draws. A region nobody has painted is what shows the desktop
/// through a non-opaque window, and a floor removes that region.
///
/// `.behindWindow` is the part that matters. It is what samples the desktop
/// behind the window, which is the job the private CGS blur was doing. SwiftUI's
/// `.glassEffect` cannot do it: that material samples what is behind it inside
/// the app's own drawing, so over a transparent window it has nothing to work
/// with and the desktop comes through nearly raw.
enum WindowGlassBackdrop {
    /// Whether this window draws on the material rather than on a blurred
    /// window. Every window that asked for blur does.
    static func isActive(_ blur: Ghostty.Config.BackgroundBlur) -> Bool {
        blur.isEnabled
    }

    static func make(config: Ghostty.Config) -> NSView? {
        guard isActive(config.backgroundBlur) else { return nil }

        let view = NSVisualEffectView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .followsWindowActiveState
        return view
    }

    /// Wraps `content` so the material sits behind it, or hands `content` back
    /// untouched when this window is not on the material.
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
