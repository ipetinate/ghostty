import AppKit
import SwiftUI

/// Everything one card can have to say about itself.
enum WelcomeThemeState: Equatable {
    /// The catalogue has not arrived. Nothing is wrong yet.
    case searching

    /// The catalogue could not be read, in the store's own words.
    case unreachable(String)

    /// The catalogue arrived and lists no such extension.
    case unlisted

    /// Listed, on nobody's mark.
    case offered

    /// On the mark, and waiting for Next. `isInstalled` separates the
    /// theme that has only to be applied from the one that has to be
    /// fetched first, because those are two different waits to promise.
    case chosen(isInstalled: Bool)

    /// An install is running, at the step the store last reported.
    case working(ExtensionActivity)

    /// On disk, and not the theme in force: the card a reader pressed
    /// before pressing another one.
    case installed

    /// On disk, and the theme every window is drawing.
    case inUse

    /// What went wrong, in the words of whatever failed.
    case failed(String)
}

/// The fourth step: the colours the reader works in, and the icons their file
/// explorer draws with.
///
/// Four theme cards — two dark, two light — and then the icon packs, in
/// ``WelcomeIconPacks``. Two questions on one screen because they are one
/// question asked twice: what this window looks like. A press is the choice,
/// the same gesture `WelcomeTabPlacementStep` uses and for the same reason: an
/// Apply button under a grid of pictures is a second thing to find before the
/// picture means anything.
///
/// **What is not the same is what a press costs.** This build ships no theme
/// as an extension, so three of these four are not on the machine when the
/// window opens. A press therefore has to reach the registry, and a card that
/// only lit up would be a card that claimed something it had not done. So
/// every card says which of the things happened to it — it is waiting, it is
/// downloading, it is in use, or it failed and why — and ``line(_:)`` is the
/// whole of that vocabulary.
///
/// **Nothing is written until a theme is on disk and readable.** The only
/// record the step leaves is `theme` in the GUI configuration, written by
/// `GuiConfigStore.setTheme` after the install returns without an error *and*
/// after `ThemeCatalog.parse` has read the file the extension shipped.
/// `WelcomeShownRecord` is deliberately not given a "chose Dracula" of its
/// own: a record like that is exactly the thing that would tell the next
/// launch a theme is in use when the download that would have made it so
/// never finished.
///
/// **Chosen is not applied.** Dracula by Phantom starts with the mark on it
/// and nothing installed. A tour that spent a reader's network on a choice
/// they had not made yet would be a tour charging for its own opening frame.
///
/// **A theme the registry does not list still gets a card.** The four ids are
/// written here and the index is fetched at runtime, so the two are allowed to
/// disagree — Alucard was not published when this step was written. Such a
/// card is drawn, says it is not there yet, and cannot be pressed. See
/// ``WelcomeThemeState/unlisted``.
///
/// No keyboard shortcut is printed on this step, for the reason
/// `WelcomeBasicsStep` states.
struct WelcomeThemeStep: View {
    @ObservedObject var selection: WelcomeThemeSelection
    @ObservedObject var packs: WelcomeIconPackSelection

    @ObservedObject private var store: ExtensionStore = .shared
    @ObservedObject private var config: GuiConfigStore = .shared
    @ObservedObject private var languages: LanguageResolver = .shared
    @ObservedObject private var palette: ThemePalette = .shared

    private var accent: Color { palette.accent ?? .accentColor }

    /// One card: a registry id, what to call it, which half of the grid it
    /// sits in, and one line about it.
    ///
    /// The id is the registry's and the name is ours. An extension contributes
    /// a theme under whatever name it likes, and for three of these four the
    /// two differ — so a card that printed the theme's own name would be blank
    /// until the index arrived, and would read differently offline.
    struct Choice: Identifiable, Equatable {
        let id: String
        let name: String
        let appearance: ThemeContribution.Appearance
        let detail: String
    }

    /// The four, in the order they are drawn: the dark pair, then the light
    /// pair.
    ///
    /// Two families in two appearances rather than four unrelated palettes.
    /// Dracula and Alucard are one theme's night and day, and so are Nord and
    /// Nord Light — which makes the grid legible as a grid: the column a
    /// reader's eye lands in is the appearance, and the row is the palette.
    ///
    /// The two ids without a `theme-` in them are the two the owner wrote.
    /// That is the registry's own distinction: `phantom.theme-*` is a
    /// repackaged terminal palette and colours the terminal, while
    /// `phantom.dracula` and `phantom.alucard` also set the split divider, the
    /// search bar, the title bar and the app icon.
    static let choices: [Choice] = [
        Choice(
            id: "phantom.dracula",
            name: "Dracula by Phantom",
            appearance: .dark,
            detail: "Purple on near-black. It colours the window, not just the terminal."),
        Choice(
            id: "phantom.theme-nord",
            name: "Nord",
            appearance: .dark,
            detail: "Cold blue-grey, low contrast, quiet over a long day."),
        Choice(
            id: "phantom.alucard",
            name: "Alucard by Phantom",
            appearance: .light,
            detail: "Dracula's daylight half: the same hues on warm paper."),
        Choice(
            id: "phantom.theme-nord-light",
            name: "Nord Light",
            appearance: .light,
            detail: "The same cold blues, read off paper instead of ink."),
    ]

    /// The card the grid opens with.
    ///
    /// Dracula because a fresh install is already running the bundled theme of
    /// that name — `ThemeCatalog.defaultThemeName` — so the mark starts on the
    /// card that matches the window the reader is looking at, and going on
    /// without touching anything installs the packaged version of the theme
    /// they are already in. That version colours the title bar, the splits and
    /// the app icon too, which the bundled file cannot do.
    static let preselected = "phantom.dracula"

    /// Two sentences: what a press does, and what it costs.
    static let sentence = """
        Press a card for a theme, and one below for the file explorer's icons. \
        Both are extensions, downloaded when you go on — and both are optional.
        """

    static let spacing: CGFloat = 14

    /// The sentence's own line, reserved so the cards below it are a height
    /// rather than whatever is left over.
    static let sentenceHeight: CGFloat = 18

    /// The Dark or Light label above a row of two cards, and the gap under it.
    static let groupTitleHeight: CGFloat = 12
    static let titleGap: CGFloat = 6

    static let cardSpacing: CGFloat = 12

    /// The swatch's side. Square, because that is the shape the registry
    /// publishes: every theme's card icon is a 256-point picture of its own
    /// palette.
    static let swatchSize: CGFloat = 84

    /// Two rows of theme cards fill what the step is left once the icon packs
    /// have taken their row, the way the other two list steps' cards do.
    ///
    /// Three groups now, so three titles and three gaps under the sentence —
    /// and `WelcomeIconPacks.cardHeight` comes off the top, because that row
    /// is a fixed height and these two take what is left rather than the
    /// other way round. A pack card carries no palette and no sentence, so it
    /// is the one of the three that has a height of its own.
    static var cardHeight: CGFloat {
        let available = WelcomeWindowController.size.height
            - WelcomeView.chromeHeight
            - sentenceHeight
            - spacing * 3
            - (groupTitleHeight + titleGap) * 3
            - WelcomeIconPacks.cardHeight
        return (available / 2).rounded(.down)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            Text(Self.sentence)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(
                    maxWidth: .infinity,
                    minHeight: Self.sentenceHeight,
                    alignment: .leading)

            group(.dark)
            group(.light)
            WelcomeIconPacks(selection: packs)
        }
        /// The step asks for the catalogue rather than assuming somebody else
        /// has: on a first launch nothing else has fetched it, because the
        /// only other reader of it is the Extensions pane. The store decides
        /// whether there is anything to fetch — see
        /// `ExtensionStore.loadIfNeeded`.
        .task { await store.loadIfNeeded() }
    }

    static func title(_ appearance: ThemeContribution.Appearance) -> String {
        switch appearance {
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }

    /// The two cards of one appearance, under the word for it — the same two
    /// words, in the same order, that split the theme grid in Settings.
    private func group(_ appearance: ThemeContribution.Appearance) -> some View {
        VStack(alignment: .leading, spacing: Self.titleGap) {
            Text(Self.title(appearance))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(height: Self.groupTitleHeight, alignment: .leading)

            HStack(alignment: .top, spacing: Self.cardSpacing) {
                ForEach(Self.choices.filter { $0.appearance == appearance }) { choice in
                    card(choice)
                }
            }
        }
    }

    /// One card: the theme's own palette, its name, one line about it, and
    /// what has happened to it.
    ///
    /// A `Button` rather than a tap gesture, so the card is one thing to the
    /// accessibility tree as well as to the mouse — the placement step's
    /// reason, unchanged. It is disabled in the states where a press could not
    /// do anything: while the index is still coming, when it never came, when
    /// the registry does not list the theme, and while an install is already
    /// running.
    private func card(_ choice: Choice) -> some View {
        let state = state(of: choice)
        let isChosen = selection.chosen == choice.id

        return Button {
            Task { await selection.press(choice) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                swatch(choice)

                VStack(alignment: .leading, spacing: 4) {
                    VStack(alignment: .leading, spacing: 4) {
                        header(choice, isChosen: isChosen)

                        Text(choice.detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    /// A card that cannot be pressed is drawn back, and only
                    /// down to here: the report under it keeps its full weight,
                    /// because the reason a card is unavailable is the one
                    /// thing on it worth reading.
                    .opacity(Self.isPressable(state) ? 1 : 0.55)

                    Spacer(minLength: 4)

                    WelcomeExtensionReport(state: state, line: Self.line(state))
                }
                /// The column takes the card's whole height, so the spacer
                /// above pushes the report to the bottom edge. Without it the
                /// line sits under the sentence, and the four cards then hold
                /// it at two different heights depending on whether their own
                /// sentence wrapped.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.cardHeight, alignment: .top)
            /// The treatment every card in this window wears: the chosen one
            /// is accent-tinted with an accent border. A second way of saying
            /// "this one" would read as a second kind of selection.
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isChosen ? accent.opacity(0.10) : Color.secondary.opacity(0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isChosen ? accent.opacity(0.45) : Color.secondary.opacity(0.16)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!Self.isPressable(state))
        .help(Self.isPressable(state)
            ? (isChosen ? "Already your theme" : "Use " + choice.name)
            : Self.line(state))
        .onHover { hovering in
            guard Self.isPressable(state) else { return }
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }

    /// The mark and the name. Two states of one symbol rather than a mark that
    /// appears and disappears, so a card whose header is picked does not move
    /// the line under it.
    private func header(_ choice: Choice, isChosen: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(isChosen ? accent : Color.secondary)

            Text(choice.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    /// The theme's real colours, drawn from the index and not from a download.
    ///
    /// Every theme in the registry publishes a picture of its own palette as
    /// its card icon, and the index carries that image inline in
    /// `card.iconData` — so the four cards show what the reader is choosing
    /// between while none of them is installed. `ExtensionIconView` prefers a
    /// file where there is one, which is what an already-installed theme has,
    /// and falls back to those bytes where there is not.
    ///
    /// A theme with no entry gets a drawn stand-in rather than
    /// `ExtensionIconView`'s puzzle piece: the puzzle is the mark for an
    /// extension whose artwork failed to load, and this one has no artwork to
    /// fail.
    @ViewBuilder
    private func swatch(_ choice: Choice) -> some View {
        if let entry = entry(for: choice) {
            ExtensionIconView(source: store.icon(for: entry), size: Self.swatchSize)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
                .frame(width: Self.swatchSize, height: Self.swatchSize)
                .overlay(
                    Image(systemName: "paintpalette")
                        .font(.system(size: Self.swatchSize * 0.32))
                        .foregroundStyle(.tertiary))
        }
    }

    // MARK: What a card says

    /// Everything four stores know about one card, gathered so that reading
    /// them can be a function of its arguments and nothing else.
    struct Facts: Equatable {
        /// The catalogue, and why it is missing when it is missing. Nil with
        /// no error is a fetch that has not finished.
        var index: ExtensionIndex?
        var indexError: String?

        var isInstalled = false

        /// The step of an install the store last reported, and nil when none
        /// is running.
        var activity: ExtensionActivity?

        /// Where the install failed, and where applying failed. Two failures
        /// with two repairs — see `WelcomeThemeSelection.applyFailures`.
        var installError: String?
        var applyError: String?

        /// The extension whose theme every window is drawing, whichever card
        /// that is and whether or not it is one of these four.
        var appliedID: String?

        var chosen: String = WelcomeThemeStep.preselected
    }

    /// What a card says.
    ///
    /// Static and pure, so the order of the checks is something a test can
    /// hold rather than something only a running window can be asked — and the
    /// order is most of the meaning. What is *running* answers first, because
    /// it is the newest fact. A failure answers next, ahead of `inUse`, so a
    /// reader who re-pressed the theme in force and lost the network is told so
    /// rather than reassured. What is on disk answers before the catalogue
    /// does, which is what lets an offline reader apply a theme they already
    /// have.
    static func state(of choice: Choice, from facts: Facts) -> WelcomeThemeState {
        if let activity = facts.activity { return .working(activity) }
        if let reason = facts.installError ?? facts.applyError { return .failed(reason) }
        if facts.appliedID == choice.id { return .inUse }
        if facts.isInstalled {
            return facts.chosen == choice.id ? .chosen(isInstalled: true) : .installed
        }
        guard let index = facts.index else {
            return facts.indexError.map(WelcomeThemeState.unreachable) ?? .searching
        }
        guard index.extensions.contains(where: { $0.id == choice.id }) else { return .unlisted }
        return facts.chosen == choice.id ? .chosen(isInstalled: false) : .offered
    }

    static func line(_ state: WelcomeThemeState) -> String {
        switch state {
        case .searching:
            return "Looking for it in the registry…"
        case .unreachable(let reason):
            return reason
        case .unlisted:
            return "Not in the registry yet, so this one cannot be installed."
        case .offered:
            return ""
        case .chosen(let isInstalled):
            return isInstalled
                ? "Chosen. Go on and it is applied."
                : "Chosen. Go on and it is downloaded, then applied."
        case .working(let activity):
            return progress(activity)
        case .installed:
            return "Installed, and not the theme in use."
        case .inUse:
            return "In use, in every window."
        case .failed(let reason):
            return reason
        }
    }

    /// The store's four steps, in the words the Extensions pane already uses
    /// for them. One name per step, in one place, or the same download reads
    /// as two different things in two windows.
    static func progress(_ activity: ExtensionActivity) -> String {
        switch activity {
        case .downloading: return "Downloading…"
        case .verifying: return "Verifying…"
        case .installing: return "Installing…"
        case .removing: return "Removing…"
        }
    }

    /// The way out of a failure: the same press again. Every installer behind
    /// this step is idempotent, which is the rule `WelcomeView.finish` states
    /// for the agents step.
    static let retry = "Press the card again to try once more."

    static func isFailure(_ state: WelcomeThemeState) -> Bool {
        switch state {
        case .failed, .unreachable: return true
        default: return false
        }
    }

    /// Whether a press could do anything. `searching` is included in what it
    /// could not: a card whose entry has not arrived has no download to start.
    static func isPressable(_ state: WelcomeThemeState) -> Bool {
        switch state {
        case .searching, .unreachable, .unlisted, .working: return false
        case .offered, .chosen, .installed, .inUse, .failed: return true
        }
    }

    // MARK: Reading the stores

    private func entry(for choice: Choice) -> ExtensionIndex.Entry? {
        store.index?.extensions.first { $0.id == choice.id }
    }

    private func state(of choice: Choice) -> WelcomeThemeState {
        Self.state(of: choice, from: Facts(
            index: store.index,
            indexError: store.lastRefreshError,
            isInstalled: store.installed.contains { $0.id == choice.id },
            activity: store.activity[choice.id],
            installError: store.errors[choice.id],
            applyError: selection.applyFailures[choice.id],
            appliedID: selection.appliedID,
            chosen: selection.chosen))
    }
}

/// What the theme step has picked, and the one place that makes it real.
///
/// Held by `WelcomeView` rather than by the step itself, for two reasons. Next
/// is a button in the window's own bottom bar, and going on is the gesture the
/// step gives the install — so the thing that installs cannot live in a view
/// the bottom bar has never heard of. And SwiftUI throws a step's `@State`
/// away when `WelcomeView` switches steps, so a reader who stepped back and
/// forward again would find a failure message gone and a running install
/// unaccounted for.
///
/// Fresh on every open, because `WelcomeWindowController` rebuilds its hosting
/// view every time: a walk-through returned to halfway through somebody else's
/// session is not a state worth keeping.
@MainActor
final class WelcomeThemeSelection: ObservableObject {
    /// Which card has the mark. A choice, and by itself nothing else — see
    /// ``WelcomeThemeStep`` on what is and is not written down.
    @Published private(set) var chosen: String = WelcomeThemeStep.preselected

    /// What *applying* failed at, per extension.
    ///
    /// Kept apart from `ExtensionStore.errors`, which is where the install
    /// failed. Two failures with two repairs, and the store's one is shared
    /// with the Extensions pane — a theme whose download failed should say the
    /// same thing in both windows.
    @Published private(set) var applyFailures: [String: String] = [:]

    /// The extension whose theme every window is drawing, or nil when the
    /// theme in force came from somewhere else: the bundle, or a file the
    /// reader wrote.
    var appliedID: String? {
        Self.appliedID(
            themes: LanguageResolver.shared.catalog.themes,
            currentThemeURL: GuiConfigStore.shared.currentThemeURL)
    }

    /// Which installed extension the `theme` setting points into.
    ///
    /// By file path, which is what `GuiConfigStore.setTheme` writes for a
    /// contributed theme and what `isCurrentTheme` compares — so this answers
    /// the same question the Appearance pane's checkmark does, and answers it
    /// for a theme applied there rather than here.
    static func appliedID(
        themes: [LanguageCatalog.ContributedTheme],
        currentThemeURL: URL?
    ) -> String? {
        guard let path = currentThemeURL?.standardizedFileURL.path else { return nil }
        return themes.first { $0.theme.fileURL.standardizedFileURL.path == path }?.listIdentity
    }

    /// A card press: the mark moves, and the theme is fetched and applied.
    func press(_ choice: WelcomeThemeStep.Choice) async {
        chosen = choice.id
        await use(choice)
    }

    /// What going on does: the chosen card's own work, and only what is left
    /// of it.
    ///
    /// Started and not waited for. A reader must be able to leave this step
    /// with a slow download still running, and the model outlives the step, so
    /// the card shows what happened if they come back to look.
    func goOn() {
        guard let choice = WelcomeThemeStep.choices.first(where: { $0.id == chosen }),
              appliedID != choice.id
        else { return }
        Task { await use(choice) }
    }

    /// Fetches what is not on disk, then applies it.
    ///
    /// Idempotent: a second press of a theme already in use costs one re-apply
    /// and no download, and a press during an install is ignored rather than
    /// queued behind it.
    ///
    /// It stops at the first thing that failed and leaves the reason where the
    /// card can read it. Nothing is applied after a failed install, which is
    /// the whole of not lying about it: with no `theme` written, the next
    /// launch runs the theme the reader already had.
    func use(_ choice: WelcomeThemeStep.Choice) async {
        let store = ExtensionStore.shared
        guard store.activity[choice.id] == nil else { return }
        applyFailures[choice.id] = nil

        if !store.installed.contains(where: { $0.id == choice.id }) {
            guard let entry = store.index?.extensions.first(where: { $0.id == choice.id }) else {
                applyFailures[choice.id] = store.lastRefreshError ?? Self.notListed(choice)
                return
            }
            await store.install(entry)
            guard store.errors[choice.id] == nil else { return }
        }

        apply(choice)
    }

    /// Writes the theme and reloads the configuration, which is the whole of
    /// applying one: `AppearanceSettingsView` does exactly this pair on a card
    /// press, and `GuiConfigStore.apply` is what posts `didApply` for
    /// `ThemePalette` and every open `TerminalController` to read. It is also
    /// why this window's own accent changes under the reader's hand — the
    /// welcome window is themed by the same palette the terminals are.
    ///
    /// Every guard reports rather than passes. Writing `theme` for a file
    /// nothing can parse would point the next launch at a theme it cannot
    /// draw, which is worse than saying so here.
    private func apply(_ choice: WelcomeThemeStep.Choice) {
        guard let contributed = LanguageResolver.shared.catalog.themes
            .first(where: { $0.listIdentity == choice.id })
        else {
            applyFailures[choice.id] = Self.noTheme(choice)
            return
        }

        guard let theme = ThemeCatalog.parse(
            url: contributed.theme.fileURL,
            source: .contributed(extension: contributed.extensionName),
            name: contributed.theme.name,
            declaredAppearance: contributed.theme.appearance)
        else {
            applyFailures[choice.id] = Self.unreadable(choice)
            return
        }

        guard let ghostty = (NSApp.delegate as? AppDelegate)?.ghostty else {
            applyFailures[choice.id] = Self.notRunning
            return
        }

        GuiConfigStore.shared.setTheme(theme)
        GuiConfigStore.shared.apply(ghostty: ghostty)
    }

    /// Pressing Next on a theme the catalogue does not offer, which is the one
    /// path that reaches an unlisted theme — the card for one cannot be
    /// pressed. It is what a reader who leaves Dracula on the mark and goes on
    /// gets when the registry answered but does not list it.
    static func notListed(_ choice: WelcomeThemeStep.Choice) -> String {
        choice.name + " is not in the registry, so there is nothing to install."
    }

    static func noTheme(_ choice: WelcomeThemeStep.Choice) -> String {
        choice.name + " installed, but it contributes no theme."
    }

    static func unreadable(_ choice: WelcomeThemeStep.Choice) -> String {
        choice.name + " installed, but its colours could not be read."
    }

    /// The branch that says the app is not there to reload. Unreachable while
    /// this window is on screen, and kept because the alternative is writing
    /// the setting and claiming a theme is in use in windows that never heard
    /// about it.
    static let notRunning = "Phantom could not reload its configuration."
}
