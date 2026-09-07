import Foundation

/// The glob dialect `contributes.languages[].fileNamePatterns` is written in,
/// and the one place it is defined.
///
/// A language can claim a file by extension or by whole name, and neither can
/// express `.env.*`: the set of suffixes people put after `.env` is open, so
/// listing `.env.local` and `.env.production` leaves `.env.staging-eu`
/// behind. A pattern closes that gap without opening a bigger one.
///
/// **The dialect is deliberately two characters wide.**
///
/// - `*` matches any run of scalars, including none.
/// - `?` matches exactly one scalar.
/// - Every other scalar is a literal, `.` included.
/// - The whole name has to match. There is no partial match and no anchor to
///   write, because a pattern that matched a substring would claim far more
///   than its author meant.
///
/// Character classes (`[abc]`) and alternation (`{a,b}`) are **not** in it,
/// and the four characters that spell them are refused rather than treated as
/// literals — an author who writes `*.{js,ts}` has made a mistake, and
/// matching a file named exactly that is not a kindness. Both constructs are
/// only ever shorthand: `{a,b}` is two patterns and `[abc]` is three, so
/// nothing becomes inexpressible, only longer. Every construct left out is
/// one fewer place where this matcher and the registry's validator can
/// quietly disagree about what a published manifest means.
///
/// Lengths are counted in **Unicode scalars** and matching consumes scalars,
/// for the same reason: the registry validates the same patterns in
/// TypeScript, where a string is measured in UTF-16 code units and iterated
/// in scalars. Counting scalars on both sides is the only measure the two
/// languages agree on without either of them going out of its way.
///
/// **A pattern sees the file's name and never its path.** Separators are
/// refused at parse, so there is no pattern that can reach out of the file it
/// is deciding about, and no path for one to walk.
///
/// **Matching is bounded by the two lengths and never recurses.** The one `*`
/// backtrack point is remembered rather than explored, so the classic
/// `*a*a*a*a*b` against a long run of `a` — the input that hangs a
/// backtracking matcher — costs at most `pattern × name` scalar comparisons.
/// With the caps below that is 64 × 255 for one pattern, a bounded cost this
/// app pays on every file the reader opens.
enum FileNamePattern {
    /// Long enough for any real pattern and short enough that the worst case
    /// stays a rounding error. Counted in Unicode scalars.
    static let maxLength = 64

    /// Per language. A language needing more than this many patterns is
    /// describing something other than its own file names.
    static let maxPatterns = 32

    /// Names longer than this exist on no filesystem this app opens, so the
    /// matcher refuses them rather than paying for them.
    static let maxNameLength = 255

    /// Spelled out rather than derived, so the set a pattern may not contain
    /// is readable in one place: the two path separators, and the four
    /// characters that would be a class or an alternation in a dialect this
    /// one is not.
    private static let forbidden: Set<Unicode.Scalar> = ["/", "\\", "[", "]", "{", "}"]

    /// A pattern in canonical form — trimmed and lower-cased, the way
    /// `fileNames` is — or nil when the manifest may not have it.
    static func valid(_ candidate: String) -> String? {
        let text = candidate.trimmingCharacters(in: .whitespaces).lowercased()
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty, scalars.count <= maxLength else { return nil }
        guard text != ".", text != ".." else { return nil }
        guard !scalars.contains(where: forbidden.contains) else { return nil }
        guard !scalars.contains(where: LanguageContribution.isUnsafeScalar) else { return nil }
        return text
    }

    /// Whether a canonical pattern claims a lower-cased file name.
    static func matches(_ pattern: String, name: String) -> Bool {
        let pattern = Array(pattern.unicodeScalars)
        let name = Array(name.unicodeScalars)
        guard name.count <= maxNameLength else { return false }

        var patternIndex = 0
        var nameIndex = 0
        var lastStar: Int?
        var resumeAt = 0

        while nameIndex < name.count {
            if patternIndex < pattern.count,
               pattern[patternIndex] == "?" || pattern[patternIndex] == name[nameIndex] {
                patternIndex += 1
                nameIndex += 1
            } else if patternIndex < pattern.count, pattern[patternIndex] == "*" {
                lastStar = patternIndex
                resumeAt = nameIndex
                patternIndex += 1
            } else if let star = lastStar {
                patternIndex = star + 1
                resumeAt += 1
                nameIndex = resumeAt
            } else {
                return false
            }
        }

        while patternIndex < pattern.count, pattern[patternIndex] == "*" {
            patternIndex += 1
        }
        return patternIndex == pattern.count
    }
}
