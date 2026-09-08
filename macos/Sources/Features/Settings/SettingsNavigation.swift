import Combine
import Foundation

/// A request to open Settings at one place in it.
///
/// The settings window keeps a single hosting view alive across opens, so
/// the starting selection cannot travel as an argument: by the second open
/// the view that would read it already exists. Both halves watch this
/// instead — ``SettingsRootView`` for the section, and the section's own
/// view for the row inside it.
@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()

    /// Where to land. `row` is the id of a row in that section's list, nil
    /// for a section with no list or a caller with nothing more specific to
    /// say than the pane.
    struct Target: Equatable {
        let section: SettingsRootView.SettingsSection
        let row: String?

        /// One request, distinct from the next. Without it a second click
        /// on the same button would publish an equal value and change
        /// nothing, so a reader who had navigated away could not get back.
        let id = UUID()
    }

    /// Set by whoever wants the window somewhere specific, cleared by the
    /// view that lands on it.
    @Published var target: Target?

    private init() {}

    /// The Extensions pane's row for a server definition, or nil when no
    /// installed extension contributed it.
    ///
    /// Every server this app can start now comes from a manifest, so the
    /// question "where is this server configured" is answered by naming the
    /// extension that shipped it — the pane holds one form per extension
    /// and every one of its servers is a section inside that form. A
    /// definition that carries no manifest provenance has no such home and
    /// gets nil, which lands the caller on the pane itself.
    static func extensionRow(for definition: LSPServerDefinition) -> String? {
        guard case .manifest(let provenance) = definition.origin else { return nil }
        return extensionRow(provenance.extensionID)
    }

    /// How ``ExtensionsSettingsView`` spells its row ids. Here so the caller
    /// naming a row and the list drawing it read one definition rather than
    /// two that agree today.
    ///
    /// `nonisolated` because the list's own row type is a plain value that
    /// asks for its id outside any actor.
    nonisolated static func extensionRow(_ extensionID: String) -> String {
        rowPrefix + extensionID
    }

    /// The inverse, for the pane resolving a request back to an extension.
    nonisolated static func extensionID(fromRow row: String) -> String? {
        guard row.hasPrefix(rowPrefix) else { return nil }
        let id = String(row.dropFirst(rowPrefix.count))
        return id.isEmpty ? nil : id
    }

    private static let rowPrefix = "ext:"
}
