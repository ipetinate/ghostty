import Foundation

struct InstalledExtension: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let version: String
    let root: URL
    var publisher: String = ""
    var iconURL: URL?
}

enum ExtensionState: Equatable, Sendable {
    case notInstalled
    case installed(version: String)
    case updateAvailable(installed: String, available: String)
}

enum ExtensionActivity: Equatable, Sendable {
    case downloading(fraction: Double?)
    case verifying
    case installing
    case removing
}

enum PreviewState: Equatable, Sendable {
    case loading
    case ready(document: URL, base: URL)
    case unavailable(String)
}

@MainActor
final class ExtensionStore: ObservableObject {
    static let shared = ExtensionStore()

    static let indexURL = URL(
        string: "https://github.com/ipetinate/phantom-extensions/releases/download/index/index.json"
    )!

    @Published private(set) var index: ExtensionIndex?
    @Published private(set) var installed: [InstalledExtension] = []
    @Published private(set) var activity: [String: ExtensionActivity] = [:]
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var previews: [String: PreviewState] = [:]

    @Published private(set) var pendingRequirements: [String: [ExtensionRequirement]] = [:]
    @Published private(set) var viewerHTML: URL?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshError: String?

    private let extensionsDirOverride: URL?
    private let cachesDirOverride: URL?
    private var stagings: [String: Task<URL, Error>] = [:]

    init(extensionsDir: URL? = nil, cachesDir: URL? = nil) {
        self.extensionsDirOverride = extensionsDir
        self.cachesDirOverride = cachesDir
        reloadInstalled()

        guard cachesDir != nil || extensionsDir == nil else { return }
        let root = previewRoot
        Task.detached(priority: .utility) { ExtensionPreviewCache.evict(root: root) }
    }

    var extensionsDir: URL {
        extensionsDirOverride ?? GuiConfigStore.shared.extensionsDirURL
    }

    var cachesDir: URL {
        cachesDirOverride ?? GuiConfigStore.shared.cachesDirURL
    }

    var previewRoot: URL {
        ExtensionPreviewCache.root(cachesDir: cachesDir)
    }

    /// The catalogue, read once for the whole app.
    ///
    /// The two views that show it — the Extensions pane and the sidebar
    /// panel — used to hold this guard in a `@State` flag of their own, and
    /// SwiftUI destroys the pane's state when the settings window changes
    /// section. So every visit to Extensions rescanned the folder and
    /// refetched the index, and every value that published laid the list out
    /// again. Measured with 131 extensions installed: four full layout
    /// passes, the pane painting between 0.9 s and 1.2 s after the click —
    /// 1.5 s to 3.0 s on the sweep that reported it.
    ///
    /// What is installed stays current without this: `install`, `remove`
    /// and `reload` all rescan, and Refresh is how somebody picks up a
    /// folder they edited by hand.
    func loadIfNeeded() async {
        guard index == nil, !isRefreshing else { return }
        await reloadInstalledOffMainThread()
        await refresh()
    }

    /// Fetches the catalogue, and publishes what changed.
    ///
    /// `@Published` notifies on assignment rather than on change. Assigning
    /// the index already held, or clearing an error that was already nil,
    /// notified every row reading this store and bought a full layout pass
    /// of the list for nothing.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let fetched = try await Self.fetchIndex()
            if fetched != index { index = fetched }
            if lastRefreshError != nil { lastRefreshError = nil }
        } catch {
            lastRefreshError = Self.refreshMessage(for: error)
        }
    }

    func reloadInstalled() {
        publish(installed: Self.scanInstalled(in: extensionsDir))
    }

    /// The same scan, off the main thread.
    ///
    /// Reading the 131 manifests in the owner's folder costs 53 ms to 79 ms,
    /// and on the path that opens the Extensions pane that is time between
    /// the click and the first frame.
    func reloadInstalledOffMainThread() async {
        let directory = extensionsDir
        publish(installed: await Task.detached(priority: .userInitiated) {
            Self.scanInstalled(in: directory)
        }.value)
    }

    /// Publishes only a list that differs from the one already held.
    ///
    /// A rescan that finds the same 131 extensions is the common case, and
    /// republishing it laid every row out again for no visible change. See
    /// `refresh()` for the same rule on the catalogue.
    private func publish(installed scanned: [InstalledExtension]) {
        guard scanned != installed else { return }
        installed = scanned
    }

    /// The whole store, read again: the catalogue, what is installed, and
    /// the staged pages an icon may have been drawn from.
    ///
    /// `refresh()` fetches the index and stops there, which is not what a
    /// reader means by refreshing the store. A page staged earlier keeps
    /// answering for the version it was staged at, and `iconURL(for:)`
    /// prefers that copy over the index, so an extension whose page had been
    /// opened kept showing its old icon until the app was restarted.
    func reload() async {
        previews.removeAll()
        errors.removeAll()
        reloadInstalled()
        await refresh()
    }

    /// Downloads and installs, rather than installing whatever the preview
    /// cache happens to hold.
    ///
    /// It used to reuse the staged tree, which saved a download for anyone
    /// who read the page before pressing Install. That worked only while
    /// the page and the install came from one asset. The cache now holds
    /// the document bundle, which is not an extension, so an install
    /// fetches the installable asset every time.
    func install(_ entry: ExtensionIndex.Entry) async {
        guard activity[entry.id] == nil else { return }
        errors[entry.id] = nil
        activity[entry.id] = .verifying
        defer { activity[entry.id] = nil }

        let directory = extensionsDir
        do {
            try await ExtensionInstaller.install(
                entry,
                into: directory,
                progress: report(for: entry.id)
            )
            noteInstalledChanged()
            Task { await self.refreshRequirements(id: entry.id) }
        } catch {
            errors[entry.id] = Self.message(for: error)
            reloadInstalled()
        }
    }

    /// Forwards a step to the row, and only while the row is showing one.
    private func report(for id: String) -> @MainActor @Sendable (ExtensionActivity) -> Void {
        { [weak self] step in
            guard let self, self.activity[id] != nil else { return }
            self.activity[id] = step
        }
    }

    func remove(id: String) async {
        guard activity[id] == nil else { return }
        errors[id] = nil
        activity[id] = .removing
        defer { activity[id] = nil }

        let directory = extensionsDir
        let candidate = installed.first { $0.id == id }?.root
            ?? directory.appendingPathComponent(id, isDirectory: true)
        let outcome = await Task.detached(priority: .utility) {
            Result { try ExtensionInstaller.remove(at: candidate, in: directory) }
        }.value

        switch outcome {
        case .success:
            pendingRequirements[id] = nil
            noteInstalledChanged()
        case .failure(let error):
            errors[id] = Self.message(for: error)
            reloadInstalled()
        }
    }

    func manifestDirectory(for id: String) -> URL? {
        if let root = installed.first(where: { $0.id == id })?.root { return root }
        guard case .ready(let document, _)? = previews[id] else { return nil }
        return document.deletingLastPathComponent()
    }

    func refreshRequirements(id: String) async {
        guard let root = installed.first(where: { $0.id == id })?.root else {
            pendingRequirements[id] = nil
            return
        }
        let found = await Task.detached(priority: .utility) {
            ExtensionRequirements.probe(directory: root)
        }.value
        let missing = found.filter { !$0.isInstalled }
        pendingRequirements[id] = missing.isEmpty ? nil : missing
    }

    nonisolated static func requirementsBadge(_ missing: [ExtensionRequirement]) -> String? {
        switch missing.count {
        case 0: return nil
        case 1: return "Needs " + missing[0].program
        default: return "Needs \(missing.count) programs"
        }
    }

    private func noteInstalledChanged() {
        reloadInstalled()
        guard extensionsDirOverride == nil else { return }
        LanguageResolver.shared.reload()
        LSPCenter.shared.noteAvailabilityChanged()
    }

    // MARK: Preview

    func preview(_ entry: ExtensionIndex.Entry) async {
        let root = previewRoot
        let expected = ExtensionPreviewCache.directory(for: entry, root: root)
        guard shouldPreview(id: entry.id, expecting: expected) else { return }
        previews[entry.id] = .loading

        do {
            try await prepareViewer(in: root)
            let directory = try await stagedDirectory(for: entry)
            try await Task.detached(priority: .utility) {
                try ExtensionMediaGate.check(directory: directory)
            }.value
            previews[entry.id] = Self.previewState(directory: directory, root: root, preferring: entry.card?.document)
        } catch {
            previews[entry.id] = .unavailable(Self.message(for: error))
        }
    }

    func preview(installed: InstalledExtension) async {
        let root = previewRoot
        guard let manifest = LanguageManifest.load(directory: installed.root, scope: .user) else {
            previews[installed.id] = .unavailable(ExtensionPreviewCache.Failure.unreadableManifest.message)
            return
        }
        let expected = ExtensionPreviewCache.localDirectory(
            id: installed.id, version: installed.version, manifestDigest: manifest.digest, root: root)
        guard shouldPreview(id: installed.id, expecting: expected) else { return }
        previews[installed.id] = .loading

        do {
            try await prepareViewer(in: root)
            let digest = manifest.digest
            let directory = try await Task.detached(priority: .utility) {
                try ExtensionPreviewCache.mirror(installed: installed, manifestDigest: digest, root: root)
            }.value
            previews[installed.id] = Self.previewState(directory: directory, root: root)
        } catch {
            previews[installed.id] = .unavailable(Self.message(for: error))
        }
    }

    func forgetPreview(id: String) {
        previews[id] = nil
    }

    /// The icon and the name of one extension by id, wherever they are to be
    /// had: the registry index when it lists the extension, the installed
    /// copy otherwise.
    ///
    /// Asked by id rather than by entry because the callers have only an id:
    /// a document tab holds a `phantom-extension://` path, and the settings
    /// form is keyed on the id as well.
    func iconSource(forExtension id: String) -> ExtensionIconSource? {
        if let entry = index?.extensions.first(where: { $0.id == id }) { return icon(for: entry) }
        return installed.first { $0.id == id }?.iconURL.map(ExtensionIconSource.file)
    }

    func displayName(forExtension id: String) -> String? {
        if let installed = installed.first(where: { $0.id == id }) { return installed.name }
        guard let entry = index?.extensions.first(where: { $0.id == id }) else { return nil }
        return entry.card?.title ?? entry.name
    }

    func icon(for entry: ExtensionIndex.Entry) -> ExtensionIconSource? {
        ExtensionIconSource.of(entry: entry, file: iconURL(for: entry))
    }

    /// **The installed copy answers first.** It used to be the staged page,
    /// and that is how the store kept putting an old icon back: reading an
    /// extension's page downloads the version the index names and unpacks it
    /// into the preview cache, so from then on the row drew the icon of
    /// whatever version was published rather than the one on the machine.
    /// Elixir 1.1.1 was installed with the owner's logo and the store went
    /// back to the drawn one every time its page was opened.
    ///
    /// The staged tree still answers for an extension that is *not*
    /// installed, which is the case it exists for: showing an icon before
    /// anybody presses Install.
    func iconURL(for entry: ExtensionIndex.Entry) -> URL? {
        let onDisk = installed.first { $0.id == entry.id }
        guard let icon = entry.card?.icon else { return onDisk?.iconURL }
        if let root = onDisk?.root, let url = LanguageContribution.containedURL(icon, root: root) {
            return url
        }
        if case .ready(let document, _)? = previews[entry.id],
           let url = LanguageContribution.containedURL(icon, root: document.deletingLastPathComponent()) {
            return url
        }
        return onDisk?.iconURL
    }

    private func shouldPreview(id: String, expecting directory: URL) -> Bool {
        switch previews[id] {
        case .loading:
            return false
        case .ready(let document, _):
            return document.deletingLastPathComponent().standardizedFileURL != directory.standardizedFileURL
        case .unavailable, .none:
            return true
        }
    }

    private func prepareViewer(in root: URL) async throws {
        let viewer = try await Task.detached(priority: .utility) {
            try ExtensionViewerBundle.copyIfNeeded(into: root)
        }.value
        viewerHTML = ExtensionViewerBundle.html(in: viewer)
    }

    private func stagedDirectory(for entry: ExtensionIndex.Entry) async throws -> URL {
        if let running = stagings[entry.id] { return try await running.value }

        let root = previewRoot
        let verified = await Task.detached(priority: .utility) {
            ExtensionPreviewCache.verified(entry, root: root)
        }.value
        if let verified { return verified }

        let report = report(for: entry.id)
        let staging = Task<URL, Error>.detached(priority: .utility) {
            try await ExtensionPreviewCache.stage(entry, root: root, progress: report)
        }
        stagings[entry.id] = staging
        defer { stagings[entry.id] = nil }
        return try await staging.value
    }

    nonisolated static func previewState(directory: URL, root: URL, preferring name: String? = nil) -> PreviewState {
        let names = [name].compactMap { $0 } + ExtensionCard.documentFileNames
        for candidate in names {
            let document = directory.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: document.path) {
                return .ready(document: document, base: root)
            }
        }
        return .unavailable("The extension ships no document.")
    }

    // MARK: Registry

    static let refreshTimeout: TimeInterval = 15

    /// The registry's index carries a stamp of the minute it is asked for.
    ///
    /// A release asset is served from a cache that keeps answering with the
    /// bytes it already has for minutes after the asset is replaced, so a
    /// freshly published extension was invisible to the store while the plain
    /// URL was still handing out yesterday's catalogue.
    nonisolated static func indexRequestURL(_ base: URL = indexURL, now: Date = Date()) -> URL {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base }
        let minute = Int(now.timeIntervalSince1970 / 60)
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "t", value: String(minute))]
        return components.url ?? base
    }

    nonisolated static func fetchIndex() async throws -> ExtensionIndex {
        let request = URLRequest(
            url: indexRequestURL(),
            cachePolicy: .reloadRevalidatingCacheData,
            timeoutInterval: refreshTimeout
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ExtensionInstaller.Failure.download("the server did not answer over HTTP.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ExtensionInstaller.Failure.httpStatus(http.statusCode)
        }
        return try ExtensionIndex.parse(data)
    }

    nonisolated static func refreshMessage(for error: Error) -> String {
        switch error {
        case let parse as ExtensionIndex.ParseError:
            return "The registry could not be read: \(parse.message)."
        case ExtensionInstaller.Failure.httpStatus(let code):
            return "Could not reach the registry: the server answered \(code)."
        default:
            return "Could not reach the registry: \(error.localizedDescription)"
        }
    }

    nonisolated static func message(for error: Error) -> String {
        switch error {
        case let failure as ExtensionInstaller.Failure: return failure.message
        case let violation as ExtensionMediaGate.Violation: return violation.message
        case let failure as ExtensionPreviewCache.Failure: return failure.message
        case let failure as ExtensionViewerBundle.Failure: return failure.message
        default: return error.localizedDescription
        }
    }

    func state(for entry: ExtensionIndex.Entry) -> ExtensionState {
        Self.state(
            installedVersion: installed.first { $0.id == entry.id }?.version,
            available: entry.version
        )
    }

    nonisolated static func state(installedVersion: String?, available: String) -> ExtensionState {
        guard let installedVersion else { return .notInstalled }
        guard let have = SemanticVersion(installedVersion),
              let offered = SemanticVersion(available),
              offered > have
        else { return .installed(version: installedVersion) }
        return .updateAvailable(installed: installedVersion, available: available)
    }

    nonisolated static func scanInstalled(in directory: URL) -> [InstalledExtension] {
        let manifests = LanguageCatalog.load(directory: directory, scope: .user)
            .filter { !$0.id.isEmpty }
            .sorted { $0.root.lastPathComponent < $1.root.lastPathComponent }

        var seen: Set<String> = []
        return manifests
            .filter { seen.insert($0.id).inserted }
            .map {
                InstalledExtension(
                    id: $0.id, name: $0.name, version: $0.version, root: $0.root,
                    publisher: $0.publisher, iconURL: $0.languages.first?.iconURL)
            }
            .sorted(by: displayOrder)
    }

    nonisolated private static func displayOrder(_ lhs: InstalledExtension, _ rhs: InstalledExtension) -> Bool {
        switch lhs.name.localizedCaseInsensitiveCompare(rhs.name) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs.id < rhs.id
        }
    }
}
