import Foundation
@testable import Ghostty
import Testing

struct ExtensionViewFileScopeTests {
    private struct Tree {
        let workspace: URL
        let package: URL
        let outside: URL

        var scope: ExtensionViewFileScope {
            ExtensionViewFileScope(workspace: workspace, package: package)
        }
    }

    private func tree() throws -> Tree {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scope-" + UUID().uuidString, isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let package = root.appendingPathComponent("package", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)

        try fileManager.createDirectory(
            at: workspace.appendingPathComponent("api/users", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: workspace.appendingPathComponent("node_modules/left-pad", isDirectory: true),
            withIntermediateDirectories: true)
        try fileManager.createDirectory(at: package, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)

        try Data("get {\n  url: https://api.example.com\n}".utf8)
            .write(to: workspace.appendingPathComponent("api/users/list.bru"))
        try Data("meta {}".utf8).write(to: workspace.appendingPathComponent("api/collection.bru"))
        try Data("module".utf8).write(to: package.appendingPathComponent("view.js"))
        try Data("secret".utf8).write(to: outside.appendingPathComponent("id_rsa"))
        try Data("dep".utf8).write(to: workspace.appendingPathComponent("node_modules/left-pad/index.js"))

        return Tree(workspace: workspace, package: package, outside: outside)
    }

    @Test func readsAFileInsideTheWorkspace() throws {
        let tree = try tree()
        #expect(try tree.scope.read(root: .workspace, path: "api/users/list.bru").hasPrefix("get {"))
        #expect(try tree.scope.read(root: .package, path: "view.js") == "module")
    }

    @Test func aPathThatEscapesIsOutOfScope() throws {
        let tree = try tree()
        #expect(throws: ExtensionViewFileScope.Failure.outOfScope("../outside/id_rsa")) {
            try tree.scope.read(root: .workspace, path: "../outside/id_rsa")
        }
    }

    /// A symlink planted inside the workspace is the second half of the
    /// containment rule: the resolved path has to be inside as well.
    @Test func aSymlinkOutOfTheWorkspaceIsOutOfScope() throws {
        let tree = try tree()
        let link = tree.workspace.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: tree.outside)

        #expect(throws: ExtensionViewFileScope.Failure.outOfScope("escape/id_rsa")) {
            try tree.scope.read(root: .workspace, path: "escape/id_rsa")
        }
    }

    /// A view opened with no workspace refuses rather than reading from
    /// somewhere arbitrary.
    @Test func noWorkspaceIsARefusal() throws {
        let tree = try tree()
        let scope = ExtensionViewFileScope(workspace: nil, package: tree.package)
        #expect(throws: ExtensionViewFileScope.Failure.noWorkspace) {
            try scope.read(root: .workspace, path: "api/collection.bru")
        }
        #expect(try scope.read(root: .package, path: "view.js") == "module")
    }

    @Test func refusesAFolderAFileAndBinary() throws {
        let tree = try tree()
        #expect(throws: ExtensionViewFileScope.Failure.notAFile("api")) {
            try tree.scope.read(root: .workspace, path: "api")
        }
        #expect(throws: ExtensionViewFileScope.Failure.missing("api/absent.bru")) {
            try tree.scope.read(root: .workspace, path: "api/absent.bru")
        }

        let binary = tree.workspace.appendingPathComponent("binary.bru")
        try Data([0xFF, 0xFE, 0x00]).write(to: binary)
        #expect(throws: ExtensionViewFileScope.Failure.notText("binary.bru")) {
            try tree.scope.read(root: .workspace, path: "binary.bru")
        }
    }

    @Test func listsOneLevelByDefault() throws {
        let tree = try tree()
        let entries = try tree.scope.list(root: .workspace, path: "api", depth: 1)
        #expect(entries.map(\.path).sorted() == ["api/collection.bru", "api/users"])
        #expect(entries.first { $0.name == "users" }?.isDirectory == true)
        #expect(entries.first { $0.name == "collection.bru" }?.bytes == 7)
    }

    @Test func walksDeeperWhenAsked() throws {
        let tree = try tree()
        let entries = try tree.scope.list(root: .workspace, path: "api", depth: 2)
        #expect(entries.map(\.path).sorted() == ["api/collection.bru", "api/users", "api/users/list.bru"])
    }

    /// Not a security rule — everything skipped is inside the workspace. It
    /// keeps a walk of a JavaScript project from spending `maxEntries` before
    /// it reaches the files the author was looking for.
    @Test func doesNotEnterTheFoldersNobodyWants() throws {
        let tree = try tree()
        let entries = try tree.scope.list(root: .workspace, path: nil, depth: 4)
        #expect(entries.contains { $0.path == "node_modules" })
        #expect(!entries.contains { $0.path.hasPrefix("node_modules/") })
    }

    @Test func listingSomethingThatIsNotAFolderIsARefusal() throws {
        let tree = try tree()
        #expect(throws: ExtensionViewFileScope.Failure.notADirectory("api/collection.bru")) {
            try tree.scope.list(root: .workspace, path: "api/collection.bru", depth: 1)
        }
    }

    /// `LSPCenter.workspaceRoot(for:)` answers this for a *file* and drops
    /// the last component first, which is one folder too many for a
    /// directory that is already the root.
    @Test func theWorkspaceRootOfADirectoryIsItsRepository() throws {
        let tree = try tree()
        try FileManager.default.createDirectory(
            at: tree.workspace.appendingPathComponent(".git", isDirectory: true), withIntermediateDirectories: true)

        let deep = tree.workspace.appendingPathComponent("api/users").path
        #expect(ExtensionViewFileScope.workspaceRoot(forDirectory: deep)?.resolvingSymlinksInPath()
            == tree.workspace.resolvingSymlinksInPath())
        #expect(ExtensionViewFileScope.workspaceRoot(forDirectory: tree.workspace.path)?.resolvingSymlinksInPath()
            == tree.workspace.resolvingSymlinksInPath())
        #expect(ExtensionViewFileScope.workspaceRoot(forDirectory: nil) == nil)
        #expect(ExtensionViewFileScope.workspaceRoot(forDirectory: tree.workspace.appendingPathComponent("api/collection.bru").path) == nil)
    }

    /// A folder with no repository above it is its own root: a view opened
    /// over a plain directory still has one folder to work in.
    @Test func aFolderWithNoRepositoryIsItsOwnRoot() throws {
        let tree = try tree()
        let resolved = ExtensionViewFileScope.workspaceRoot(forDirectory: tree.outside.path)
        #expect(resolved?.resolvingSymlinksInPath() == tree.outside.resolvingSymlinksInPath())
    }
}
