import AppKit
import Foundation
@testable import Ghostty
import Testing

/// The order the Languages pane puts things in.
///
/// The pane sorts both levels itself, so these pin the inputs that sort has
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
/// the row with it. The same failure the asset-catalogue check used to catch
/// for the per-server logos, at the one place an icon still comes from the
/// binary rather than from a manifest.
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

/// The logo beside a row, which is the other icon the binary still decides.
///
/// It fails the same silent way a section symbol does — an asset name that is
/// not in the catalogue draws nothing, an 18-point hole — and it lost its
/// check when the server table it used to be enumerated from was deleted.
@MainActor
struct LanguageIconAssetTests {
    @Test func everyLogoTheListCanAskForIsInTheCatalogue() {
        let names = LSPServerDefinition.languageIconNames

        #expect(names.count > 15, "expected the whole set of logos, got \(names.count)")

        for (languageID, name) in names.sorted(by: { $0.key < $1.key }) {
            #expect(name.hasPrefix("Lang-"), "\(languageID) names \(name)")
            #expect(NSImage(named: name) != nil, "\(name) is not in Assets.xcassets")
            #expect(LSPServerDefinition.iconName(forLanguageID: languageID) == name)
        }
    }

    /// The ids that share one image. Four spellings of one language family
    /// and two preprocessors of one stylesheet language, which is a decision
    /// worth pinning: drawing `scss` with no logo at all would be a
    /// regression nobody would notice from a green suite.
    @Test func theSharedLogosStaySharedAndDoNotLeak() {
        let tsjs = ["typescript", "typescriptreact", "javascript", "javascriptreact"]
        #expect(tsjs.allSatisfy { LSPServerDefinition.iconName(forLanguageID: $0) == "Lang-ts-js" })

        let css = ["css", "scss", "less"]
        #expect(css.allSatisfy { LSPServerDefinition.iconName(forLanguageID: $0) == "Lang-css" })

        #expect(LSPServerDefinition.iconName(forLanguageID: "shellscript") == "Lang-bash")
    }

    /// A language this app ships no logo for gets the generic glyph rather
    /// than a blank, and after 0.17.0 that is the normal case: every language
    /// comes from an extension, and an extension is free to name one this
    /// build has never heard of.
    @Test func aLanguageWithNoLogoFallsBackToASymbolThatResolves() {
        for languageID in ["elixir", "fixture", "", "TypeScript", "swift-testing"] {
            #expect(
                LSPServerDefinition.iconName(forLanguageID: languageID) == nil,
                "\(languageID) claimed a logo this app does not ship"
            )
        }

        #expect(
            NSImage(
                systemSymbolName: LSPServerDefinition.genericLanguageSymbol,
                accessibilityDescription: nil
            ) != nil
        )
    }
}
