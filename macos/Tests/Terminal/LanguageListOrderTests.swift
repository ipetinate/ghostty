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
