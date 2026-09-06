import Foundation
@testable import Ghostty
import Testing

struct OnigRegexTests {
    @Test func matchesAndReportsTheWholeSpan() throws {
        let regex = try #require(OnigRegex(pattern: "b+"))
        let groups = try #require(regex.firstMatch(in: "aabbbcc"))
        #expect(groups[0] == 2..<5)
    }

    @Test func reportsNothingWhenItDoesNotMatch() throws {
        let regex = try #require(OnigRegex(pattern: "zzz"))
        #expect(regex.firstMatch(in: "aabbbcc") == nil)
    }

    @Test func refusesAPatternItCannotCompile() {
        #expect(OnigRegex(pattern: "(unclosed") == nil)
    }

    @Test func countsTheGroupsIncludingTheWholeMatch() throws {
        #expect(try #require(OnigRegex(pattern: "a")).captureCount == 1)
        #expect(try #require(OnigRegex(pattern: "(a)(b)")).captureCount == 3)
    }

    @Test func readsEachGroupSeparately() throws {
        let regex = try #require(OnigRegex(pattern: "(\\w+)=(\\w+)"))
        let groups = try #require(regex.firstMatch(in: "  key=value  "))
        #expect(groups[0] == 2..<11)
        #expect(groups[1] == 2..<5)
        #expect(groups[2] == 6..<11)
    }

    @Test func leavesAGroupThatTookPartInNoMatchEmpty() throws {
        let regex = try #require(OnigRegex(pattern: "(a)|(b)"))
        let groups = try #require(regex.firstMatch(in: "b"))
        #expect(groups[1] == nil)
        #expect(groups[2] == 0..<1)
    }

    /// The reason this bridge exists. A TextMate `end` pattern refers back to
    /// a group its `begin` captured, which is how Lua's `--[==[` finds the
    /// `]==]` that closes it and no other.
    @Test func honoursABackreference() throws {
        let regex = try #require(OnigRegex(pattern: "\\[(=*)\\[.*?\\]\\1\\]"))
        #expect(regex.firstMatch(in: "[==[ body ]==]")?[0] == 0..<14)
        #expect(regex.firstMatch(in: "[==[ body ]=]") == nil)
    }

    /// The second reason. `\G` anchors a match to where the search started,
    /// which is what makes a `while` rule continue a region instead of
    /// finding the next thing that looks like one.
    @Test func honoursTheContinuationAnchor() throws {
        let regex = try #require(OnigRegex(pattern: "\\Gabc"))
        #expect(regex.firstMatch(in: "xxabc", from: 2)?[0] == 2..<5)
        #expect(regex.firstMatch(in: "xxabc", from: 0) == nil)
    }

    @Test func honoursLookbehind() throws {
        let regex = try #require(OnigRegex(pattern: "(?<=\\$)\\w+"))
        #expect(regex.firstMatch(in: "cost $total here")?[0] == 6..<11)
        #expect(regex.firstMatch(in: "cost total here") == nil)
    }

    /// A start beyond the text is a caller bug, not a crash.
    @Test func refusesAStartOutsideTheText() throws {
        let regex = try #require(OnigRegex(pattern: "a"))
        #expect(!regex.search(Array("aaa".utf8), from: 9))
    }

    @Test func searchesFromAnOffsetWithoutLosingContext() throws {
        let regex = try #require(OnigRegex(pattern: "^a"))
        #expect(regex.firstMatch(in: "aXa", from: 1) == nil)
        #expect(regex.firstMatch(in: "aXa", from: 0)?[0] == 0..<1)
    }

    /// Offsets are UTF-8 bytes, and the caller converts. Proving it here
    /// stops somebody reading a byte offset as a UTF-16 one later.
    @Test func countsInBytesNotInCharacters() throws {
        let regex = try #require(OnigRegex(pattern: "fim"))
        let groups = try #require(regex.firstMatch(in: "acentuação fim"))
        #expect(groups[0] == 12..<15)
        #expect(("acentuação fim" as NSString).range(of: "fim").location == 11)
    }

    @Test func reusesOneHandleAcrossSearches() throws {
        let regex = try #require(OnigRegex(pattern: "(\\d+)"))
        #expect(regex.firstMatch(in: "a 12 b")?[1] == 2..<4)
        #expect(regex.firstMatch(in: "a 345 b")?[1] == 2..<5)
        #expect(regex.firstMatch(in: "none") == nil)
    }

    /// A blank line still has to be searchable: a rule anchored with `^$`
    /// matches one, and an empty buffer has no pointer to hand Oniguruma.
    @Test func searchesAnEmptyLine() throws {
        let regex = try #require(OnigRegex(pattern: "^$"))
        #expect(regex.search([]))
        #expect(regex.range(of: 0) == 0..<0)
    }

    @Test func findsNothingInAnEmptyLineWhenThePatternNeedsContent() throws {
        let regex = try #require(OnigRegex(pattern: "\\w+"))
        #expect(!regex.search([]))
    }

    /// A pattern that would backtrack forever is stopped by the retry limit
    /// the bridge sets, rather than hanging the editor on a grammar somebody
    /// else wrote.
    @Test func givesUpOnCatastrophicBacktracking() throws {
        let regex = try #require(OnigRegex(pattern: "(a+)+$"))
        let subject = String(repeating: "a", count: 40) + "!"
        #expect(regex.firstMatch(in: subject) == nil)
    }
}
