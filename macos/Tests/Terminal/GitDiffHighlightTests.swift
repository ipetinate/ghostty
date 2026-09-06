import Foundation
@testable import Ghostty
import Testing

/// The token colouring a diff document carries for its two columns.
///
/// Every line of a diff used to be drawn in one foreground colour, which made
/// a screen of additions a screen of undifferentiated green. These tests pin
/// the three rules that changed it: which grammar each column is lexed with,
/// where a token lands once it is cut back up per line, and what a file no
/// installed extension claims falls back to.
///
/// The grammar is ``FixtureGrammar``, installed into a snapshot of its own,
/// because the binary ships none: a `.fx` file is coloured and a `.bin` file
/// is not, and that is the whole of what the highlighter knows.
@MainActor
struct GitDiffHighlightTests {
    private func document(_ output: String) throws -> GitDiffDocument {
        GitDiffDocument(
            file: try #require(GitDiffParser.parse(unified: output).first),
            snapshot: try FixtureGrammar.snapshot())
    }

    private func drawn(_ span: GitDiffHighlight.Span, of line: GitDiffLine?) throws -> String {
        (try #require(line).displayText as NSString).substring(with: span.range)
    }

    @Test func theGrammarComesFromTheNameAndNotThePath() throws {
        let snapshot = try FixtureGrammar.snapshot()

        #expect(!GitDiffHighlight.highlighter(forPath: "src/lib/total.fx", in: snapshot).isPlain)
        #expect(GitDiffHighlight.highlighter(forPath: "src/lib/total.fx.bak", in: snapshot).isPlain)
        #expect(GitDiffHighlight.highlighter(forPath: "assets/data.bin", in: snapshot).isPlain)
    }

    /// The rule that replaced the compiled-in lexers: a name nothing
    /// installed claims is plain, however well the binary once knew it.
    @Test func aNameNoExtensionClaimsIsPlain() {
        let nothing = FixtureGrammar.emptySnapshot()

        #expect(GitDiffHighlight.highlighter(forPath: "src/lib/total.fx", in: nothing).isPlain)
        #expect(GitDiffHighlight.highlighter(forPath: "macos/Sources/App.swift", in: nothing).isPlain)
    }

    /// Both columns of one row, each lexed on its own text: the old line is a
    /// comment and the new one is code, and neither answer leaks across.
    @Test func eachColumnIsColouredByItsOwnTokens() throws {
        let document = try document(#"""
        diff --git a/src/total.fx b/src/total.fx
        --- a/src/total.fx
        +++ b/src/total.fx
        @@ -1 +1 @@
        -// the total
        +const total = "two"
        """#)

        let row = try #require(document.rows.first)
        let left = document.highlight.spans(forRow: row.id, side: .left)
        let right = document.highlight.spans(forRow: row.id, side: .right)

        #expect(left.map(\.kind) == [.comment])
        #expect(right.map(\.kind) == [.keyword, .string])
        #expect(try right.map { try drawn($0, of: row.right) } == ["const", #""two""#])
    }

    /// The offsets are into the line the pane draws, which is the reason the
    /// colouring is worked out on `displayText`: measured on `text`, every
    /// span of a CRLF file would sit one character short of the glyph it
    /// belongs to and the last of them would run past the end.
    @Test func aCarriageReturnIsOutsideEverySpan() throws {
        let document = try document(
            "diff --git a/x.fx b/x.fx\n--- a/x.fx\n+++ b/x.fx\n@@ -1 +1 @@\n-const a = \"1\"\r\n+const a = \"2\"\r\n")

        let row = try #require(document.rows.first)
        let spans = document.highlight.spans(forRow: row.id, side: .right)
        let drawnLength = (try #require(row.right).displayText as NSString).length

        #expect(spans.map(\.kind) == [.keyword, .string])
        #expect(spans.allSatisfy { NSMaxRange($0.range) <= drawnLength })
        #expect(try drawn(try #require(spans.last), of: row.right) == #""2""#)
    }

    /// Why a side is lexed whole rather than a line at a time: none of these
    /// three lines is a comment on its own, and a per-line pass would colour
    /// the opener and leave the body plain.
    @Test func aBlockCommentKeepsItsColourOnEveryLineItSpans() throws {
        let document = try document(#"""
        diff --git a/lib.fx b/lib.fx
        --- a/lib.fx
        +++ b/lib.fx
        @@ -1,2 +1,5 @@
         const one = "1"
        +/*
        + * why this exists
        + */
         const two = "2"
        """#)

        let added = document.rows.filter { $0.left == nil && $0.right != nil }
        #expect(added.count == 3)

        for row in added {
            #expect(document.highlight.spans(forRow: row.id, side: .right).map(\.kind) == [.comment])
        }
        #expect(try added.map {
            try drawn(try #require(document.highlight.spans(forRow: $0.id, side: .right).first), of: $0.right)
        } == ["/*", " * why this exists", " */"])

        /// The rows are filler on the left, and the two sides are indexed
        /// apart — the old column's spans belong to the lines it actually
        /// has.
        for row in added {
            #expect(document.highlight.spans(forRow: row.id, side: .left).isEmpty)
        }
    }

    /// A rename can carry a file into a language, and the old column is still
    /// the old file: lexed by the new name, the old comment would take a
    /// colour its file never had.
    @Test func aRenameLexesEachColumnByTheNameThatColumnHad() throws {
        let document = try document(#"""
        diff --git a/tool.txt b/tool.fx
        similarity index 60%
        rename from tool.txt
        rename to tool.fx
        --- a/tool.txt
        +++ b/tool.fx
        @@ -1 +1 @@
        -// the old comment
        +// the new comment
        """#)

        let row = try #require(document.rows.first)
        #expect(document.highlight.spans(forRow: row.id, side: .left).isEmpty)
        #expect(document.highlight.spans(forRow: row.id, side: .right).map(\.kind) == [.comment])
    }

    /// The fallback, and the reason it is an empty list rather than an empty
    /// line: a file nothing installed can lex draws exactly as it did before
    /// there was any colouring.
    @Test func aLanguageWithNoRulesLeavesEveryLinePlain() throws {
        let document = try document(#"""
        diff --git a/data.bin b/data.bin
        --- a/data.bin
        +++ b/data.bin
        @@ -1 +1 @@
        -const total = "1"
        +const total = "2"
        """#)

        let row = try #require(document.rows.first)
        #expect(document.highlight.spans(forRow: row.id, side: .left).isEmpty)
        #expect(document.highlight.spans(forRow: row.id, side: .right).isEmpty)
    }

    /// The budget degrades the way the inline-edit budget does: the lines
    /// past it keep their numbers, their signs and their band, and only lose
    /// their colours.
    @Test func pastTheBudgetTheColouringStopsRatherThanTheDiff() throws {
        let line = "const value = \"1\""
        let count = (GitDiffHighlight.textBudget / (line.count + 1)) * 2

        var output = "diff --git a/big.fx b/big.fx\n--- a/big.fx\n+++ b/big.fx\n@@ -0,0 +1,\(count) @@\n"
        output += String(repeating: "+\(line)\n", count: count)
        let document = try document(output)

        #expect(document.rows.count == count)
        #expect(!document.highlight.spans(forRow: 0, side: .right).isEmpty)
        #expect(document.highlight.spans(forRow: count - 1, side: .right).isEmpty)
    }
}

/// Colouring a fragment of a document whose grammar carries state.
///
/// A block comment opened above the hunk changes what every line of the hunk
/// is, and the hunk alone cannot say the comment is open: lexed on its own it
/// reads as code. The whole version of the file answers instead, mapped on by
/// line number.
@MainActor
struct GitDiffWholeFileHighlightTests {
    /// Six lines, and the change is on the fourth — two lines below the
    /// opener and one above the closer, so a two-line hunk carries neither.
    private let source = """
    let a = "1"
    /* opened here
    const searchTerm = "x"
    const total = "one"
    closed here */
    let b = "2"
    """

    private var updated: String {
        source.replacingOccurrences(of: "const total = \"one\"", with: "const total = \"two\"")
    }

    private let fragment = """
    diff --git a/lib.fx b/lib.fx
    --- a/lib.fx
    +++ b/lib.fx
    @@ -3,2 +3,2 @@
     const searchTerm = "x"
    -const total = "one"
    +const total = "two"
    """

    private func document(_ output: String, source: GitDiffSource = .none) throws -> GitDiffDocument {
        GitDiffDocument(
            file: try #require(GitDiffParser.parse(unified: output).first),
            source: source,
            snapshot: try FixtureGrammar.snapshot())
    }

    private func drawn(_ span: GitDiffHighlight.Span, of line: GitDiffLine?) throws -> String {
        (try #require(line).displayText as NSString).substring(with: span.range)
    }

    /// **The defect, pinned.** The fragment carries no opener, so the diff
    /// alone colours a commented-out line as if it were live code.
    @Test func theDiffAloneCannotSeeTheCommentOpenedAbove() throws {
        let document = try document(fragment)
        let row = try #require(document.rows.first { $0.left?.kind == .removed })

        #expect(document.highlight.spans(forRow: row.id, side: .left).map(\.kind) == [.keyword, .string])
        #expect(document.highlight.spans(forRow: row.id, side: .right).map(\.kind) == [.keyword, .string])
    }

    @Test func theWholeFileColoursTheSameFragment() throws {
        let document = try document(fragment, source: GitDiffSource(old: source, new: updated))
        let row = try #require(document.rows.first { $0.left?.kind == .removed })

        let left = document.highlight.spans(forRow: row.id, side: .left)
        let right = document.highlight.spans(forRow: row.id, side: .right)

        #expect(left.map(\.kind) == [.comment])
        #expect(right.map(\.kind) == [.comment])
        #expect(try left.map { try drawn($0, of: row.left) } == ["const total = \"one\""])
        #expect(try right.map { try drawn($0, of: row.right) } == ["const total = \"two\""])
    }

    /// The context lines too — they are most of a fragment, and they are the
    /// lines the reader has to read the change against.
    @Test func theContextLinesAreColouredAsWell() throws {
        let document = try document(fragment, source: GitDiffSource(old: source, new: updated))
        let row = try #require(document.rows.first { $0.left?.kind == .context })

        #expect(document.highlight.spans(forRow: row.id, side: .right).map(\.kind) == [.comment])
    }

    /// The state is carried through the closer as well as up to it: a hunk
    /// that reaches past `*/` has its last line coloured as code again.
    @Test func theLinesAfterTheCloserAreCodeAgain() throws {
        let output = """
        diff --git a/lib.fx b/lib.fx
        --- a/lib.fx
        +++ b/lib.fx
        @@ -4,3 +4,3 @@
        -const total = "one"
        +const total = "two"
         closed here */
         let b = "2"
        """
        let document = try document(output, source: GitDiffSource(old: source, new: updated))
        let last = try #require(document.rows.last)

        #expect(try #require(last.right).displayText == "let b = \"2\"")
        #expect(document.highlight.spans(forRow: last.id, side: .right).map(\.kind) == [.keyword, .string])
    }

    /// One side read and the other not is an ordinary state — a rename whose
    /// old name is gone, a base that could not be resolved — and the side
    /// with nothing falls back rather than taking the other's answer.
    @Test func oneSideWithNoVersionLeavesTheOtherAlone() throws {
        let document = try document(fragment, source: GitDiffSource(old: nil, new: updated))
        let row = try #require(document.rows.first { $0.left?.kind == .removed })

        #expect(document.highlight.spans(forRow: row.id, side: .left).map(\.kind) == [.keyword, .string])
        #expect(document.highlight.spans(forRow: row.id, side: .right).map(\.kind) == [.comment])
    }

    /// A version that is not the one the diff was taken against maps onto
    /// nothing, and the diff's own text answers instead. Colouring a line
    /// from the wrong file is the failure this refuses.
    @Test func aVersionThatDoesNotMatchIsDiscarded() throws {
        let document = try document(
            fragment,
            source: GitDiffSource(old: "something else\n", new: "something else\n"))
        let row = try #require(document.rows.first { $0.left?.kind == .removed })

        #expect(document.highlight.spans(forRow: row.id, side: .right).map(\.kind) == [.keyword, .string])
    }

    /// The fallback, with a version in hand: a file nothing installed can lex
    /// draws plain whatever else is known about it.
    @Test func aLanguageWithNoRulesIsStillPlain() throws {
        let output = """
        diff --git a/data.bin b/data.bin
        --- a/data.bin
        +++ b/data.bin
        @@ -3,2 +3,2 @@
         const searchTerm = "x"
        -const total = "one"
        +const total = "two"
        """
        let document = try document(output, source: GitDiffSource(old: source, new: updated))
        let row = try #require(document.rows.first { $0.left?.kind == .removed })

        #expect(document.highlight.spans(forRow: row.id, side: .left).isEmpty)
        #expect(document.highlight.spans(forRow: row.id, side: .right).isEmpty)
    }
}

/// Which diffs pay for reading both versions of their file.
@MainActor
struct GitDiffWholeFileNeedTests {
    private func file(_ output: String) throws -> GitFileDiff {
        try #require(GitDiffParser.parse(unified: output).first)
    }

    private func diff(_ path: String) -> String {
        """
        diff --git a/\(path) b/\(path)
        --- a/\(path)
        +++ b/\(path)
        @@ -4,1 +4,1 @@
        -const total = "one"
        +const total = "two"
        """
    }

    /// Every grammar carries state across lines, so every file a grammar
    /// colours asks for its whole version when it changes.
    @Test func aChangedFileAGrammarColoursAsksForIt() throws {
        let snapshot = try FixtureGrammar.snapshot()

        #expect(GitDiffHighlight.needsWholeFile(try file(diff("src/lib.fx")), snapshot: snapshot))
    }

    @Test func aFileNothingColoursDoesNot() throws {
        let snapshot = try FixtureGrammar.snapshot()

        #expect(!GitDiffHighlight.needsWholeFile(try file(diff("assets/data.bin")), snapshot: snapshot))
        #expect(!GitDiffHighlight.needsWholeFile(try file(diff("src/lib.fx")), snapshot: FixtureGrammar.emptySnapshot()))
    }

    /// Either name is enough: the old column is lexed by the old name and
    /// the new by the new, and a rename into a coloured language pays for
    /// the side that is coloured.
    @Test func aRenameAsksWhenEitherNameIsColoured() throws {
        let renamed = """
        diff --git a/tool.txt b/tool.fx
        similarity index 60%
        rename from tool.txt
        rename to tool.fx
        --- a/tool.txt
        +++ b/tool.fx
        @@ -1 +1 @@
        -const total = "one"
        +const total = "two"
        """
        #expect(GitDiffHighlight.needsWholeFile(try file(renamed), snapshot: try FixtureGrammar.snapshot()))
    }

    /// A file arriving or leaving already has every line of itself in the
    /// hunks, and a branch of new work is mostly made of those.
    @Test func aWholeFileArrivingOrLeavingDoesNot() throws {
        let added = """
        diff --git a/lib.fx b/lib.fx
        new file mode 100644
        --- /dev/null
        +++ b/lib.fx
        @@ -0,0 +1,1 @@
        +const total = "one"
        """
        let deleted = """
        diff --git a/lib.fx b/lib.fx
        deleted file mode 100644
        --- a/lib.fx
        +++ /dev/null
        @@ -1,1 +0,0 @@
        -const total = "one"
        """
        let snapshot = try FixtureGrammar.snapshot()
        #expect(!GitDiffHighlight.needsWholeFile(try file(added), snapshot: snapshot))
        #expect(!GitDiffHighlight.needsWholeFile(try file(deleted), snapshot: snapshot))
    }
}

/// Which two versions each side of a diff compares, named for `git show`.
struct GitDiffRevisionTests {
    /// The new side of a working-tree diff is the file on disk. Git prints a
    /// hash for it in the diff header and that hash names no object — so nil
    /// here means "read the file", not "give up".
    @Test func aWorkingTreeDiffComparesTheIndexAgainstTheDisk() {
        let revisions = GitDiffLoader.revisions(for: .unstaged, in: "/")
        #expect(revisions?.old == ":0")
        #expect(revisions?.new == nil)
    }

    @Test func aStagedDiffComparesTheCommitAgainstTheIndex() {
        let revisions = GitDiffLoader.revisions(for: .staged, in: "/")
        #expect(revisions?.old == "HEAD")
        #expect(revisions?.new == ":0")
    }
}
