@testable import Ghostty
import Testing

/// Three marks in the explorer, and what each one means.
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
    /// moves to another file. Exactly one row is filled, and it is the second.
    @Test func clickingOneFileAndOpeningAnotherLeavesOneFill() {
        let clicked = emphasis(open: false, selected: true)
        let opened = emphasis(open: true, selected: false)

        #expect(clicked.fill == .none, "the clicked row kept a fill")
        #expect(clicked.showsSelectionRing, "the selection stopped being visible at all")
        #expect(opened.fill == .open)
    }

    @Test func theOpenFileIsAlwaysTheFilledRow() {
        #expect(emphasis(open: true).fill == .open)
        #expect(emphasis(open: true, selected: true).fill == .open)
        #expect(emphasis(open: true, hovered: true).fill == .open)
    }

    /// The open file wins over the pointer, or the fill would move as the mouse
    /// crossed the list and "where am I" would answer differently every second.
    @Test func hoverNeverOutranksTheOpenFile() {
        #expect(emphasis(open: true, hovered: true).fill == .open)
        #expect(emphasis(open: false, hovered: true).fill == .hover)
    }

    /// The selected row still answers the pointer. Its fill is the neutral
    /// hover surface and not the open file's tint, so a visit cannot make one
    /// row look like the other.
    @Test func hoveringTheSelectionStillMarksIt() {
        let hovered = emphasis(selected: true, hovered: true)

        #expect(hovered.fill == .hover)
        #expect(hovered.showsSelectionRing)
    }

    /// After a click the two facts are the same row, and one mark is enough.
    @Test func theOpenFileIsNotAlsoRinged() {
        #expect(!emphasis(open: true, selected: true).showsSelectionRing)
        #expect(emphasis(open: false, selected: true).showsSelectionRing)
    }

    /// Nothing about the selection was removed — three commands read it — so a
    /// selected row away from the editor still says so.
    @Test func aSelectionAwayFromTheEditorIsStillMarked() {
        let elsewhere = emphasis(open: false, selected: true, hovered: false)

        #expect(elsewhere.showsSelectionRing)
        #expect(elsewhere.fill == .none)
    }

    /// The naming report: the field is the only thing marked while it is open.
    @Test func namingSilencesEveryOtherRow() {
        let quiet = FileExplorerRowEmphasis(fill: .none, showsSelectionRing: false)

        #expect(emphasis(open: true, naming: true) == quiet)
        #expect(emphasis(selected: true, naming: true) == quiet)
        #expect(emphasis(hovered: true, naming: true) == quiet)
        #expect(emphasis(open: true, selected: true, hovered: true, naming: true) == quiet)
    }

    @Test func anUntouchedRowIsUnmarked() {
        #expect(emphasis() == FileExplorerRowEmphasis(fill: .none, showsSelectionRing: false))
    }
}
