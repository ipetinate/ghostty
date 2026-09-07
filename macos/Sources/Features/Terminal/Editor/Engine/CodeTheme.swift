import AppKit

/// What the highlighter recognizes.
///
/// Deliberately small. These are the distinctions a terminal palette can
/// actually express — sixteen colors, of which a handful read as different
/// at a glance — so a richer set would be invented precision that nothing
/// downstream could show.
enum TokenKind: String, CaseIterable, Equatable, Sendable {
    case plain
    case keyword
    case string
    case comment
    case number
    case type
    case function
    case attribute
    case punctuation
}

/// The colors a code view paints with.
///
/// A plain value on purpose: the engine must never reach for the app's
/// theme singleton. The host builds one of these from whatever it calls a
/// theme and hands it over, which is what lets this whole directory move
/// into a package later without dragging Phantom behind it.
struct CodeTheme: Equatable {
    var foreground: NSColor
    var background: NSColor
    var tokens: [TokenKind: NSColor]

    /// The gutter's digits, and the rule between gutter and text.
    var lineNumber: NSColor
    var currentLineNumber: NSColor
    var currentLineBackground: NSColor?

    /// The band behind selected text, or nil for a theme that names none.
    var selectionBackground: NSColor?

    /// The colour selected glyphs take, or nil for a theme that names none.
    ///
    /// Nil is the interesting case and the common one: a theme silent about
    /// selected text keeps the code's own colours under the band.
    var selectionForeground: NSColor?

    /// What the text view paints the selection with while it has focus.
    ///
    /// **A background, and a foreground only when the theme asked for one.**
    /// AppKit's default dictionary carries `NSColor.selectedTextColor`, which
    /// measured `#ffffff` under this appearance and replaced every token
    /// colour inside the selected range: selecting a line turned it
    /// monochrome and dropping the selection brought its colours back. That
    /// is right for a terminal, where selected text taking one colour is
    /// what every terminal does, and wrong for a code editor, where the band
    /// is drawn *behind* code that keeps its colours. This app is both, which
    /// is why the terminal's behaviour reached the editor and read as
    /// deliberate. Omitting `.foregroundColor` is the whole of the repair.
    ///
    /// The band comes from the theme's `selection-background` and falls back
    /// to `NSColor.selectedTextBackgroundColor` — the `#476288` that was
    /// measured — for a theme that declares none.
    var selectedTextAttributes: [NSAttributedString.Key: Any] {
        var attributes = unemphasizedSelectedTextAttributes
        if let selectionForeground {
            attributes[.foregroundColor] = selectionForeground
        }
        return attributes
    }

    /// What it paints the selection with while the window is not key.
    ///
    /// The band only — no `selection-foreground`, however loudly the theme
    /// declared one. AppKit substitutes
    /// `NSColor.unemphasizedSelectedTextBackgroundColor` for the band in this
    /// state and keeps whatever foreground it was handed: measured `#464646`
    /// dark and `#dcdcdc` light. A theme picks its selected-text colour
    /// against its *own* band, so on that grey the pairing is one nobody
    /// chose. Of the 606 themes installed here, 206 fall under 3.0:1 that
    /// way and 143 of those clear 4.5:1 on the band they declared.
    /// Catppuccin Mocha is the extreme: `#1e1e2e` reads 12.95:1 on its own
    /// `#f5e0dc` and 1.74:1 on the grey, which on screen is a selection with
    /// no readable text in it at all.
    ///
    /// The tokens' own colours are legible there — Mocha's measure 4.48:1 to
    /// 7.43:1 on `#464646` — so an unfocused selection is given the same
    /// treatment as a theme that named no selected-text colour.
    var unemphasizedSelectedTextAttributes: [NSAttributedString.Key: Any] {
        [.backgroundColor: selectionBackground ?? .selectedTextBackgroundColor]
    }

    func color(for kind: TokenKind) -> NSColor {
        tokens[kind] ?? foreground
    }

    /// The colours brackets cycle through, by nesting depth.
    ///
    /// Borrowed from the token colours rather than added to the theme: a
    /// terminal theme has sixteen colours and no notion of a bracket, so
    /// inventing three more would mean inventing them out of nothing. These
    /// three are far enough apart to tell at a glance and are already in the
    /// palette the reader chose.
    var bracketColors: [NSColor] {
        [
            color(for: .number),
            color(for: .keyword),
            color(for: .type),
        ]
    }

    /// The wash behind the bracket under the caret and behind its partner.
    ///
    /// Derived from the foreground rather than added to the theme, for the
    /// same reason as `bracketColors`: a terminal palette has sixteen colours
    /// and no notion of this, so a new field would be a colour invented out
    /// of nothing and wrong for half the themes somebody might pick.
    ///
    /// A translucent wash rather than a replacement colour, because the two
    /// marks on that character say different things and both are wanted: the
    /// glyph keeps its depth colour — which pair it belongs to — while the
    /// wash says the caret is on this one. Painting over the glyph would
    /// trade one fact for the other.
    var bracketMatchBackground: NSColor {
        foreground.withAlphaComponent(0.22)
    }

    /// The colour of the box drawn round a symbol a jump landed on.
    ///
    /// Borrowed from the palette rather than added to the theme, for the same
    /// reason as `bracketColors`: a terminal theme has sixteen colours and no
    /// notion of this one, so a new field would be a colour invented out of
    /// nothing and wrong for half the themes somebody might pick.
    ///
    /// The number slot, which is yellow in every sixteen-colour scheme — the
    /// colour every editor marks a search hit in, and the reason it is that
    /// slot and not the blue one: **the selection is blue**, and telling the
    /// mark apart from a selection is the whole point of drawing it. Full
    /// strength here; how much of it the wash and the outline take is the
    /// drawing's business.
    var revealHighlight: NSColor {
        color(for: .number)
    }

    /// A neutral theme, used before a host supplies one and by the tests.
    static var fallback: CodeTheme {
        CodeTheme(
            foreground: .textColor,
            background: .textBackgroundColor,
            tokens: [
                .keyword: .systemPurple,
                .string: .systemGreen,
                .comment: .secondaryLabelColor,
                .number: .systemOrange,
                .type: .systemTeal,
                .function: .systemBlue,
                .attribute: .systemPink,
                .punctuation: .secondaryLabelColor,
            ],
            lineNumber: .tertiaryLabelColor,
            currentLineNumber: .secondaryLabelColor,
            currentLineBackground: nil
        )
    }
}

/// How the code view behaves: everything a preferences screen would drive.
///
/// Also a value, for the same reason as `CodeTheme` — the engine reads no
/// `UserDefaults` of its own.
struct CodeEditorConfiguration: Equatable {
    var font: NSFont
    var showsLineNumbers: Bool
    var wrapsLines: Bool

    /// Spaces a tab is drawn as. Only affects display; what gets typed is
    /// decided by `insertsSpacesForTab`.
    var tabWidth: Int
    var insertsSpacesForTab: Bool
    var highlightsCurrentLine: Bool

    /// Whether brackets are coloured by nesting depth.
    var colorsBracketPairs: Bool = true

    /// Whether the minimap is drawn beside the text.
    ///
    /// Part of the configuration rather than a property of its own, so that
    /// turning it off in Settings is a change the appearance pass *notices*.
    /// As a separate value it was only read when the view was first made, and
    /// the switch did nothing until the file was reopened.
    var showsMinimap: Bool = true

    /// Whether typing an opener writes its closer too.
    ///
    /// Three switches rather than one because they fail differently and are
    /// disliked separately — see `EditorSettings` for the reasoning. All
    /// three default to on, which is what every editor this one is measured
    /// against does.
    ///
    /// **These are read on every keystroke, unlike everything above them.**
    /// The rest of this type describes how the text is *drawn*, so it is
    /// consulted when appearance is applied; these three decide what gets
    /// *written*, so they have to be current at the moment a key is pressed
    /// rather than at the moment the view was last restyled.
    var closesBrackets: Bool = true
    var closesQuotes: Bool = true
    var closesTags: Bool = true

    /// Whether the completion list may open at all.
    ///
    /// One flag rather than a global and a per-language pair, because the
    /// engine has no idea what language it is showing — the host resolves
    /// "completion is on, and it is on for *this* language" into a single
    /// yes before the value gets here. Same direction as everything else in
    /// this type: the engine is told, it does not ask.
    ///
    /// **Read on every keystroke, like the three switches above it and
    /// unlike everything above those.** The rest of this type describes how
    /// the text is drawn, so it is consulted when appearance is applied;
    /// this decides whether a keystroke opens a list, so it has to be
    /// current at the moment the key is pressed rather than at the moment
    /// the view was last restyled — which is the bug `showsMinimap`
    /// documents, and the reason its consumer belongs outside the
    /// `unchanged` guard in `applyAppearance`.
    var completionEnabled: Bool = true

    /// Whether the list falls back to words already in the buffer.
    ///
    /// Separate from `completionEnabled` because they fail differently: the
    /// fallback is what makes a language with no server installed still
    /// complete, and it is also what puts a variable name from a comment
    /// beside the server's answer. Somebody who dislikes the second should
    /// not have to lose the first.
    var completesFromBuffer: Bool = true

    /// How long the caret rests before suggestions are asked for.
    ///
    /// Part of the configuration rather than left at the engine's own
    /// default so that changing it in Settings is a change the running
    /// editor notices — a value read once when the view was built would do
    /// nothing until the file was reopened.
    var completionFetchDelay: Duration = .milliseconds(120)

    static var `default`: CodeEditorConfiguration {
        CodeEditorConfiguration(
            font: .monospacedSystemFont(ofSize: 12, weight: .regular),
            showsLineNumbers: true,
            wrapsLines: false,
            tabWidth: 4,
            insertsSpacesForTab: true,
            highlightsCurrentLine: true,
            colorsBracketPairs: true,
            showsMinimap: true,
            closesBrackets: true,
            closesQuotes: true,
            closesTags: true,
            completionEnabled: true,
            completesFromBuffer: true,
            completionFetchDelay: .milliseconds(120)
        )
    }
}
