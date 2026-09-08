import AppKit
import Foundation
@testable import Ghostty
import Testing

/// The order a grouped listing of languages puts things in — the store's,
/// now that the Languages pane is gone.
///
/// The view sorts both levels itself, so these pin the inputs that sort has
/// to work with rather than the view — a `private var` in a `View` is not
/// reachable from here, and reaching for it would test the wrong thing
/// anyway.
struct LanguageListOrderTests {
    /// Alphabetical by header, so a reader hunting for a section scans
    /// instead of learning somebody's idea of importance. Pinned as a
    /// literal because the sort key is the *title*, not the case name — the
    /// two disagree for every case, and sorting the wrong one still
    /// produces a plausible-looking list.
    @Test func theHeadersAreAlphabetical() {
        let sorted = LSPServerCategory.allCases
            .map(\.title)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        #expect(sorted == [
            "Compiled", "Data", "Frontend Frameworks",
            "Infrastructure", "Markup", "Script", "Styles",
        ])
    }

    /// `localizedStandardCompare`, not `<`. A plain comparison orders by
    /// scalar value, which puts "(" before a digit and would separate two
    /// rows of one family by whatever else happens to share their prefix.
    @Test func digitsSortAsNumbersRatherThanCharacters() {
        let names = ["TypeScript 10 (Go)", "TypeScript 7 (Go)", "TypeScript (npm)"]
        let sorted = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        #expect(sorted.firstIndex(of: "TypeScript 7 (Go)")! < sorted.firstIndex(of: "TypeScript 10 (Go)")!)
    }

}

/// The symbols beside the section headers, which nothing checked until the
/// row logos left with the server table.
///
/// A symbol name that does not resolve draws **nothing** — no crash, no
/// warning, an 18-point hole in the list, and in a `List` row it can take
/// the row with it. These headings are now the only artwork in the store's
/// listing the binary still decides; the icon beside a row comes from the
/// extension, and `LanguageIconTests` covers that.
@MainActor
struct LanguageSectionSymbolTests {
    @Test func everySectionHeaderDrawsItsSymbol() {
        for category in LSPServerCategory.allCases {
            #expect(!category.title.isEmpty, "\(category.rawValue) has no title")
            #expect(
                NSImage(systemSymbolName: category.systemImage, accessibilityDescription: nil) != nil,
                "\(category.rawValue) names \(category.systemImage), which is not an SF Symbol"
            )
        }
    }
}

/// The icon beside a row, which the extension decides and this build does
/// not.
///
/// It replaced a table of 22 bundled logos keyed on language id — the last
/// compiled-in language table in the binary, and redundant once every
/// contributed language declared its own `icon`. What is left to get wrong is
/// the wiring: reading the wrong field, or losing the fallback and drawing an
/// 18-point hole for a contribution that declares nothing.
///
/// The path rules the icon has to satisfy are not asserted here.
/// `LanguageManifestTests.anIconOutsideTheExtensionIsRefused` already pins
/// them, and a second copy would drift.
@MainActor
struct LanguageIconTests {
    private static let root = URL(fileURLWithPath: "/tmp/phantom-tests/acme.rust")

    private func language(_ body: String) throws -> LanguageContribution {
        let json = #"""
        {
          "schemaVersion": 1,
          "id": "acme.rust",
          "name": "Rust Pack",
          "version": "1.0.0",
          "publisher": "acme",
          "contributes": { "languages": [{ \#(body) }] }
        }
        """#
        let manifest = try #require(LanguageManifest.parse(
            data: Data(json.utf8),
            url: Self.root.appendingPathComponent(LanguageManifest.fileName),
            root: Self.root,
            scope: .user))
        return try #require(manifest.languages.first)
    }

    /// The row draws what the manifest named, resolved against the
    /// extension's own directory.
    @Test func theRowDrawsTheIconTheContributionDeclares() throws {
        let rust = try language(#""languageId": "rust", "icon": "icons/rust.png""#)
        let icon = try #require(rust.iconURL)

        #expect(icon.lastPathComponent == "rust.png")
        #expect(icon.deletingLastPathComponent().lastPathComponent == "icons")
        #expect(icon.path.hasPrefix(Self.root.path + "/"))
        #expect(ExtensionIconSource.file(icon).key == "file:" + icon.path)
    }

    /// A contribution that declares none falls back to a symbol rather than
    /// to nothing. An unresolved SF Symbol draws no glyph and no warning, so
    /// the fallback is checked against the system rather than assumed.
    @Test func aContributionWithNoIconFallsBackToASymbolThatResolves() throws {
        let rust = try language(#""languageId": "rust""#)

        #expect(rust.iconURL == nil)
        #expect(
            NSImage(systemSymbolName: LanguageIconView.genericSymbol, accessibilityDescription: nil) != nil,
            "\(LanguageIconView.genericSymbol) is not an SF Symbol")
    }

    /// Nothing in the app bundle is named after a language any more. The
    /// deleted assets were reachable by name alone, so a caller left behind
    /// would have kept drawing one until somebody looked.
    @Test func theBundleShipsNoLanguageLogos() {
        for name in ["Lang-rust", "Lang-ts-js", "Lang-css", "Lang-tailwind"] {
            #expect(NSImage(named: name) == nil, "\(name) is still in Assets.xcassets")
        }
    }
}
