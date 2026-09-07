import Foundation
@testable import Ghostty
import Testing

/// The second release asset: the document and its media, published beside
/// the installable zip.
///
/// The defect it fixes is that opening an extension's page downloaded the
/// extension. GitHub counts every asset download and the store shows that
/// count, so one asset for both meant one number that mixed "read the page"
/// with "installed it".
///
/// Two properties matter here and neither is about rendering. The first is
/// that the bundle is held to the same guards as the installable archive,
/// because it is still a file off the internet being unzipped. The second is
/// that an entry carrying no preview asset — every entry the registry
/// published before this existed — falls back to the installable zip instead
/// of showing an empty page.
struct ExtensionPreviewAssetTests {
    private static let previewSHA = String(repeating: "b", count: 64)

    private static var previewJSON: [String: Any] {
        [
            "url": "https://github.com/ipetinate/phantom-extensions/releases/download/"
                + "ipetinate.lua-v1.0.0/ipetinate.lua-1.0.0-preview.zip",
            "sha256": previewSHA,
            "bytes": 620,
        ]
    }

    private func parse(_ preview: Any?) throws -> ExtensionIndex.Entry {
        let json = ExtensionIndexTests.entry(["preview": preview])
        let index = try ExtensionIndex.parse(try ExtensionIndexTests.index(entries: [json]))
        return try #require(index.extensions.first)
    }

    // MARK: The index entry

    @Test func readsThePreviewAssetBesideTheInstallableOne() throws {
        let entry = try parse(Self.previewJSON)
        let preview = try #require(entry.preview)
        #expect(preview.url.lastPathComponent == "ipetinate.lua-1.0.0-preview.zip")
        #expect(preview.sha256 == Self.previewSHA)
        #expect(preview.bytes == 620)
        #expect(entry.download.sha256 == ExtensionIndexTests.luaSHA)
        #expect(preview.sha256 != entry.download.sha256)
    }

    /// The state every entry is in until the registry publishes again, and
    /// the one the fallback exists for.
    @Test func anEntryWithNoPreviewAssetCarriesNone() throws {
        let entry = try parse(nil)
        #expect(entry.preview == nil)
        #expect(entry.download.url.lastPathComponent == "ipetinate.lua-1.0.0.zip")
    }

    /// A preview asset is three fields that are useless apart, so a defect in
    /// any one of them costs the whole asset and the entry falls back —
    /// rather than costing the entry, which would hide the extension.
    @Test func aMalformedPreviewAssetLeavesTheEntryWithoutOne() throws {
        let bad: [String: Any?] = [
            "url": "http://example.com/preview.zip",
            "sha256": "nope",
            "bytes": 0,
        ]
        for (key, value) in bad {
            var json = Self.previewJSON
            if let value { json[key] = value } else { json.removeValue(forKey: key) }
            let entry = try parse(json)
            #expect(entry.preview == nil, "\(key)")
            #expect(entry.id == "ipetinate.lua", "\(key)")
        }

        var oversized = Self.previewJSON
        oversized["bytes"] = ExtensionIndex.maxPreviewBytes + 1
        #expect(try parse(oversized).preview == nil)
        #expect(try parse("not an object").preview == nil)
    }

    // MARK: The archive

    @Test func aDocumentAtTheRootIsWhatMakesItAPreviewBundle() {
        #expect(ExtensionArchive.hasDocumentAtRoot(["extension.mdx", "media/a.png"]))
        #expect(ExtensionArchive.hasDocumentAtRoot(["./extension.md"]))
        #expect(!ExtensionArchive.hasDocumentAtRoot(["media/a.png"]))
        #expect(!ExtensionArchive.hasDocumentAtRoot(["docs/extension.mdx"]))
        #expect(!ExtensionArchive.hasDocumentAtRoot(["extension.json"]))
    }

    private struct Bundle {
        let scratch: URL
        let archive: URL
        let asset: ExtensionIndex.Asset

        func staged() -> URL {
            scratch.appendingPathComponent("staged", isDirectory: true)
        }

        func remove() {
            try? FileManager.default.removeItem(at: scratch)
        }
    }

    /// A real zip through `ditto`, the way `ExtensionInstaller` unpacks one,
    /// so the test exercises the archive path rather than a stand-in.
    private func makeBundle(document: Bool = true, symlink: Bool = false) throws -> Bundle {
        let fileManager = FileManager.default
        let scratch = fileManager.temporaryDirectory
            .appendingPathComponent("phantom-preview-\(UUID().uuidString)", isDirectory: true)
        let source = scratch.appendingPathComponent("source", isDirectory: true)
        try fileManager.createDirectory(
            at: source.appendingPathComponent("media", isDirectory: true),
            withIntermediateDirectories: true
        )
        if document {
            try "# Lua\n\n![shot](media/a.png)\n".write(
                to: source.appendingPathComponent(ExtensionCard.documentFileName),
                atomically: true,
                encoding: .utf8
            )
        }
        try Data(count: 16).write(to: source.appendingPathComponent("media/a.png"))
        if symlink {
            try fileManager.createSymbolicLink(
                atPath: source.appendingPathComponent("media/b.png").path,
                withDestinationPath: "a.png"
            )
        }

        let archive = scratch.appendingPathComponent("preview.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--norsrc", source.path, archive.path]
        try ditto.run()
        ditto.waitUntilExit()
        try #require(ditto.terminationStatus == 0)

        let bytes = try #require(try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        return Bundle(
            scratch: scratch,
            archive: archive,
            asset: ExtensionIndex.Asset(
                url: URL(string: "https://example.com/preview.zip")!,
                sha256: try ExtensionInstaller.digest(of: archive),
                bytes: bytes
            )
        )
    }

    @Test func stagesADocumentBundleTheIndexVouchesFor() async throws {
        let bundle = try makeBundle()
        defer { bundle.remove() }
        let staged = bundle.staged()

        try await ExtensionInstaller.stagePreview(
            archive: bundle.archive,
            expecting: bundle.asset,
            into: staged
        )

        #expect(ExtensionPreviewCache.hasDocument(in: staged))
        let media = staged.appendingPathComponent("media/a.png")
        #expect(FileManager.default.fileExists(atPath: media.path))
        #expect(!FileManager.default.fileExists(
            atPath: staged.appendingPathComponent(LanguageManifest.fileName).path
        ))
    }

    /// The digest is the whole of what proves this is the right bundle,
    /// since it carries no manifest to check an id against.
    @Test func aBundleThatDoesNotMatchTheIndexIsRefused() async throws {
        let bundle = try makeBundle()
        defer { bundle.remove() }

        let wrongDigest = ExtensionIndex.Asset(
            url: bundle.asset.url,
            sha256: String(repeating: "c", count: 64),
            bytes: bundle.asset.bytes
        )
        await #expect(throws: ExtensionInstaller.Failure.digestMismatch) {
            try await ExtensionInstaller.stagePreview(
                archive: bundle.archive, expecting: wrongDigest, into: bundle.staged())
        }

        let wrongSize = ExtensionIndex.Asset(
            url: bundle.asset.url,
            sha256: bundle.asset.sha256,
            bytes: bundle.asset.bytes + 1
        )
        await #expect(throws: ExtensionInstaller.Failure.sizeMismatch(
            received: bundle.asset.bytes, expected: bundle.asset.bytes + 1)) {
            try await ExtensionInstaller.stagePreview(
                archive: bundle.archive, expecting: wrongSize, into: bundle.staged())
        }
    }

    @Test func aBundleWithNoDocumentIsRefused() async throws {
        let bundle = try makeBundle(document: false)
        defer { bundle.remove() }
        await #expect(throws: ExtensionInstaller.Failure.noDocument) {
            try await ExtensionInstaller.stagePreview(
                archive: bundle.archive, expecting: bundle.asset, into: bundle.staged())
        }
    }

    /// The same guard the installable archive has. A preview bundle carries
    /// no code, which is not a reason to unzip a symbolic link out of it.
    @Test func aBundleCarryingASymbolicLinkIsRefused() async throws {
        let bundle = try makeBundle(symlink: true)
        defer { bundle.remove() }
        await #expect(throws: ExtensionInstaller.Failure.symbolicLink("media/b.png")) {
            try await ExtensionInstaller.stagePreview(
                archive: bundle.archive, expecting: bundle.asset, into: bundle.staged())
        }
    }
}
