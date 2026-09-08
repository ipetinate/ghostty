import Foundation
@testable import Ghostty
import Testing

/// The icon packs on the welcome window's theme step: which three it offers,
/// what each card says about itself, the order in which the facts are read,
/// and the one card that never reaches the registry.
@MainActor
struct WelcomeIconPacksTests {
    private static func entry(
        _ id: String,
        homepage: URL? = nil
    ) -> ExtensionIndex.Entry {
        ExtensionIndex.Entry(
            id: id,
            name: id,
            version: "1.0.0",
            publisher: "Isac Petinate",
            summary: "",
            homepage: homepage,
            minimumPhantomVersion: nil,
            contributes: ["iconThemes"],
            languages: [],
            downloadURL: URL(string: "https://example.com/\(id).zip")!,
            sha256: String(repeating: "a", count: 64),
            bytes: 1,
            card: nil)
    }

    private static func index(_ ids: [String]) -> ExtensionIndex {
        ExtensionIndex(generatedAt: nil, repository: nil, extensions: ids.map { entry($0) })
    }

    /// The catalogue with both packs in it, which is what the registry lists
    /// today.
    private static var fullIndex: ExtensionIndex {
        index(WelcomeIconPacks.choices.compactMap(\.id))
    }

    private static func choice(_ id: String?) -> WelcomeIconPacks.Choice {
        WelcomeIconPacks.choices.first { $0.id == id }!
    }

    private static var noPack: WelcomeIconPacks.Choice { choice(nil) }
    private static var symbols: WelcomeIconPacks.Choice { choice("phantom.symbols-icons") }
    private static var material: WelcomeIconPacks.Choice {
        choice("ipetinate.material-icon-theme")
    }

    // MARK: The three cards

    @Test func thereAreThreeCardsAndExactlyOneOfThemInstallsNothing() {
        let installing = WelcomeIconPacks.choices.filter { $0.id != nil }

        #expect(WelcomeIconPacks.choices.count == 3)
        #expect(installing.count == 2)
        #expect(WelcomeIconPacks.choices.first?.id == nil)
    }

    /// Every card that installs something names an extension the installer
    /// would accept, so a card can never be one the app is unable to fetch by
    /// construction.
    @Test func everyPackNamesADistinctExtensionTheAppCouldInstall() {
        let ids = WelcomeIconPacks.choices.compactMap(\.id)

        #expect(Set(ids).count == ids.count)
        #expect(ids == ["phantom.symbols-icons", "ipetinate.material-icon-theme"])
        for id in ids {
            #expect(LanguageManifest.validID(id) == id)
        }
    }

    @Test func everyCardHasItsOwnName() {
        let names = WelcomeIconPacks.choices.map(\.name)

        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { !$0.isEmpty })
    }

    // MARK: The default

    /// The mark opens on the card that installs nothing, and it opens there
    /// because that is what the app is doing: the bundle ships no pack, so
    /// `FileIconProvider` selects none and the explorer draws SF Symbols.
    ///
    /// The two facts are asserted together on purpose. Preselecting a
    /// download would spend a reader's network on a question they had not
    /// answered, and preselecting anything at all is only honest while the
    /// app is really on it.
    @Test func theRowOpensOnTheCardThatInstallsNothing() {
        #expect(WelcomeIconPacks.preselected == nil)
        #expect(FileIconProvider.defaultThemeName == FileIconProvider.symbolsOnly)
        #expect(Self.noPack.name == "No Pack (SF Symbols)")
    }

    /// That card is in use until a pack is applied, needs no catalogue to say
    /// so, and can be pressed with the registry unreachable — which is what
    /// makes it a safe thing to open on.
    @Test func theCardThatInstallsNothingNeverReachesTheRegistry() {
        let offline = WelcomeIconPacks.Facts(
            indexError: "Could not reach the registry: offline.")
        let state = WelcomeIconPacks.state(of: Self.noPack, from: offline)

        #expect(state == .inUse)
        #expect(WelcomeThemeStep.isPressable(state))
        #expect(!WelcomeThemeStep.isFailure(state))
        #expect(WelcomeIconPacks.state(of: Self.noPack, from: .init()) == .inUse)
    }

    /// With a pack drawing the explorer it steps aside and says nothing: it is
    /// still the way back, and a card claiming to be in use beside the pack
    /// that is would be two answers to one question.
    @Test func theCardThatInstallsNothingStepsAsideForAPackInForce() {
        let facts = WelcomeIconPacks.Facts(
            index: Self.fullIndex,
            appliedID: "ipetinate.material-icon-theme")
        let state = WelcomeIconPacks.state(of: Self.noPack, from: facts)

        #expect(state == .offered)
        #expect(WelcomeThemeStep.isPressable(state))
        #expect(WelcomeIconPacks.line(state).isEmpty)
    }

    // MARK: A pack the registry does not list

    /// The two ids are written in the step and the index is fetched at
    /// runtime, so the two are allowed to disagree. Such a card is drawn, says
    /// why it cannot be had, and refuses the press.
    @Test func aPackTheIndexDoesNotListSaysSoAndCannotBePressed() {
        let facts = WelcomeIconPacks.Facts(
            index: Self.index(["ipetinate.material-icon-theme"]))
        let state = WelcomeIconPacks.state(of: Self.symbols, from: facts)

        #expect(state == .unlisted)
        #expect(!WelcomeThemeStep.isPressable(state))
        #expect(WelcomeIconPacks.line(state)
            == "Not in the registry yet, so this one cannot be installed.")
    }

    /// Being unlisted is a fact about one card and not about the row. The
    /// catalogue therefore has to list the other pack — built with neither in
    /// it, both are unlisted and the assertion reads a second missing entry.
    @Test func anUnlistedPackLeavesTheOtherTwoAlone() {
        let facts = WelcomeIconPacks.Facts(
            index: Self.index(["ipetinate.material-icon-theme"]))

        #expect(WelcomeIconPacks.state(of: Self.material, from: facts) == .offered)
        #expect(WelcomeIconPacks.state(of: Self.noPack, from: facts) == .inUse)
    }

    /// A catalogue that has not arrived is not a catalogue that failed. Both
    /// refuse the press; only one of them is drawn as a failure.
    @Test func anIndexStillComingIsNotAnIndexThatFailed() {
        let waiting = WelcomeIconPacks.state(of: Self.symbols, from: .init())
        #expect(waiting == .searching)
        #expect(!WelcomeThemeStep.isFailure(waiting))
        #expect(!WelcomeThemeStep.isPressable(waiting))

        let refused = WelcomeIconPacks.state(
            of: Self.symbols,
            from: .init(indexError: "Could not reach the registry: offline."))
        #expect(refused == .unreachable("Could not reach the registry: offline."))
        #expect(WelcomeThemeStep.isFailure(refused))
        #expect(!WelcomeThemeStep.isPressable(refused))
    }

    // MARK: The order the facts are read in

    @Test func aRunningInstallAnswersBeforeEverythingElse() {
        let facts = WelcomeIconPacks.Facts(
            index: Self.fullIndex,
            isInstalled: true,
            activity: .downloading(fraction: 0.4),
            installError: "an older failure",
            appliedID: "phantom.symbols-icons")

        #expect(WelcomeIconPacks.state(of: Self.symbols, from: facts)
            == .working(.downloading(fraction: 0.4)))
    }

    /// A pack in force that has just failed to reinstall says so. Reading
    /// `inUse` first would leave the reader looking at a card that reports
    /// success for the press that failed.
    @Test func aFailureAnswersBeforeThePackInForce() {
        let facts = WelcomeIconPacks.Facts(
            index: Self.fullIndex,
            isInstalled: true,
            installError: "The download does not match the registry's checksum.",
            appliedID: "phantom.symbols-icons")

        let state = WelcomeIconPacks.state(of: Self.symbols, from: facts)
        #expect(state == .failed("The download does not match the registry's checksum."))
        #expect(WelcomeThemeStep.isPressable(state))
    }

    /// A failure the *install* reported and one *applying* reported both land
    /// on the card, because a reader has one card to look at either way.
    @Test func applyingCanFailOnItsOwn() {
        let facts = WelcomeIconPacks.Facts(
            index: Self.fullIndex,
            isInstalled: true,
            applyError: WelcomeIconPackSelection.unreadable(Self.material))

        #expect(WelcomeIconPacks.state(of: Self.material, from: facts)
            == .failed("Material Icon Theme installed, but it draws no icons."))
    }

    /// What is on disk is read before the catalogue is, so a reader with no
    /// network can still put on a pack they already have.
    @Test func aPackAlreadyOnDiskCanBeAppliedWithNoCatalogue() {
        let facts = WelcomeIconPacks.Facts(
            indexError: "Could not reach the registry: offline.",
            isInstalled: true,
            chosen: "phantom.symbols-icons")

        let state = WelcomeIconPacks.state(of: Self.symbols, from: facts)
        #expect(state == .chosen(isInstalled: true))
        #expect(WelcomeThemeStep.isPressable(state))
    }

    @Test func aCardPressedBeforeAnotherOneSaysItIsInstalledAndNotInUse() {
        let facts = WelcomeIconPacks.Facts(
            index: Self.fullIndex,
            isInstalled: true,
            appliedID: "ipetinate.material-icon-theme",
            chosen: "ipetinate.material-icon-theme")

        #expect(WelcomeIconPacks.state(of: Self.symbols, from: facts) == .installed)
        #expect(WelcomeIconPacks.line(.installed) == "Installed, and not the pack in use.")
    }

    // MARK: What the copy promises

    /// The chosen card promises a download only when there is one to do, so
    /// the sentence never announces work that has already happened.
    @Test func theChosenCardPromisesADownloadOnlyWhenThereIsOneToDo() {
        let fresh = WelcomeIconPacks.line(.chosen(isInstalled: false))
        let here = WelcomeIconPacks.line(.chosen(isInstalled: true))

        #expect(fresh.contains("downloaded"))
        #expect(!here.contains("downloaded"))
        #expect(here.contains("applied"))
    }

    /// Only the state that means the pack is on disk and in force is allowed
    /// to say it is drawing anything.
    @Test func onlyThePackInForceSaysItIsDrawing() {
        let notInUse: [WelcomeThemeState] = [
            .searching, .unreachable("no"), .unlisted, .offered,
            .chosen(isInstalled: false), .chosen(isInstalled: true),
            .working(.installing), .installed, .failed("no"),
        ]

        for state in notInUse {
            #expect(!WelcomeIconPacks.line(state).contains("Drawing"))
        }
        #expect(WelcomeIconPacks.line(.inUse) == "Drawing every file explorer.")
    }

    /// A pack is not a theme, so nothing on these cards calls itself one —
    /// the states are shared, the words are not.
    @Test func noPackCardCallsItselfATheme() {
        let states: [WelcomeThemeState] = [
            .searching, .unreachable("why"), .unlisted, .offered,
            .chosen(isInstalled: false), .chosen(isInstalled: true),
            .working(.verifying), .installed, .inUse, .failed("why"),
        ]

        for state in states {
            #expect(!WelcomeIconPacks.line(state).lowercased().contains("theme"))
        }
    }

    /// Every state says something a reader can act on, except the one that has
    /// nothing to report.
    @Test func everyStateButTheOfferedOneSaysSomething() {
        let speaking: [WelcomeThemeState] = [
            .searching, .unreachable("why"), .unlisted,
            .chosen(isInstalled: false), .chosen(isInstalled: true),
            .working(.verifying), .installed, .inUse, .failed("why"),
        ]

        for state in speaking {
            #expect(!WelcomeIconPacks.line(state).isEmpty)
        }
        #expect(WelcomeIconPacks.line(.offered).isEmpty)
    }

    /// The rule the whole window follows: nothing here prints a key
    /// equivalent, because every one of them is rebindable.
    @Test func theRowPrintsNoKeyboardShortcut() {
        let text = [WelcomeIconPacks.title, WelcomeIconPacks.storeLink]
            + WelcomeIconPacks.choices.map(\.name)

        for line in text {
            #expect(!line.contains("⌘"))
            #expect(!line.contains("⌥"))
            #expect(!line.contains("⌃"))
        }
    }

    // MARK: The link to the store

    /// The pack's own page, which is where the icons are — this row draws
    /// none of them. The card that installs nothing has no page.
    @Test func everyPackLinksToItsOwnPageAndTheOtherCardToNone() {
        let page = URL(
            string: "https://github.com/ipetinate/phantom-extensions/tree/main/extensions/symbols-icons")!
        let listed = Self.entry("phantom.symbols-icons", homepage: page)

        #expect(WelcomeIconPacks.storeURL(for: Self.symbols, entry: listed) == page)
        #expect(WelcomeIconPacks.storeURL(for: Self.noPack, entry: nil) == nil)
        #expect(WelcomeIconPacks.storeLink == "See the icons")
    }

    /// A pack whose entry has not arrived still links somewhere a reader can
    /// look, because a link that appears only once the index does is a link
    /// nobody offline can follow.
    @Test func aPackWithNoEntryYetLinksToTheRegistryItself() {
        #expect(WelcomeIconPacks.storeURL(for: Self.symbols, entry: nil)
            == ExtensionsSettingsView.registryURL)
        #expect(WelcomeIconPacks.storeURL(for: Self.material, entry: Self.entry("x"))
            == ExtensionsSettingsView.registryURL)
    }

    /// The card with no artwork of its own wears the mark the explorer's gear
    /// menu already puts beside SF Symbols, and a pack waiting on the index
    /// wears a different one.
    @Test func theCardThatInstallsNothingWearsItsOwnMark() {
        #expect(WelcomeIconPacks.symbol(for: Self.noPack) == "textformat")
        #expect(WelcomeIconPacks.symbol(for: Self.symbols)
            != WelcomeIconPacks.symbol(for: Self.noPack))
    }

    // MARK: What counts as applied

    /// The selection names a pack and the extension that contributes that pack
    /// is the one in use, so a pack selected in Settings shows up here too.
    @Test func theAppliedCardIsTheOneWhosePackIsSelected() {
        let packs = [
            Self.contributed(id: "phantom.symbols-icons", pack: "Symbols"),
            Self.contributed(id: "ipetinate.material-icon-theme", pack: "Material Icon Theme"),
        ]

        #expect(WelcomeIconPackSelection.appliedID(
            iconThemes: packs, selectedName: "Material Icon Theme")
            == "ipetinate.material-icon-theme")
    }

    /// SF Symbols is no extension's pack, and nothing may claim it is.
    @Test func theBuiltInTableBelongsToNoCard() {
        let packs = [Self.contributed(id: "phantom.symbols-icons", pack: "Symbols")]

        #expect(WelcomeIconPackSelection.appliedID(
            iconThemes: packs, selectedName: FileIconProvider.symbolsOnly) == nil)
        #expect(WelcomeIconPackSelection.appliedID(
            iconThemes: packs, selectedName: "a pack nobody installed") == nil)
    }

    /// The reader the bundled pack left behind. Their stored selection is the
    /// bundle's directory name, `symbols`, and the extension that packages
    /// that same pack declares it as `Symbols` — so installing it gives their
    /// icons back under the selection they already have, and the card says it
    /// is in use rather than offering an install for what is drawing every
    /// row.
    @Test func theNameLeftBySelectingTheBundledPackFindsTheExtension() {
        let packs = [Self.contributed(id: "phantom.symbols-icons", pack: "Symbols")]

        #expect(WelcomeIconPackSelection.appliedID(iconThemes: packs, selectedName: "symbols")
            == "phantom.symbols-icons")
    }

    private static func contributed(
        id: String,
        pack: String
    ) -> LanguageCatalog.ContributedIconTheme {
        LanguageCatalog.ContributedIconTheme(
            listIdentity: id,
            extensionName: pack,
            extensionRoot: URL(fileURLWithPath: "/tmp/extensions/\(id)"),
            iconTheme: IconThemeContribution(
                name: pack,
                directoryURL: URL(fileURLWithPath: "/tmp/extensions/\(id)/icons")))
    }

    // MARK: The row's own arithmetic

    /// A pack card is shorter than a theme card, which is the whole reason it
    /// has a height of its own: there is no palette to show and no sentence to
    /// read on it.
    @Test func aPackCardIsShorterThanAThemeCard() {
        #expect(WelcomeIconPacks.cardHeight > 0)
        #expect(WelcomeIconPacks.cardHeight < WelcomeThemeStep.cardHeight)
        #expect(WelcomeIconPacks.artworkSize < WelcomeIconPacks.cardHeight)
    }

    /// Three cards to a row, each leaving room beside its report for the link
    /// drawn over it.
    @Test func theLinkLeavesRoomForTheReportBesideIt() {
        let card = WelcomeWindowController.size.width / 3
        #expect(WelcomeIconPacks.linkGutter < card)
    }
}
