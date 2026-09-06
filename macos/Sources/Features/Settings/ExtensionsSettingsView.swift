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

    var body: some View {
        let sections = catalog

        return Form {
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
            consumeRequest()
            loadOnce()
        }
        .onChange(of: navigation.target) { _ in consumeRequest() }
    }

    private func consumeRequest() {
        guard navigation.target?.section == .extensions else { return }
        navigation.target = nil
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
                Task { await store.refresh() }
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
        }

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

    private func entryRow(_ entry: ExtensionIndex.Entry) -> ExtensionRow {
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
    }

    private func orphanRow(_ installed: InstalledExtension) -> ExtensionRow {
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
    }
}
