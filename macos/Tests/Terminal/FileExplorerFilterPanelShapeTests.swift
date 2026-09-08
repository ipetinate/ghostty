import SwiftUI
@testable import Ghostty
import Testing

/// The filter panel's card: where its pointer lands, and what it does when
/// the sidebar is too narrow to put it where it was asked for.
struct FileExplorerFilterPanelShapeTests {
    private let inset: CGFloat = 12

    private func shape() -> FileExplorerFilterPanelShape {
        FileExplorerFilterPanelShape(pointerInset: inset)
    }

    private func rect(width: CGFloat, height: CGFloat = 90) -> CGRect {
        CGRect(x: 0, y: 0, width: width, height: height)
    }

    // MARK: The card

    /// The pointer stands above the card, so the card is shorter than the
    /// space the panel was given by exactly that much.
    @Test func itLeavesTheTopStripToThePointer() {
        let box = rect(width: 220)
        let card = shape().cardRect(in: box)

        #expect(card.minY == box.minY + FileExplorerFilterPanelShape.pointerHeight)
        #expect(card.height == box.height - FileExplorerFilterPanelShape.pointerHeight)
        #expect(card.width == box.width)
    }

    @Test func itKeepsTheCornerRadiusTheSearchFieldCarries() {
        #expect(shape().radius(in: rect(width: 220)) == FileExplorerFilterPanelShape.cornerRadius)
    }

    /// A radius wider than the card would draw corners that cross each
    /// other, which is what a sidebar dragged to nothing would ask for.
    @Test func itShrinksTheCornerRadiusToFitATinyCard() {
        #expect(shape().radius(in: rect(width: 6, height: 11)) == 3)
    }

    // MARK: The pointer

    @Test func itAimsThePointerAtTheButtonItCameFrom() {
        let box = rect(width: 220)

        #expect(shape().tipX(in: box) == box.maxX - inset)
    }

    @Test func itAimsFromTheTrailingEdgeWhateverTheWidth() {
        #expect(shape().tipX(in: rect(width: 160)) == 160 - inset)
        #expect(shape().tipX(in: rect(width: 400)) == 400 - inset)
    }

    /// The base has to stay on the straight part of the top edge. A tip
    /// aimed into a rounded corner would cut the corner away.
    @Test func itPullsThePointerOffTheCorner() {
        let narrow = FileExplorerFilterPanelShape(pointerInset: 2)
        let box = rect(width: 220)
        let clearance = FileExplorerFilterPanelShape.cornerRadius
            + FileExplorerFilterPanelShape.pointerWidth / 2

        #expect(narrow.tipX(in: box) == box.maxX - clearance)
    }

    @Test func itPullsThePointerOffTheLeadingCornerToo() {
        let wide = FileExplorerFilterPanelShape(pointerInset: 500)
        let box = rect(width: 220)
        let clearance = FileExplorerFilterPanelShape.cornerRadius
            + FileExplorerFilterPanelShape.pointerWidth / 2

        #expect(wide.tipX(in: box) == box.minX + clearance)
    }

    /// Neither corner can be cleared, so the pointer goes in the middle
    /// rather than to whichever limit was compared first.
    @Test func itCentresThePointerWhenNoCornerCanBeCleared() {
        let box = rect(width: 14)

        #expect(shape().tipX(in: box) == box.midX)
    }

    // MARK: The path

    @Test func itDrawsThePointerAboveTheCard() {
        let box = rect(width: 220)
        let bounds = shape().path(in: box).boundingRect

        #expect(bounds.minY == box.minY)
        #expect(bounds.maxY == box.maxY)
    }

    /// One closed subpath, so the fill, the border and the pointer follow
    /// the same edge and no seam is drawn across the top.
    @Test func itDrawsOneClosedSubpath() {
        var closes = 0
        var moves = 0

        shape().path(in: rect(width: 220)).forEach { element in
            switch element {
            case .move: moves += 1
            case .closeSubpath: closes += 1
            default: break
            }
        }

        #expect(moves == 1)
        #expect(closes == 1)
    }
}
