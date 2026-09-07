import AppKit
@testable import Ghostty
import Testing

struct ExtensionRowTests {
    static func entry(version: String = "1.0.6", downloads: ExtensionIndex.Downloads? = nil) -> ExtensionIndex.Entry {
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
            downloads: downloads,
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

    @Test func anExtensionNotInTheRegistryOffersItsOwnVersionAndNoCount() {
        let subject = ExtensionRow.Subject.orphan(Self.installed)

        #expect(subject.installedVersion == nil)
        #expect(subject.offeredVersion == "0.4.0")
        #expect(subject.downloads == nil)
    }

    @Test func theRowCarriesTheCountTheIndexBrought() {
        let counted = Self.entry(downloads: ExtensionIndex.Downloads(total: 530, current: 12))

        #expect(ExtensionRow.Subject.entry(counted, state: .notInstalled).downloads?.total == 530)
        #expect(ExtensionRow.Subject.entry(Self.entry(), state: .notInstalled).downloads == nil)
    }

    /// An SF Symbol name that does not resolve makes SwiftUI drop the whole
    /// row, with no log and no error, so both names are checked here rather
    /// than found missing on somebody's screen.
    @Test func theRowsSymbolsResolve() {
        for symbol in [ExtensionRow.authorSymbol, ExtensionDownloadsLabel.symbol] {
            #expect(
                NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil,
                "\(symbol) is not an SF Symbol")
        }
    }

    @Test func theCountIsShortenedOnlyOnceItIsLong() {
        #expect(ExtensionDownloadsLabel.short(0) == "0")
        #expect(ExtensionDownloadsLabel.short(999) == "999")
        #expect(!ExtensionDownloadsLabel.short(3241).isEmpty)
        #expect(ExtensionDownloadsLabel.short(3241).count < "3241".count + 2)
    }
}
