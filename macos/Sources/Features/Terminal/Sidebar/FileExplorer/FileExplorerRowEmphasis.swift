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
/// Three marks now, and each answers a different question. A neutral fill
/// follows the pointer. An accent tint is the file open in the focused tab,
/// and only one row can be that. An accent ring is the selection — the row
/// Return renames, Delete trashes, and a new file lands beside. Two of them
/// can land on one row, and none of them repeats another's meaning.
struct FileExplorerRowEmphasis: Equatable {
    /// What the row is painted with.
    enum Fill: Equatable {
        case none

        /// The pointer's row, drawn on the sidebar's neutral card surface.
        case hover

        /// The open file's row: a tint of the accent, quiet enough that a
        /// selection ring beside it still reads as the louder mark.
        case open
    }

    let fill: Fill

    /// Whether the row is outlined as the selection.
    ///
    /// Selection survives as a fact because three commands read it, so a tree
    /// without one is a tree where those three have nothing to act on. It is
    /// drawn as a ring rather than as a block of the accent, which is what
    /// made it compete with the open file for the same visual language.
    let showsSelectionRing: Bool

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
            return FileExplorerRowEmphasis(fill: .none, showsSelectionRing: false)
        }

        let fill: Fill = if isOpenInEditor {
            .open
        } else if isHovered {
            .hover
        } else {
            .none
        }

        /// No ring on the row that is already tinted. After a click the two
        /// facts coincide — that is the common case — and drawing both would
        /// put two marks on one row for one thing.
        return FileExplorerRowEmphasis(
            fill: fill,
            showsSelectionRing: isSelected && !isOpenInEditor
        )
    }
}
