import Foundation
@testable import Ghostty
import Testing

/// The welcome window's placement step: where it sits, what each card writes,
/// and whether the two cards still fit the window they were measured against.
@MainActor
struct WelcomeTabPlacementStepTests {
    private static let scratchSuite = "WelcomeTabPlacementStepTests"

    @Test func theTourRunsHeroBasicsLayoutThemeAgents() {
        #expect(WelcomeView.Step.allCases == [.hero, .basics, .layout, .theme, .agents])
    }

    /// The choice comes before the agents step, which is the one that installs
    /// things: a reader deciding the window's shape should not have to walk
    /// back past a plan they have already ticked.
    @Test func theLayoutStepComesBeforeTheAgents() {
        #expect(WelcomeView.Step.layout.rawValue < WelcomeView.Step.agents.rawValue)
        #expect(WelcomeView.Step.layout.rawValue > WelcomeView.Step.basics.rawValue)
    }

    /// Every step past the hero names itself in the header, and no two share a
    /// name — the header used to pick between two titles with a ternary, which
    /// a third step would have answered wrongly rather than not at all.
    @Test func everyStepPastTheHeroNamesItself() {
        #expect(WelcomeView.Step.hero.title == nil)

        let titles = WelcomeView.Step.allCases.dropFirst().compactMap(\.title)
        #expect(titles.count == WelcomeView.Step.allCases.count - 1)
        #expect(Set(titles).count == titles.count)
    }

    /// Every step but the first has one behind it, so the bottom bar draws a
    /// Back button everywhere except the hero — where there is nothing to go
    /// back to and a disabled button would be the only thing to look at.
    @Test func everyStepPastTheFirstHasOneBehindIt() {
        #expect(WelcomeView.Step.hero.previous == nil)
        #expect(WelcomeView.Step.basics.previous == .hero)
        #expect(WelcomeView.Step.layout.previous == .basics)
        #expect(WelcomeView.Step.theme.previous == .layout)
        #expect(WelcomeView.Step.agents.previous == .theme)
    }

    /// Walking the whole tour backwards reaches the hero and stops, which is
    /// what keeps a reader pressing Back from falling off the end.
    @Test func walkingBackwardsEndsAtTheHero() {
        var step = WelcomeView.Step.agents
        var visited: [WelcomeView.Step] = [step]
        while let previous = step.previous {
            step = previous
            visited.append(step)
        }
        #expect(step == .hero)
        #expect(visited.count == WelcomeView.Step.allCases.count)
    }

    /// What a card writes is what a window reads back. The card sets the
    /// placement's raw value under `SidebarTabBarPlacement.defaultsKey`, and
    /// `SidebarWidthRule.placement` is the read `TerminalController` makes when
    /// the notification arrives.
    @Test func eachCardWritesAPlacementTheWindowsReadBack() throws {
        let defaults = try #require(UserDefaults(suiteName: Self.scratchSuite))
        defer { defaults.removeObject(forKey: SidebarTabBarPlacement.defaultsKey) }

        for placement in SidebarTabBarPlacement.allCases {
            defaults.set(placement.rawValue, forKey: SidebarTabBarPlacement.defaultsKey)
            #expect(SidebarWidthRule.placement(defaults) == placement)
        }
    }

    /// A value from nowhere — a hand-edited plist, a key from a later build —
    /// leaves the step showing the card the app actually draws.
    @Test func anUnreadableStoredValueLeavesTheTopCardChosen() throws {
        let defaults = try #require(UserDefaults(suiteName: Self.scratchSuite))
        defer { defaults.removeObject(forKey: SidebarTabBarPlacement.defaultsKey) }

        defaults.set("beside", forKey: SidebarTabBarPlacement.defaultsKey)
        #expect(SidebarWidthRule.placement(defaults) == .top)

        defaults.removeObject(forKey: SidebarTabBarPlacement.defaultsKey)
        #expect(SidebarWidthRule.placement(defaults) == .top)
    }

    @Test func thereIsOneCardPerPlacement() {
        #expect(SidebarTabBarPlacement.allCases.count == 2)

        let details = SidebarTabBarPlacement.allCases.map(WelcomeTabPlacementStep.detail)
        #expect(Set(details).count == details.count)
        #expect(details.allSatisfy { !$0.isEmpty })
    }

    /// The rule the whole window follows: nothing here prints a key
    /// equivalent, because every one of them is rebindable. See
    /// `WelcomeBasicsStep`.
    @Test func theStepPrintsNoKeyboardShortcut() {
        let text = [WelcomeTabPlacementStep.sentence]
            + SidebarTabBarPlacement.allCases.map(WelcomeTabPlacementStep.detail)

        for line in text {
            #expect(!line.contains("⌘"))
            #expect(!line.contains("⌥"))
            #expect(!line.contains("⌃"))
        }
    }

    /// The step does its own height arithmetic, so the arithmetic is what a
    /// test can hold: the sentence, the gap and the cards have to come to no
    /// more than the window leaves a step.
    @Test func theCardsFitTheWindowTheyWereMeasuredFor() {
        let available = WelcomeWindowController.size.height - WelcomeView.chromeHeight
        let used = WelcomeTabPlacementStep.sentenceHeight
            + WelcomeTabPlacementStep.spacing
            + WelcomeTabPlacementStep.cardHeight

        #expect(WelcomeTabPlacementStep.cardHeight > 0)
        #expect(used <= available)
    }

    /// Three named tabs are what the preview's sidebar fits. The count is the
    /// constraint; terminals leading is the sidebar's own tab order.
    @Test func thePreviewShowsThreePanelsStartingWithTerminals() {
        #expect(WelcomeSidebarPreview.panes.count == 3)
        #expect(WelcomeSidebarPreview.panes.first == .terminals)
        #expect(Set(WelcomeSidebarPreview.panes).count == WelcomeSidebarPreview.panes.count)
        #expect(WelcomeSidebarPreview.panes.allSatisfy { SidebarPane.allCases.contains($0) })
    }

    /// The one thing the two cards are there to show: moving the tabs to the
    /// side widens the pane rather than narrowing the list.
    @Test func theSideCardsPaneIsWiderByTheColumn() {
        let top = SidebarWidthRule.pane(
            content: WelcomeSidebarPreview.contentWidth, placement: .top)
        let side = SidebarWidthRule.pane(
            content: WelcomeSidebarPreview.contentWidth, placement: .side)

        #expect(side - top == SidebarActivityBarMetrics.totalWidth)
    }
}
