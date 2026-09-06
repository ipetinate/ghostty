import Foundation

/// The tokenizer state at the start of every line the editor has coloured.
///
/// A grammar carries state across lines — inside a block comment, inside a
/// heredoc — and this is what makes that cheap: a line is tokenized from the
/// state its predecessor ended in, and an edit throws away only the states
/// from the edited line down. The old highlighter had no state and paid for it
/// with a 4096-character window around every edit, which was a guess.
///
/// Two parallel arrays, valid as a prefix. `starts[i]` is the UTF-16 offset
/// where line `i` begins and `states[i]` is the state the tokenizer is in when
/// it gets there, so `states[0]` is always the initial state and the arrays
/// are never empty.
final class LineTokenizationCache {
    private var starts: [Int] = [0]
    private var states: [TokenizerState]

    init(initialState: TokenizerState) {
        states = [initialState]
    }

    var lineCount: Int { starts.count }

    /// Forgets every line from the one containing `location` onwards. The
    /// line containing the edit keeps its *start* state, because nothing
    /// before it changed, and loses everything after.
    func invalidate(from location: Int) {
        let line = lineIndex(containing: location)
        guard line + 1 < starts.count else { return }
        starts.removeSubrange((line + 1)...)
        states.removeSubrange((line + 1)...)
    }

    func reset(initialState: TokenizerState) {
        starts = [0]
        states = [initialState]
    }

    /// Tokens for `range`, tokenizing forward from the last line the cache
    /// knows about when the range lies beyond it.
    ///
    /// `seed` is for a document too large to walk from the top on every
    /// paint: when set and the range starts past the cached prefix, the
    /// lines between are skipped and the first visible line is tokenized from
    /// the initial state instead. That can miscolour a construct that opened
    /// above the viewport, which is the trade the old highlighter made for
    /// every file; this makes it only for the ones that need it.
    func tokens(
        in content: NSString,
        range: NSRange,
        highlighter: GrammarHighlighter,
        seedWhenBehind: Bool = false
    ) -> [GrammarHighlighter.Token] {
        guard let initial = highlighter.initialState else { return [] }
        let end = min(NSMaxRange(range), content.length)
        guard range.location < end else { return [] }

        var line = lineIndex(containing: range.location)
        var location = starts[line]
        var state = states[line]

        if seedWhenBehind, line == starts.count - 1, location < range.location {
            let visible = content.lineRange(for: NSRange(location: range.location, length: 0))
            if visible.location > location {
                location = visible.location
                state = initial
                line = -1
            }
        }

        var tokens: [GrammarHighlighter.Token] = []
        while location < end {
            let lineRange = content.lineRange(for: NSRange(location: location, length: 0))
            let lineEnd = NSMaxRange(lineRange)
            let bytes = Array(content.substring(with: lineRange).utf8)
            let result = highlighter.tokens(inLine: bytes, at: lineRange.location, state: state)
            if lineEnd > range.location {
                tokens.append(contentsOf: result.tokens)
            }
            state = result.state
            guard lineEnd > location else { break }
            if line >= 0, line + 1 == starts.count, lineEnd < content.length {
                starts.append(lineEnd)
                states.append(state)
            }
            if line >= 0 { line += 1 }
            location = lineEnd
        }

        let window = NSRange(location: range.location, length: end - range.location)
        return tokens.compactMap { token in
            let clipped = NSIntersectionRange(token.range, window)
            return clipped.length > 0 ? GrammarHighlighter.Token(range: clipped, kind: token.kind) : nil
        }
    }

    /// The index of the cached line containing `location`, or the last cached
    /// line when `location` lies beyond the prefix.
    func lineIndex(containing location: Int) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= location {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }
}
