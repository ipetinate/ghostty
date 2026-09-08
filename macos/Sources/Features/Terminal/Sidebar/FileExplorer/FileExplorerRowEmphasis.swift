import Foundation

/// How one row in the file explorer is marked.
///
/// A value because the rule it encodes was got wrong by accident: three
/// different facts were drawn as the same thing at three strengths — the row
/// last clicked, the file open in the focused tab, and the terminal's working
/// directory — and two of them could be true of *different* rows at the same
/// time. What that looks like on screen is two highlights, one brighter, and a
/// reader working out which shade means what.
///
/// The rule now spends two marks and no more, both borrowed from the card the
/// rest of the sidebar draws: a neutral fill, and an accent ring. Fill alone
/// is the pointer. Ring alone is the selection. Fill and ring together is the
/// file open in the focused tab, and only one row in the list can be that.
struct FileExplorerRowEmphasis: Equatable {
    /// Whether the row carries the neutral surface fill.
    let isFilled: Bool

    /// Whether the row carries the accent ring.
    ///
    /// Selection survives as a fact because three commands read it — Return
    /// renames it, Delete trashes it, a new file lands beside it — so a tree
    /// without one is a tree where those three have nothing to act on. It stops
    /// being a *fill* so it no longer competes with the open file for the same
    /// visual language.
    let isRinged: Bool

    /// - Parameters:
    ///   - isOpenInEditor: the file this row is, is the one in the focused tab.
    ///   - isSelected: the row was clicked, or a keyboard command moved here.
    ///   - isHovered: the pointer is over it.
    ///   - isNaming: a name field is open somewhere in the tree.
    static func resolve(
        isOpenInEditor: Bool,
        isSelected: Bool,
        isHovered: Bool,
        isNaming: Bool
    ) -> FileExplorerRowEmphasis {
        /// Every other row goes quiet while a name is being given. The field is
        /// the only thing the reader can act on — every key the tree answers
        /// for is refused until the name is settled — and a row still marked
        /// behind it is a second answer to "which one is this about".
        guard !isNaming else {
            return FileExplorerRowEmphasis(isFilled: false, isRinged: false)
        }

        /// Hover fills a row that carries no mark of its own, and adds nothing
        /// to one that does: filling the selected row would draw it exactly as
        /// the open file is drawn, for as long as the pointer rests there.
        return FileExplorerRowEmphasis(
            isFilled: isOpenInEditor || (isHovered && !isSelected),
            isRinged: isOpenInEditor || isSelected
        )
    }
}
