import Foundation
@testable import Ghostty
import Testing

/// The welcome window's theme step: which four themes it offers, what each
/// card says about itself, and the order in which the facts are read.
@MainActor
struct WelcomeThemeStepTests {
    private static func entry(_ id: String) -> ExtensionIndex.Entry {
        ExtensionIndex.Entry(
            id: id,
            name: id,
            version: "1.0.0",
            publisher: "Isac Petinate",
            summary: "",
            homepage: nil,
            minimumPhantomVersion: nil,
            contributes: ["themes"],
            languages: [],
            downloadURL: URL(string: "https://example.com/\(id).zip")!,
            sha256: String(repeating: "a", count: 64),
            bytes: 1,
            card: nil)
    }

    private static func index(_ ids: [String]) -> ExtensionIndex {
        ExtensionIndex(generatedAt: nil, repository: nil, extensions: ids.map(entry))
    }

    /// The catalogue with every card in it, which is what the registry has
    /// carried since Alucard was published.
    private static var fullIndex: ExtensionIndex {
        index(WelcomeThemeStep.choices.map(\.id))
    }

    private static func choice(_ id: String) -> WelcomeThemeStep.Choice {
        WelcomeThemeStep.choices.first { $0.id == id }!
    }

    private static var dracula: WelcomeThemeStep.Choice { choice("phantom.dracula") }
    private static var alucard: WelcomeThemeStep.Choice { choice("phantom.alucard") }
    private static var nord: WelcomeThemeStep.Choice { choice("phantom.theme-nord") }
    private static var nordLight: WelcomeThemeStep.Choice { choice("phantom.theme-nord-light") }

    // MARK: Where the step sits

    /// Between the placement step and the agents: the second of the two
    /// questions about what this window looks like, and still ahead of the one
    /// step that installs things on the machine and has a plan to tick.
    ///
    /// The title names both of the questions the step asks, because the icon
    /// packs sit on this screen rather than on a sixth one.
    @Test func theThemeStepSitsBetweenThePlacementAndTheAgents() {
        #expect(WelcomeView.Step.theme.rawValue > WelcomeView.Step.layout.rawValue)
        #expect(WelcomeView.Step.theme.rawValue < WelcomeView.Step.agents.rawValue)
        #expect(WelcomeView.Step.theme.title == "Your theme and icons")
    }

    // MARK: The four cards

    @Test func thereAreTwoDarkCardsAndTwoLightOnes() {
        let dark = WelcomeThemeStep.choices.filter { $0.appearance == .dark }
        let light = WelcomeThemeStep.choices.filter { $0.appearance == .light }

        #expect(WelcomeThemeStep.choices.count == 4)
        #expect(dark.count == 2)
        #expect(light.count == 2)
    }

    /// The mark starts on Dracula, and starting there is all it does: no state
    /// here says a theme has been installed or applied.
    @Test func draculaByPhantomIsTheCardTheGridOpensWith() {
        #expect(WelcomeThemeStep.preselected == "phantom.dracula")
        #expect(Self.dracula.name == "Dracula by Phantom")
        #expect(Self.dracula.appearance == .dark)

        let state = WelcomeThemeStep.state(
            of: Self.dracula, from: .init(index: Self.fullIndex))
        #expect(state == .chosen(isInstalled: false))
    }

    /// Every card names an extension the installer would accept, so a card can
    /// never be one the app is unable to fetch by construction.
    @Test func everyCardNamesADistinctExtensionTheAppCouldInstall() {
        let ids = WelcomeThemeStep.choices.map(\.id)

        #expect(Set(ids).count == ids.count)
        for id in ids {
            #expect(LanguageManifest.validID(id) == id)
        }
    }

    @Test func everyCardHasItsOwnNameAndItsOwnLine() {
        let names = WelcomeThemeStep.choices.map(\.name)
        let details = WelcomeThemeStep.choices.map(\.detail)

        #expect(Set(names).count == names.count)
        #expect(Set(details).count == details.count)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(details.allSatisfy { !$0.isEmpty })
    }

    @Test func theTwoGroupsAreTheTwoWordsTheSettingsGridUses() {
        #expect(WelcomeThemeStep.title(.dark) == "Dark")
        #expect(WelcomeThemeStep.title(.light) == "Light")
    }

    // MARK: A theme the registry does not list

    /// A card whose id the catalogue does not carry. The card is still drawn,
    /// says why it cannot be had, and refuses the press — the one thing it
    /// must not do is look pressed and do nothing.
    ///
    /// This was Alucard's real situation while the step was written and the
    /// registry had not published it yet. The catalogue carries it now, so the
    /// case is held by the fixture rather than by the world.
    @Test func aThemeTheIndexDoesNotListSaysSoAndCannotBePressed() {
        let facts = WelcomeThemeStep.Facts(index: Self.index(["phantom.dracula"]))
        let state = WelcomeThemeStep.state(of: Self.alucard, from: facts)

        #expect(state == .unlisted)
        #expect(!WelcomeThemeStep.isPressable(state))
        #expect(WelcomeThemeStep.line(state)
            == "Not in the registry yet, so this one cannot be installed.")
    }

    /// Being unlisted is a fact about one card and not about the step: the
    /// other three are still offered, and the tour still goes on.
    ///
    /// The catalogue therefore has to hold those three. Built with one entry
    /// instead, every other card is unlisted too, and the assertions below
    /// read the state of a second missing entry rather than of a listed one —
    /// which is what this test did while claiming the opposite.
    @Test func anUnlistedCardLeavesTheOtherThreeAlone() {
        let listed = WelcomeThemeStep.choices.map(\.id).filter { $0 != Self.alucard.id }
        let facts = WelcomeThemeStep.Facts(index: Self.index(listed))

        #expect(WelcomeThemeStep.state(of: Self.alucard, from: facts) == .unlisted)
        #expect(WelcomeThemeStep.state(of: Self.nord, from: facts) == .offered)
        #expect(WelcomeThemeStep.state(of: Self.nordLight, from: facts) == .offered)
        #expect(WelcomeThemeStep.state(of: Self.dracula, from: facts)
            == .chosen(isInstalled: false))
    }

    /// A catalogue that has not arrived is not a catalogue that failed. Both
    /// refuse the press; only one of them is drawn as a failure, and only one
    /// of them says what went wrong.
    @Test func anIndexStillComingIsNotAnIndexThatFailed() {
        let waiting = WelcomeThemeStep.state(of: Self.nord, from: .init())
        #expect(waiting == .searching)
        #expect(!WelcomeThemeStep.isFailure(waiting))
        #expect(!WelcomeThemeStep.isPressable(waiting))

        let refused = WelcomeThemeStep.state(
            of: Self.nord,
            from: .init(indexError: "Could not reach the registry: offline."))
        #expect(refused == .unreachable("Could not reach the registry: offline."))
        #expect(WelcomeThemeStep.isFailure(refused))
        #expect(WelcomeThemeStep.line(refused) == "Could not reach the registry: offline.")
    }

    // MARK: The order the facts are read in

    @Test func aRunningInstallAnswersBeforeEverythingElse() {
        let facts = WelcomeThemeStep.Facts(
            index: Self.fullIndex,
            isInstalled: true,
            activity: .downloading(fraction: 0.4),
            installError: "an older failure",
            appliedID: "phantom.dracula")

        #expect(WelcomeThemeStep.state(of: Self.dracula, from: facts)
            == .working(.downloading(fraction: 0.4)))
    }

    /// A theme in force that has just failed to reinstall says so. Reading
    /// `inUse` first would leave the reader looking at a card that reports
    /// success for the press that failed.
    @Test func aFailureAnswersBeforeTheThemeInForce() {
        let facts = WelcomeThemeStep.Facts(
            index: Self.fullIndex,
            isInstalled: true,
            installError: "The download does not match the registry's checksum.",
            appliedID: "phantom.dracula")

        let state = WelcomeThemeStep.state(of: Self.dracula, from: facts)
        #expect(state == .failed("The download does not match the registry's checksum."))
        #expect(WelcomeThemeStep.isPressable(state))
    }

    /// A failure the *install* reported and one *applying* reported both land
    /// on the card, because a reader has one card to look at either way.
    @Test func applyingCanFailOnItsOwn() {
        let facts = WelcomeThemeStep.Facts(
            index: Self.fullIndex,
            isInstalled: true,
            applyError: WelcomeThemeSelection.unreadable(Self.nord))

        #expect(WelcomeThemeStep.state(of: Self.nord, from: facts)
            == .failed("Nord installed, but its colours could not be read."))
    }

    /// What is on disk is read before the catalogue is, so a reader with no
    /// network can still put on a theme they already have.
    @Test func aThemeAlreadyOnDiskCanBeAppliedWithNoCatalogue() {
        let facts = WelcomeThemeStep.Facts(
            indexError: "Could not reach the registry: offline.",
            isInstalled: true,
            chosen: "phantom.theme-nord")

        let state = WelcomeThemeStep.state(of: Self.nord, from: facts)
        #expect(state == .chosen(isInstalled: true))
        #expect(WelcomeThemeStep.isPressable(state))
    }

    @Test func aCardPressedBeforeAnotherOneSaysItIsInstalledAndNotInUse() {
        let facts = WelcomeThemeStep.Facts(
            index: Self.fullIndex,
            isInstalled: true,
            appliedID: "phantom.theme-nord-light",
            chosen: "phantom.theme-nord-light")

        #expect(WelcomeThemeStep.state(of: Self.nord, from: facts) == .installed)
        #expect(WelcomeThemeStep.line(.installed) == "Installed, and not the theme in use.")
    }

    // MARK: What the copy promises

    /// The chosen card promises a download only when there is one to do, so
    /// the sentence never announces work that has already happened.
    @Test func theChosenCardPromisesADownloadOnlyWhenThereIsOneToDo() {
        let fresh = WelcomeThemeStep.line(.chosen(isInstalled: false))
        let here = WelcomeThemeStep.line(.chosen(isInstalled: true))

        #expect(fresh.contains("downloaded"))
        #expect(!here.contains("downloaded"))
        #expect(here.contains("applied"))
    }

    /// The whole of requirement three, as copy: only the state that means the
    /// theme is on disk and in force is allowed to say it is in use.
    @Test func onlyTheThemeInForceSaysItIsInUse() {
        let notInUse: [WelcomeThemeState] = [
            .searching, .unreachable("no"), .unlisted, .offered,
            .chosen(isInstalled: false), .chosen(isInstalled: true),
            .working(.installing), .installed, .failed("no"),
        ]

        for state in notInUse {
            #expect(!WelcomeThemeStep.line(state).contains("In use"))
        }
        #expect(WelcomeThemeStep.line(.inUse) == "In use, in every window.")
    }

    /// Every state says something a reader can act on, except the one that has
    /// nothing to report: a card nobody has touched shows its own line and no
    /// second one.
    @Test func everyStateButTheOfferedOneSaysSomething() {
        let speaking: [WelcomeThemeState] = [
            .searching, .unreachable("why"), .unlisted,
            .chosen(isInstalled: false), .chosen(isInstalled: true),
            .working(.verifying), .installed, .inUse, .failed("why"),
        ]

        for state in speaking {
            #expect(!WelcomeThemeStep.line(state).isEmpty)
        }
        #expect(WelcomeThemeStep.line(.offered).isEmpty)
    }

    @Test func everyStepOfAnInstallHasItsOwnWord() {
        let activities: [ExtensionActivity] = [
            .downloading(fraction: nil), .verifying, .installing, .removing,
        ]
        let words = activities.map(WelcomeThemeStep.progress)

        #expect(Set(words).count == words.count)
        #expect(words.allSatisfy { $0.hasSuffix("…") })
    }

    /// A failure is never a dead end: the card names the repair, and the
    /// repair is the same press again.
    @Test func aFailureNamesItsRepair() {
        #expect(WelcomeThemeStep.retry == "Press the card again to try once more.")
        #expect(WelcomeThemeStep.isPressable(.failed("anything")))
    }

    /// The rule the whole window follows: nothing here prints a key
    /// equivalent, because every one of them is rebindable. See
    /// `WelcomeBasicsStep`.
    @Test func theStepPrintsNoKeyboardShortcut() {
        let text = [WelcomeThemeStep.sentence, WelcomeThemeStep.retry]
            + WelcomeThemeStep.choices.map(\.detail)
            + WelcomeThemeStep.choices.map(\.name)

        for line in text {
            #expect(!line.contains("⌘"))
            #expect(!line.contains("⌥"))
            #expect(!line.contains("⌃"))
        }
    }

    // MARK: What counts as applied

    /// The `theme` setting names a file, and the card that owns that file is
    /// the one in use. Matching by path is what `GuiConfigStore.isCurrentTheme`
    /// does for a contributed theme, so a theme applied in Settings shows up
    /// here as well.
    @Test func theAppliedCardIsTheOneWhoseThemeFileIsInForce() {
        let file = URL(fileURLWithPath: "/tmp/extensions/phantom.dracula/themes/dracula.conf")
        let themes = [
            Self.contributed(
                id: "phantom.dracula", name: "Dracula by Phantom", file: file),
            Self.contributed(
                id: "phantom.theme-nord", name: "Nord",
                file: URL(fileURLWithPath: "/tmp/extensions/phantom.theme-nord/nord.conf")),
        ]

        #expect(WelcomeThemeSelection.appliedID(themes: themes, currentThemeURL: file)
            == "phantom.dracula")
    }

    /// A path is compared standardized, so the same file reached by two
    /// spellings is one theme.
    @Test func theAppliedCardIsFoundThroughAnUntidyPath() {
        let file = URL(fileURLWithPath: "/tmp/extensions/phantom.dracula/themes/dracula.conf")
        let themes = [Self.contributed(
            id: "phantom.dracula", name: "Dracula by Phantom", file: file)]
        let untidy = URL(
            fileURLWithPath: "/tmp/extensions/phantom.dracula/themes/./dracula.conf")

        #expect(WelcomeThemeSelection.appliedID(themes: themes, currentThemeURL: untidy)
            == "phantom.dracula")
    }

    /// The bundled theme a fresh install runs is not one of these four, and
    /// nothing may claim it is: the reader is on Dracula and no extension owns
    /// that file.
    @Test func aBundledThemeBelongsToNoCard() {
        let themes = [Self.contributed(
            id: "phantom.dracula", name: "Dracula by Phantom",
            file: URL(fileURLWithPath: "/tmp/extensions/phantom.dracula/themes/dracula.conf"))]

        #expect(WelcomeThemeSelection.appliedID(
            themes: themes,
            currentThemeURL: URL(fileURLWithPath: "/Applications/Phantom.app/ghostty/themes/Dracula"))
            == nil)
        #expect(WelcomeThemeSelection.appliedID(themes: themes, currentThemeURL: nil) == nil)
    }

    private static func contributed(
        id: String,
        name: String,
        file: URL
    ) -> LanguageCatalog.ContributedTheme {
        LanguageCatalog.ContributedTheme(
            listIdentity: id,
            extensionName: name,
            theme: ThemeContribution(name: name, fileURL: file, appearance: nil))
    }

    // MARK: The step's own arithmetic

    /// The sentence, the three group labels, the gaps, the two rows of theme
    /// cards and the row of icon packs have to come to no more than the window
    /// leaves a step.
    @Test func theCardsFitTheWindowTheyWereMeasuredFor() {
        let available = WelcomeWindowController.size.height - WelcomeView.chromeHeight
        let used = WelcomeThemeStep.sentenceHeight
            + WelcomeThemeStep.spacing * 3
            + (WelcomeThemeStep.groupTitleHeight + WelcomeThemeStep.titleGap) * 3
            + WelcomeThemeStep.cardHeight * 2
            + WelcomeIconPacks.cardHeight

        #expect(WelcomeThemeStep.cardHeight > 0)
        #expect(used <= available)
    }

    /// Two cards to a row, so a card is half the window less the gap between
    /// them — which is what the swatch and three lines of text were sized
    /// against.
    @Test func theSwatchLeavesRoomForTheTextBesideIt() {
        #expect(WelcomeThemeStep.swatchSize < WelcomeThemeStep.cardHeight)
        #expect(WelcomeThemeStep.swatchSize * 2 < WelcomeWindowController.size.width / 2)
    }
}
