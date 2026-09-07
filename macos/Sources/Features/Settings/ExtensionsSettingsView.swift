import AppKit
import SwiftUI

struct ExtensionsSettingsView: View {
    static let registryURL = URL(string: "https://github.com/ipetinate/phantom-extensions")!

    @ObservedObject private var store = ExtensionStore.shared
    @ObservedObject private var navigation = SettingsNavigation.shared

    @State private var searchText = ""
    @State private var kind: ExtensionCatalogFilter.Kind = .all
    @State private var sort: ExtensionCatalogFilter.Sort = .name
    @State private var hasRequestedRegistry = false

    /// The extension whose configuration form is open, if any. A path of
    /// ids rather than of values, so a registry reload underneath the form
    /// leaves it pointing at the new one rather than at a stale copy.
    @State private var path: [String] = []

    /// A row a deep link named that has no form to open — not installed, so
    /// there is nothing to configure and the useful answer is to show the
    /// reader where it is in the list.
    @State private var rowToReveal: String?

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
                folderSection
            }
            .formStyle(.grouped)
            .navigationTitle("Extensions")
            .onAppear {
                loadOnce()
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

    private func loadOnce() {
        guard !hasRequestedRegistry else { return }
        hasRequestedRegistry = true
        store.reloadInstalled()
        Task { await store.refresh() }
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $searchText, prompt: Text("Search extensions"))
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
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
                    ForEach(sections.entries) { entry in
                        entryRow(entry)
                    }
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

    @ViewBuilder
    private func groupSections(_ list: [ExtensionCatalogGrouping.Group]) -> some View {
        ForEach(list) { group in
            Section {
                ForEach(group.entries) { entry in
                    entryRow(entry)
                }
            } header: {
                Label(group.title, systemImage: group.systemImage)
            }
        }
    }

    @ViewBuilder
    private func orphanSection(_ sections: ExtensionCatalogFilter.Sections) -> some View {
        if !sections.orphans.isEmpty {
            Section {
                ForEach(sections.orphans) { installed in
                    orphanRow(installed)
                }
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
        kind == .all
            ? "No extension matches."
            : "No extension matches in " + kind.title + "."
    }

    private func message(_ text: String) -> some View {
        Text(verbatim: text)
            .foregroundStyle(.secondary)
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
