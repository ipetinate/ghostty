import Foundation
@testable import Ghostty
import Testing

/// What a contributed view remembers, and what it may not.
struct ExtensionViewStateTests {
    private func caches() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("view-state-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func workspace(_ caches: URL, _ name: String = "project") throws -> URL {
        let url = caches.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func remembersOneObjectPerWorkspace() throws {
        let caches = try caches()
        defer { try? FileManager.default.removeItem(at: caches) }

        let here = ExtensionViewState(
            extensionID: "ipetinate.bruno", workspace: try workspace(caches, "here"))
        let there = ExtensionViewState(
            extensionID: "ipetinate.bruno", workspace: try workspace(caches, "there"))

        try here.write(["collection": "api"], cachesDir: caches)
        #expect(here.read(cachesDir: caches)["collection"] as? String == "api")
        #expect(there.read(cachesDir: caches).isEmpty)
    }

    /// Two windows on one repository read the same record, and two checkouts
    /// of it do not.
    @Test func theKeyIsTheResolvedWorkspacePath() throws {
        let caches = try caches()
        defer { try? FileManager.default.removeItem(at: caches) }

        let root = try workspace(caches)
        let same = ExtensionViewState.key(for: root)
        let trailing = ExtensionViewState.key(for: URL(fileURLWithPath: root.path + "/"))
        #expect(same == trailing)
        #expect(same != ExtensionViewState.key(for: try workspace(caches, "other")))
        #expect(ExtensionViewState.key(for: nil) == "any")
    }

    /// The key that bounds the view's filesystem methods is the app's. A
    /// page able to write it would be a page able to move its own scope.
    @Test func aPageCannotWriteAReservedKey() throws {
        let caches = try caches()
        defer { try? FileManager.default.removeItem(at: caches) }

        let state = ExtensionViewState(
            extensionID: "ipetinate.bruno", workspace: try workspace(caches))

        #expect(throws: ExtensionViewState.Failure.reservedKey) {
            try state.write([ExtensionViewState.chosenWorkspaceKey: "/etc"], cachesDir: caches)
        }
        #expect(throws: ExtensionViewState.Failure.reservedKey) {
            try state.write(["$anything": 1], cachesDir: caches)
        }
        #expect(state.read(cachesDir: caches).isEmpty)
    }

    @Test func aReservedKeyIsHiddenFromThePage() throws {
        let caches = try caches()
        defer { try? FileManager.default.removeItem(at: caches) }

        let root = try workspace(caches)
        let state = ExtensionViewState(extensionID: "ipetinate.bruno", workspace: root)
        try state.write(["collection": "api"], cachesDir: caches)
        state.setChosenWorkspace(root, cachesDir: caches)

        #expect(state.read(cachesDir: caches).count == 2)
        #expect(state.readForPage(cachesDir: caches).count == 1)
        #expect(state.readForPage(cachesDir: caches)["collection"] as? String == "api")
    }

    /// Remembering the folder keeps what the page had stored.
    @Test func rememberingAFolderKeepsThePagesKeys() throws {
        let caches = try caches()
        defer { try? FileManager.default.removeItem(at: caches) }

        let root = try workspace(caches)
        let state = ExtensionViewState(extensionID: "ipetinate.bruno", workspace: root)
        try state.write(["collection": "api"], cachesDir: caches)
        state.setChosenWorkspace(root, cachesDir: caches)

        #expect(state.chosenWorkspace(cachesDir: caches)?.path == root.standardizedFileURL.path)
        #expect(state.readForPage(cachesDir: caches)["collection"] as? String == "api")
    }

    /// A remembered folder that is gone answers nil, and the record is left
    /// alone: an unmounted volume is mounted again tomorrow.
    @Test func aFolderThatIsGoneAnswersNilAndIsKept() throws {
        let caches = try caches()
        defer { try? FileManager.default.removeItem(at: caches) }

        let root = try workspace(caches)
        let gone = try workspace(caches, "gone")
        let state = ExtensionViewState(extensionID: "ipetinate.bruno", workspace: root)
        state.setChosenWorkspace(gone, cachesDir: caches)
        try FileManager.default.removeItem(at: gone)

        #expect(state.chosenWorkspace(cachesDir: caches) == nil)
        #expect(state.read(cachesDir: caches)[ExtensionViewState.chosenWorkspaceKey] != nil)
    }

    @Test func refusesAnObjectOverTheBound() throws {
        let caches = try caches()
        defer { try? FileManager.default.removeItem(at: caches) }

        let state = ExtensionViewState(
            extensionID: "ipetinate.bruno", workspace: try workspace(caches))
        let big = ["a": String(repeating: "x", count: ExtensionViewState.maxBytes)]
        #expect(throws: (any Error).self) { try state.write(big, cachesDir: caches) }
        #expect(state.read(cachesDir: caches).isEmpty)
    }

    /// An extension id is a path segment here, so it goes back through the
    /// rule that made it.
    @Test func anUnusableExtensionIDHasNoFile() throws {
        let caches = try caches()
        defer { try? FileManager.default.removeItem(at: caches) }

        let bad = ExtensionViewState(extensionID: "../../etc", workspace: nil)
        #expect(bad.file(cachesDir: caches) == nil)
        #expect(bad.read(cachesDir: caches).isEmpty)
    }
}
