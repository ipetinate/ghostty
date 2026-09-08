import AppKit
@testable import Ghostty
import Testing

struct ExtensionRowTests {
    static func entry(version: String = "1.0.6") -> ExtensionIndex.Entry {
        ExtensionIndex.Entry(
            id: "phantom.rust",
            name: "Rust",
            version: version,
            publisher: "phantom",
            summary: "",
            homepage: nil,
            minimumPhantomVersion: nil,
            contributes: [],
            languages: [],
            downloadURL: URL(string: "https://example.com/phantom.rust-\(version).zip")!,
            sha256: String(repeating: "a", count: 64),
            bytes: 1,
            card: nil)
    }

    static let installed = InstalledExtension(
        id: "phantom.local",
        name: "Local",
        version: "0.4.0",
        root: URL(fileURLWithPath: "/tmp/phantom.local"),
        publisher: "someone")

    @Test func aRowWithNoUpdateShowsOneVersionAndNoInstalledHalf() {
        let subject = ExtensionRow.Subject.entry(Self.entry(), state: .installed(version: "1.0.6"))

        #expect(subject.installedVersion == nil)
        #expect(subject.offeredVersion == "1.0.6")
    }

    @Test func aRowWaitingForAnUpdateSplitsTheTwoVersions() {
        let subject = ExtensionRow.Subject.entry(
            Self.entry(), state: .updateAvailable(installed: "1.0.3", available: "1.0.6"))

        #expect(subject.installedVersion == "1.0.3")
        #expect(subject.offeredVersion == "1.0.6")
    }

    @Test func anExtensionNotInTheRegistryOffersItsOwnVersion() {
        let subject = ExtensionRow.Subject.orphan(Self.installed)

        #expect(subject.installedVersion == nil)
        #expect(subject.offeredVersion == "0.4.0")
    }

    /// An SF Symbol name that does not resolve makes SwiftUI drop the whole
    /// row, with no log and no error, so the name is checked here rather
    /// than found missing on somebody's screen.
    @Test func theAuthorSymbolResolves() {
        #expect(
            NSImage(systemSymbolName: ExtensionRow.authorSymbol, accessibilityDescription: nil) != nil,
            "\(ExtensionRow.authorSymbol) is not an SF Symbol")
    }
}
