import AppKit
import Combine
import SwiftUI

/// The file explorer panel: the workspace tree for whichever terminal is
/// selected.
struct FileExplorerView: View {
    @ObservedObject var tabManager: SidebarTabManager
    @ObservedObject var store: SidebarGroupStore

    /// Opens a terminal beside the selected one; every file opened here
    /// gets its own. See `FileOpener.openInTerminal`.
    var onSpawnTerminal: () -> Ghostty.SurfaceView? = { nil }

    /// Opens the file in this window's editor pane.
    var onOpenInEditor: (URL) -> Void = { _ in }

    /// The pane's open files, so the tree can say which one is on screen.
    ///
    /// Without it the only highlighted row was the terminal's working
    /// directory, and a reader looking at a file had no way to tell which of
    /// forty names in the tree it was.
    @ObservedObject var editorCenter: EditorCenter

    @StateObject private var model = FileExplorerModel()
    @ObservedObject private var palette: ThemePalette = .shared
    @ObservedObject private var icons: FileIconProvider = .shared
    @ObservedObject private var refresh: FileExplorerRefresh = .shared
    @ObservedObject private var shortcuts: PhantomShortcutStore = .shared

    /// Whether the tree owns the keyboard. Keys like Return and Delete only
    /// mean rename and trash while the explorer is the one being typed at.
    @FocusState private var treeFocused: Bool

    /// The path waiting for the "Move to Trash" confirmation.
    @State private var pendingDelete: String?

    /// Whether the filter panel under the search field is open.
    ///
    /// Closed until asked for, and remembered afterwards. Most searches
    /// never need it, and a panel that is always on screen would push the
    /// tree down for every reader to buy something few of them use. Closed
    /// means gone — there is no header row left behind, which is what the
    /// button beside the search field is for.
    @AppStorage(FileExplorerModel.filtersExpandedKey) private var filtersExpanded = false

    /// The file a reveal still owes a scroll to, or nil when nothing is
    /// pending.
    ///
    /// Held for one reason: a row inside a folder that had never been listed
    /// does not exist yet, and the listing lands off the main actor a moment
    /// later. Cleared as soon as the scroll happens, which is what keeps the
    /// reveal an event — a folder the reader collapses afterwards stays
    /// collapsed, because nothing remembers it was ever revealed.
    @State private var revealTarget: String?

    private var selectedTab: SidebarTabModel? {
        tabManager.models.first { $0.isSelected }
    }

    private func surface(for tab: SidebarTabModel?) -> Ghostty.SurfaceView? {
        guard let controller = tab?.window?.windowController as? BaseTerminalController
        else { return nil }
        return controller.focusedSurface ?? controller.surfaceTree.root?.leftmostLeaf()
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if model.root == nil {
                empty
            } else {
                search
                if filtersExpanded {
                    filters
                }
                tree
            }
        }
        .onAppear {
            model.onRootModeChanged = syncRoot
            syncRoot()
        }
        .onChange(of: tabManager.groupingVersion) { _ in syncRoot() }
        .onChange(of: refresh.token) { _ in model.reloadVisible() }
        .onReceive(
            Publishers.MergeMany(tabManager.models.map { $0.objectWillChange })
        ) { _ in
            DispatchQueue.main.async { syncRoot() }
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("You can restore it from the Trash later.")
        }
        .alert(
            "Couldn't do that",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var deleteTitle: String {
        guard let pendingDelete else { return "Move to the Trash?" }
        return "Move “\((pendingDelete as NSString).lastPathComponent)” to the Trash?"
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            Text(model.root?.lastPathComponent ?? "No Folder")
                .font(palette.font(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.head)

            Spacer(minLength: 0)

            SidebarIconMenu(help: "New File or Folder", icon: "plus") {
                Button("New File") { model.beginCreateDefault(isFolder: false) }
                Button("New Folder") { model.beginCreateDefault(isFolder: true) }
            }

            SidebarIconMenu(help: model.rootMode.detail) {
                Picker("Root", selection: $model.rootMode) {
                    ForEach(WorkspaceRootMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.inline)

                Divider()

                Toggle("Show Hidden Files", isOn: $model.showHiddenFiles)

                /// Drawn even with no pack installed, which is now the state a
                /// fresh install opens in: the app bundles none. The guard
                /// that hid this menu was written when a pack always shipped,
                /// where an empty list meant an impossible choice — it now
                /// hides the choice at the one moment a reader needs to be
                /// told it exists.
                Menu("Icon Theme") {
                    /// `active`, not `selectedName`. A reader who selected the
                    /// bundled pack before it was removed has `symbols`
                    /// stored and is looking at SF Symbols, so the stored name
                    /// would mark a row for a pack that draws nothing here.
                    /// `active` is what the explorer resolved and therefore
                    /// what the menu exists to report.
                    Button {
                        icons.select(FileIconProvider.symbolsOnly)
                    } label: {
                        IconThemeMenuLabel(
                            title: "SF Symbols",
                            symbol: "textformat",
                            isInUse: icons.active == nil)
                    }

                    if !icons.themes.isEmpty {
                        Divider()
                        ForEach(icons.themes, id: \.name) { theme in
                            Button { icons.select(theme.name) } label: {
                                IconThemeMenuLabel(
                                    title: theme.displayName,
                                    artwork: icons.artwork(for: theme),
                                    isInUse: icons.active?.foldedName == theme.foldedName)
                            }
                            .disabled(!theme.isSupported)
                        }
                    }

                    Divider()

                    /// An offer, not a state, and the only route from this
                    /// panel to the store. A reader who skipped the tour and
                    /// never opens Settings has no other way to learn that
                    /// icon packs exist. It goes where `WelcomeIconPacks`
                    /// sends a reader whose pack has no page of its own yet.
                    Button {
                        NSWorkspace.shared.open(ExtensionsSettingsView.registryURL)
                    } label: {
                        Label("Get Icon Packs…", systemImage: "arrow.up.right.square")
                    }
                }

                Divider()

                Button("Choose Editor App…") {
                    FileOpener.chooseApp(in: NSApp.keyWindow) { _ in }
                }
                if FileOpener.preferredApp != nil {
                    Button("Forget Editor App") { FileOpener.clearPreferredApp() }
                }
            }
        }
        .foregroundStyle(.secondary)
        // Sized from the chip metrics, same as the Git panel's header, so
        // the two panels' menus sit at the same height and their
        // highlights keep the same margin.
        .frame(height: SidebarIconChipMetrics.rowHeight)
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text("No folder for this terminal")
                .font(palette.captionFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    // MARK: Tree

    /// The search row: the field, and the button that opens the filters
    /// under it.
    private var search: some View {
        HStack(spacing: 4) {
            searchField
            filterButton
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.bottom, 4)
    }

    /// The search field, always there.
    ///
    /// No submit button and no disclosure: a field you have to reveal before
    /// you can use it is a field you forget exists, and one you have to press
    /// Return in makes you wait to find out you typed the wrong thing. It
    /// filters as you type, debounced in the model.
    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            TextField("Search files", text: $model.filter)
                .textFieldStyle(.plain)
                .font(palette.font(size: 11))

            if model.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
            } else if !model.filter.isEmpty {
                Button {
                    model.filter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.12))
        )
    }

    /// The button that shows and hides the filter panel, wearing the accent
    /// while a closed panel is still filtering. See
    /// `FileExplorerFilterButton` for what it draws and why.
    private var filterButton: some View {
        let button = FileExplorerFilterButton.resolve(
            isExpanded: filtersExpanded,
            activeFilterCount: model.excludes.patterns.count
        )

        return SidebarIconButton(
            help: button.help,
            action: { filtersExpanded.toggle() },
            label: {
                Image(systemName: button.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        button.isAccented
                            ? AnyShapeStyle(palette.accent ?? .accentColor)
                            : AnyShapeStyle(.secondary)
                    )
            }
        )
    }

    /// The filter panel: one labelled row per filter, stacked on a card
    /// that points back at the button, and nothing at all while it is
    /// closed.
    ///
    /// A stack rather than a field with a title bolted on, so the next
    /// filter is a row here and not a redesign. Excludes is the only one
    /// today, and it earns no special place for that.
    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            filterRow("Excludes", inForce: model.excludes.patterns.count) {
                excludes
            }
        }
        .padding(.top, FileExplorerFilterPanelShape.pointerHeight + 8)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .background(filterCard)
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.bottom, 8)
    }

    /// The card behind the filters, wearing the sidebar's own card fill and
    /// border so it reads as a surface on top of the panel rather than as
    /// more of it.
    ///
    /// The pointer is aimed at the middle of the filter button, which the
    /// card can name without measuring anything: the two share a trailing
    /// edge, so the middle of the button is half a chip in from it.
    private var filterCard: some View {
        let shape = FileExplorerFilterPanelShape(
            pointerInset: SidebarIconChipMetrics.width / 2
        )

        return shape
            .fill(Color.secondary.opacity(0.08))
            .overlay(shape.stroke(Color.secondary.opacity(0.16), lineWidth: 1))
    }

    /// One filter: its name, how many of it are in force, and its control.
    private func filterRow<Content: View>(
        _ title: String,
        inForce: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(title)
                    .font(palette.font(size: 10, weight: .semibold))
                    .textCase(.uppercase)

                if inForce > 0 {
                    SidebarCountBadge(count: inForce)
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)

            content()
        }
    }

    /// The excludes control: one line of comma-separated glob patterns, and
    /// a chip for each pattern that took effect.
    ///
    /// The chips are the field's only feedback, and they are the reason the
    /// field can stay one line. A pattern that did not compile has no chip,
    /// so `(build|dist` and `*.{ts` say what is wrong by being absent, and
    /// nothing has to be explained in prose next to an input.
    private var excludes: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("node_modules, *.log, (build|dist)/**", text: $model.excludeText)
                .textFieldStyle(.plain)
                .font(palette.font(size: 11))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.12))
                )

            if !model.excludes.isEmpty {
                WrapLayout(horizontalSpacing: 4, verticalSpacing: 3) {
                    ForEach(model.excludes.patterns) { pattern in
                        excludeChip(pattern)
                    }
                }
            }
        }
    }

    /// One pattern, with the click that drops it.
    ///
    /// The whole chip is the button rather than the cross alone. A target
    /// this size in a sidebar this narrow is hard enough to hit once; making
    /// the reader hit the smaller half of it twice is how a pattern stays in
    /// force longer than it was wanted.
    private func excludeChip(_ pattern: FileExplorerSearchExcludes.Pattern) -> some View {
        Button {
            model.removeExclude(pattern)
        } label: {
            HStack(spacing: 3) {
                Text(pattern.source)
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .semibold))
            }
            .font(palette.font(size: 9))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary.opacity(0.6))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Stop excluding \(pattern.source)")
    }

    /// The directory to show beside a name, on every search result.
    ///
    /// It used to appear only where two matches shared a name, on the theory
    /// that a path on every row is noise. Using it says otherwise: a flat
    /// list of names strips the one thing that tells you *which* file you are
    /// about to open, and having to notice a collision before the folder
    /// appears means the reader is doing the disambiguating the list was
    /// meant to do. Repeated paths read as a column; a path that comes and
    /// goes reads as a glitch.
    ///
    /// Still search-only. The tree already shows where a file is by where it
    /// sits, so a folder name beside it there would be saying it twice.
    private func ghostPath(for row: FileRow) -> String? {
        guard model.matches != nil, let root = model.root else { return nil }

        let directory = (row.node.path as NSString).deletingLastPathComponent
        guard directory.hasPrefix(root.path) else { return directory }
        let relative = String(directory.dropFirst(root.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? nil : relative
    }

    /// The rows to show: matches while searching, the tree otherwise.
    private var visibleRows: [FileRow] {
        model.matches ?? model.rows
    }

    private var tree: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: FileExplorerRow.rowGap) {
                    if let matches = model.matches, matches.isEmpty, !model.isSearching {
                        Text("No files match \"\(model.filter)\"")
                            .font(palette.font(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }

                    ForEach(visibleRows) { row in
                        rowView(row).id(row.id)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
                .background(alignment: .top) { OverlayScrollers() }
            }
            // Hidden rather than automatic: the modifier does not reach the
            // overlay scroller `OverlayScrollers` installs, so the bar still
            // appears while scrolling and fades after. Asking for an
            // indicator only has SwiftUI reserve the band a legacy one takes.
            .scrollIndicators(.hidden)
            .onChange(of: model.currentDirectory) { path in
                guard let path else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    /// No anchor: `scrollTo` then moves the least it can to
                    /// bring the row into view, and leaves the list alone when
                    /// the row is already there. Centring instead re-scrolled
                    /// on every change, which is what made a click feel
                    /// mechanical — the row you aimed at jumped to the middle
                    /// under the pointer.
                    proxy.scrollTo(path)
                }
            }
            .onChange(of: model.editing) { _ in
                guard let id = model.createPlaceholderID else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    /// Centred, unlike the others: a name field that opens
                    /// at the very bottom of a long folder is half off screen
                    /// with a minimal scroll, and there is nothing to preserve
                    /// about a position the reader is about to type into.
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onChange(of: editorCenter.tabs.selectedPath) { path in
                revealOpenFile(path, using: proxy)
            }
            .onChange(of: model.rows) { _ in
                guard let target = revealTarget else { return }
                scrollToReveal(target, using: proxy)
            }
            /// Clearing the search is what pays the scroll a search deferred.
            /// Watched as a `Bool` rather than on the matches themselves: the
            /// question is only whether the tree is back, and every keystroke
            /// in that field rebuilds the array.
            .onChange(of: model.matches == nil) { isTree in
                guard isTree, let target = revealTarget else { return }
                scrollToReveal(target, using: proxy)
            }
            // A create field lands at the end of a possibly long folder, so
            // it can start below the fold; make sure the keys the explorer
            // answers for have somewhere to land.
            .onChange(of: model.editing) { editing in
                if editing != nil { treeFocused = true }
            }
            .focusable()
            .focused($treeFocused)
            // Focusable for the keys, without the ring: selecting a file put
            // a blue outline around the entire tree, which reads as the list
            // being a control you are editing rather than a place you are
            // looking at. The selected row already says where focus is.
            .backport.focusEffectDisabled()
            .backport.onKeyPress { press in handleKeyPress(press, using: proxy) }
            .dropDestination(for: URL.self) { urls, _ in
                handleDrop(urls, into: model.root?.path ?? "")
                return true
            }
        }
    }

    // MARK: Actions

    private func handleTap(_ row: FileRow) {
        guard !row.isTruncationNotice else { return }
        model.select(row.node.path)
        treeFocused = true

        if row.node.isDirectory {
            model.toggle(row.node)
            return
        }

        openFile(row.node.url)
    }

    /// Opens a file the same way whether a click or Space asked for it.
    ///
    /// Shared rather than repeated because "the same action a click performs"
    /// is the whole specification of Space here: this decides nothing itself,
    /// so the destination setting, the app fallback and the terminal it lands
    /// beside can only ever be answered once.
    private func openFile(_ url: URL) {
        FileOpener.prompt(
            for: url,
            in: selectedTab?.window,
            currentTerminal: surface(for: selectedTab),
            spawnTerminal: onSpawnTerminal,
            openInEditor: onOpenInEditor
        )
    }

    /// Opens the folders holding the file the pane just switched to, and
    /// scrolls its row into view.
    ///
    /// Answers the *change* of open file, never the file that is open: the
    /// highlight can only be seen if the row is on screen, and a reveal that
    /// ran on every redraw would re-open a folder the reader had deliberately
    /// collapsed, which is a worse thing than an unseen highlight.
    ///
    /// While a search is on, the list on screen is matches rather than the
    /// tree, so scrolling one of those into view would say nothing about
    /// where the file lives. The folders open anyway, so clearing the search
    /// — which is how most files reached from a search get opened — finds
    /// the tree already standing open at the right place.
    private func revealOpenFile(_ path: String?, using proxy: ScrollViewProxy) {
        revealTarget = nil
        guard let path else { return }

        model.expandAncestors(of: path)

        /// Set before the search is considered, so a file opened from a search
        /// result has its scroll owed rather than skipped. `scrollToReveal`
        /// declines to act while matches are on screen and is called again the
        /// moment they go.
        revealTarget = path
        scrollToReveal(path, using: proxy)
    }

    /// Scrolls to the file a reveal is waiting on, a runloop turn later.
    ///
    /// Never in the same turn: a row inside a folder that just opened does
    /// not exist until the rebuilt list has been through a render, and
    /// `scrollTo` an id the list doesn't hold does nothing at all. A folder
    /// that had never been listed takes longer than a turn — its rows arrive
    /// with the listing, off the main actor — which is why `rows` changing
    /// calls this again.
    ///
    /// The target is dropped once nothing is listing and the row still isn't
    /// there: a folder that couldn't be read yields no children and no row,
    /// and a file outside the tree never had one. Waiting forever would let
    /// an unrelated expansion, minutes later, jump the tree somewhere the
    /// reader didn't ask to go.
    ///
    /// A search does not drop it, it defers it. While the field has text the
    /// list on screen is matches rather than tree rows, so there is nothing to
    /// scroll to — but clicking a result is the single most common way a file
    /// deep in a tree gets opened, and the tree is where the reader looks
    /// next. So the target waits, and clearing the field spends it.
    private func scrollToReveal(_ target: String, using proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            guard revealTarget == target else { return }
            /// Kept, not cleared: the scroll is owed until the tree is what
            /// is on screen again. See `revealPendingTargetWhenSearchClears`.
            guard model.matches == nil else { return }
            guard model.rows.contains(where: { $0.id == target }) else {
                if model.loading.isEmpty { revealTarget = nil }
                return
            }

            revealTarget = nil
            /// Minimal, for the reason on `currentDirectory` above: a reveal
            /// should put the row on screen, not rearrange the list around it.
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(target)
            }
        }
    }

    /// The keys the explorer answers for while it has focus: the arrows and
    /// Space to walk the tree, the configured create shortcuts, Return to
    /// rename the selection, Delete to trash it.
    ///
    /// Delete was advertised in Settings — `ShortcutCollisionChecker` lists it
    /// under **Fixed** as "Move to Trash in the file explorer" — and did
    /// nothing. The key reached this method every time; the comparison was
    /// what failed, against the wrong character. See
    /// `FileExplorerKeyCommand.moveToTrashCharacter`, which is where both
    /// spellings now meet.
    private func handleKeyPress(
        _ press: BackportKeyPress,
        using proxy: ScrollViewProxy
    ) -> BackportKeyPressResult {
        guard model.editing == nil else { return .ignored }
        let modifiers = PhantomShortcut.modifiers(from: press.modifiers)

        /// Resolved against the whole map rather than the two explorer
        /// commands, so a combination the reader gave to an editor command
        /// falls through to the editor instead of being swallowed here.
        switch shortcuts.map.action(key: press.key, modifiers: modifiers) {
        case .newFile:
            model.beginCreateDefault(isFolder: false)
            return .handled
        case .newFolder:
            model.beginCreateDefault(isFolder: true)
            return .handled
        default:
            break
        }

        /// Bare keys only. An arrow carries the function-key flag and nothing
        /// else here, so `modifiers` — already narrowed to the four a shortcut
        /// can hold — is empty for the presses this owns, and ⇧⌥↑ goes on
        /// reaching the editor's Move Line Up.
        if modifiers.isEmpty, let key = FileTreeNavigation.Key(character: press.key) {
            return navigate(key, using: proxy)
        }

        /// `treeFocused` is redundant with the press having arrived at all —
        /// SwiftUI only delivers to the focused view — and is passed anyway,
        /// because "the explorer has focus" is the condition a test of a
        /// destructive command needs to be able to state and to falsify.
        guard let command = FileExplorerKeyCommand.resolve(
            character: press.key,
            hasFocus: treeFocused,
            isEditing: model.editing != nil,
            selection: model.selection
        ) else { return .ignored }

        switch command {
        case .rename(let path):
            model.beginRename(path: path)
        case .moveToTrash(let path):
            requestDelete(path)
        }
        return .handled
    }

    /// Walks the tree: `FileTreeNavigation` decides, this spends the answer.
    ///
    /// The rows handed over are the ones on screen — matches while a search is
    /// on — because every one of these keys is about what the reader can see.
    private func navigate(
        _ key: FileTreeNavigation.Key,
        using proxy: ScrollViewProxy
    ) -> BackportKeyPressResult {
        let navigation = FileTreeNavigation(
            rows: visibleRows,
            expanded: model.expanded,
            selection: model.selection
        )

        switch navigation.command(for: key) {
        case .nothing:
            break
        case .select(let path):
            model.select(path)
            /// Unanimated, unlike every other scroll here: a held arrow key
            /// repeats every few dozen milliseconds, and a fifth of a second
            /// of easing per step leaves the list trailing the row it is
            /// supposed to be following. Minimal for the reason on
            /// `currentDirectory` — a step through a list should move it as
            /// little as it takes to see the row.
            proxy.scrollTo(path)
        case .expand(let node), .collapse(let node):
            model.toggle(node)
        case .open(let node):
            openFile(node.url)
        }

        /// Handled even when nothing moved. These keys belong to the tree
        /// while the tree has focus, and letting a clamped ↓ through would
        /// scroll the list out from under the selection the reader is
        /// stepping through — the one thing they are watching.
        return .handled
    }

    /// Both commits ask the model whether the edit they belong to is still
    /// the live one.
    ///
    /// A field's focus loss arrives after the row it belonged to is gone, so
    /// a cancelled create and an already-committed rename can each deliver
    /// one more commit — against a placeholder that was never written, or a
    /// name that has already moved. The row only knows what it was told when
    /// it was last drawn; the model knows what is being asked for now.
    private func commitRename(_ row: FileRow, to name: String) {
        guard model.isEditing(.rename(path: row.node.path)) else { return }

        let result = model.commitRename(path: row.node.path, to: name)
        if case .success(let target) = result, target.path != row.node.path {
            editorCenter.repath(from: row.node.path, to: target.path)
        }
        treeFocused = true
    }

    private func commitCreate(parent: String, isFolder: Bool, name: String) {
        guard model.isEditing(.create(parent: parent, isFolder: isFolder)) else { return }

        let result = model.commitCreate(parent: parent, isFolder: isFolder, name: name)
        guard let created = FileExplorerModel.fileToOpen(after: result, isFolder: isFolder) else {
            treeFocused = true
            return
        }

        openFile(created)
    }

    /// One row, built in a function of its own.
    ///
    /// Inline in the `ForEach` this initializer's seventeen arguments are more
    /// than the SwiftUI type checker will solve — it gives up and fails the
    /// build rather than compiling slowly, which is what adding the menu's
    /// value to it did.
    @ViewBuilder
    private func rowView(_ row: FileRow) -> some View {
        FileExplorerRow(
            row: row,
            editing: model.editing,
            isExpanded: model.isExpanded(row.node),
            isCurrent: row.node.path == model.currentDirectory,
            isSelected: row.node.path == model.selection,
            ghostPath: ghostPath(for: row),
            isOpenInEditor: row.node.path == editorCenter.tabs.selectedPath,
            onTap: { handleTap(row) },
            onBeginRename: { model.beginRename(path: row.node.path) },
            onCommitRename: { name in commitRename(row, to: name) },
            onCommitCreate: { parent, isFolder, name in
                commitCreate(parent: parent, isFolder: isFolder, name: name)
            },
            onCancelEdit: { model.cancelEditing() },
            onDelete: { requestDelete(row.node.path) },
            onCreateFile: { model.beginCreate(in: row.node.path, isFolder: false) },
            onCreateFolder: { model.beginCreate(in: row.node.path, isFolder: true) },
            rowMenu: rowMenu(for: row.node),
            onDropInto: { urls in handleDrop(urls, into: row.node.path) }
        )
    }

    /// What a row's menu may offer, which for the split commands is a question
    /// about the editor rather than about the file.
    ///
    /// A file that is not open yet can still be opened into a split — the pane
    /// is divided around whatever is already there — so `canSplit` asks about
    /// the destination when the file is closed, and about the file's own cell
    /// when it is already open.
    private func rowMenu(for node: FileNode) -> FileExplorerRowMenu {
        let isOpen = editorCenter.isOpen(node.path)

        return FileExplorerRowMenu(
            availability: FileExplorerRowCommand.Availability(
                isDirectory: node.isDirectory,
                canSplit: isOpen
                    ? editorCenter.canSplitOut(.file(node.path))
                    : editorCenter.canSplitAnything,
                canReturnToMainPane: isOpen && !editorCenter.isInMainPane(node.path)),
            openInSplit: { editorCenter.openInSplit(node.url, zone: $0) },
            moveToMainPane: { editorCenter.moveToMainPane(.file(node.path)) })
    }

    private func requestDelete(_ path: String) {
        guard model.editing == nil else { return }
        pendingDelete = path
    }

    private func confirmDelete() {
        guard let path = pendingDelete else { return }
        pendingDelete = nil
        if case .success = model.delete(path: path) {
            editorCenter.didDelete(path: path)
        }
        treeFocused = true
    }

    /// Takes dropped items into a folder: the tree background into the root,
    /// a folder row into that folder.
    ///
    /// Only a move carries an open tab with it — see
    /// `FileExplorerModel.drop(path:into:)` for which drags move and which
    /// copy.
    private func handleDrop(_ urls: [URL], into directory: String) {
        guard !directory.isEmpty else { return }
        for url in urls where url.isFileURL {
            let result = model.drop(path: url.path, into: directory)
            if case .success(.moved(let target)) = result, target.path != url.path {
                editorCenter.repath(from: url.path, to: target.path)
            }
        }
    }

    /// Recomputes the root from the selected terminal, then points the
    /// highlight at wherever that terminal currently is.
    private func syncRoot() {
        let tab = selectedTab

        var groupRoot: String?
        if let tab,
           let group = store.resolveGroup(surfaceId: tab.surfaceId, pwd: tab.pwd),
           case .project(let root) = group.kind {
            groupRoot = root
        }

        model.setRoot(WorkspaceRootResolver.resolve(
            mode: model.rootMode,
            groupRoot: groupRoot,
            repoRoot: tab?.repoRoot,
            pwd: tab?.pwd
        ))
        model.reveal(tab?.pwd)
    }
}

/// One entry of the Icon Theme menu: the pack's name beside artwork the
/// pack itself draws, so the menu shows what picking it does.
///
/// A pack with no artwork gets no icon rather than a placeholder one. The
/// only packs that reach that branch are the font-based ones, which the
/// menu already draws disabled.
/// The row the explorer is drawing with carries a `checkmark`, which is the
/// whole of what the menu says about state.
///
/// Trailing, and conditional rather than reserved: this is the shape
/// `SidebarView.colorMenu` already uses for a hand-built menu whose rows
/// carry artwork — swatch, name, then the mark on the one in force. Nothing
/// ahead of the mark moves when it moves, so there is no leading space to
/// reserve, and two hand-built menus in one app mark the row in force the
/// same way.
private struct IconThemeMenuLabel: View {
    let title: String
    var artwork: NSImage?

    /// For the one row that stands for no pack at all, which has no artwork
    /// to draw and is not the artwork-less case above — that one is a pack
    /// that draws nothing.
    var symbol: String?

    let isInUse: Bool

    var body: some View {
        HStack {
            if let artwork {
                Image(nsImage: artwork)
            } else if let symbol {
                Image(systemName: symbol)
            }

            Text(verbatim: title)

            if isInUse { Image(systemName: "checkmark") }
        }
    }
}

/// One row of the tree.
private struct FileExplorerRow: View {
    let row: FileRow

    /// What the explorer is asking for a name for, if anything — lets this
    /// row know whether it is the one showing a field.
    let editing: FileEditState?
    let isExpanded: Bool
    let isCurrent: Bool
    let isSelected: Bool

    /// The containing folder, shown only when the name alone is ambiguous.
    let ghostPath: String?

    /// The file showing in the pane right now.
    ///
    /// Only this one is marked. Marking every open file as well turned the
    /// tree into a wall of highlight that answered a question nobody asked —
    /// the tab bar already says what is open, and the point of this mark is
    /// "here is where you are".
    let isOpenInEditor: Bool
    let onTap: () -> Void
    let onBeginRename: () -> Void
    let onCommitRename: (String) -> Void
    let onCommitCreate: (String, Bool, String) -> Void
    let onCancelEdit: () -> Void
    let onDelete: () -> Void
    let onCreateFile: () -> Void
    let onCreateFolder: () -> Void

    /// What the menu may offer for this row, and the two commands the editor
    /// answers. Handed in rather than read from the centre here: a row that
    /// observed the editor would redraw on every keystroke in an open file,
    /// and there is one of these per visible line of the tree.
    let rowMenu: FileExplorerRowMenu
    let onDropInto: ([URL]) -> Void

    @ObservedObject private var palette: ThemePalette = .shared
    @ObservedObject private var icons: FileIconProvider = .shared
    @State private var isHovered = false

    /// When this row was last clicked, or nil when the next click starts a
    /// fresh count. Read by `handleClick` to tell a double click from two
    /// singles.
    @State private var lastClickAt: TimeInterval?

    /// What the rename/create field holds while it is open.
    @State private var draftName = ""
    @State private var draftSelection: Range<String.Index>?
    @FocusState private var fieldFocused: Bool

    private var accent: Color { palette.accent ?? .accentColor }

    private var isRenaming: Bool { editing == .rename(path: row.node.path) }

    /// True only while the model is still asking for this name.
    ///
    /// Derived from `editing` rather than from the row alone: a placeholder
    /// row keeps saying it is one after Esc, and the field's focus loss then
    /// arrives at a `commit()` that took itself for a rename — of a file
    /// that was never created.
    private var isCreateField: Bool {
        guard row.isCreatePlaceholder, case .create(let parent, _) = editing else { return false }
        return parent == (row.node.path as NSString).deletingLastPathComponent
    }

    var body: some View {
        if row.isTruncationNotice {
            notice
        } else if isRenaming || isCreateField {
            field
        } else {
            content
        }
    }

    private var notice: some View {
        Text(row.node.name)
            .font(palette.font(size: 10))
            .foregroundStyle(.tertiary)
            .padding(.leading, indent + 18)
            .padding(.vertical, 3)
    }

    /// Only a folder can be dropped into.
    ///
    /// The drop target used to be every row, so releasing a drag half a row
    /// low asked the filesystem to move a file *inside* another file and
    /// surfaced whatever `FileManager` said about that — an error message
    /// about a gesture the tree should never have accepted in the first
    /// place.
    @ViewBuilder
    private var content: some View {
        if row.node.isDirectory {
            label.dropDestination(for: URL.self) { urls, _ in
                onDropInto(urls)
                return true
            }
        } else {
            label
        }
    }

    private var label: some View {
        Button(action: handleClick) {
            HStack(spacing: 4) {
                disclosure
                FileIconView(icon: icon)
                Text(row.node.name)
                    .font(palette.font(
                        size: 11,
                        weight: isCurrent || isOpenInEditor || isSelected ? .semibold : .regular
                    ))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let ghostPath {
                    Text(ghostPath)
                        .font(palette.font(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        // Truncated from the front: the folder nearest the
                        // file is the part that tells two of them apart.
                        .truncationMode(.head)
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, indent)
            .padding(.trailing, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(ring, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .contextMenu { menu }
        .help(row.node.path)
        .draggable(row.node.url)
    }

    /// The row drawn while a name is being given: the text field that
    /// replaces the label, and nothing else that can swallow a key.
    private var field: some View {
        HStack(spacing: 4) {
            disclosure
            FileIconView(icon: icon)
            BackportSelectionTextField("", text: $draftName, selection: $draftSelection)
                .textFieldStyle(.plain)
                .font(palette.font(size: 11))
                .focused($fieldFocused)
                .onAppear { startEditing() }
                .onSubmit { commit() }
                .onExitCommand { cancel() }
                .onChange(of: fieldFocused) { focused in
                    guard !focused else { return }
                    if isRenaming || isCreateField { commit() }
                }
            Spacer(minLength: 0)
        }
        .padding(.leading, indent)
        .padding(.trailing, 6)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Self.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(ringColor, lineWidth: 1)
        )
    }

    /// Opens the field on the part of the name the reader is being asked for:
    /// the whole of a proposal, everything before the extension of a real
    /// file. See `FileExplorerFilesystem.selectedRange(in:isFolder:isCreating:)`.
    private func startEditing() {
        draftName = row.node.name
        fieldFocused = true
        DispatchQueue.main.async {
            draftSelection = FileExplorerFilesystem.selectedRange(
                in: draftName,
                isFolder: row.node.isDirectory,
                isCreating: isCreateField
            )
        }
    }

    /// Commits whichever edit this row is showing, and nothing when it is
    /// showing none — the `else` that used to fall through to a rename is
    /// how a cancelled create ended up renaming a file that never existed.
    private func commit() {
        if isCreateField, case .create(let parent, let isFolder) = editing {
            onCommitCreate(parent, isFolder, draftName)
        } else if isRenaming {
            onCommitRename(draftName)
        }
    }

    private func cancel() {
        onCancelEdit()
    }

    @ViewBuilder
    private var disclosure: some View {
        if row.node.isDirectory {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 10)
        } else {
            Color.clear.frame(width: 10, height: 1)
        }
    }

    /// What this row's menu holds, separators included — one list, walked by
    /// both the right-click menu below and the double-click menu in
    /// `showMenu`.
    private var menuEntries: [FileExplorerRowMenuEntry] {
        FileExplorerRowCommand.menu(rowMenu.availability)
    }

    /// The row's own availability comes from the parent — see the property.

    /// Keyed by position rather than by entry: a menu with two separators in
    /// it has two entries that compare equal, and `ForEach` needs them apart.
    @ViewBuilder
    private var menu: some View {
        ForEach(Array(menuEntries.enumerated()), id: \.offset) { entry in
            switch entry.element {
            case .separator:
                Divider()
            case .command(let command):
                if command.isDestructive {
                    Button { perform(command) } label: {
                        Label(command.title, systemImage: command.icon)
                    }
                    .foregroundStyle(.red)
                } else {
                    Button { perform(command) } label: {
                        Label(command.title, systemImage: command.icon)
                    }
                }
            }
        }
    }

    /// Opens this row's menu at the pointer, which is what a double click on a
    /// row asks for.
    ///
    /// An `NSMenu` rather than the `.contextMenu` above, because SwiftUI gives
    /// no way to open one of those without a right-click — and built from
    /// `menuEntries` rather than written out a second time, so the two ways in
    /// cannot come to offer different things. It is the same machinery
    /// `.contextMenu` uses underneath, so it draws as a menu and not as a
    /// popover pretending to be one.
    ///
    /// Popped a runloop turn later, at a location read before the hop: `popUp`
    /// runs its own modal event loop, and starting one from inside a SwiftUI
    /// button action means re-entering the framework in the middle of its own
    /// update. The pointer has not moved by then — it takes a mouse-up to get
    /// here.
    private func showMenu() {
        let location = NSEvent.mouseLocation
        let menu = NSMenu()
        for entry in menuEntries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .command(let command):
                menu.addItem(
                    ClosureMenuItem(title: command.title, systemImage: command.icon) {
                        perform(command)
                    })
            }
        }

        DispatchQueue.main.async {
            menu.popUp(positioning: nil, at: location, in: nil)
        }
    }

    private func perform(_ command: FileExplorerRowCommand) {
        switch command {
        case .newFile:
            onCreateFile()
        case .newFolder:
            onCreateFolder()
        case .rename:
            onBeginRename()
        case .delete:
            onDelete()
        case .revealInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([row.node.url])
        case .copyPath:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(row.node.path, forType: .string)
        case .openLeading, .openTrailing, .openTop, .openBottom:
            guard let zone = command.zone else { return }
            rowMenu.openInSplit(zone)
        case .moveToMainPane:
            rowMenu.moveToMainPane()
        }
    }

    /// One click opens the row, two ask for its menu.
    ///
    /// The first click of a double click has already opened it — see
    /// `FileExplorerRowClick` for why that is the trade and not an oversight —
    /// and the second one deliberately does not open it again.
    private func handleClick() {
        let now = Date.timeIntervalSinceReferenceDate
        switch FileExplorerRowClick.resolve(
            at: now,
            previous: lastClickAt,
            interval: NSEvent.doubleClickInterval
        ) {
        case .open:
            lastClickAt = now
            onTap()
        case .menu:
            /// Forgotten rather than kept, so a third click opens the row
            /// again instead of reading as the second half of another pair.
            lastClickAt = nil
            showMenu()
        }
    }

    private var icon: FileIcon {
        row.node.isDirectory
            ? icons.icon(forFolder: row.node.name, expanded: isExpanded)
            : icons.icon(forFile: row.node.name, at: row.node.path)
    }

    /// The neutral surface the sidebar's cards are drawn on, and the radius
    /// they carry. A row is the smallest of those cards, so it takes the same
    /// two values.
    private static let surface = Color.secondary.opacity(0.08)

    static let cornerRadius: CGFloat = 6

    /// The gap between rows, so the list reads as items rather than as one
    /// block with lines drawn on it. Small: the tree is a hierarchy, and air
    /// between siblings past a point loosens what the indent is holding
    /// together.
    static let rowGap: CGFloat = 2

    /// The ring the selection and the open name field are both drawn with.
    private var ringColor: Color { accent.opacity(0.55) }

    /// What the row is painted with: the sidebar's neutral surface under the
    /// pointer, a tint of the accent under the open file, nothing otherwise.
    ///
    /// The open file's tint used to be `0.45`, a block of colour loud enough
    /// that a name field beside it read as a second selection. It only has to
    /// beat the neutral surface, not the ring.
    private var fill: Color {
        switch emphasis.fill {
        case .open: accent.opacity(0.18)
        case .hover: Self.surface
        case .none: .clear
        }
    }

    /// The selection, as a ring rather than a fill.
    ///
    /// Selection cannot simply be dropped — Return renames it, Delete moves it
    /// to the trash, and a new file lands beside it, so a tree with no
    /// selection is a tree where those three commands have nothing to act on.
    /// A ring is how it says so without a block of colour.
    private var ring: Color {
        emphasis.showsSelectionRing ? ringColor : .clear
    }

    private var emphasis: FileExplorerRowEmphasis {
        .resolve(
            isOpenInEditor: isOpenInEditor,
            isSelected: isSelected,
            isHovered: isHovered,
            isNaming: editing != nil
        )
    }

    private var indent: CGFloat {
        CGFloat(row.depth) * 12
    }
}

