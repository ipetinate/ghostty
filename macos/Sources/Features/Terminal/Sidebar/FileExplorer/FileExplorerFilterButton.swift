import Foundation

/// How the button beside the explorer's search field is drawn.
///
/// A value because the button says two things at once and they are not
/// independent. Open or closed decides the symbol, and the tint answers a
/// question only a closed panel leaves open: a reader whose search is
/// quietly missing a folder can see that filters are in force without
/// opening anything. An open panel already shows its own fields, so
/// tinting it there would mark a state the reader is looking at.
struct FileExplorerFilterButton: Equatable {
    /// The filter glyph, worn while the panel is closed.
    static let closedSymbol = "line.3.horizontal.decrease"

    /// The way back, worn while the panel is open. Bare rather than
    /// circled, the same as `magnifyingglass` in the field beside it.
    static let openSymbol = "chevron.down"

    let symbol: String

    /// Whether the symbol is tinted with the accent.
    let isAccented: Bool

    let help: String

    /// - Parameters:
    ///   - isExpanded: the filter panel is on screen.
    ///   - activeFilterCount: how many filters are in force, across every
    ///     row the panel holds.
    static func resolve(isExpanded: Bool, activeFilterCount: Int) -> FileExplorerFilterButton {
        FileExplorerFilterButton(
            symbol: isExpanded ? openSymbol : closedSymbol,
            isAccented: !isExpanded && activeFilterCount > 0,
            help: help(isExpanded: isExpanded, activeFilterCount: activeFilterCount)
        )
    }

    private static func help(isExpanded: Bool, activeFilterCount: Int) -> String {
        if isExpanded { return "Hide search filters" }
        guard activeFilterCount > 0 else { return "Search filters" }
        return activeFilterCount == 1
            ? "Search filters — 1 in force"
            : "Search filters — \(activeFilterCount) in force"
    }
}
