import SwiftUI

struct ExtensionsPanelView: View {
    @ObservedObject private var store: ExtensionStore = .shared
    @ObservedObject private var palette: ThemePalette = .shared

    @State private var searchText = ""
    @State private var kind: ExtensionCatalogFilter.Kind = .all
    @State private var sort: ExtensionCatalogFilter.Sort = .name
    @State private var selectedID: String?
    @State private var hasLoaded = false

    var body: some View {
        let sections = catalog

        return VStack(spacing: 0) {
            ExtensionKindTabs(selection: $kind, counts: sections.counts, style: .compact)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 12)
            searchRow
            registryContent(sections)
        }
        .onAppear(perform: loadOnce)
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
        guard !hasLoaded else { return }
        hasLoaded = true
        store.reloadInstalled()
        Task { await store.refresh() }
    }

    private var searchRow: some View {
        HStack(spacing: 2) {
            search
            sortMenu
            refreshButton
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
    }

    private var refreshButton: some View {
        SidebarIconButton(help: "Reload the registry") {
            Task { await store.reload() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .disabled(store.isRefreshing)
    }

    private var sortMenu: some View {
        SidebarIconMenu(help: "Sort by " + sort.title, icon: "arrow.up.arrow.down") {
            Picker("Sort", selection: $sort) {
                ForEach(ExtensionCatalogFilter.Sort.allCases) { option in
                    Text(verbatim: option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
        }
    }

    private var search: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            TextField("Search extensions", text: $searchText)
                .textFieldStyle(.plain)
                .font(palette.font(size: 11))

            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
            } else if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
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

    @ViewBuilder
    private func registryContent(_ sections: ExtensionCatalogFilter.Sections) -> some View {
        if let index = store.index {
            if let error = store.lastRefreshError {
                Text(verbatim: error)
                    .font(palette.font(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
            }
            list(index, sections)
        } else if !store.isRefreshing, let error = store.lastRefreshError {
            failure(error)
        } else {
            ProgressView("Loading the registry…")
                .controlSize(.small)
                .font(palette.font(size: 11))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func failure(_ error: String) -> some View {
        VStack(spacing: 8) {
            Text("The registry could not be loaded.")
                .font(palette.font(size: 11))
            Text(verbatim: error)
                .font(palette.font(size: 10))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry") {
                Task { await store.refresh() }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func list(
        _ index: ExtensionIndex,
        _ sections: ExtensionCatalogFilter.Sections
    ) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if index.extensions.isEmpty {
                    message("The registry has no extensions yet.")
                } else if sections.isEmpty {
                    message(emptyMessage)
                } else if kind == .all {
                    let split = ExtensionCatalogGrouping.partitioned(sections.entries)
                    groups(split.leading)
                    orphans(sections)
                    groups(split.trailing)
                } else {
                    ForEach(sections.entries) { entry in
                        row(for: entry)
                    }
                    orphans(sections)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func groups(_ list: [ExtensionCatalogGrouping.Group]) -> some View {
        ForEach(list) { group in
            heading(group.title, systemImage: group.systemImage)
            ForEach(group.entries) { entry in
                row(for: entry)
            }
        }
    }

    @ViewBuilder
    private func orphans(_ sections: ExtensionCatalogFilter.Sections) -> some View {
        if !sections.orphans.isEmpty {
            heading("Installed, not in the registry", systemImage: "questionmark.folder")
            ForEach(sections.orphans) { installed in
                row(for: installed)
            }
        }
    }

    private func heading(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(palette.font(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private func row(for entry: ExtensionIndex.Entry) -> some View {
        ExtensionRow(
            subject: .entry(entry, state: store.state(for: entry)),
            style: .compact,
            icon: store.icon(for: entry),
            activity: store.activity[entry.id],
            error: store.errors[entry.id],
            isSelected: selectedID == entry.id,
            onOpen: {
                selectedID = entry.id
                ExtensionDocumentTabs.open(entry)
            },
            onInstall: { Task { await store.install(entry) } },
            onRemove: { Task { await store.remove(id: entry.id) } }
        )
        .contextMenu { openInSettings(id: entry.id) }
    }

    private func row(for installed: InstalledExtension) -> some View {
        ExtensionRow(
            subject: .orphan(installed),
            style: .compact,
            icon: installed.iconURL.map(ExtensionIconSource.file),
            activity: store.activity[installed.id],
            error: store.errors[installed.id],
            isSelected: selectedID == installed.id,
            onOpen: {
                selectedID = installed.id
                ExtensionDocumentTabs.open(installed: installed)
            },
            onInstall: {},
            onRemove: { Task { await store.remove(id: installed.id) } }
        )
        .contextMenu { openInSettings(id: installed.id) }
    }

    /// Offered only once the extension is installed, which is the same rule
    /// the store card and the Extensions pane apply. Nothing is configured
    /// about an extension that is not on this machine, so the item led to a
    /// list rather than to settings.
    @ViewBuilder
    private func openInSettings(id: String) -> some View {
        if store.installed.contains(where: { $0.id == id }) {
            Button {
                ExtensionDocumentTabs.openInSettings(id: id)
            } label: {
                Label("Open in Settings", systemImage: "gearshape")
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
            .font(palette.font(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }
}
