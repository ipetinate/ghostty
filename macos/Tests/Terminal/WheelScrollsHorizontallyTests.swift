import AppKit
@testable import Ghostty
import Testing

/// The wheel that scrolled a tab strip out of its own band.
///
/// Headless throughout: a scroll view laid out by hand answers
/// `constrainBoundsRect` the same way the one on screen did, so none of this
/// needs a window.
@MainActor
struct WheelScrollsHorizontallyTests {
    /// Flipped, because the clip view takes its orientation from the document
    /// view and SwiftUI's is flipped. Unflipped, a row shorter than its
    /// viewport parks at the other end and the numbers below stop matching
    /// what the tab strip does.
    private final class FlippedRow: NSView {
        override var isFlipped: Bool { true }
    }

    /// A tab strip 500 points wide, in a viewport `viewport` points tall.
    ///
    /// The interesting case is a viewport *taller* than the row: that is the
    /// state a legacy scroll indicator's reserved strip left behind, and the
    /// state in which AppKit has somewhere vertical to park the row.
    private func row(viewport: CGFloat, rowHeight: CGFloat = 30) -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: viewport))
        scrollView.documentView = FlippedRow(
            frame: NSRect(x: 0, y: 0, width: 500, height: rowHeight))
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.layoutSubtreeIfNeeded()
        return scrollView
    }

    private let overflow: CGFloat = 400

    @Test func aStepMovesTheRowSidewaysAndNowhereElse() {
        let clipView = row(viewport: 30).contentView

        let destination = WheelScrollsHorizontally.destination(
            in: clipView, step: -48, overflow: overflow)

        #expect(destination == NSPoint(x: 48, y: 0))
    }

    /// The regression. A 30-point row in a 47-point viewport had been parked
    /// 17 points down — the width of the strip a legacy indicator reserves —
    /// and the strip on screen sat clipped at the top of its band with an
    /// empty band under it. Carrying that offset over is what made it
    /// permanent, so the destination has to come back on the axis.
    @Test func aRowParkedOffItsBandComesBackToIt() {
        let clipView = row(viewport: 47).contentView
        clipView.scroll(to: NSPoint(x: 0, y: 17))
        #expect(clipView.bounds.origin.y == 17, "the parked state did not set up")

        let destination = WheelScrollsHorizontally.destination(
            in: clipView, step: -48, overflow: overflow)

        #expect(destination.y == 0)
        #expect(destination.x == 48)
    }

    /// And committing it heals the row rather than freezing it, which is the
    /// whole reason the point goes through `constrainBoundsRect`.
    @Test func committingTheDestinationLeavesTheRowInItsBand() {
        let scrollView = row(viewport: 47)
        let clipView = scrollView.contentView
        clipView.scroll(to: NSPoint(x: 0, y: 17))

        clipView.scroll(
            to: WheelScrollsHorizontally.destination(
                in: clipView, step: -48, overflow: overflow))

        #expect(clipView.bounds.origin == NSPoint(x: 48, y: 0))
    }

    @Test func theRowStopsAtEitherEnd() {
        let clipView = row(viewport: 30).contentView

        #expect(
            WheelScrollsHorizontally.destination(in: clipView, step: 48, overflow: overflow)
                == NSPoint(x: 0, y: 0),
            "scrolled back past the first tab")

        clipView.scroll(to: NSPoint(x: overflow, y: 0))
        #expect(
            WheelScrollsHorizontally.destination(in: clipView, step: -48, overflow: overflow)
                == NSPoint(x: overflow, y: 0),
            "scrolled on past the last tab")
    }
}
