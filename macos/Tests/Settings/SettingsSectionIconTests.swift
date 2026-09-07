import AppKit
@testable import Ghostty
import Testing

/// The marks the settings window's own section list wears.
///
/// Every name here is asserted rather than trusted: SwiftUI drops a `List`
/// row whose `Image(systemName:)` does not resolve, and it does it without a
/// log, so a typo removes a whole settings pane from the window and nothing
/// says why.
struct SettingsSectionIconTests {
    typealias Section = SettingsRootView.SettingsSection

    /// Extensions is one thing with one mark. The settings row said
    /// `puzzlepiece` while the sidebar tab, the store's All tab and its cards
    /// had all moved to the grid.
    @Test func extensionsWearsTheSameMarkEverywhere() {
        #expect(Section.extensions.icon == "square.grid.2x2")
        #expect(Section.extensions.icon == SidebarPane.extensions.symbol)
        #expect(Section.extensions.icon == ExtensionCatalogFilter.Kind.all.systemImage)
    }

    /// Worktrees is the one section with no SF Symbol, because its mark is
    /// this app's own drawing. Nil is load-bearing: it is what sends the row
    /// to `WorktreeIcon`, so no other section may answer it by accident.
    @Test func onlyWorktreesShipsItsOwnArtwork() {
        let withoutSymbol = Section.allCases.filter { $0.icon == nil }
        #expect(withoutSymbol == [.worktrees])
    }

    @Test func everySymbolResolves() {
        for section in Section.allCases {
            guard let symbol = section.icon else { continue }
            #expect(
                NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil,
                "\(section.rawValue) names \(symbol), which does not resolve")
        }
    }
}
