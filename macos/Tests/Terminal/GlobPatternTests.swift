import CryptoKit
import Foundation
@testable import Ghostty
import Testing

/// The glob dialect, checked against the table the registry checks itself
/// against.
///
/// The registry validates published manifests in TypeScript and this app
/// reads them in Swift. Two implementations that disagree is the failure that
/// matters here — the registry would accept a manifest this build then
/// ignores, and the extension would ship claiming files it never gets — so
/// the cases live in a JSON file rather than in either language, and both
/// suites read it.
///
/// Neither repository can read the other's working copy, so the file is
/// duplicated and the duplication is guarded: `digestIsTheOneBothSuitesPin`
/// hashes the bytes and compares them against a constant declared here and
/// again in `packages/registry/test/patterns.test.ts`. Editing one copy fails
/// that side until the digest is updated, and updating a digest is the moment
/// the other copy is remembered.
///
/// The `paths` section is the dialect's own contract rather than the
/// manifest field's: separators, and which run token crosses one. No caller
/// matches a path yet — `.editorconfig` is the one that will — and the cases
/// are here so the semantics cannot drift before it arrives.
struct GlobPatternTests {
    /// Update together with the copy in the registry, never alone.
    static let casesDigest = "abc31d520a055dca86da45e9c9167008532f8d9b305175b5046e137c970db710"

    private struct Cases: Decodable {
        struct Limits: Decodable {
            let maxSourceLength: Int
            let maxBranches: Int
            let maxPatternsPerLanguage: Int
            let maxCandidateLength: Int
        }

        struct Accepted: Decodable {
            let pattern: String
            let canonical: String
            let branches: Int
        }

        struct Rejected: Decodable {
            let pattern: String
            let why: String
        }

        struct Match: Decodable {
            let pattern: String
            let name: String
            let matches: Bool
        }

        struct Path: Decodable {
            let pattern: String
            let path: String
            let matches: Bool
        }

        let limits: Limits
        let accepted: [Accepted]
        let rejected: [Rejected]
        let matches: [Match]
        let paths: [Path]
    }

    private static var casesURL: URL {
        URL(fileURLWithPath: #filePath)          // …/macos/Tests/Terminal/<this>.swift
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/glob-pattern-cases.json")
    }

    private static func data() throws -> Data {
        try Data(contentsOf: casesURL)
    }

    private static func load() throws -> Cases {
        try JSONDecoder().decode(Cases.self, from: data())
    }

    @Test func digestIsTheOneBothSuitesPin() throws {
        let digest = SHA256.hash(data: try Self.data())
            .map { String(format: "%02x", $0) }
            .joined()
        #expect(
            digest == Self.casesDigest,
            "the shared case table changed: copy it to phantom-extensions and update both digests"
        )
    }

    @Test func theCapsAreTheOnesTheRegistryEnforces() throws {
        let limits = try Self.load().limits
        #expect(limits.maxSourceLength == GlobPattern.maxSourceLength)
        #expect(limits.maxBranches == GlobPattern.maxBranches)
        #expect(limits.maxPatternsPerLanguage == GlobPattern.maxPatternsPerLanguage)
        #expect(limits.maxCandidateLength == GlobPattern.maxCandidateLength)
    }

    /// The canonical form and the branch count, because a brace list is only
    /// honoured if both sides expand it to the same number of alternatives.
    @Test func everyAcceptedPatternCompilesTheSharedWay() throws {
        for entry in try Self.load().accepted {
            let pattern = try #require(
                GlobPattern.fileNamePattern(entry.pattern),
                "pattern \(entry.pattern.debugDescription)"
            )
            #expect(pattern.source == entry.canonical, "pattern \(entry.pattern.debugDescription)")
            #expect(
                pattern.branches.count == entry.branches,
                "pattern \(entry.pattern.debugDescription)"
            )
        }
    }

    @Test func everyRejectedPatternIsRefused() throws {
        for entry in try Self.load().rejected {
            #expect(
                GlobPattern.fileNamePattern(entry.pattern) == nil,
                "pattern \(entry.pattern.debugDescription): \(entry.why)"
            )
        }
    }

    @Test func everySharedMatchAnswersTheSharedWay() throws {
        for entry in try Self.load().matches {
            let pattern = try #require(
                GlobPattern.fileNamePattern(entry.pattern),
                "pattern \(entry.pattern.debugDescription)"
            )
            #expect(
                pattern.matches(entry.name) == entry.matches,
                "pattern \(entry.pattern.debugDescription) against \(entry.name.debugDescription)"
            )
        }
    }

    /// The dialect with separators in it, which is what a caller matching a
    /// whole path gets. `compile` rather than `fileNamePattern`: the field
    /// refuses a separator, the dialect does not.
    @Test func everySharedPathAnswersTheSharedWay() throws {
        for entry in try Self.load().paths {
            let pattern = try #require(
                GlobPattern.compile(entry.pattern),
                "pattern \(entry.pattern.debugDescription)"
            )
            #expect(
                pattern.matches(entry.path) == entry.matches,
                "pattern \(entry.pattern.debugDescription) against \(entry.path.debugDescription)"
            )
        }
    }

    // MARK: Structure

    /// A separator is what makes a language's pattern name-only, and the
    /// dialect has to keep serving the caller that wants one. Both facts in
    /// one test, because either alone would look like an oversight.
    @Test func theFieldRefusesASeparatorAndTheDialectDoesNot() {
        #expect(GlobPattern.fileNamePattern("src/*.env") == nil)
        #expect(GlobPattern.compile("src/*.env") != nil)
    }

    /// A single-star run may not cross a separator and a double-star run
    /// may, which is the only difference between them — so in a file name,
    /// where there is no separator, they are the same token in effect.
    @Test func theTwoRunTokensDifferOnlyOverSeparators() throws {
        let single = try #require(GlobPattern.compile("a*b"))
        let double = try #require(GlobPattern.compile("a**b"))
        #expect(single.matches("axb"))
        #expect(double.matches("axb"))
        #expect(!single.matches("ax/xb"))
        #expect(double.matches("ax/xb"))
    }

    /// Three or more stars are one crossing run rather than an error: an
    /// author who typed one too many meant the run they were writing.
    @Test func aRunOfStarsBeyondTwoIsStillOneCrossingRun() throws {
        let pattern = try #require(GlobPattern.compile("a***b"))
        #expect(pattern.matches("ax/xb"))
    }

    // MARK: Cost

    /// A brace list nested with `*` is where a backtracking matcher goes
    /// exponential, so it is the shape measured here: every branch is the
    /// classic `*a*a*…*b` against a run of the one scalar each star can eat,
    /// with a literal at the end that never arrives.
    ///
    /// Run at the caps a single language can reach — `maxPatternsPerLanguage`
    /// patterns, each expanded to `maxBranches`, each branch as long as
    /// `maxSourceLength` allows — because that product is the bound worth
    /// stating. A matcher that explored the run positions would take on the
    /// order of `candidate ^ runs` steps here; this one simulates the
    /// positions as states advanced together, so the cost cannot rise above
    /// `candidate × tokens`. The measured figure for the whole sweep is a
    /// few milliseconds, so a limit of one second is not a benchmark — it is
    /// the difference between a bounded answer and a frozen editor.
    @Test func aPathologicalPatternSetAnswersInBoundedTime() throws {
        let candidate = String(repeating: "a", count: GlobPattern.maxCandidateLength)
        let branch = String(repeating: "*a", count: 10) + "*b"
        let listed = try #require(GlobPattern.fileNamePattern("{\(branch),\(branch)x}"))
        let longest = try #require(
            GlobPattern.fileNamePattern(String(repeating: "*a", count: 32))
        )

        let elapsed = ContinuousClock().measure {
            for _ in 0..<GlobPattern.maxPatternsPerLanguage {
                #expect(listed.matches(candidate) == false)
                #expect(longest.matches(candidate) == true)
            }
        }

        #expect(elapsed < .seconds(1), "matching took \(elapsed)")
    }

    /// Expansion is refused before a branch is built, so the pattern that
    /// asks for 4096 alternatives costs the manifest one entry rather than
    /// the memory.
    @Test func expansionIsRefusedRatherThanPaidFor() {
        let doubling = String(repeating: "{a,b}", count: 12)
        #expect(doubling.count <= GlobPattern.maxSourceLength)
        #expect(GlobPattern.fileNamePattern(doubling) == nil)
    }

    /// A pattern longer than the cap never reaches the matcher at all, which
    /// is what keeps the bound a bound.
    @Test func aPatternOverTheCapIsNotAPattern() {
        let long = String(repeating: "*a", count: GlobPattern.maxSourceLength)
        #expect(GlobPattern.fileNamePattern(long) == nil)
    }
}
