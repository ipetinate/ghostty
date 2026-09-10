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

    /// Which material the floor is made of. A material has no intensity, so
    /// the blur radius that used to be configurable means nothing here and
    /// this replaces it.
    /// Two, because there are two results. The system's materials are named
    /// for the role they play rather than the look they have, and it is free
    /// to render several of them the same way: under a dark theme the sidebar
    /// material comes out as the window one and the full-screen material as
    /// the HUD. Four names for two surfaces reads as an app whose settings do
    /// nothing.
    enum Material: String, CaseIterable {
        case soft
        case deep

        var label: String {
            switch self {
            case .soft: return "Soft"
            case .deep: return "Deep"
            }
        }

        var official: NSVisualEffectView.Material {
            switch self {
            case .soft: return .underWindowBackground
            case .deep: return .hudWindow
            }
        }
    }

    /// Phantom's own chrome preference, so it lives in `UserDefaults`: an
    /// unknown key in `gui-settings` raises Ghostty's config errors.
    static let materialKey = "WindowBackdropMaterial"

    /// The names this used to store are carried across rather than dropped,
    /// so a choice already made keeps the surface it was making.
    static var material: Material {
        switch UserDefaults.standard.string(forKey: materialKey) ?? "" {
        case Material.soft.rawValue, "underWindow", "sidebar": return .soft
        default: return .deep
        }
    }

    static func make(config: Ghostty.Config) -> NSVisualEffectView? {
        guard isActive(config.backgroundBlur) else { return nil }

        let view = NSVisualEffectView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.blendingMode = .behindWindow
        view.material = material.official
        /// Held active rather than following the window. Left to follow, the
        /// material flattens whenever the window is not the active one, which
        /// is a window that changes colour while the reader is in another app
        /// and changes back when they return.
        view.state = .active
        return view
    }

    /// Wraps `content` so the material sits behind it, or hands `content` back
    /// untouched when this window is not on the material.
    static func install(_ backdrop: NSVisualEffectView?, behind content: NSView) -> NSView {
        guard let backdrop else { return content }

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
