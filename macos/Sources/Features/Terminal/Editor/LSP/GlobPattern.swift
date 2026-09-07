import Foundation

/// The glob dialect Phantom reads, compiled once and matched many times.
///
/// Written for two callers. The first is
/// `contributes.languages[].fileNamePatterns`, which claims a file whose name
/// follows a shape rather than a list: no repository surveyed had a plain
/// `.env`, and the names that do exist — `.env.prod`, `.env.dev1`,
/// `.env.dev1.local` — are an open set that no enumeration finishes. The
/// second is `.editorconfig`, whose section headers are globs of exactly this
/// kind: `[*.{tf,tfvars,hcl}]`, `[{*Test.kt,*Tests.kt,*Spec.kt}]`,
/// `[sales-portal-bff/**.kt]`.
///
/// ## The dialect
///
/// - `*` matches any run of scalars, including none, but never a `/`.
/// - `**` matches any run of scalars, including none, `/` included.
/// - `?` matches exactly one scalar, and never a `/`.
/// - `{a,b,c}` matches any one of the alternatives, each of which may hold
///   `*`, `**`, `?` and literals.
/// - Every other scalar is a literal, `.` included.
/// - The whole candidate has to match. There is no partial match and no
///   anchor to write, because a pattern that matched a substring would claim
///   far more than its author meant.
///
/// Character classes (`[abc]`) are **not** in it, and `[` and `]` are refused
/// rather than matched literally — an author who writes `[0-9].env` has made
/// a mistake, and matching a file named exactly that is not a kindness.
/// Braces do not nest: a `{` inside a brace list is refused, because nesting
/// buys an author nothing that a second pattern does not and costs both
/// implementations of this dialect a place to disagree.
///
/// ## Name or path
///
/// Nothing here is specific to a bare file name. `/` is an ordinary scalar
/// that `*` and `?` decline to cross and `**` crosses, so the same compiled
/// value serves a caller matching a whole path. What makes
/// `fileNamePatterns` name-only is `fileNamePattern(_:)`, which refuses a
/// source carrying a separator at all — a pattern for a language may not
/// reach outside the file it is deciding about. A path caller uses
/// `compile(_:)` and skips that rule.
///
/// ## Cost
///
/// Matching simulates the pattern as a state machine over the candidate: one
/// pass, `candidate × tokens` state checks, no recursion and no backtracking
/// to explode. `{a,b}` nested with `*` is where a backtracking matcher goes
/// exponential; there is nothing here to explode, because the alternatives
/// are expanded at compile time and each one is matched by a walk that never
/// revisits a position.
///
/// The caps below bound the rest. A source is at most `maxSourceLength`
/// scalars, so a branch holds at most that many tokens. Expansion is refused
/// past `maxBranches`, counted as a product before any branch is built, so
/// `{a,b}{a,b}{a,b}{a,b}{a,b}` never allocates the 32 branches it asks for.
/// A candidate longer than `maxCandidateLength` is refused unmatched, because
/// no filesystem this app reads holds one.
struct GlobPattern: Equatable, Sendable {
    enum Token: Equatable, Sendable {
        case literal(Unicode.Scalar)

        /// `?`
        case oneScalar

        /// `*`
        case run

        /// `**`
        case runAcrossSeparators

        var isRun: Bool {
            switch self {
            case .run, .runAcrossSeparators: return true
            case .literal, .oneScalar: return false
            }
        }
    }

    static let maxSourceLength = 64
    static let maxBranches = 16
    static let maxCandidateLength = 255

    /// Per language. A language needing more than this many patterns is
    /// describing something other than its own file names.
    static let maxPatternsPerLanguage = 32

    /// `/` only. A backslash is a legal scalar in a macOS file name, so
    /// treating it as a separator here would stop `*` from matching a name
    /// that legitimately holds one. `fileNamePattern(_:)` refuses a
    /// backslash in the *pattern* for a different reason: a Windows-shaped
    /// path should not be writable at all.
    static let separator: Unicode.Scalar = "/"

    /// The pattern as written, after canonicalization. Kept because it is
    /// what a claim token, a Settings row and an error message all need, and
    /// because two patterns with the same source compile the same way.
    let source: String

    let branches: [[Token]]

    // MARK: Compiling

    /// The dialect, with no opinion about what the candidate is. Separators
    /// are ordinary scalars here.
    static func compile(_ source: String) -> GlobPattern? {
        let scalars = Array(source.unicodeScalars)
        guard !scalars.isEmpty, scalars.count <= maxSourceLength else { return nil }
        guard let groups = parse(scalars) else { return nil }
        guard let branches = expand(groups) else { return nil }
        return GlobPattern(source: source, branches: branches)
    }

    /// The pattern a manifest's `fileNamePatterns` may hold: canonical the
    /// way `fileNames` is canonical, and carrying no separator, so it can
    /// only ever decide about the name it is handed.
    static func fileNamePattern(_ candidate: String) -> GlobPattern? {
        let text = candidate.trimmingCharacters(in: .whitespaces).lowercased()
        guard text != ".", text != ".." else { return nil }
        guard !text.contains("/"), !text.contains("\\") else { return nil }
        guard !text.unicodeScalars.contains(where: LanguageContribution.isUnsafeScalar)
        else { return nil }
        return compile(text)
    }

    /// One position of the source: a fixed token, or a list of alternatives
    /// each of which is a token sequence.
    private enum Group {
        case token(Token)
        case alternatives([[Token]])
    }

    /// A single scan. `{` opens a list, `,` separates inside one and is a
    /// literal outside one, `}` closes one, and anything unbalanced is
    /// refused rather than guessed at.
    private static func parse(_ scalars: [Unicode.Scalar]) -> [Group]? {
        var groups: [Group] = []
        var alternatives: [[Token]]?
        var current: [Token] = []
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]
            switch scalar {
            case "[", "]":
                return nil
            case "{":
                guard alternatives == nil else { return nil }
                groups += current.map(Group.token)
                current = []
                alternatives = []
                index += 1
                continue
            case ",":
                guard alternatives != nil else {
                    current.append(.literal(scalar))
                    index += 1
                    continue
                }
                guard !current.isEmpty else { return nil }
                alternatives?.append(current)
                current = []
                index += 1
                continue
            case "}":
                guard var list = alternatives, !current.isEmpty else { return nil }
                list.append(current)
                groups.append(.alternatives(list))
                alternatives = nil
                current = []
                index += 1
                continue
            case "*":
                var stars = 0
                while index < scalars.count, scalars[index] == "*" {
                    stars += 1
                    index += 1
                }
                current.append(stars == 1 ? .run : .runAcrossSeparators)
                continue
            case "?":
                current.append(.oneScalar)
            default:
                current.append(.literal(scalar))
            }
            index += 1
        }

        guard alternatives == nil else { return nil }
        groups += current.map(Group.token)
        return groups
    }

    /// The product of the alternative counts, refused before anything is
    /// built when it would pass the cap.
    private static func expand(_ groups: [Group]) -> [[Token]]? {
        var count = 1
        for group in groups {
            guard case .alternatives(let list) = group else { continue }
            count *= list.count
            guard count <= maxBranches else { return nil }
        }

        var branches: [[Token]] = [[]]
        for group in groups {
            switch group {
            case .token(let token):
                for index in branches.indices { branches[index].append(token) }
            case .alternatives(let list):
                var grown: [[Token]] = []
                grown.reserveCapacity(branches.count * list.count)
                for branch in branches {
                    for alternative in list { grown.append(branch + alternative) }
                }
                branches = grown
            }
        }
        return branches.isEmpty ? nil : branches
    }

    // MARK: Matching

    func matches(_ candidate: String) -> Bool {
        let scalars = Array(candidate.unicodeScalars)
        guard scalars.count <= Self.maxCandidateLength else { return false }
        return branches.contains { Self.matches(branch: $0, scalars: scalars) }
    }

    /// The branch simulated as a state machine, where a state is a position
    /// between two tokens and every reachable state is advanced together.
    ///
    /// One pass over the candidate, and one pass over the token positions for
    /// each scalar. A backtracking matcher would explore the run positions
    /// instead, which is what makes `*a*a*a*a*b` against a long run of `a`
    /// hang; here the positions are simply all live at once and the cost
    /// cannot rise above the product.
    private static func matches(branch: [Token], scalars: [Unicode.Scalar]) -> Bool {
        var live = [Bool](repeating: false, count: branch.count + 1)
        close(&live, from: 0, branch: branch)

        var next = [Bool](repeating: false, count: branch.count + 1)
        for scalar in scalars {
            for index in next.indices { next[index] = false }
            var advanced = false

            for position in 0..<branch.count where live[position] {
                switch branch[position] {
                case .literal(let expected):
                    guard expected == scalar else { continue }
                    close(&next, from: position + 1, branch: branch)
                case .oneScalar:
                    guard scalar != separator else { continue }
                    close(&next, from: position + 1, branch: branch)
                case .run:
                    guard scalar != separator else { continue }
                    close(&next, from: position, branch: branch)
                case .runAcrossSeparators:
                    close(&next, from: position, branch: branch)
                }
                advanced = true
            }

            guard advanced else { return false }
            swap(&live, &next)
        }

        return live[branch.count]
    }

    /// Marks a position live, and every position a run can reach without
    /// consuming anything — a run matches an empty span, so the position
    /// after it is reachable the moment the position before it is.
    private static func close(_ live: inout [Bool], from position: Int, branch: [Token]) {
        var position = position
        live[position] = true
        while position < branch.count, branch[position].isRun {
            position += 1
            live[position] = true
        }
    }
}
