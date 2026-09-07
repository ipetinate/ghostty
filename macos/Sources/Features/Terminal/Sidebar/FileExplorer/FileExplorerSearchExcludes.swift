import Foundation

/// The patterns a file search refuses to walk into, as the reader wrote
/// them.
///
/// One field rather than a list of inputs. A list makes the reader decide
/// where a pattern goes before they know whether it works, and it turns
/// "also skip the build output" into three gestures. A comma-separated line
/// is the shape every ignore file already taught them, and the chips under
/// it say which parts of the line took effect — a pattern with no chip was
/// refused, and that is the only report this field makes.
///
/// ## The dialect
///
/// `GlobPattern`'s, with two rules of this layer's own on top of it.
///
/// The first is alternation, written `(a|b)`. `GlobPattern` spells the same
/// thing `{a,b}`, and that form cannot survive this field: the comma is the
/// separator between patterns, so a typed `*.{ts,tsx}` is torn into `*.{ts`
/// and `tsx}` before anything could expand it. A group is rewritten to the
/// brace form before compiling, so the expansion, the branch cap and the
/// refusal to nest stay `GlobPattern`'s and there is no second matcher
/// here.
///
/// The second is case. Pattern and candidate are both lowered before they
/// meet, because this sits under a search field that has always been
/// case-insensitive, and because `MVCALB*.PRW` is how the files it names
/// are really spelled. Asking a reader which case a directory was created
/// in is asking them something they do not know.
///
/// ## What a pattern is matched against
///
/// The relative path below the search root, and every component of it — so
/// a bare `node_modules` drops the directory and everything under it, and
/// `logs/**`, which no single component can equal, drops the tree under
/// `logs`.
///
/// A directory is matched a third time with a separator appended. That is
/// what lets `logs/**` prune `logs` itself instead of reading it and
/// refusing each child on the way out: the appended separator is the
/// question "is everything in here excluded", and only a pattern that
/// answers yes prunes. `logs/*.tmp` fails it on purpose — it excludes some
/// files inside `logs`, so `logs` still has to be read.
struct FileExplorerSearchExcludes: Equatable, Sendable {
    /// One pattern: what the reader typed, and what it compiled to.
    ///
    /// The typed text is kept because it is what the chip shows and what
    /// goes back into the field when a neighbouring chip is removed.
    /// Rebuilding the field from the compiled form would lower the case of
    /// every pattern the reader still has, which is an edit they did not
    /// ask for.
    struct Pattern: Equatable, Identifiable, Sendable {
        let source: String
        let glob: GlobPattern

        var id: String { source }
    }

    /// Enough for a project's build output, its vendored dependencies and
    /// the handful of file shapes a reader is tired of scrolling past. A
    /// field holding more than this is a `.gitignore` written in the wrong
    /// place, and `FileExplorerModel.skippedDirectories` already covers the
    /// common half of it without being asked.
    static let maxPatterns = 32

    static let empty = FileExplorerSearchExcludes(patterns: [])

    /// `GlobPattern`'s, spelled as a `Character` because that is what
    /// splitting and joining a path here want.
    private static let separator = Character(GlobPattern.separator)

    let patterns: [Pattern]

    var isEmpty: Bool { patterns.isEmpty }

    /// The line these patterns came from, rebuilt.
    ///
    /// Only ever the *effective* line — a pattern that was refused is not
    /// in `patterns` and so is not in here either. It is written back to
    /// the field when a chip is removed, which is the one moment the
    /// reader has said they want the line rewritten.
    var text: String {
        patterns.map(\.source).joined(separator: ", ")
    }

    // MARK: Parsing

    /// Splits the line, drops what will not compile, and keeps the rest in
    /// the order it was written.
    ///
    /// A duplicate is dropped rather than kept, compared after lowering,
    /// because two chips reading `*.LOG` and `*.log` would both be true and
    /// neither would be worth clicking.
    static func parse(_ source: String) -> FileExplorerSearchExcludes {
        var patterns: [Pattern] = []
        var seen: Set<String> = []

        for piece in source.split(separator: ",") {
            let typed = piece.trimmingCharacters(in: .whitespaces)
            guard !typed.isEmpty else { continue }

            let lowered = typed.lowercased()
            guard seen.insert(lowered).inserted else { continue }
            guard let braced = braceForm(of: lowered),
                  let glob = GlobPattern.compile(braced)
            else { continue }

            patterns.append(Pattern(source: typed, glob: glob))
            guard patterns.count < maxPatterns else { break }
        }

        return FileExplorerSearchExcludes(patterns: patterns)
    }

    func removing(_ pattern: Pattern) -> FileExplorerSearchExcludes {
        FileExplorerSearchExcludes(patterns: patterns.filter { $0.id != pattern.id })
    }

    /// `(a|b)` rewritten as `{a,b}`, or nil for a line this dialect refuses.
    ///
    /// Each refusal is something the reader can act on once they see the
    /// chip is missing:
    ///
    /// - A brace of their own. Braces are what this rewrite produces, and
    ///   the comma that a brace list needs is already spoken for, so a
    ///   typed `{ts,tsx}` arrives here in halves. Letting a half through
    ///   would claim names nobody wrote a pattern for.
    /// - A `|` outside a group. The bar means alternation here, and
    ///   `ts|tsx` is somebody reaching for it with the parentheses
    ///   forgotten. Matching a file literally named `ts|tsx` is a worse
    ///   answer than no chip.
    /// - A group inside a group, and a group left open. `GlobPattern`
    ///   refuses both of the braces these become; refusing them before the
    ///   rewrite keeps the reason on the side that knows about parentheses.
    ///
    /// An empty alternative — `(ts|)` — is the one refusal left downstream,
    /// because `{ts,}` is already nothing `GlobPattern` will compile.
    private static func braceForm(of source: String) -> String? {
        var result = ""
        var isInGroup = false

        for scalar in source.unicodeScalars {
            switch scalar {
            case "{", "}":
                return nil
            case "(":
                guard !isInGroup else { return nil }
                isInGroup = true
                result.unicodeScalars.append("{")
            case ")":
                guard isInGroup else { return nil }
                isInGroup = false
                result.unicodeScalars.append("}")
            case "|":
                guard isInGroup else { return nil }
                result.unicodeScalars.append(",")
            default:
                result.unicodeScalars.append(scalar)
            }
        }

        return isInGroup ? nil : result
    }

    // MARK: Matching

    /// Whether the entry at `relativePath` — below the search root,
    /// separated by `/` — is one the search should not report and, when it
    /// is a directory, should not read.
    func excludes(relativePath: String, isDirectory: Bool) -> Bool {
        guard !patterns.isEmpty else { return false }

        let path = relativePath.lowercased()
        let components = path.split(separator: Self.separator).map(String.init)
        let contents = isDirectory ? path + String(Self.separator) : nil

        return patterns.contains { pattern in
            if pattern.glob.matches(path) { return true }
            if let contents, pattern.glob.matches(contents) { return true }
            return components.contains { pattern.glob.matches($0) }
        }
    }
}
