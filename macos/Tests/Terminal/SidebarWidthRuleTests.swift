import Foundation
@testable import Ghostty
import Testing

struct SidebarWidthRuleTests {
    @Test func theSidebarStartsAt480() {
        #expect(SidebarWidthRule.defaultContent == 480)
        #expect(SidebarWidthRule.maximumContent == 600)
    }

    @Test func onlyTheSideBarCostsAColumn() {
        #expect(SidebarWidthRule.inset(for: .top) == 0)
        #expect(SidebarWidthRule.inset(for: .side) == SidebarActivityBarMetrics.totalWidth)
    }

    @Test func thePaneGrowsByTheColumnSoTheContentDoesNot() {
        let inset = SidebarActivityBarMetrics.totalWidth
        #expect(SidebarWidthRule.pane(content: 480, placement: .top) == 480)
        #expect(SidebarWidthRule.pane(content: 480, placement: .side) == 480 + inset)
    }

    @Test func aPaneWidthReadsBackAsTheContentItHolds() {
        let inset = SidebarActivityBarMetrics.totalWidth
        #expect(SidebarWidthRule.content(pane: 480, placement: .top) == 480)
        #expect(SidebarWidthRule.content(pane: 480 + inset, placement: .side) == 480)
    }

    @Test func aWidthDraggedInOnePlacementSurvivesTheOther() {
        let dragged = SidebarWidthRule.content(pane: 530, placement: .top)
        #expect(SidebarWidthRule.pane(content: dragged, placement: .side)
            == 530 + SidebarActivityBarMetrics.totalWidth)
    }

    @Test(arguments: [
        (100.0, 200.0),
        (200.0, 200.0),
        (480.0, 480.0),
        (600.0, 600.0),
        (900.0, 600.0),
    ])
    func aWidthOutsideTheRangeIsPulledBackIn(_ given: Double, _ expected: Double) {
        #expect(SidebarWidthRule.clamp(content: CGFloat(given)) == CGFloat(expected))
    }

    @Test func theLimitsCarryTheColumnToo() {
        let inset = SidebarActivityBarMetrics.totalWidth
        #expect(SidebarWidthRule.minimumPane(.top) == 200)
        #expect(SidebarWidthRule.maximumPane(.top) == 600)
        #expect(SidebarWidthRule.minimumPane(.side) == 200 + inset)
        #expect(SidebarWidthRule.maximumPane(.side) == 600 + inset)
    }

    @Test func anUnsetPlacementReadsAsTop() throws {
        let defaults = try #require(UserDefaults(suiteName: "SidebarWidthRuleTests"))
        defaults.removePersistentDomain(forName: "SidebarWidthRuleTests")
        #expect(SidebarWidthRule.placement(defaults) == .top)

        defaults.set(SidebarTabBarPlacement.side.rawValue, forKey: SidebarTabBarPlacement.defaultsKey)
        #expect(SidebarWidthRule.placement(defaults) == .side)

        defaults.set("nonsense", forKey: SidebarTabBarPlacement.defaultsKey)
        #expect(SidebarWidthRule.placement(defaults) == .top)
        defaults.removePersistentDomain(forName: "SidebarWidthRuleTests")
    }
}
