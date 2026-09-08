import AppKit
import SwiftUI

struct ExtensionsSettingsView: View {
    static let registryURL = URL(string: "https://github.com/ipetinate/phantom-extensions")!

    /// The search field's label and its placeholder, which are the same
    /// sentence — see `searchField`.
    static let searchLabel = "Search extensions"

    @ObservedObject private var store = ExtensionStore.shared
    @ObservedObject private var navigation = SettingsNavigation.shared

    @State private var searchText = ""
    @State private var kind: ExtensionCatalogFilter.Kind = .all
    @State private var sort: ExtensionCatalogFilter.Sort = .name

    /// The extension whose configuration form is open, if any. A path of
    /// ids rather than of values, so a registry reload underneath the form
    /// leaves it pointing at the new one rather than at a stale copy.
    @State private var path: [String] = []

    /// A row a deep link named that has no form to open — not installed, so
    /// there is nothing to configure and the useful answer is to show the
    /// reader where it is in the list.
    @State private var rowToReveal: String?

    @AppStorage(ExtensionViewHTTP.allowsPrivateNetworkKey) private var allowsPrivateNetwork = false

    var body: some View {
        NavigationStack(path: $path) {
            list
                .navigationDestination(for: String.self) { id in
                    ExtensionSettingsForm(extensionID: id)
                }
        }
    }

    private var list: some View {
        let sections = catalog

        return ScrollViewReader { proxy in
            Form {
                Section {
                    ExtensionKindTabs(selection: $kind, counts: sections.counts)
                        .padding(.vertical, 6)
                    headerRow
                        .padding(.vertical, 4)
                    if store.index != nil, let error = store.lastRefreshError {
                        Text(verbatim: error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                registryContent(sections)
                viewSection
                folderSection
            }
            .formStyle(.grouped)
            .navigationTitle("Extensions")
            .onAppear {
                load()
                consumeRequest()
                reveal(with: proxy)
            }
            .onChange(of: navigation.target) { _ in
                consumeRequest()
                reveal(with: proxy)
            }
        }
    }

    /// Answers a request to open this pane at one extension.
    ///
    /// An installed extension has a configuration form, so the request opens
    /// it — that is what every caller of this deep link is after: the editor
    /// banner about a server that will not start, and the store's own link
    /// beside an installed card. One that is not installed has no form, so
    /// the request only reveals its row in the list below.
    private func consumeRequest() {
        guard let target = navigation.target, target.section == .extensions else { return }
        navigation.target = nil

        guard let row = target.row,
              let id = SettingsNavigation.extensionID(fromRow: row)
        else {
            path = []
            return
        }

        guard store.installed.contains(where: { $0.id == id }) else {
            path = []
            /// A query left over from the last visit filters the list, and a
            /// row that is filtered out cannot be scrolled to.
            searchText = ""
            kind = .all
            rowToReveal = id
            return
        }

        path = [id]
    }

    private func reveal(with proxy: ScrollViewProxy) {
        guard let id = rowToReveal else { return }
        rowToReveal = nil
        /// Next turn of the loop, not this one: the row being asked for may
        /// not have been laid out until the filter reset above has been.
        DispatchQueue.main.async {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private var catalog: ExtensionCatalogFilter.Sections {
        ExtensionCatalogFilter.sections(
            entries: store.index?.extensions ?? [],
            installed: store.installed,
            query: searchText,
            kind: kind,
            sort: sort)
    }

    /// **The store decides whether there is anything to load, not this
    /// view.** The guard used to be a `@State` flag here, and SwiftUI throws
    /// this pane's state away every time the settings window changes
    /// section, so every visit reloaded the whole catalogue. See
    /// `ExtensionStore.loadIfNeeded` for what that cost.
    private func load() {
        Task { await store.loadIfNeeded() }
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            searchField
            sortMenu
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Refresh") {
                Task { await store.reload() }
            }
            .disabled(store.isRefreshing)
        }
    }

    /// The field the sidebar's Extensions panel already wears: one rounded
    /// box, one placeholder, the magnifier inside it.
    ///
    /// It used to be a bare `TextField("Search", …, prompt:)`, and a grouped
    /// `Form` draws a labelled control as its label on the left and its
    /// control on the right — so the row read as two labels, a bold `Search`
    /// facing a grey `Search extensions` across the width, with no field
    /// around either. `labelsHidden` drops the half that was never meant to
    /// be read, and the background gives the other half an edge.
    ///
    /// The label and the prompt then have to say the same thing, which is
    /// why one constant feeds both. Outside a `Form` a plain field draws its
    /// label as the placeholder, so the sidebar's needs no prompt; hiding
    /// the label here takes that placeholder with it, and the field came out
    /// boxed and empty.
    ///
    /// Not shared with `ExtensionsPanelView.search` yet: that one is sized
    /// for the sidebar — the palette font at 11pt, a 10pt magnifier, the
    /// refresh spinner inside the box — and one component carrying both type
    /// scales would be a parameter list, not a shape.
    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(Self.searchLabel, text: $searchText, prompt: Text(Self.searchLabel))
                .textFieldStyle(.plain)
                .labelsHidden()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.12))
        )
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(ExtensionCatalogFilter.Sort.allCases) { option in
                    Text(verbatim: option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort by " + sort.title)
    }

    // MARK: Registry

    @ViewBuilder
    private func registryContent(_ sections: ExtensionCatalogFilter.Sections) -> some View {
        if let index = store.index {
            listSections(index, sections)
        } else if !store.isRefreshing, let error = store.lastRefreshError {
            Section {
                LabeledContent {
                    Button("Retry") {
                        Task { await store.refresh() }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The registry could not be loaded.")
                        Text(verbatim: error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        } else {
            Section {
                HStack {
                    Spacer()
                    ProgressView("Loading the registry…")
                        .controlSize(.small)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func listSections(
        _ index: ExtensionIndex,
        _ sections: ExtensionCatalogFilter.Sections
    ) -> some View {
        if index.extensions.isEmpty {
            Section { message("The registry has no extensions yet.") }
        } else if sections.isEmpty {
            Section { message(emptyMessage) }
        } else if !sections.entries.isEmpty {
            if kind == .all {
                let split = ExtensionCatalogGrouping.partitioned(sections.entries)
                groupSections(split.leading)
                orphanSection(sections)
                groupSections(split.trailing)
                Section {
                    Text("Each extension is a zip published as a GitHub release of the registry. Phantom checks its digest against the index before unpacking it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    rows(sections.entries, row: entryRow)
                } header: {
                    Text("Registry")
                } footer: {
                    Text("Each extension is a zip published as a GitHub release of the registry. Phantom checks its digest against the index before unpacking it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                orphanSection(sections)
            }
        } else {
            orphanSection(sections)
        }
    }

    /// One section's rows, realised as the reader scrolls to them.
    ///
    /// A grouped `Form` lays out every row it is handed before it shows a
    /// frame. With 131 extensions installed, `onAppear` arrived 366 ms after
    /// the pane had built its rows — and because the sidebar highlight moves
    /// in the same turn of the loop, the window read as hung: the row was
    /// already selected while the pane still drew the section the reader had
    /// left. Inside the form's own scroll view a `LazyVStack` realises about
    /// twenty rows instead of all 131, and `onAppear` arrives 100 ms after
    /// the click. It is the shape `ExtensionsPanelView` already draws the
    /// same catalogue with.
    ///
    /// The stack has to draw what the form drew for its own rows: the
    /// separator between two of them, and the inset above and below each.
    /// Both were matched against a capture of the eager form. `ExtensionRow`
    /// dropped the `LabeledContent` from its form body for the same reason —
    /// that container takes its metrics from the enclosing form row, so
    /// inside a stack it drew every trailing control half a row above its
    /// own label. Replacing it did not itself make the eager form faster:
    /// `onAppear` still arrived at 343 ms to 381 ms, which is what pointed
    /// at the row count rather than the row.
    @ViewBuilder
    private func rows<Item: Identifiable, Row: View>(
        _ items: [Item],
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(items) { item in
                if item.id != items.first?.id { Divider() }
                row(item)
                    .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private func groupSections(_ list: [ExtensionCatalogGrouping.Group]) -> some View {
        ForEach(list) { group in
            Section {
                rows(group.entries, row: entryRow)
            } header: {
                Label(group.title, systemImage: group.systemImage)
            }
        }
    }

    @ViewBuilder
    private func orphanSection(_ sections: ExtensionCatalogFilter.Sections) -> some View {
        if !sections.orphans.isEmpty {
            Section {
                rows(sections.orphans, row: orphanRow)
            } header: {
                Text("Installed, not in the registry")
            } footer: {
                Text("Found in the extensions folder, but the registry no longer lists them — or never did, if they were copied in by hand.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyMessage: String {
        ExtensionCatalogFilter.emptyMessage(kind: kind, query: searchText)
    }

    private func message(_ text: String) -> some View {
        Text(verbatim: text)
            .foregroundStyle(.secondary)
    }

    // MARK: Contributed views

    /// The one decision about `http.request` that is the reader's to make.
    ///
    /// Off by default and stated in full, because switching it on is what
    /// lets an extension from a store talk to whatever is listening on this
    /// machine — a database, a dev server, a container's admin port — for as
    /// long as its window is open. It is also what an HTTP client is for
    /// when the API being developed is on `localhost`, which is why the
    /// answer is a switch rather than a refusal.
    ///
    /// What it does **not** unlock: the link-local metadata range
    /// (`169.254.0.0/16`, `fd00:ec2::254`), a `.internal` name, and every
    /// reserved range. Those are refused with this on, by every extension,
    /// always. See `ExtensionViewHTTP`.
    private var viewSection: some View {
        Section {
            Toggle("Let Views Reach This Machine", isOn: $allowsPrivateNetwork)
                .toggleStyle(.switch)
        } header: {
            Text("Extension Views")
        } footer: {
            Text("An extension's view runs in a sandboxed page that cannot open a socket, read a file or start a process. It asks Phantom to do each of those, and Phantom refuses anything the extension did not declare in its manifest. Files are limited to the folder of the terminal the sidebar follows and to the extension's own directory. Off, a view's HTTP requests reach the public internet only — localhost, your private network and your machine's own ports are refused. On, they are allowed, which is what an HTTP client needs to call an API you are running locally. Cloud metadata endpoints and reserved addresses stay refused either way.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Folder

    private var folderSection: some View {
        Section {
            LabeledContent("Extensions Folder") {
                HStack(spacing: 8) {
                    Text(verbatim: folderPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Button("Open Folder", action: openFolder)
                }
            }
            Link(destination: Self.registryURL) {
                Label("Registry", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.link)
        } footer: {
            Text("Extensions are installed into this folder, one directory per extension. The registry is a GitHub repository; its index lists every extension above and the zip each one installs from.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var folderPath: String {
        (GuiConfigStore.shared.extensionsDirURL.path as NSString).abbreviatingWithTildeInPath
    }

    private func openFolder() {
        let url = GuiConfigStore.shared.extensionsDirURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    // MARK: Rows

    private func entryRow(_ entry: ExtensionIndex.Entry) -> some View {
        HStack(spacing: 8) {
            ExtensionRow(
                subject: .entry(entry, state: store.state(for: entry)),
                style: .form,
                icon: store.icon(for: entry),
                activity: store.activity[entry.id],
                error: store.errors[entry.id],
                onOpen: { ExtensionDocumentTabs.open(entry) },
                onInstall: { Task { await store.install(entry) } },
                onRemove: { Task { await store.remove(id: entry.id) } }
            )
            configureButton(id: entry.id)
        }
        .id(entry.id)
    }

    private func orphanRow(_ installed: InstalledExtension) -> some View {
        HStack(spacing: 8) {
            ExtensionRow(
                subject: .orphan(installed),
                style: .form,
                icon: installed.iconURL.map(ExtensionIconSource.file),
                activity: store.activity[installed.id],
                error: store.errors[installed.id],
                onOpen: { ExtensionDocumentTabs.open(installed: installed) },
                onInstall: {},
                onRemove: { Task { await store.remove(id: installed.id) } }
            )
            configureButton(id: installed.id)
        }
        .id(installed.id)
    }

    /// The way into an extension's own settings, offered only once it is
    /// installed — a form about a binary that is not on this machine, and an
    /// override of arguments nothing reads, would be a screen with nothing
    /// true on it.
    @ViewBuilder
    private func configureButton(id: String) -> some View {
        if store.installed.contains(where: { $0.id == id }) {
            Button {
                path = [id]
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Configure this extension")
        }
    }
}
