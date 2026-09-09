import AppKit
@testable import Ghostty
import Testing

@MainActor
struct SidebarMetadataPassTests {
    private func makeRepo(branch: String) -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("phantom-facts-\(UUID().uuidString)")
        let gitDir = root.appendingPathComponent(".git")
        try? FileManager.default.createDirectory(
            at: gitDir,
            withIntermediateDirectories: true)
        try? "ref: refs/heads/\(branch)\n".write(
            to: gitDir.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8)
        return root
    }

    @Test func pathFactsResolveTheBranchOfTheEnclosingRepository() {
        let root = makeRepo(branch: "feat/0.19.0")
        defer { try? FileManager.default.removeItem(at: root) }

        let facts = SidebarTabManager.pathFacts(for: root.path)

        #expect(facts.root == root.path)
        #expect(facts.branch == "feat/0.19.0")
    }

    @Test func pathFactsAreTheSameForTheSameDirectory() {
        let root = makeRepo(branch: "main")
        defer { try? FileManager.default.removeItem(at: root) }

        let nested = root.appendingPathComponent("src")
        try? FileManager.default.createDirectory(
            at: nested,
            withIntermediateDirectories: true)

        #expect(
            SidebarTabManager.pathFacts(for: nested.path)
                == SidebarTabManager.pathFacts(for: nested.path))
    }

    @Test func pathFactsOfAnUntrackedDirectoryCarryNoRoot() {
        let bare = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("phantom-bare-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: bare,
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bare) }

        #expect(SidebarTabManager.pathFacts(for: bare.path).root == nil)
    }

    @Test func repeatedDirectoriesAskForStatusOnce() {
        let facts = [
            SidebarTabManager.PathFacts(
                root: "/repo", branch: "main",
                inManagedWorktree: false, worktreeRepo: nil),
            SidebarTabManager.PathFacts(
                root: "/repo", branch: "main",
                inManagedWorktree: false, worktreeRepo: nil),
            SidebarTabManager.PathFacts(
                root: "/repo", branch: "main",
                inManagedWorktree: true, worktreeRepo: "other"),
        ]

        #expect(SidebarTabManager.uniqueStatusTargets(facts).count == 1)
    }

    @Test func oneRepositoryOnTwoBranchesAsksTwice() {
        let facts = [
            SidebarTabManager.PathFacts(
                root: "/repo", branch: "main",
                inManagedWorktree: false, worktreeRepo: nil),
            SidebarTabManager.PathFacts(
                root: "/repo", branch: "feat/0.19.0",
                inManagedWorktree: false, worktreeRepo: nil),
        ]

        let targets = SidebarTabManager.uniqueStatusTargets(facts)

        #expect(targets.count == 2)
        #expect(targets.allSatisfy { $0.root == "/repo" })
    }

    @Test func aDirectoryWithNoRepositoryIsNeverAskedAbout() {
        let facts = [
            SidebarTabManager.PathFacts(
                root: nil, branch: nil,
                inManagedWorktree: false, worktreeRepo: nil),
        ]

        #expect(SidebarTabManager.uniqueStatusTargets(facts).isEmpty)
    }
}
