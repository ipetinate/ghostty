import AppKit
import SwiftUI

/// The third group on the theme step: which icon pack the file explorer
/// draws with.
///
/// It sits under the two rows of theme cards because it is the same kind of
/// question — what this window looks like — and a reader who has just been
/// asked about colours should not meet a second screen to be asked about
/// icons.
///
/// **No preview.** The card carries the pack's own artwork, its name, and
/// what has happened to it. A grid of sample icons is what the registry's
/// own page is for, so every pack card carries a link to it — see
/// ``storeURL(for:entry:)``.
///
/// **One state machine, two vocabularies.** A pack is an extension, so it
/// reports exactly what a theme card reports and in the same order —
/// ``WelcomeThemeStep/state(of:from:)`` is the model this follows, down to
/// which fact answers first. Only the words differ, because "the theme in
/// use" is not what an icon pack is.
///
/// **Nothing is written until a pack is on disk and draws something.** The
/// only record is `FileExplorerIconTheme` in `UserDefaults`, written by
/// `FileIconProvider.select` after the install returns without an error
/// *and* after `IconTheme.load` has read the directory the extension
/// shipped.
///
/// **The card that installs nothing never reaches the registry.** It is
/// neither listed nor missing, so it is pressable offline and while the
/// index is still coming — which is what makes it a safe thing to open on.
struct WelcomeIconPacks: View {
    @ObservedObject var selection: WelcomeIconPackSelection

    @ObservedObject private var store: ExtensionStore = .shared
    @ObservedObject private var icons: FileIconProvider = .shared
    @ObservedObject private var languages: LanguageResolver = .shared
    @ObservedObject private var palette: ThemePalette = .shared

    private var accent: Color { palette.accent ?? .accentColor }

    /// One card: a registry id, and what to call it.
    ///
    /// The id is nil for the card that installs nothing, which is the whole
    /// of what makes it different — every branch that reaches the registry
    /// is behind that one optional.
    struct Choice: Identifiable, Equatable {
        let id: String?
        let name: String
    }

    /// The three, in the order they are drawn.
    ///
    /// The pack that installs nothing comes first because it is the answer a
    /// fresh install is already on, and the two packs follow in the order
    /// the registry lists them.
    static let choices: [Choice] = [
        Choice(id: nil, name: "No Pack (SF Symbols)"),
        Choice(id: "phantom.symbols-icons", name: "Symbols Icons"),
        Choice(id: "ipetinate.material-icon-theme", name: "Material Icon Theme"),
    ]

    /// The card the row opens with: the one that installs nothing.
    ///
    /// A step nobody has answered yet must not have answered itself. The app
    /// bundles no pack, so this is also what the explorer behind the window
    /// is drawing — the mark starts on the truth, the way the theme step's
    /// mark starts on the theme already in force. Opening on either pack
    /// would spend a reader's network on a choice they had not made.
    static let preselected: String? = nil

    static let title = "Icons"

    /// Shorter than a theme card, because there is less on it: no palette to
    /// show and no sentence to read, so the artwork and the name are a row
    /// and the report is the row under it.
    ///
    /// It is measured against the tallest report a card can carry, which is a
    /// failure — two lines of reason and the line naming the repair — rather
    /// than against the one-line report every other state draws.
    static let cardHeight: CGFloat = 96

    /// The pack's artwork, at the side the registry's cards are square to.
    static let artworkSize: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: WelcomeThemeStep.titleGap) {
            Text(Self.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(height: WelcomeThemeStep.groupTitleHeight, alignment: .leading)

            HStack(alignment: .top, spacing: WelcomeThemeStep.cardSpacing) {
                ForEach(Self.choices) { choice in
                    card(choice)
                }
            }
        }
    }

    /// One card, and the link to its page beside it.
    ///
    /// The link is a sibling of the button rather than a control inside it:
    /// a `Link` nested in a `Button` is one hit target to the accessibility
    /// tree, and pressing "See the icons" would install the pack.
    private func card(_ choice: Choice) -> some View {
        let state = state(of: choice)
        let isChosen = selection.chosen == choice.id

        return ZStack(alignment: .bottomTrailing) {
            Button {
                Task { await selection.press(choice) }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 10) {
                        artwork(choice)
                        header(choice, isChosen: isChosen)
                    }
                    /// A card that cannot be pressed is drawn back, and only
                    /// down to here: the report keeps its full weight,
                    /// because the reason a card is unavailable is the one
                    /// thing on it worth reading.
                    .opacity(WelcomeThemeStep.isPressable(state) ? 1 : 0.55)

                    Spacer(minLength: 2)

                    WelcomeExtensionReport(state: state, line: Self.line(state))
                        .padding(.trailing, Self.linkGutter)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Self.cardHeight, alignment: .top)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isChosen ? accent.opacity(0.10) : Color.secondary.opacity(0.06)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isChosen ? accent.opacity(0.45) : Color.secondary.opacity(0.16)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!WelcomeThemeStep.isPressable(state))
            .help(WelcomeThemeStep.isPressable(state)
                ? (isChosen ? "Already your icons" : "Use " + choice.name)
                : Self.line(state))
            .onHover { hovering in
                guard WelcomeThemeStep.isPressable(state) else { return }
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }

            if let url = Self.storeURL(for: choice, entry: entry(for: choice)) {
                Link(destination: url) {
                    Label(Self.storeLink, systemImage: "arrow.up.right.square")
                        .font(.system(size: 10.5))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.link)
                .help("Open " + choice.name + " in the registry")
                .padding(10)
            }
        }
    }

    /// What the store link says, and the room the report leaves for it.
    static let storeLink = "See the icons"
    static let linkGutter: CGFloat = 96

    /// The mark and the name. Two states of one symbol rather than a mark
    /// that appears and disappears, so a card whose header is picked does
    /// not move the row under it.
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

    /// The pack's own icon, drawn from the index and not from a download.
    ///
    /// Every extension in the registry publishes its icon as its card icon
    /// and the index carries those bytes inline, so both packs show their
    /// own artwork while neither is installed. `ExtensionIconView` prefers
    /// the file where there is one, which is what an installed pack has.
    @ViewBuilder
    private func artwork(_ choice: Choice) -> some View {
        if let entry = entry(for: choice) {
            ExtensionIconView(source: store.icon(for: entry), size: Self.artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
                .frame(width: Self.artworkSize, height: Self.artworkSize)
                .overlay(
                    Image(systemName: Self.symbol(for: choice))
                        .font(.system(size: Self.artworkSize * 0.5))
                        .foregroundStyle(.tertiary))
        }
    }

    /// The stand-in for a card with no artwork to draw.
    ///
    /// The card that installs nothing has none by construction, and wears
    /// the mark the explorer's own gear menu puts beside SF Symbols. A pack
    /// whose entry has not arrived wears a grid, not
    /// `ExtensionIconView`'s puzzle piece: the puzzle is the mark for
    /// artwork that failed to load, and this one has no artwork to fail.
    static func symbol(for choice: Choice) -> String {
        choice.id == nil ? "textformat" : "square.grid.2x2"
    }

    /// The pack's own page in the registry, which is where a reader goes to
    /// see the icons — this step draws none of them.
    ///
    /// The index carries it as `homepage`, written by the registry as the
    /// extension's directory in its repository. It falls back to the
    /// registry's front page so the link works before the index has
    /// arrived, and the card that installs nothing has no page at all.
    static func storeURL(for choice: Choice, entry: ExtensionIndex.Entry?) -> URL? {
        guard choice.id != nil else { return nil }
        return entry?.homepage ?? ExtensionsSettingsView.registryURL
    }

    // MARK: What a card says

    /// Everything three stores know about one card, gathered so that reading
    /// them can be a function of its arguments and nothing else.
    struct Facts: Equatable {
        var index: ExtensionIndex?
        var indexError: String?

        var isInstalled = false
        var activity: ExtensionActivity?

        var installError: String?
        var applyError: String?

        /// The extension whose pack the explorer draws with, and nil when it
        /// draws SF Symbols — whichever card that is and whether or not it
        /// is one of these three.
        var appliedID: String?

        var chosen: String? = WelcomeIconPacks.preselected
    }

    /// What a card says.
    ///
    /// The order of the checks is ``WelcomeThemeStep/state(of:from:)``'s,
    /// unchanged and for its reasons: what is running answers first because
    /// it is the newest fact, a failure answers ahead of `inUse` so a reader
    /// who lost the network is told rather than reassured, and what is on
    /// disk answers before the catalogue so an offline reader can still
    /// apply a pack they already have.
    ///
    /// The card that installs nothing is read first and separately. It has
    /// no entry to find and no download to fail, so the three answers a
    /// registry can give would all be lies about it.
    static func state(of choice: Choice, from facts: Facts) -> WelcomeThemeState {
        guard let id = choice.id else {
            return facts.appliedID == nil ? .inUse : .offered
        }

        if let activity = facts.activity { return .working(activity) }
        if let reason = facts.installError ?? facts.applyError { return .failed(reason) }
        if facts.appliedID == id { return .inUse }
        if facts.isInstalled {
            return facts.chosen == id ? .chosen(isInstalled: true) : .installed
        }
        guard let index = facts.index else {
            return facts.indexError.map(WelcomeThemeState.unreachable) ?? .searching
        }
        guard index.extensions.contains(where: { $0.id == id }) else { return .unlisted }
        return facts.chosen == id ? .chosen(isInstalled: false) : .offered
    }

    /// The same nine states in the words an icon pack goes by. A pack does
    /// not colour a window and is not "the theme in use", so the two
    /// vocabularies differ where the subject does and nowhere else.
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
            return WelcomeThemeStep.progress(activity)
        case .installed:
            return "Installed, and not the pack in use."
        case .inUse:
            return "Drawing every file explorer."
        case .failed(let reason):
            return reason
        }
    }

    // MARK: Reading the stores

    private func entry(for choice: Choice) -> ExtensionIndex.Entry? {
        guard let id = choice.id else { return nil }
        return store.index?.extensions.first { $0.id == id }
    }

    private func state(of choice: Choice) -> WelcomeThemeState {
        Self.state(of: choice, from: Facts(
            index: store.index,
            indexError: store.lastRefreshError,
            isInstalled: choice.id.map { id in store.installed.contains { $0.id == id } } ?? false,
            activity: choice.id.flatMap { store.activity[$0] },
            installError: choice.id.flatMap { store.errors[$0] },
            applyError: choice.id.flatMap { selection.applyFailures[$0] },
            appliedID: selection.appliedID,
            chosen: selection.chosen))
    }
}

/// What the icon pack row has picked, and the one place that makes it real.
///
/// Held by `WelcomeView` beside `WelcomeThemeSelection` and for that type's
/// reasons: Next is a button in the window's own bottom bar, and SwiftUI
/// throws a step's `@State` away when the window switches steps, so a reader
/// who stepped back and forward again would find a failure message gone and
/// a running install unaccounted for.
@MainActor
final class WelcomeIconPackSelection: ObservableObject {
    /// Which card has the mark, and nil for the card that installs nothing.
    @Published private(set) var chosen: String? = WelcomeIconPacks.preselected

    /// What *applying* failed at, per extension. Kept apart from
    /// `ExtensionStore.errors`, which is where the install failed — two
    /// failures with two repairs, and the store's one is shared with the
    /// Extensions pane.
    @Published private(set) var applyFailures: [String: String] = [:]

    /// The extension whose pack the explorer draws with, or nil when it
    /// draws SF Symbols or a pack the reader dropped in a folder themselves.
    var appliedID: String? {
        Self.appliedID(
            iconThemes: LanguageResolver.shared.catalog.iconThemes,
            selectedName: FileIconProvider.shared.selectedName)
    }

    /// Which installed extension the `FileExplorerIconTheme` selection points
    /// into.
    ///
    /// Folded, for the reason `FileIconProvider.themes(inDirectories:)`
    /// folds: the stored spelling and the manifest's own may differ in case,
    /// which is exactly what a reader who selected the bundled `symbols`
    /// before it was removed and then installed the extension's `Symbols`
    /// has. Compared raw, their pack would read as not in use while it drew
    /// every row.
    static func appliedID(
        iconThemes: [LanguageCatalog.ContributedIconTheme],
        selectedName: String
    ) -> String? {
        guard selectedName != FileIconProvider.symbolsOnly else { return nil }
        let folded = IconTheme.folded(selectedName)
        return iconThemes.first { IconTheme.folded($0.iconTheme.name) == folded }?.listIdentity
    }

    /// A card press: the mark moves, and the pack is fetched and applied.
    func press(_ choice: WelcomeIconPacks.Choice) async {
        chosen = choice.id
        await use(choice)
    }

    /// What going on does: the chosen card's own work, and only what is left
    /// of it.
    ///
    /// Started and not waited for, so a reader can leave this step with a
    /// slow download still running. The card that installs nothing does
    /// nothing here — a step nobody answered must not change what the
    /// explorer draws, and pressing that card is how a reader asks for SF
    /// Symbols on purpose.
    func goOn() {
        guard let choice = WelcomeIconPacks.choices.first(where: { $0.id == chosen }),
              let id = choice.id,
              appliedID != id
        else { return }
        Task { await use(choice) }
    }

    /// Fetches what is not on disk, then applies it.
    ///
    /// Idempotent: a second press of a pack already in use costs one
    /// re-apply and no download, and a press during an install is ignored
    /// rather than queued behind it. It stops at the first thing that failed
    /// and leaves the reason where the card can read it.
    func use(_ choice: WelcomeIconPacks.Choice) async {
        guard let id = choice.id else {
            FileIconProvider.shared.select(FileIconProvider.symbolsOnly)
            return
        }

        let store = ExtensionStore.shared
        guard store.activity[id] == nil else { return }
        applyFailures[id] = nil

        if !store.installed.contains(where: { $0.id == id }) {
            guard let entry = store.index?.extensions.first(where: { $0.id == id }) else {
                applyFailures[id] = store.lastRefreshError ?? Self.notListed(choice)
                return
            }
            await store.install(entry)
            guard store.errors[id] == nil else { return }
        }

        apply(choice)
    }

    /// Selects the pack the extension contributes, which is the whole of
    /// applying one: `FileIconProvider.select` writes the same key the
    /// explorer's gear menu writes and repaints every explorer on screen.
    ///
    /// Every guard reports rather than passes. Selecting a pack that draws
    /// nothing would leave the next launch pointed at a name it resolves to
    /// no artwork, which is worse than saying so here.
    ///
    /// The provider is reloaded first. It learns about new packs from
    /// `LanguageResolver.$catalog`, which publishes before the catalogue it
    /// announces is readable, so the pack just installed is not in `themes`
    /// yet and the selection would resolve to nothing.
    private func apply(_ choice: WelcomeIconPacks.Choice) {
        guard let id = choice.id else { return }

        guard let contributed = LanguageResolver.shared.catalog.iconThemes
            .first(where: { $0.listIdentity == id })
        else {
            applyFailures[id] = Self.noPack(choice)
            return
        }

        guard IconTheme.load(
            directory: contributed.iconTheme.directoryURL,
            name: contributed.iconTheme.name,
            contributedBy: contributed.extensionName)?.isSupported == true
        else {
            applyFailures[id] = Self.unreadable(choice)
            return
        }

        FileIconProvider.shared.reload()
        FileIconProvider.shared.select(contributed.iconTheme.name)
    }

    /// Pressing Next on a pack the catalogue does not offer, which is the one
    /// path that reaches an unlisted pack — the card for one cannot be
    /// pressed.
    static func notListed(_ choice: WelcomeIconPacks.Choice) -> String {
        choice.name + " is not in the registry, so there is nothing to install."
    }

    static func noPack(_ choice: WelcomeIconPacks.Choice) -> String {
        choice.name + " installed, but it contributes no icon pack."
    }

    static func unreadable(_ choice: WelcomeIconPacks.Choice) -> String {
        choice.name + " installed, but it draws no icons."
    }
}

/// The line under a welcome card: what has happened to the extension it
/// names, and — on a failure — how to have another go at it.
///
/// Shared by the theme cards and the icon pack cards, which report the same
/// states in different words. The words arrive resolved so the drawing is
/// one thing in one place: two copies of this diverged the moment one of
/// them grew a progress spinner.
struct WelcomeExtensionReport: View {
    let state: WelcomeThemeState
    let line: String

    @ObservedObject private var palette: ThemePalette = .shared

    /// The theme's own red where there is one, so a failure warms to the
    /// palette the reader chose rather than to the one SwiftUI ships.
    private var failure: Color { palette.danger ?? .red }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if case .working = state {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 10, height: 10)
                }

                Text(line)
                    .font(.system(size: 11))
                    .foregroundStyle(WelcomeThemeStep.isFailure(state) ? failure : Color.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            if WelcomeThemeStep.isFailure(state) {
                Text(WelcomeThemeStep.retry)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
