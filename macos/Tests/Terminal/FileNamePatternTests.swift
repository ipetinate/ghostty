import CryptoKit
import Foundation
@testable import Ghostty
import Testing

/// The glob dialect of `contributes.languages[].fileNamePatterns`, checked
/// against the table the registry checks itself against.
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
struct FileNamePatternTests {
    /// Update together with the copy in the registry, never alone.
    static let casesDigest = "f825add59767fc6984be0b9c33619f3308656c6a9ff48f7a8400ba712d1203b0"

    private struct Cases: Decodable {
        struct Limits: Decodable {
            let maxLength: Int
            let maxPatterns: Int
            let maxNameLength: Int
        }

        struct Accepted: Decodable {
            let pattern: String
            let canonical: String
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

        let limits: Limits
        let accepted: [Accepted]
        let rejected: [Rejected]
        let matches: [Match]
    }

    private static var casesURL: URL {
        URL(fileURLWithPath: #filePath)          // …/macos/Tests/Terminal/<this>.swift
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/file-name-pattern-cases.json")
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
        #expect(limits.maxLength == FileNamePattern.maxLength)
        #expect(limits.maxPatterns == FileNamePattern.maxPatterns)
        #expect(limits.maxNameLength == FileNamePattern.maxNameLength)
    }

    @Test func everyAcceptedPatternCanonicalizesTheSharedWay() throws {
        for entry in try Self.load().accepted {
            #expect(
                FileNamePattern.valid(entry.pattern) == entry.canonical,
                "pattern \(entry.pattern.debugDescription)"
            )
        }
    }

    @Test func everyRejectedPatternIsRefused() throws {
        for entry in try Self.load().rejected {
            #expect(
                FileNamePattern.valid(entry.pattern) == nil,
                "pattern \(entry.pattern.debugDescription): \(entry.why)"
            )
        }
    }

    @Test func everySharedMatchAnswersTheSharedWay() throws {
        for entry in try Self.load().matches {
            #expect(
                FileNamePattern.matches(entry.pattern, name: entry.name) == entry.matches,
                "pattern \(entry.pattern.debugDescription) against \(entry.name.debugDescription)"
            )
        }
    }

    // MARK: Cost

    /// The input that turns a backtracking glob matcher into a hang, run at a
    /// size no cap would catch on its own: ten stars against a name of the
    /// scalar every one of them can eat, with a literal at the end that never
    /// arrives.
    ///
    /// A matcher that explored the star positions would take on the order of
    /// `nameLength ^ stars` steps here. The bound this one holds to is
    /// `pattern × name` — a few thousand comparisons — so a limit measured in
    /// tenths of a second is not a tight benchmark, it is the difference
    /// between a bounded answer and a frozen editor. Run for every pattern
    /// length up to the cap so the cost is shown not to turn over anywhere
    /// along the way.
    @Test func aPathologicalPatternAnswersInBoundedTime() {
        let name = String(repeating: "a", count: FileNamePattern.maxNameLength)
        let clock = ContinuousClock()

        let elapsed = clock.measure {
            for stars in 1...20 {
                let pattern = String(repeating: "*a", count: stars) + "*b"
                guard let canonical = FileNamePattern.valid(pattern) else { continue }
                #expect(FileNamePattern.matches(canonical, name: name) == false)
            }
        }

        #expect(elapsed < .milliseconds(500), "matching took \(elapsed)")
    }

    /// A pattern longer than the cap never reaches the matcher at all, which
    /// is what keeps the bound a bound.
    @Test func aPatternOverTheCapIsNotAPattern() {
        let long = String(repeating: "*a", count: FileNamePattern.maxLength)
        #expect(FileNamePattern.valid(long) == nil)
    }
}
