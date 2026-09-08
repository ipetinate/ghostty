import AppKit
import SwiftUI

/// A language's own artwork at a fixed size, so icons of any aspect ratio
/// line up across a list.
///
/// The icon is a file inside the extension that contributed the language,
/// read from `LanguageContribution.iconURL` and already proven to sit inside
/// that extension's directory. There is no table of bundled logos to draw
/// from any more: no language is compiled into this build, so the extension
/// that taught the app about a language is the only thing that knows what it
/// looks like.
///
/// Loading goes through `ExtensionIconView.resolve`, which is the store's
/// loader and its cache. A second loader would read the same files twice and
/// could answer differently about the same icon.
struct LanguageIconView: View {
    let icon: URL?
    var size: CGFloat = 18

    @State private var image: NSImage?

    /// Drawn for a contribution that declares no icon, and for the moment
    /// before one it does declare has been read off disk.
    static let genericSymbol = "chevron.left.forwardslash.chevron.right"

    private var source: ExtensionIconSource? {
        icon.map(ExtensionIconSource.file)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: Self.genericSymbol)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .task(id: source?.key) {
            image = await ExtensionIconView.resolve(source)
        }
    }
}
