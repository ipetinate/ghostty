import Foundation
@testable import Ghostty
import Testing

/// Which characters a jump marks.
///
/// String arithmetic, which is the point: the box needs a laid-out text view,
/// a window and a font, and the part that is easy to get wrong needs none of
/// them. What is asserted here is the rule a reader would complain about — a
/// mark over a whole module, a mark over indentation, a mark over nothing at
/// all — and the boundaries where a range meets the end of the file.
struct CodeRevealHighlightTests {
    private func mark(_ range: NSRange, in text: String) -> String? {
        guard let found = CodeRevealHighlight.range(for: range, in: text as NSString)
        else { return nil }
        return (text as NSString).substring(with: found)
    }

    // MARK: A range that fits on one line is the name already

    /// What most servers answer with, and it is handed back untouched.
    @Test func aSingleLineRangeIsMarkedAsItCame() {
        let text = "let total = count + 1\n"
        #expect(mark(NSRange(location: 4, length: 5), in: text) == "total")
    }

    @Test func aRangeStartingMidLineKeepsItsOwnStart() {
        let text = "defmodule Blog.Content.Post do\n"
        #expect(mark(NSRange(location: 10, length: 20), in: text) == "Blog.Content.Post do")
    }

    /// A range that runs to the end of its line must not swallow the newline:
    /// a mark over a line terminator draws a box reaching past the last glyph.
    @Test func theLineTerminatorIsNeverMarked() {
        let text = "alpha\nbeta\n"
        #expect(mark(NSRange(location: 0, length: 6), in: text) == "alpha")
    }

    // MARK: A range over several lines is marked on its first

    /// The reported defect. Elixir's server answers with the whole module, and
    /// what the reader wanted to see was the declaration.
    @Test func aWholeModuleIsMarkedOnItsDeclaration() {
        let text = """
        defmodule Blog.Content.Post do
          use Ecto.Schema

          schema "posts" do
            field :title, :string
          end
        end
        """
        let whole = NSRange(location: 0, length: (text as NSString).length)
        #expect(mark(whole, in: text) == "defmodule Blog.Content.Post do")
    }

    /// Leading indentation is not part of the name, and a box that starts in
    /// empty space reads as a misplaced one.
    @Test func indentationIsTrimmedOffTheFirstLine() {
        let text = "class Post {\n    func save() {\n        write()\n    }\n}\n"
        let definition = NSRange(location: 13, length: 40)
        #expect(mark(definition, in: text) == "func save() {")
    }

    /// A range whose first line is blank falls through to the first line in it
    /// that has something on it — a mark over nothing points at nothing.
    @Test func aBlankFirstLineFallsThroughToTheNextWithContent() {
        let text = "\n   \n  def save do\n    :ok\n  end\n"
        let whole = NSRange(location: 0, length: (text as NSString).length)
        #expect(mark(whole, in: text) == "def save do")
    }

    /// Nothing after the first line is ever marked, even when the first line
    /// is short and the rest is where the interesting text is.
    @Test func nothingBelowTheFirstLineWithContentIsMarked() {
        let text = "do\n  the_actual_body()\nend\n"
        let whole = NSRange(location: 0, length: (text as NSString).length)
        #expect(mark(whole, in: text) == "do")
    }

    // MARK: Nothing worth marking

    @Test func anEmptyRangeMarksNothing() {
        #expect(mark(NSRange(location: 3, length: 0), in: "let x = 1\n") == nil)
    }

    @Test func aRangeOfOnlyWhitespaceMarksNothing() {
        #expect(mark(NSRange(location: 3, length: 4), in: "let     x\n") == nil)
    }

    @Test func aRangeOfOnlyBlankLinesMarksNothing() {
        let text = "a\n\n\n\nb\n"
        #expect(mark(NSRange(location: 2, length: 3), in: text) == nil)
    }

    @Test func anEmptyDocumentMarksNothing() {
        #expect(CodeRevealHighlight.range(for: NSRange(location: 0, length: 0), in: "") == nil)
    }

    // MARK: The ends of the file

    /// A server describes the file it was last told about, and the reader has
    /// been deleting since. A range past the end is clipped, not trusted.
    @Test func aRangePastTheEndIsClippedToWhatIsThere() {
        let text = "short\n"
        #expect(mark(NSRange(location: 0, length: 900), in: text) == "short")
    }

    @Test func aRangeStartingPastTheEndMarksNothing() {
        #expect(mark(NSRange(location: 400, length: 5), in: "short\n") == nil)
    }

    /// The last line of a file with no newline after it: the line has no
    /// terminator to stop at, so the end of the text has to be that stop.
    @Test func theLastLineWithNoNewlineIsStillMarked() {
        let text = "first\nlast_line"
        let range = NSRange(location: 6, length: 9)
        #expect(mark(range, in: text) == "last_line")
    }

    // MARK: A pathological line cannot take the screen

    @Test func aVeryLongLineIsCappedAndStartsWhereTheRangeDid() {
        let text = String(repeating: "x", count: 4_000)
        let found = CodeRevealHighlight.range(
            for: NSRange(location: 0, length: 4_000),
            in: text as NSString
        )

        #expect(found?.location == 0)
        #expect(found?.length == CodeRevealHighlight.maximumLength)
    }

    /// The cap counts UTF-16 units, so it can land between the halves of a
    /// surrogate pair — a range the layout manager cannot measure. It has to
    /// fall back to the boundary below.
    ///
    /// One ASCII character before the emoji is what puts the cap on an odd
    /// offset, which is where the split would happen.
    @Test func theCapNeverSplitsACharacter() {
        let text = "x" + String(repeating: "😀", count: 400)
        let found = CodeRevealHighlight.range(
            for: NSRange(location: 0, length: (text as NSString).length),
            in: text as NSString
        )

        #expect(found?.length == CodeRevealHighlight.maximumLength - 1)

        let marked = (text as NSString).substring(with: found ?? NSRange())
        #expect(!marked.contains("\u{FFFD}"))
    }

    /// A single-line range shorter than the cap is left alone by it.
    @Test func aShortRangeIsNotCapped() {
        let text = "let name = \"phantom\"\n"
        #expect(mark(NSRange(location: 0, length: 20), in: text) == "let name = \"phantom\"")
    }
}
