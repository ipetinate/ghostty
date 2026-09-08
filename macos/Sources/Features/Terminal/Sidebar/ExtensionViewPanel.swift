import SwiftUI

/// A contributed `sidebar` view, in the sidebar panel its button selects.
///
/// The panel is selected the way Files and Git are, and the extension's own
/// page is what fills it. What a row of that page does is the extension's
/// business: `views.open` is how it asks for a tab.
struct ExtensionViewPanel: View {
    let descriptor: ExtensionViewDescriptor

    /// The folder of the terminal the sidebar is following.
    let workspace: URL?

    var body: some View {
        ExtensionViewSurface(descriptor: descriptor, workspace: workspace)
    }
}
