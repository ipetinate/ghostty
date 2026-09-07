import AppKit
@testable import Ghostty
import Testing

/// The colours the editor paints a selection with.
///
/// Selecting text turned every token white and dropping the selection brought
/// the colours back. Nothing in the editor set `selectedTextAttributes`, so
/// AppKit's default dictionary applied: `#476288` for the band and `#ffffff`
/// for the glyphs, measured on the running app under `Dracula by Phantom` —
/// a theme that declares `selection-background = #44475A` and no
/// `selection-foreground`, so neither painted colour came from the theme.
///
/// These hold the two halves of the repair: the band is the theme's, and the
/// glyphs keep the highlighter's colours unless the theme names a colour for
/// them.
struct EditorSelectionColorTests {
    /// Sixteen distinct colours in the shape `make` requires. Same device as
    /// `CurrentLineHighlightTests`: the live palette is whatever the running
    /// app loaded, which on a clean checkout is nothing at all.
    private var samplePalette: [NSColor] {
        (0..<16).map { NSColor(white: CGFloat($0) / 16, alpha: 1) }
    }

    private func background(of theme: CodeTheme) -> NSColor? {
        theme.selectedTextAttributes[.backgroundColor] as? NSColor
    }

    @Test func theBandComesFromTheTheme() {
        let band = NSColor(hex: "#44475a")!
        let theme = EditorTheme.make(
            colors: samplePalette,
            background: nil,
            selectionBackground: band
        )
        #expect(background(of: theme) == band)
    }

    /// The bug, stated as an expectation. A theme silent about selected text
    /// must not put a foreground in the dictionary at all — an entry there is
    /// what replaces the token colours, whatever colour it holds.
    @Test func aSilentThemeLeavesTheTokensAlone() {
        let theme = EditorTheme.make(
            colors: samplePalette,
            background: nil,
            selectionBackground: NSColor(hex: "#44475a")!
        )
        #expect(theme.selectionForeground == nil)
        #expect(theme.selectedTextAttributes[.foregroundColor] == nil)
    }

    /// A theme that names one is asking for it *in the terminal*, which is
    /// where the key comes from and where it still holds. The editor reads
    /// none of it.
    ///
    /// All 606 themes installed on the machine this was measured on declare
    /// the key, 246 of them equal to their plain foreground — they are
    /// terminal palettes, and honouring it here left the selection
    /// monochrome on every theme but the one that omits it.
    @Test func aDeclaredForegroundReachesTheThemeAndNotTheEditor() {
        let ink = NSColor(hex: "#4a4543")!
        let theme = EditorTheme.make(
            colors: samplePalette,
            background: nil,
            selectionBackground: NSColor(hex: "#a5a2a2")!,
            selectionForeground: ink
        )
        #expect(theme.selectionForeground == ink)
        #expect(theme.selectedTextAttributes[.foregroundColor] == nil)
    }

    /// No `selection-background` means the system's band rather than no band:
    /// a selection nobody can see is worse than one in the wrong blue.
    @Test func anAbsentBandFallsBackToTheSystem() {
        let theme = EditorTheme.make(colors: samplePalette, background: nil)
        #expect(theme.selectionBackground == nil)
        #expect(background(of: theme) == .selectedTextBackgroundColor)
    }

    /// True of the neutral theme too, which is what a host supplies before
    /// the config has been read.
    @Test func theFallbackThemeStillPaintsABandAndNoForeground() {
        let theme = CodeTheme.fallback
        #expect(background(of: theme) == .selectedTextBackgroundColor)
        #expect(theme.selectedTextAttributes[.foregroundColor] == nil)
    }

    /// Neither dictionary carries a foreground, focused or not.
    ///
    /// AppKit swaps the band for its own grey while the window is not key and
    /// keeps the foreground it was handed. Catppuccin Mocha's `#1e1e2e` reads
    /// 12.95:1 on the `#f5e0dc` band it declared and 1.74:1 on that grey,
    /// measured `#464646`, which on screen is a selection with no readable
    /// text in it. 206 of the 606 themes installed here fall under 3.0:1 that
    /// way.
    @Test func theUnfocusedStateDropsADeclaredForeground() {
        let theme = EditorTheme.make(
            colors: samplePalette,
            background: nil,
            selectionBackground: NSColor(hex: "#f5e0dc")!,
            selectionForeground: NSColor(hex: "#1e1e2e")!
        )
        #expect(theme.selectedTextAttributes[.foregroundColor] == nil)
        #expect(theme.unemphasizedSelectedTextAttributes[.foregroundColor] == nil)
    }

    /// Both states agree on the band. Only the foreground is at stake — the
    /// band AppKit actually paints when unfocused is its own either way.
    @Test func bothStatesCarryTheSameBand() {
        let band = NSColor(hex: "#44475a")!
        let theme = EditorTheme.make(
            colors: samplePalette,
            background: nil,
            selectionBackground: band,
            selectionForeground: NSColor(hex: "#ffffff")!
        )
        #expect(background(of: theme) == band)
        #expect(theme.unemphasizedSelectedTextAttributes[.backgroundColor] as? NSColor == band)
    }

    /// The parser has to produce both, or the band above has nothing to come
    /// from. `selection-foreground` was already an accepted key for a
    /// contributed theme — see `ThemeContribution.colorKeys` — and was the
    /// one of the pair the parser dropped.
    @Test func theParserReadsBothSelectionKeys() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phantom-selection-\(UUID().uuidString).theme")
        try """
        background = #f7f7f7
        foreground = #4a4543
        selection-background = #a5a2a2
        selection-foreground = #4a4543
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let theme = try #require(ThemeCatalog.parse(url: url, source: .user))
        #expect(theme.selectionBackground == NSColor(hex: "#a5a2a2"))
        #expect(theme.selectionForeground == NSColor(hex: "#4a4543"))
    }

    /// And a theme that names only the band leaves the other nil, which is
    /// the state `Dracula by Phantom` is in and the one the defect was
    /// reported against.
    @Test func theParserLeavesAnUndeclaredForegroundNil() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phantom-selection-\(UUID().uuidString).theme")
        try """
        background = #060608
        foreground = #f8f8f2
        selection-background = #44475a
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let theme = try #require(ThemeCatalog.parse(url: url, source: .user))
        #expect(theme.selectionBackground == NSColor(hex: "#44475a"))
        #expect(theme.selectionForeground == nil)
    }
}
