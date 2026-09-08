import Foundation
@testable import Ghostty
import Testing

/// Which of the two things on screen the close command takes down.
///
/// The key used to be answered by whatever held first responder, and
/// selecting a tab takes nothing away from the terminal surface — so a media
/// file, an extension page or a review left ⌘W closing the terminal, and a
/// root surface takes the window's every tab with it. The rule here asks the
/// cell in focus what it is showing instead.
@MainActor
struct EditorCloseFocusedTabTests {
    private func directory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    private func write(_ directory: URL, _ name: String, _ bytes: Data) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try bytes.write(to: url)
        return url
    }

    private func source(_ directory: URL, _ name: String) throws -> URL {
        try write(directory, name, Data("let a = 1".utf8))
    }

    @Test func aFileClosesItselfAndNotTheTerminal() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = try source(dir, "First.swift")
        let second = try source(dir, "Second.swift")

        let center = EditorCenter()
        #expect(center.open(first))
        #expect(center.open(second))
        center.select(center.tabs.tabs[0].path)

        #expect(center.closeFocusedTab())
        #expect(center.tabs.tabs.count == 1)
        #expect(center.tabs.tabs[0].path.hasSuffix("Second.swift"))
        #expect(center.tabs.selection == .file(center.tabs.tabs[0].path))
    }

    /// The case that was reported. A PNG has no code view to hold the caret,
    /// so nothing but the surface could answer the key — an extension page
    /// and a theme page arrive the same way.
    @Test func aPageWithNoEditorBehindItAnswersTheKey() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try write(dir, "shot.png", Data([0x89, 0x50, 0x4E, 0x47]))

        let center = EditorCenter()
        #expect(center.open(url))
        #expect(center.media[center.tabs.tabs[0].path]?.kind == .image)

        #expect(center.closeFocusedTab())
        #expect(center.tabs.isEmpty)
        #expect(center.tabs.selection == .terminal)
    }

    @Test func aReviewClosesItsOwnTab() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = try source(dir, "First.swift")
        let root = "/phantom-close-\(UUID().uuidString)"

        let center = EditorCenter()
        #expect(center.open(file))
        center.openReview(.commit(root: root, sha: "a1b2c3d4", subject: "Fix the drag"))

        #expect(center.closeFocusedTab())
        #expect(center.openReviews.isEmpty)
        #expect(center.tabs.tabs.count == 1)
        #expect(center.tabs.selection == .file(center.tabs.tabs[0].path))

        #expect(center.closeFocusedTab())
        #expect(center.tabs.isEmpty)
    }

    /// `false` is what hands the key back to `close_surface`, so the terminal
    /// keeps closing on the same combination it always has.
    @Test func theTerminalHandsTheKeyBack() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = try source(dir, "First.swift")

        let empty = EditorCenter()
        #expect(!empty.closeFocusedTab())

        let center = EditorCenter()
        #expect(center.open(file))
        center.selectTerminal()

        #expect(!center.closeFocusedTab())
        #expect(center.tabs.tabs.count == 1)
    }

    /// One press, one page. The reported behaviour was every tab going at
    /// once, because the window went with the terminal.
    @Test func eachPressClosesOnePage() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["A.swift", "B.swift", "C.swift"] { _ = try source(dir, name) }

        let center = EditorCenter()
        for name in ["A.swift", "B.swift", "C.swift"] {
            #expect(center.open(dir.appendingPathComponent(name)))
        }
        #expect(center.tabs.tabs.count == 3)

        for remaining in [2, 1, 0] {
            #expect(center.closeFocusedTab())
            #expect(center.tabs.tabs.count == remaining)
        }
        #expect(center.tabs.selection == .terminal)
        #expect(!center.closeFocusedTab())
    }
}
