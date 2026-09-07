import Foundation
@testable import Ghostty
import Testing

/// The excludes line under the explorer's search field: what parses, what
/// it matches, and which directories the walk stops reading because of it.
struct FileExplorerExcludeTests {
    private func parse(_ line: String) -> FileExplorerSearchExcludes {
        FileExplorerSearchExcludes.parse(line)
    }

    private func sources(_ line: String) -> [String] {
        parse(line).patterns.map(\.source)
    }

    // MARK: Parsing

    @Test func itSplitsTheLineOnCommasAndTrimsEachPattern() {
        #expect(sources(" node_modules ,*.log,  logs/** ") == ["node_modules", "*.log", "logs/**"])
    }

    @Test func itIgnoresEmptyPiecesRatherThanTreatingThemAsPatterns() {
        #expect(sources(",, node_modules ,,") == ["node_modules"])
        #expect(parse("   ").isEmpty)
        #expect(parse("").isEmpty)
    }

    /// A pattern that did not compile gets no chip, which is the whole
    /// report this field makes.
    @Test func itDropsAPatternThatDoesNotCompileAndKeepsTheRest() {
        #expect(sources("node_modules, [0-9].log, *.tmp") == ["node_modules", "*.tmp"])
    }

    /// Two chips reading `*.LOG` and `*.log` would both be true and neither
    /// would be worth clicking.
    @Test func itDropsADuplicateComparedWithoutCase() {
        #expect(sources("*.LOG, *.log") == ["*.LOG"])
    }

    @Test func itStopsAtTheMaximumNumberOfPatterns() {
        let line = (0..<(FileExplorerSearchExcludes.maxPatterns + 8))
            .map { "dir\($0)" }
            .joined(separator: ", ")
        #expect(parse(line).patterns.count == FileExplorerSearchExcludes.maxPatterns)
    }

    /// The chip carries the case the reader typed, because removing a
    /// neighbouring chip writes these back into the field.
    @Test func aChipKeepsThePatternAsItWasTyped() {
        #expect(sources("MVCALB*.PRW") == ["MVCALB*.PRW"])
    }

    // MARK: Alternation

    @Test func itExpandsAParenthesisedAlternation() {
        let excludes = parse("*.(ts|tsx)")
        #expect(excludes.patterns.count == 1)
        #expect(excludes.excludes(relativePath: "src/app.ts", isDirectory: false))
        #expect(excludes.excludes(relativePath: "src/app.tsx", isDirectory: false))
        #expect(!excludes.excludes(relativePath: "src/app.js", isDirectory: false))
    }

    @Test func itExpandsAnAlternationThatNamesDirectories() {
        let excludes = parse("(build|dist)/**")
        #expect(excludes.excludes(relativePath: "build", isDirectory: true))
        #expect(excludes.excludes(relativePath: "dist", isDirectory: true))
        #expect(!excludes.excludes(relativePath: "src", isDirectory: true))
    }

    /// `{ts,}` is nothing `GlobPattern` will compile, and an alternative the
    /// reader left blank is a comma they have not finished typing.
    @Test func itRefusesAnEmptyAlternative() {
        #expect(parse("*.(ts|)").isEmpty)
        #expect(parse("*.(|ts)").isEmpty)
        #expect(parse("*.()").isEmpty)
    }

    @Test func itRefusesAGroupLeftOpen() {
        #expect(parse("(build|dist/**").isEmpty)
        #expect(parse("build|dist)/**").isEmpty)
    }

    /// The bar means alternation here, so `ts|tsx` is somebody reaching for
    /// it with the parentheses forgotten. Matching a file literally named
    /// `ts|tsx` would be a worse answer than no chip.
    @Test func itRefusesABarOutsideAGroup() {
        #expect(parse("ts|tsx").isEmpty)
        #expect(parse("*.(ts|tsx)|*.js").isEmpty)
    }

    @Test func itRefusesAGroupInsideAGroup() {
        #expect(parse("(a|(b|c))").isEmpty)
    }

    /// The comma is this field's separator, so a brace list is torn in half
    /// before it can be expanded. Both halves are refused rather than
    /// matched as literals.
    @Test func itRefusesTheBraceFormTheCommaWouldHaveTornInHalf() {
        #expect(sources("*.{ts,tsx}") == [])
        #expect(parse("*.{ts").isEmpty)
        #expect(parse("tsx}").isEmpty)
    }

    // MARK: Matching

    @Test func nothingIsExcludedWhileTheFieldIsEmpty() {
        let excludes = FileExplorerSearchExcludes.empty
        #expect(!excludes.excludes(relativePath: "node_modules", isDirectory: true))
        #expect(!excludes.excludes(relativePath: "src/app.log", isDirectory: false))
    }

    @Test func itMatchesTheFilesOwnName() {
        let excludes = parse("*.log")
        #expect(excludes.excludes(relativePath: "app.log", isDirectory: false))
        #expect(!excludes.excludes(relativePath: "app.ts", isDirectory: false))
    }

    /// A bare `node_modules` has to reach the directory wherever it sits,
    /// which is what makes one word enough to drop a whole subtree.
    @Test func itMatchesAnyPathComponentBelowTheRoot() {
        let excludes = parse("node_modules")
        #expect(excludes.excludes(relativePath: "node_modules", isDirectory: true))
        #expect(excludes.excludes(relativePath: "web/node_modules", isDirectory: true))
        #expect(excludes.excludes(relativePath: "web/node_modules/pkg/index.ts", isDirectory: false))
        #expect(!excludes.excludes(relativePath: "web/src/index.ts", isDirectory: false))
    }

    /// `*` declines to cross a separator, so a name pattern cannot claim a
    /// path by accident.
    @Test func aNamePatternDoesNotSpanASeparator() {
        let excludes = parse("src*")
        #expect(excludes.excludes(relativePath: "srclib", isDirectory: true))
        #expect(!excludes.excludes(relativePath: "web/srx/lib", isDirectory: false))
    }

    /// A pattern carrying a separator can only ever be the relative path,
    /// which is the case no single component covers.
    @Test func itMatchesTheRelativePathAsAWhole() {
        let excludes = parse("logs/**")
        #expect(excludes.excludes(relativePath: "logs/2024/app.log", isDirectory: false))
        #expect(!excludes.excludes(relativePath: "web/logs/2024/app.log", isDirectory: false))
    }

    /// The rule that turns an exclude into a directory the walk never
    /// reads: a pattern that claims everything under a directory claims the
    /// directory.
    @Test func itPrunesADirectoryWhenEverythingUnderItIsExcluded() {
        let excludes = parse("logs/**")
        #expect(excludes.excludes(relativePath: "logs", isDirectory: true))
        #expect(!excludes.excludes(relativePath: "logs", isDirectory: false))
    }

    /// The other side of the same rule. `logs/*.tmp` excludes some files
    /// inside `logs`, so `logs` still has to be read.
    @Test func itDoesNotPruneADirectoryOnlySomeOfWhoseFilesAreExcluded() {
        let excludes = parse("logs/*.tmp")
        #expect(!excludes.excludes(relativePath: "logs", isDirectory: true))
        #expect(excludes.excludes(relativePath: "logs/build.tmp", isDirectory: false))
        #expect(!excludes.excludes(relativePath: "logs/build.log", isDirectory: false))
    }

    /// Asking a reader which case a directory was created in is asking them
    /// something they do not know.
    @Test func itMatchesWithoutRegardToCase() {
        let excludes = parse("MVCALB*.PRW")
        #expect(excludes.excludes(relativePath: "mvcalb001.prw", isDirectory: false))
        #expect(excludes.excludes(relativePath: "src/MVCALB900.PRW", isDirectory: false))

        let lowered = parse("node_modules")
        #expect(lowered.excludes(relativePath: "Node_Modules", isDirectory: true))
    }

    // MARK: Chips

    @Test func removingAPatternRewritesTheLineWithTheOthersAsTyped() {
        let excludes = parse("node_modules, MVCALB*.PRW, logs/**")
        guard let middle = excludes.patterns.first(where: { $0.source == "MVCALB*.PRW" }) else {
            Issue.record("the pattern that was typed is not among the chips")
            return
        }
        #expect(excludes.removing(middle).text == "node_modules, logs/**")
    }

    /// The rewritten line has to parse back to the same chips, or removing
    /// one would quietly change another.
    @Test func theRewrittenLineParsesBackToTheSameChips() {
        let excludes = parse("node_modules, MVCALB*.PRW, *.(ts|tsx)")
        #expect(parse(excludes.text).patterns == excludes.patterns)
    }

    // MARK: The walk

    /// Builds a tree whose interesting files all share one name, so a
    /// result says only which directory it survived.
    private func makeTree() -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("phantom-excludes-\(UUID().uuidString)")
        let fm = FileManager.default

        for directory in ["src", "vendor", "vendor/pkg", "logs", "logs/2024", "build"] {
            try? fm.createDirectory(
                at: root.appendingPathComponent(directory),
                withIntermediateDirectories: true
            )
        }
        for file in [
            "index.ts",
            "src/index.ts",
            "vendor/index.ts",
            "vendor/pkg/index.ts",
            "logs/index.ts",
            "logs/2024/index.ts",
            "build/index.ts",
            "src/index.log",
        ] {
            try? "x".write(
                to: root.appendingPathComponent(file),
                atomically: true,
                encoding: .utf8
            )
        }
        return root
    }

    private func search(_ query: String, in root: URL, excluding line: String) -> [String] {
        FileExplorerModel
            .search(
                query: query,
                under: root,
                showHidden: false,
                excludes: FileExplorerSearchExcludes.parse(line)
            )
            .map(\.node.path)
    }

    /// Compared by suffix, never against `root.path`. `NSTemporaryDirectory()`
    /// answers under `/var`, `contentsOfDirectory` hands its results back
    /// under `/private/var`, and neither `resolvingSymlinksInPath` nor
    /// `standardizedFileURL` closes that gap — Foundation keeps `/var` and
    /// `/tmp` unresolved on purpose. An equality against the root is a string
    /// comparison that fails whatever the search did.
    @Test func itReportsNothingFromInsideAnExcludedDirectory() {
        let root = makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let found = search("index", in: root, excluding: "vendor")
        #expect(!found.contains { $0.contains("/vendor/") })
        #expect(found.contains { $0.hasSuffix("/src/index.ts") })
        #expect(found.contains { $0.hasSuffix("/\(root.lastPathComponent)/index.ts") })
    }

    /// The excluded directory is not reported either. It is not a result
    /// that happens to be filtered — it never enters the walk.
    @Test func theExcludedDirectoryIsNotItselfAResult() {
        let root = makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(search("vendor", in: root, excluding: "vendor").isEmpty)
    }

    @Test func aPatternCarryingASeparatorPrunesTheDirectoryItNames() {
        let root = makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let found = search("index", in: root, excluding: "logs/**")
        #expect(!found.contains { $0.contains("/logs/") })
        #expect(found.contains { $0.hasSuffix("/src/index.ts") })
    }

    @Test func anAlternationExcludesEveryDirectoryItNames() {
        let root = makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let found = search("index", in: root, excluding: "(build|vendor)/**")
        #expect(!found.contains { $0.contains("/build/") })
        #expect(!found.contains { $0.contains("/vendor/") })
        #expect(found.contains { $0.hasSuffix("/src/index.ts") })
    }

    @Test func anExtensionPatternDropsTheFilesAndLeavesTheDirectories() {
        let root = makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let found = search("index", in: root, excluding: "*.log")
        #expect(!found.contains { $0.hasSuffix(".log") })
        #expect(found.contains { $0.hasSuffix("/src/index.ts") })
    }

    /// The reader's patterns are added to the built-in skip list, not
    /// swapped for it.
    @Test func theBuiltInSkipListStillAppliesWhenPatternsAreSet() {
        let root = makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try? fm.createDirectory(
            at: root.appendingPathComponent("node_modules/pkg"),
            withIntermediateDirectories: true
        )
        try? "x".write(
            to: root.appendingPathComponent("node_modules/pkg/index.ts"),
            atomically: true,
            encoding: .utf8
        )

        let found = search("index", in: root, excluding: "vendor")
        #expect(!found.contains { $0.contains("/node_modules/") })
        #expect(!found.contains { $0.contains("/vendor/") })
    }

    /// A line nobody typed changes nothing about the search that ran before
    /// the field existed.
    @Test func anEmptyLineLeavesTheSearchAsItWas() {
        let root = makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let excluded = search("index", in: root, excluding: "")
        let plain = FileExplorerModel
            .search(query: "index", under: root, showHidden: false)
            .map(\.node.path)
        #expect(excluded == plain)
    }
}
