import AppKit
import SwiftUI

// MARK: - The scrollbar that used to run through the tabs

/// A scroller that occupies its place and draws nothing.
///
/// The tab strip drew a horizontal bar through the middle of the row, and a
/// tab strip is the one place a scroller has nothing to add: a strip with more
/// tabs than fit already says so by clipping one at its edge, which is the
/// affordance every editor with a scrolling tab strip relies on.
///
/// **A scroller that draws nothing, rather than `hasHorizontalScroller = false`.**
/// Turning the scroller off does not only remove the indicator: an
/// `NSScrollView` resolves `horizontalScrollElasticity` of `.automatic`
/// against whether that axis has a scroller, so switching it off puts the
/// strip's own scrolling at risk — and the strip has to keep scrolling by
/// trackpad and by shift-wheel, which is how a tab past the right edge is
/// reached at all.
///
/// **And why `OverlayScrollers()` is replaced here rather than deleted.** That
/// call is what keeps a *legacy* scroller off the row: with "Show scroll bars:
/// Always" in System Settings, AppKit gives every scroll view a legacy
/// scroller, which is permanent and claims a column of layout for itself.
/// Deleting the call brings that back — a wider bar than the one being
/// removed, drawn clipped over the tab labels.
///
/// `.scrollIndicators(.hidden)` is not the answer either, for the reason
/// `OverlayScrollers` already records: the modifier does not reach the
/// scroller SwiftUI's own scroll view draws.
final class InvisibleScroller: NSScroller {
    override static func scrollerWidth(
        for controlSize: NSControl.ControlSize,
        scrollerStyle: NSScroller.Style
    ) -> CGFloat {
        0
    }

    /// Required of any `NSScroller` subclass used as an overlay scroller,
    /// which is the style this installs.
    override static var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnob() {}

    override func drawKnobSlot(in slotRect: NSRect, highlight: Bool) {}
}

/// Puts an ``InvisibleScroller`` on the enclosing scroll view, in place of the
/// thin one `OverlayScrollers` installs.
///
/// Placed inside the scroll view's content with no size of its own, so it can
/// find its way up to the scroll view and otherwise does nothing — the same
/// shape, and for the same reason, as `OverlayScrollers`.
struct InvisibleScrollers: View {
    var body: some View {
        Representable()
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    private struct Representable: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView { Finder() }

        func updateNSView(_ nsView: NSView, context: Context) {
            (nsView as? Finder)?.apply()
        }
    }

    private final class Finder: NSView {
        /// Applied on arrival in a window, which is the first moment there is
        /// a scroll view above this to find.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        /// Idempotent, because SwiftUI calls `updateNSView` on every pass and
        /// replacing a scroller mid-fade throws away the one being drawn.
        func apply() {
            guard let scrollView = enclosingScrollView else { return }
            guard !(scrollView.horizontalScroller is InvisibleScroller) else { return }

            /// Overlay as well as invisible. The style is what stops AppKit
            /// from parking a scroller in the layout forever for a reader
            /// whose System Settings say to always show scroll bars.
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.horizontalScroller = InvisibleScroller()
            scrollView.verticalScroller = InvisibleScroller()
        }
    }
}
