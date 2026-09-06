import AppKit
import Foundation
@testable import Ghostty
import Testing

struct ExtensionInlineIconTests {
    static let svg = Data("<svg xmlns='http://www.w3.org/2000/svg'/>".utf8)

    static let pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

    static let sizedSVG = Data(
        "<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16'><rect width='16' height='16'/></svg>".utf8)

    static func dataURI(_ mediaType: String = "image/svg+xml", _ bytes: Data = svg) -> String {
        "data:\(mediaType);base64,\(bytes.base64EncodedString())"
    }

    @Test func readsTheDataURITheRegistryWrites() throws {
        let card = try #require(ExtensionCard.parse(ExtensionCardTests.card(["iconData": Self.dataURI()])))
        #expect(card.iconData == Self.svg)
    }

    @Test func readsAPNGIcon() throws {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let card = try #require(ExtensionCard.parse(ExtensionCardTests.card(["iconData": Self.dataURI("image/png", bytes)])))
        #expect(card.iconData == bytes)
    }

    @Test func aMissingIconLeavesTheCardStanding() throws {
        let card = try #require(ExtensionCard.parse(ExtensionCardTests.card(["iconData": nil])))
        #expect(card.iconData == nil)
    }

    @Test(arguments: [
        "https://example.com/icon.svg",
        "data:text/html;base64,PGh0bWw+",
        "data:image/svg+xml,<svg/>",
        "data:image/svg+xml;base64,not base64 at all",
        "data:image/svg+xml;base64,",
    ])
    func aFieldItCannotReadCostsOnlyTheIcon(_ raw: String) throws {
        let card = try #require(ExtensionCard.parse(ExtensionCardTests.card(["iconData": raw])))
        #expect(card.iconData == nil)
        #expect(card.title == "Lua")
    }

    @Test func refusesAnIconOverTheBudget() throws {
        let big = Data(repeating: 0x41, count: ExtensionCard.maxInlineIconBytes + 1)
        let card = try #require(ExtensionCard.parse(ExtensionCardTests.card(["iconData": Self.dataURI("image/png", big)])))
        #expect(card.iconData == nil)
    }

    @Test func theFileWinsOverTheInlineBytes() throws {
        let entry = try #require(ExtensionIndex.Entry.parse(ExtensionIndexTests.lua))
        let file = URL(fileURLWithPath: "/tmp/icon.svg")
        #expect(ExtensionIconSource.of(entry: entry, file: file)?.key == "file:/tmp/icon.svg")
    }

    @Test func theInlineBytesCarryTheVersionInTheirKey() throws {
        var json = ExtensionIndexTests.lua
        json["card"] = ExtensionCardTests.card(["iconData": Self.dataURI()])
        let entry = try #require(ExtensionIndex.Entry.parse(json))
        let source = try #require(ExtensionIconSource.of(entry: entry, file: nil))
        #expect(source.key == "inline:\(entry.id)@\(entry.version)")
    }

    /// An SVG that declares no size is not artwork this can draw, and the
    /// bytes the registry inlines are the one place icon data comes from.
    @Test func decodesTheBytesAnIconIsMadeOf() {
        #expect(ExtensionIconView.image(from: Data(base64Encoded: Self.pixel)) != nil)
        #expect(ExtensionIconView.image(from: Data("not an image".utf8)) == nil)
        #expect(ExtensionIconView.image(from: nil) == nil)
        #expect(ExtensionIconView.image(from: Self.svg) == nil)
        #expect(ExtensionIconView.image(from: Self.sizedSVG) != nil)
    }

    @Test func anEntryWithoutAnIconHasNoSource() throws {
        let entry = try #require(ExtensionIndex.Entry.parse(ExtensionIndexTests.lua))
        #expect(ExtensionIconSource.of(entry: entry, file: nil) == nil)
    }

    @MainActor
    @Test func theCacheAnswersForBothHitsAndMisses() {
        let cache = ExtensionIconCache.shared
        cache.forget()
        let image = NSImage(size: NSSize(width: 4, height: 4))

        cache.remember(image, forKey: "inline:a@1")
        cache.remember(nil, forKey: "inline:b@1")

        #expect(cache.knows("inline:a@1"))
        #expect(cache.image(forKey: "inline:a@1") === image)
        #expect(cache.knows("inline:b@1"))
        #expect(cache.image(forKey: "inline:b@1") == nil)
        #expect(!cache.knows("inline:c@1"))
        cache.forget()
    }

    @MainActor
    @Test func theCacheDropsTheOldestOverTheLimit() {
        let cache = ExtensionIconCache.shared
        cache.forget()
        for index in 0...ExtensionIconCache.limit {
            cache.remember(NSImage(size: NSSize(width: 4, height: 4)), forKey: "inline:\(index)@1")
        }

        #expect(!cache.knows("inline:0@1"))
        #expect(cache.knows("inline:\(ExtensionIconCache.limit)@1"))
        cache.forget()
    }
}
