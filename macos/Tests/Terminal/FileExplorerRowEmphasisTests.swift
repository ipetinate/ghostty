@testable import Ghostty
import Testing

/// Two marks in the explorer, and what each one means.
///
/// Three facts used to be drawn as the same thing at three strengths — clicked,
/// open, and the terminal's directory — and two of them could be true of
/// different rows at once. The report was the plainest possible statement of
/// that: click one file, switch tabs, and two rows are lit. The second report
/// was the same complaint about naming: start a new file inside a folder and a
/// third row lights up beside the field.
struct FileExplorerRowEmphasisTests {
    private func emphasis(
        open: Bool = false,
        selected: Bool = false,
        hovered: Bool = false,
        naming: Bool = false
    ) -> FileExplorerRowEmphasis {
        .resolve(
            isOpenInEditor: open,
            isSelected: selected,
            isHovered: hovered,
            isNaming: naming
        )
    }

    /// The reported scenario, as the test: a row is clicked, then the editor
    /// moves to another file. The two rows are told apart by the fill, and
    /// only one of them has it.
    @Test func clickingOneFileAndOpeningAnotherFillsOnlyTheOpenOne() {
        let clicked = emphasis(open: false, selected: true)
        let opened = emphasis(open: true, selected: false)

        #expect(!clicked.isFilled, "the clicked row kept a fill")
        #expect(clicked.isRinged, "the selection stopped being visible at all")
        #expect(opened.isFilled)
    }

    @Test func theOpenFileIsAlwaysFilled() {
        #expect(emphasis(open: true).isFilled)
        #expect(emphasis(open: true, selected: true).isFilled)
        #expect(emphasis(open: true, hovered: true).isFilled)
    }

    /// Fill and ring together is one row, and it is the open file. A selection
    /// under the pointer must not borrow that pair for the length of a visit.
    @Test func hoverNeverDrawsARowAsTheOpenFile() {
        let hoveredSelection = emphasis(selected: true, hovered: true)

        #expect(hoveredSelection.isRinged)
        #expect(!hoveredSelection.isFilled)
        #expect(emphasis(hovered: true).isFilled, "an unmarked row still answers the pointer")
    }

    /// Nothing about the selection was removed — three commands read it — so a
    /// selected row away from the editor still says so.
    @Test func aSelectionAwayFromTheEditorIsStillMarked() {
        let elsewhere = emphasis(open: false, selected: true, hovered: false)

        #expect(elsewhere.isRinged)
        #expect(!elsewhere.isFilled)
    }

    /// The naming report: the field is the only thing marked while it is open.
    @Test func namingSilencesEveryOtherRow() {
        #expect(emphasis(open: true, naming: true) == FileExplorerRowEmphasis(
            isFilled: false, isRinged: false))
        #expect(emphasis(selected: true, naming: true) == FileExplorerRowEmphasis(
            isFilled: false, isRinged: false))
        #expect(emphasis(open: true, selected: true, hovered: true, naming: true)
            == FileExplorerRowEmphasis(isFilled: false, isRinged: false))
    }

    @Test func anUntouchedRowIsUnmarked() {
        #expect(emphasis() == FileExplorerRowEmphasis(isFilled: false, isRinged: false))
    }
}
