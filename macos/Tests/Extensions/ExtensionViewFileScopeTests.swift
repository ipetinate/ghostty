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

    // MARK: The file a view is drawing

    /// A page is told its file relative to the scope's root and never
    /// absolutely, so it learns nothing about the reader's disk that it
    /// could not already ask for.
    @Test func theBoundFileIsNamedRelativeToItsRoot() throws {
        let tree = try tree()
        let file = ExtensionViewFile.inside(
            tree.scope, url: tree.workspace.appendingPathComponent("api/users/list.bru"))
        #expect(file?.root == .workspace)
        #expect(file?.path == "api/users/list.bru")

        let inPackage = ExtensionViewFile.inside(
            tree.scope, url: tree.package.appendingPathComponent("view.js"))
        #expect(inPackage?.root == .package)
        #expect(inPackage?.path == "view.js")
    }

    /// A claimed file opened from outside the scope tells the page nothing:
    /// it has no way to read it, so a path would only fail on the next call.
    @Test func aFileOutsideTheScopeIsNotNamed() throws {
        let tree = try tree()
        #expect(ExtensionViewFile.inside(
            tree.scope, url: tree.outside.appendingPathComponent("id_rsa")) == nil)
        #expect(ExtensionViewFile.inside(tree.scope, url: tree.workspace) == nil)
    }

    /// `views.open` hands the app a path to open, so the check is the read
    /// side's: a page may only open a file it could already have read.
    @Test func openingAFileFollowsTheReadScope() throws {
        let tree = try tree()
        #expect(try tree.scope.file(root: .workspace, path: "api/users/list.bru").lastPathComponent
            == "list.bru")

        #expect(throws: ExtensionViewFileScope.Failure.outOfScope("../outside/id_rsa")) {
            try tree.scope.file(root: .workspace, path: "../outside/id_rsa")
        }
        #expect(throws: ExtensionViewFileScope.Failure.missing("api/absent.bru")) {
            try tree.scope.file(root: .workspace, path: "api/absent.bru")
        }
        #expect(throws: ExtensionViewFileScope.Failure.notAFile("api")) {
            try tree.scope.file(root: .workspace, path: "api")
        }
    }

    // MARK: Writing

    @Test func createsANewFileInsideTheWorkspace() throws {
        let tree = try tree()
        let text = "meta {\n  name: New\n}"
        let bytes = try tree.scope.write(root: .workspace, path: "api/new.bru", text: text, mode: .create)
        #expect(bytes == text.utf8.count)
        #expect(try tree.scope.read(root: .workspace, path: "api/new.bru") == text)
    }

    /// Saving an edited file back over itself, which is the useful half of
    /// the write surface.
    @Test func replacesAFileThatIsAlreadyThere() throws {
        let tree = try tree()
        let text = "get {\n  url: https://api.example.com/v2\n}"
        let bytes = try tree.scope.write(
            root: .workspace, path: "api/users/list.bru", text: text, mode: .replace)
        #expect(bytes == text.utf8.count)
        #expect(try tree.scope.read(root: .workspace, path: "api/users/list.bru") == text)
    }

    /// The two are disjoint, so a typo cannot turn a save into a new file
    /// and a new request cannot clobber one that is there.
    @Test func theTwoModesRefuseEachOthersPaths() throws {
        let tree = try tree()
        #expect(throws: ExtensionViewFileScope.Failure.exists("api/collection.bru")) {
            try tree.scope.write(root: .workspace, path: "api/collection.bru", text: "clobbered", mode: .create)
        }
        #expect(try tree.scope.read(root: .workspace, path: "api/collection.bru") == "meta {}")

        #expect(throws: ExtensionViewFileScope.Failure.absent("api/absent.bru")) {
            try tree.scope.write(root: .workspace, path: "api/absent.bru", text: "x", mode: .replace)
        }
        #expect(!FileManager.default.fileExists(
            atPath: tree.workspace.appendingPathComponent("api/absent.bru").path))
    }

    /// A folder is not a file either method writes to.
    @Test func refusesAFolderAsATarget() throws {
        let tree = try tree()
        #expect(throws: ExtensionViewFileScope.Failure.exists("api")) {
            try tree.scope.write(root: .workspace, path: "api", text: "clobbered", mode: .create)
        }
        #expect(throws: ExtensionViewFileScope.Failure.notAFile("api")) {
            try tree.scope.write(root: .workspace, path: "api", text: "clobbered", mode: .replace)
        }
        #expect(ExtensionViewFileScope.isDirectory(tree.workspace.appendingPathComponent("api")))
    }

    /// The refusal that keeps the boundary from being self-lifting: the
    /// manifest in the package directory is what grants this page its
    /// methods, and `ExtensionStore.refresh()` reads it again with no
    /// restart.
    @Test func replaceDoesNotReachThePackageDirectory() throws {
        let tree = try tree()
        #expect(throws: ExtensionViewFileScope.Failure.immutableRoot(.package)) {
            try tree.scope.write(root: .package, path: "view.js", text: "owned", mode: .replace)
        }
        #expect(try tree.scope.read(root: .package, path: "view.js") == "module")

        let manifest = tree.package.appendingPathComponent("extension.json")
        try Data("{}".utf8).write(to: manifest)
        #expect(throws: ExtensionViewFileScope.Failure.immutableRoot(.package)) {
            try tree.scope.write(
                root: .package, path: "extension.json",
                text: "{\"contributes\":{}}", mode: .replace)
        }
        #expect(try tree.scope.read(root: .package, path: "extension.json") == "{}")

        /* Creating a file there is still allowed: every file the app reads
         * from a package, by manifest or by convention, already exists. */
        #expect(try tree.scope.write(root: .package, path: "scratch.txt", text: "ok", mode: .create) == 2)
    }

    /// No folder, at any depth, either method. A page that could make one
    /// could lay out a tree of its own choosing inside somebody's
    /// repository.
    @Test func neitherModeCreatesAFolder() throws {
        let tree = try tree()
        for mode in ExtensionViewFileScope.WriteMode.allCases {
            #expect(throws: ExtensionViewFileScope.Failure.noParent("fresh/new.bru")) {
                try tree.scope.write(root: .workspace, path: "fresh/new.bru", text: "x", mode: mode)
            }
        }
        #expect(!FileManager.default.fileExists(atPath: tree.workspace.appendingPathComponent("fresh").path))
    }

    @Test func aWriteThatEscapesIsOutOfScope() throws {
        let tree = try tree()
        for mode in ExtensionViewFileScope.WriteMode.allCases {
            #expect(throws: ExtensionViewFileScope.Failure.outOfScope("../outside/id_rsa")) {
                try tree.scope.write(root: .workspace, path: "../outside/id_rsa", text: "x", mode: mode)
            }
        }
        #expect(try String(contentsOf: tree.outside.appendingPathComponent("id_rsa"), encoding: .utf8)
            == "secret")
    }

    /// The second half of the containment rule, on the write side: the
    /// resolved path has to be inside as well.
    @Test func aWriteThroughASymlinkIsOutOfScope() throws {
        let tree = try tree()
        let link = tree.workspace.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: tree.outside)

        for mode in ExtensionViewFileScope.WriteMode.allCases {
            #expect(throws: ExtensionViewFileScope.Failure.outOfScope("escape/id_rsa")) {
                try tree.scope.write(root: .workspace, path: "escape/id_rsa", text: "owned", mode: mode)
            }
        }
        #expect(try String(contentsOf: tree.outside.appendingPathComponent("id_rsa"), encoding: .utf8)
            == "secret")
    }

    @Test func aWriteWithNoWorkspaceIsARefusal() throws {
        let tree = try tree()
        let scope = ExtensionViewFileScope(workspace: nil, package: tree.package)
        for mode in ExtensionViewFileScope.WriteMode.allCases {
            #expect(throws: ExtensionViewFileScope.Failure.noWorkspace) {
                try scope.write(root: .workspace, path: "new.bru", text: "x", mode: mode)
            }
        }
    }

    @Test func refusesTextOverTheWriteLimit() throws {
        let tree = try tree()
        let text = String(repeating: "a", count: ExtensionViewFileScope.maxWriteBytes + 1)
        #expect(throws: (any Error).self) {
            try tree.scope.write(root: .workspace, path: "api/big.bru", text: text, mode: .create)
        }
        #expect(!FileManager.default.fileExists(atPath: tree.workspace.appendingPathComponent("api/big.bru").path))

        #expect(throws: (any Error).self) {
            try tree.scope.write(root: .workspace, path: "api/collection.bru", text: text, mode: .replace)
        }
        #expect(try tree.scope.read(root: .workspace, path: "api/collection.bru") == "meta {}")
    }
}
