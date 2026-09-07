import AppKit

/// The box round the symbol a jump landed on.
///
/// ## Why a box and not a selection
///
/// Going to a definition used to select the range the server gave, and for a
/// server that answers with the whole definition that is a screen of solid
/// selection blue — the reader lands on it, cannot see the code through it,
/// and has to click somewhere to get rid of it. Worse, a selection is
/// *state*: the next keystroke replaces a module.
///
/// So the caret goes to the symbol and this draws over it instead. It has to
/// read as a mark and not as a selection, which is why it is a rounded
/// outline with a wash rather than a filled band, and why its colour comes
/// from the theme's palette rather than from the selection colour.
///
/// ## Why a view
///
/// The same reason as `CodeSquiggleView`, and the same shape: overriding
/// `NSTextView.draw(_:)` silently drops the text view to TextKit 1 — held by
/// `TextKitDowngradeTests` — which blanks the gutter. So this is an ordinary
/// view inside the document, which is what scrolls it with the text for free.
///
/// ## What it holds, and why that differs from the squiggle
///
/// A range, which the squiggle deliberately does not: a diagnostic lives in a
/// text attribute so the text storage moves it when the text under it moves.
/// This mark has no such problem to solve, because every edit clears it — the
/// range cannot go stale while it is still on screen. Geometry is still
/// resolved on every draw, so a scroll and a re-wrap need nothing from anyone.
final class CodeRevealHighlightView: NSView {
    /// The text this marks. Weak, and this view is inside it.
    weak var textView: NSTextView?

    /// The colour of both the wash and the outline, from the editor's theme.
    var color: NSColor = .clear

    /// How much of the colour the wash gets. Low enough that the glyphs under
    /// it keep their own colour — this sits in front of the text, so a heavy
    /// wash would be tinting the code the reader came to read.
    private static let fillAlpha: CGFloat = 0.2

    /// How much of it the outline gets. The outline is what the eye finds, so
    /// it carries nearly the full colour.
    private static let strokeAlpha: CGFloat = 0.9

    /// How long the mark takes to go once something clears it, and in how
    /// many steps. Short enough to feel like a consequence of the keystroke
    /// rather than an animation waiting to finish.
    private static let fadeSteps = 10
    private static let fadeStep = Duration.milliseconds(16)

    /// The characters being marked, or nil when nothing is.
    private(set) var range: NSRange?

    /// How much of the colour is left, while the mark fades.
    private var opacity: CGFloat = 1

    /// The fade in progress. Cancelled by a new mark, so a jump made during
    /// the fade of the last one is not drawn half transparent.
    private var fade: Task<Void, Never>?

    /// Same coordinates as the text view it sits in.
    override var isFlipped: Bool { true }

    override var isOpaque: Bool { false }

    /// Paint, not a control: every click belongs to the text underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }

    /// Marks `range`, replacing whatever was marked before.
    func show(_ range: NSRange) {
        fade?.cancel()
        fade = nil
        opacity = 1
        self.range = range
        needsDisplay = true
    }

    /// Takes the mark away, fading it out.
    ///
    /// Called by everything the reader can do — move the caret, type, click,
    /// scroll. Nothing calls it on a timer: a mark that vanished while the
    /// reader was still looking for it would be worse than one that waits.
    func clear() {
        guard range != nil, fade == nil else { return }

        fade = Task { [weak self] in
            for step in 1...Self.fadeSteps {
                try? await Task.sleep(for: Self.fadeStep)
                guard !Task.isCancelled, let self else { return }
                self.opacity = 1 - CGFloat(step) / CGFloat(Self.fadeSteps)
                self.invalidateMark()
            }
            guard !Task.isCancelled, let self else { return }

            /// The rectangles are read *before* the range goes, because they
            /// are read from the range: asking afterwards returns nothing to
            /// repaint and leaves the last frame of the fade on screen.
            let painted = marks(in: bounds)
            self.range = nil
            self.opacity = 1
            self.fade = nil
            for rect in painted { self.setNeedsDisplay(Self.repaint(rect)) }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let fill = color.withAlphaComponent(Self.fillAlpha * opacity)
        let stroke = color.withAlphaComponent(Self.strokeAlpha * opacity)

        for rect in marks(in: dirtyRect) {
            let path = NSBezierPath(
                roundedRect: rect,
                xRadius: Self.cornerRadius(for: rect),
                yRadius: Self.cornerRadius(for: rect)
            )
            path.lineWidth = 1
            fill.setFill()
            path.fill()
            stroke.setStroke()
            path.stroke()
        }
    }

    /// Every box that falls inside `dirtyRect`.
    ///
    /// One per line fragment the range covers, so a mark that wraps is two
    /// boxes rather than one rectangle swallowing the text between them.
    /// Nothing is cached: the geometry comes out of the layout manager, which
    /// is current by definition, which is what makes this survive a scroll and
    /// a re-wrap with no artefacts.
    func marks(in dirtyRect: NSRect) -> [CGRect] {
        guard let range, range.length > 0,
              let textView,
              let layout = textView.textLayoutManager,
              let content = layout.textContentManager,
              let from = content.location(content.documentRange.location, offsetBy: range.location),
              let to = content.location(content.documentRange.location, offsetBy: NSMaxRange(range)),
              let textRange = NSTextRange(location: from, end: to)
        else { return [] }

        let origin = textView.textContainerOrigin
        let interesting = dirtyRect.insetBy(dx: -Self.slack, dy: -Self.slack)

        var found: [CGRect] = []
        layout.enumerateTextSegments(in: textRange, type: .standard) { _, frame, _, _ in
            let rect = Self.box(frame.offsetBy(dx: origin.x, dy: origin.y))
            guard rect.width > 0.5, rect.height > 0, rect.intersects(interesting) else { return true }
            found.append(rect)
            return true
        }
        return found
    }

    /// Repaints the mark where it is now.
    private func invalidateMark() {
        for rect in marks(in: bounds) { setNeedsDisplay(Self.repaint(rect)) }
    }

    /// How far outside a box anything of it can reach: half the outline, and
    /// a point of margin so a repaint never shaves the edge off.
    private static let slack: CGFloat = 2

    private static func repaint(_ rect: CGRect) -> CGRect {
        rect.insetBy(dx: -slack, dy: -slack)
    }

    /// The box for a laid-out segment.
    ///
    /// A hair wider than the glyphs and a hair shorter than the line: wider so
    /// the outline does not sit on the first and last letters, shorter so two
    /// marks on adjacent lines cannot touch.
    private static func box(_ frame: CGRect) -> CGRect {
        frame.insetBy(dx: -1, dy: 0.5)
    }

    /// Rounded in proportion to the type, and never so much that the box
    /// becomes a capsule.
    private static func cornerRadius(for rect: CGRect) -> CGFloat {
        min(4, rect.height / 4)
    }
}
