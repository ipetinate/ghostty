import SwiftUI

/// The filter panel's outline: a rounded card with a pointer on its top
/// edge, aimed at the button that opened it.
///
/// One path rather than a card with a triangle laid over it. The fill, the
/// border and the pointer then follow the same edge, so no seam is drawn
/// across the top where the two would have met.
///
/// It stays an inline shape. A real `NSPopover` would float over the tree
/// and close on the next click anywhere, and the panel has to survive the
/// click that lands in its own field.
struct FileExplorerFilterPanelShape: Shape {
    /// The same radius the search field above the panel carries.
    static let cornerRadius: CGFloat = 6

    static let pointerWidth: CGFloat = 10

    static let pointerHeight: CGFloat = 5

    /// How far the pointer's tip sits from the trailing edge. Half a chip
    /// wide, when the card and the button share a trailing edge.
    let pointerInset: CGFloat

    /// The card itself: `rect` without the strip the pointer stands in.
    func cardRect(in rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: rect.minY + Self.pointerHeight,
            width: rect.width,
            height: max(0, rect.height - Self.pointerHeight)
        )
    }

    /// The corner radius a card this size can carry.
    func radius(in rect: CGRect) -> CGFloat {
        let card = cardRect(in: rect)
        return min(Self.cornerRadius, min(card.width, card.height) / 2)
    }

    /// Where the pointer's tip lands, in `rect`'s own space.
    ///
    /// Clamped so the pointer's base stays on the straight part of the top
    /// edge: a tip aimed into a rounded corner would cut the corner away.
    /// `NSPopover` moves its own anchor for the same reason.
    func tipX(in rect: CGRect) -> CGFloat {
        let half = Self.pointerWidth / 2
        let lower = rect.minX + radius(in: rect) + half
        let upper = rect.maxX - radius(in: rect) - half
        guard lower <= upper else { return rect.midX }
        return min(max(rect.maxX - pointerInset, lower), upper)
    }

    func path(in rect: CGRect) -> Path {
        let card = cardRect(in: rect)
        let corner = radius(in: rect)
        let tip = tipX(in: rect)
        let half = Self.pointerWidth / 2

        var path = Path()
        path.move(to: CGPoint(x: card.minX + corner, y: card.minY))
        path.addLine(to: CGPoint(x: tip - half, y: card.minY))
        path.addLine(to: CGPoint(x: tip, y: rect.minY))
        path.addLine(to: CGPoint(x: tip + half, y: card.minY))
        path.addLine(to: CGPoint(x: card.maxX - corner, y: card.minY))
        path.addRelativeArc(
            center: CGPoint(x: card.maxX - corner, y: card.minY + corner),
            radius: corner,
            startAngle: .degrees(-90),
            delta: .degrees(90)
        )
        path.addLine(to: CGPoint(x: card.maxX, y: card.maxY - corner))
        path.addRelativeArc(
            center: CGPoint(x: card.maxX - corner, y: card.maxY - corner),
            radius: corner,
            startAngle: .degrees(0),
            delta: .degrees(90)
        )
        path.addLine(to: CGPoint(x: card.minX + corner, y: card.maxY))
        path.addRelativeArc(
            center: CGPoint(x: card.minX + corner, y: card.maxY - corner),
            radius: corner,
            startAngle: .degrees(90),
            delta: .degrees(90)
        )
        path.addLine(to: CGPoint(x: card.minX, y: card.minY + corner))
        path.addRelativeArc(
            center: CGPoint(x: card.minX + corner, y: card.minY + corner),
            radius: corner,
            startAngle: .degrees(180),
            delta: .degrees(90)
        )
        path.closeSubpath()

        return path
    }
}
