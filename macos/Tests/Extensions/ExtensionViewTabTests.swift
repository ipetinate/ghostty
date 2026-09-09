import Foundation
@testable import Ghostty
import Testing

/// A contributed view as a tab of the editor: how it is opened, why pressing
/// the sidebar's button twice does not open a second one, and what closing
/// it takes away.
@MainActor
struct ExtensionViewTabTests {
    private func descriptor(
        _ viewID: String = "http",
        surface: ExtensionViewContribution.Surface = .editor,
        patterns: [String] = []
    ) -> ExtensionViewDescriptor {
        ExtensionViewDescriptor(
            extensionID: "ipetinate.bruno", extensionName: "Bruno",
            root: URL(fileURLWithPath: "/tmp/bruno"),
            contribution: ExtensionViewContribution(
                viewID: viewID, title: "Bruno",
                icon: URL(fileURLWithPath: "/tmp/bruno/icons/bruno.png"),
                entry: URL(fileURLWithPath: "/tmp/bruno/views/http.js"),
                style: nil, surface: surface,
                filenamePatterns: LanguageContribution.filePatterns(from: patterns),
                priority: .option,
                placements: ExtensionViewContribution.placements(nil, surface: surface),
                permissions: [.workspaceCreate, .workspaceReplace, .viewsOpen]))
    }

    /// The defect that put **two** Bruno marks in the rail: an entry naming
    /// no placement fell through to both bars, so the editor view got a
    /// button beside the panel's — and it opened an empty page.
    ///
    /// An `editor` entry has no button, whatever the manifest says. A
    /// `sidebar` entry that names none keeps both bars, because a panel with
    /// no button has no way in.
    @Test func onlyASidebarEntryHasAButton() {
        #expect(ExtensionViewContribution.placements(nil, surface: .editor).isEmpty)
        #expect(ExtensionViewContribution.placements(["sidebar"], surface: .editor).isEmpty)
        #expect(ExtensionViewContribution.placements(["sidebar", "topBar"], surface: .editor).isEmpty)

        #expect(ExtensionViewContribution.placements(nil, surface: .sidebar)
            == Set(ExtensionViewContribution.Placement.allCases))
        #expect(ExtensionViewContribution.placements(["topBar"], surface: .sidebar) == [.topBar])
    }

    /// One extension contributing both surfaces reaches the bars once.
    @Test func anExtensionWithTwoViewsShowsOneButton() {
        let panel = descriptor("collection", surface: .sidebar)
        let editor = descriptor("http", surface: .editor, patterns: ["*.bru"])

        for placement in ExtensionViewContribution.Placement.allCases {
            let offered = [panel, editor].filter { $0.contribution.placements.contains(placement) }
            #expect(offered.map(\.id) == ["ipetinate.bruno/collection"])
        }
    }

    /// An entry with no `surface` is one written before the field existed,
    /// and the sidebar is where such an entry was drawn.
    @Test func anEntryWithNoSurfaceIsASidebarPanel() {
        #expect(ExtensionViewContribution.surface(nil) == .sidebar)
        #expect(ExtensionViewContribution.surface("sidebar") == .sidebar)
        #expect(ExtensionViewContribution.surface("editor") == .editor)
        #expect(ExtensionViewContribution.surface("statusBar") == .sidebar)
    }

    // MARK: Claiming a file

    /// An editor view's tab is the file's tab, so claiming is by name.
    @Test func anEditorViewClaimsFileNames() {
        let claim = descriptor("http", surface: .editor, patterns: ["*.bru"])
        #expect(claim.contribution.claims(fileName: "users.bru"))
        #expect(claim.contribution.claims(fileName: "USERS.BRU"))
        #expect(!claim.contribution.claims(fileName: "users.json"))
        #expect(!claim.contribution.claims(fileName: "bru"))
    }

    /// A pattern on a sidebar panel is ignored: a file does not open into a
    /// panel, so honouring it would claim a file for a surface that cannot
    /// draw it.
    @Test func aSidebarPanelClaimsNothing() {
        let panel = descriptor("collection", surface: .sidebar, patterns: ["*.bru"])
        #expect(!panel.contribution.claims(fileName: "users.bru"))
    }

    /// A separator in a pattern is refused by `GlobPattern.fileNamePattern`,
    /// so an editor claims a name and never a location.
    @Test func aPatternCannotReachOutsideTheFileName() {
        let claim = descriptor("http", surface: .editor, patterns: ["api/*.bru", "../*.bru"])
        #expect(claim.contribution.filenamePatterns.isEmpty)
        #expect(!claim.contribution.claims(fileName: "users.bru"))
    }

    /// The reader's text editor keeps a claimed file unless the manifest
    /// asks for it, because taking a file over is the larger claim.
    @Test func theTextEditorKeepsAClaimedFileByDefault() {
        #expect(ExtensionViewContribution.priority(nil) == .option)
        #expect(ExtensionViewContribution.priority("option") == .option)
        #expect(ExtensionViewContribution.priority("default") == .default)
        #expect(ExtensionViewContribution.priority("always") == .option)
    }

    // MARK: A claimed file is a file tab

    /// The whole point of claiming a name instead of carrying an argument:
    /// the tab is the file's, so a view id nothing declares opens nothing
    /// rather than falling back to a tab the caller did not ask for.
    @Test func openWithRefusesAViewNothingDeclares() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("users.bru")
        try Data("get {\n  url: https://example.com\n}".utf8).write(to: file)

        let center = EditorCenter()
        #expect(!center.openWith(file, viewID: "ipetinate.bruno/http"))
        #expect(center.tabs.isEmpty)
        #expect(center.documents.isEmpty)
    }

    /// Nothing claims a name until an extension is installed, so a plain
    /// open leaves the text editor drawing the file.
    @Test func anUnclaimedFileIsDrawnByTheTextEditor() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("users.bru")
        try Data("get {}".utf8).write(to: file)

        let center = EditorCenter()
        #expect(center.open(file))
        #expect(center.documents[file.path]?.contributedView == nil)
        #expect(EditorCenter.claimingView(fileName: "users.bru") == nil)

        /* Switching is refused for a view nothing declares, so a stale
         * choice cannot leave a tab drawing nothing. */
        center.setContributedView("ipetinate.bruno/http", for: file.path)
        #expect(center.documents[file.path]?.contributedView == nil)
    }

    // MARK: Closing a tab a page has unsaved work in

    private func openedFile(_ center: EditorCenter, in directory: URL) throws -> String {
        let file = directory.appendingPathComponent("users.bru")
        try Data("get {}".utf8).write(to: file)
        #expect(center.open(file))
        return file.path
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The failure the ⌘W work exists to fix, in a new place: a tab that
    /// swallows unsaved work without asking. The app holds the fact — the
    /// page reported it — so the close path asks the reader, not the page.
    @Test func closingADirtyContributedTabAsksFirst() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let center = EditorCenter()
        let path = try openedFile(center, in: dir)
        center.setContributedDirty(true, for: path)
        #expect(center.contributedDirty.contains(path))
        #expect(center.tabs.tab(for: path)?.isDirty == true)

        center.requestClose(path)
        #expect(center.closeConfirmation?.path == path)
        #expect(center.closeConfirmation?.canSave == false)
        #expect(center.tabs.tabs.count == 1, "the tab is still open until the reader answers")
    }

    /// Discard means discard: the tab goes and the page's work goes with it,
    /// which is what the confirmation just said.
    @Test func discardingClosesTheTab() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let center = EditorCenter()
        let path = try openedFile(center, in: dir)
        center.setContributedDirty(true, for: path)
        center.requestClose(path)

        center.close(path)
        center.closeConfirmation = nil
        #expect(center.tabs.isEmpty)
        #expect(!center.contributedDirty.contains(path))
    }

    /// A page that saved says so, and then the tab closes without a
    /// question — the same gesture, a different answer.
    @Test func aSavedPageClosesWithoutAsking() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let center = EditorCenter()
        let path = try openedFile(center, in: dir)
        center.setContributedDirty(true, for: path)
        center.setContributedDirty(false, for: path)
        #expect(center.tabs.tab(for: path)?.isDirty == false)

        center.requestClose(path)
        #expect(center.closeConfirmation == nil)
        #expect(center.tabs.isEmpty)
    }

    /// A bulk close asks about nothing, so a page's unsaved work is kept
    /// back rather than discarded.
    @Test func aBulkCloseKeepsADirtyPageBack() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let center = EditorCenter()
        let page = try openedFile(center, in: dir)
        let plain = dir.appendingPathComponent("other.bru")
        try Data("post {}".utf8).write(to: plain)
        #expect(center.open(plain))

        center.setContributedDirty(true, for: page)
        let kept = center.closeAll(in: center.activeGroupID)

        #expect(kept == [page])
        #expect(center.tabs.tabs.map(\.path) == [page])
    }

    /// ⌘S is handed back when no page is drawing the focused tab, which is
    /// what keeps a code view's own save working. No extension is installed
    /// in a test, so this is the only half of the routing a test can see.
    @Test func saveIsHandedBackWhenNoPageIsDrawingTheTab() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let center = EditorCenter()
        let path = try openedFile(center, in: dir)
        #expect(center.saveTicket(for: path) == 0)

        /* No contributed view is drawing it in a test, so the key is handed
         * back — which is what keeps a code view's own ⌘S working. */
        #expect(!center.requestContributedSave())
        #expect(center.saveTicket(for: path) == 0)
    }

    /// What the confirmation says, and what it leaves out.
    ///
    /// Save is absent for a contributed tab: the unsaved text is in the
    /// page, so `saveAndClose(_:)` would write the file as it already is on
    /// disk and report success.
    @Test func theConfirmationOffersNoSaveForAPage() {
        let page = EditorCenter.CloseConfirmation(path: "/tmp/users.bru", canSave: false)
        #expect(!page.canSave)
        #expect(page.name == "users.bru")

        let document = EditorCenter.CloseConfirmation(path: "/tmp/users.bru")
        #expect(document.canSave)
    }

    // MARK: Opening one view from another

    /// A page names a view the way its author wrote it, and the descriptor
    /// id is built from the extension the page belongs to — so there is no
    /// spelling of `viewId` that reaches another extension's view.
    @Test func aViewMayOnlyOpenItsOwnExtensionsViews() {
        let opener = ExtensionViewOpener(extensionID: "ipetinate.bruno", editorViews: ["http"])

        #expect(opener.target("http") == "ipetinate.bruno/http")
        #expect(opener.target("collection") == nil)
        #expect(opener.target("phantom.tailwind/panel") == nil)
        #expect(opener.target("../tailwind/panel") == nil)
        #expect(ExtensionViewOpener.none.target("http") == nil)
    }
}
