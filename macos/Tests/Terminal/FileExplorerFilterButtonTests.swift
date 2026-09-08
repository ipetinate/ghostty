import Foundation
@testable import Ghostty
import Testing

/// The button beside the explorer's search field: which symbol it wears,
/// when it carries the accent, and what it says on hover.
struct FileExplorerFilterButtonTests {
    private func resolve(
        isExpanded: Bool,
        activeFilterCount: Int = 0
    ) -> FileExplorerFilterButton {
        FileExplorerFilterButton.resolve(
            isExpanded: isExpanded,
            activeFilterCount: activeFilterCount
        )
    }

    // MARK: Symbol

    @Test func itWearsTheFilterGlyphWhileThePanelIsClosed() {
        #expect(resolve(isExpanded: false).symbol == "line.3.horizontal.decrease")
        #expect(resolve(isExpanded: false, activeFilterCount: 3).symbol
            == "line.3.horizontal.decrease")
    }

    @Test func itWearsTheChevronWhileThePanelIsOpen() {
        #expect(resolve(isExpanded: true).symbol == "chevron.up")
        #expect(resolve(isExpanded: true, activeFilterCount: 3).symbol == "chevron.up")
    }

    // MARK: Accent

    /// The tint is the only report a closed panel makes, so it has to
    /// appear the moment a filter is in force.
    @Test func itCarriesTheAccentWhileAClosedPanelIsFiltering() {
        #expect(resolve(isExpanded: false, activeFilterCount: 1).isAccented)
        #expect(resolve(isExpanded: false, activeFilterCount: 9).isAccented)
    }

    @Test func itDropsTheAccentWhenNoFilterIsInForce() {
        #expect(!resolve(isExpanded: false, activeFilterCount: 0).isAccented)
    }

    /// An open panel shows its own fields, so tinting it would mark a state
    /// the reader is already looking at.
    @Test func itDropsTheAccentWhileThePanelIsOpen() {
        #expect(!resolve(isExpanded: true, activeFilterCount: 4).isAccented)
    }

    // MARK: Help

    @Test func itSaysHowManyFiltersAreInForceWhileClosed() {
        #expect(resolve(isExpanded: false, activeFilterCount: 0).help == "Search filters")
        #expect(resolve(isExpanded: false, activeFilterCount: 1).help
            == "Search filters — 1 in force")
        #expect(resolve(isExpanded: false, activeFilterCount: 2).help
            == "Search filters — 2 in force")
    }

    @Test func itOffersTheWayBackWhileOpen() {
        #expect(resolve(isExpanded: true).help == "Hide search filters")
        #expect(resolve(isExpanded: true, activeFilterCount: 2).help == "Hide search filters")
    }
}
