import Foundation

/// The pair of markers a block comment is written between.
struct BlockComment: Equatable, Sendable {
    let open: String
    let close: String
}

/// The comment syntax of a file, as its extension declared it.
struct CommentMarkers: Equatable, Sendable {
    let line: String?
    let block: BlockComment?

    static let none = CommentMarkers(line: nil, block: nil)
}

/// Colours text with a TextMate grammar and answers in the editor's terms:
/// UTF-16 ranges and the theme's token kinds.
///
/// The tokenizer underneath works in UTF-8 bytes a line at a time and knows
/// nothing about `NSRange`. This is the seam where bytes become UTF-16 units,
/// and where scope names become the nine kinds the theme paints. Everything
/// that used to ask the compiled-in highlighter asks this instead.
///
/// One instance per thread. It owns a tokenizer whose caches are not shared,
/// and a stateless call re-tokenizes from the top of the text, which is the
/// right cost for a diff pane or a hover card and the wrong one for the
/// editor: ``CodeTextStorage`` keeps line state through
/// ``LineTokenizationCache`` for that.
final class GrammarHighlighter: @unchecked Sendable {
    struct Token: Equatable {
        let range: NSRange
        let kind: TokenKind
    }

    let tokenizer: GrammarTokenizer?
    let theme: ScopeTheme

    /// The highlighter for a file nothing installed knows how to colour.
    static let plain = GrammarHighlighter(tokenizer: nil)

    init(tokenizer: GrammarTokenizer?, theme: ScopeTheme = .standard) {
        self.tokenizer = tokenizer
        self.theme = theme
    }

    var isPlain: Bool { tokenizer == nil }

    var initialState: TokenizerState? { tokenizer?.initialState }

    /// Every token in `range`, tokenizing from the top of the text so that a
    /// construct opened above the range is known to be open.
    func tokens(in text: String, range: NSRange) -> [Token] {
        guard let tokenizer else { return [] }
        let content = text as NSString
        let end = min(NSMaxRange(range), content.length)
        guard range.location < end else { return [] }

        var tokens: [Token] = []
        var state = tokenizer.initialState
        var location = 0
        while location < end {
            let line = content.lineRange(for: NSRange(location: location, length: 0))
            let lineEnd = NSMaxRange(line)
            let bytes = Array(content.substring(with: line).utf8)
            let result = tokenizer.tokenize(bytes, state: state)
            if lineEnd > range.location {
                append(result.spans, of: bytes, at: line.location, into: &tokens)
            }
            state = result.state
            guard lineEnd > location else { break }
            location = lineEnd
        }
        return tokens.compactMap { token in
            let clipped = NSIntersectionRange(token.range, NSRange(location: range.location, length: end - range.location))
            return clipped.length > 0 ? Token(range: clipped, kind: token.kind) : nil
        }
    }

    /// One line, carrying state in and out, for a caller that keeps the
    /// state itself.
    func tokens(
        inLine bytes: [UInt8],
        at location: Int,
        state: TokenizerState
    ) -> (tokens: [Token], state: TokenizerState) {
        guard let tokenizer else { return ([], state) }
        let result = tokenizer.tokenize(bytes, state: state)
        var tokens: [Token] = []
        append(result.spans, of: bytes, at: location, into: &tokens)
        return (tokens, result.state)
    }

    private func append(
        _ spans: [GrammarTokenizer.Span],
        of bytes: [UInt8],
        at location: Int,
        into tokens: inout [Token]
    ) {
        var offsets = UTF16Offsets(bytes: bytes)
        for span in spans {
            let kind = theme.kind(for: span.scopes)
            guard kind != .plain else { continue }
            let start = offsets.units(before: span.range.lowerBound)
            let end = offsets.units(before: span.range.upperBound)
            guard end > start else { continue }
            tokens.append(Token(range: NSRange(location: location + start, length: end - start), kind: kind))
        }
    }
}

/// Turns UTF-8 byte offsets into UTF-16 unit counts, for offsets asked in
/// increasing order, which is the order spans arrive in.
///
/// A byte that starts a sequence counts one unit, or two when the sequence
/// is four bytes long and so lands outside the BMP; continuation bytes count
/// nothing. Walking once and answering monotonically is what keeps a line
/// with a few dozen spans O(n) instead of O(n × spans).
struct UTF16Offsets {
    private let bytes: [UInt8]
    private var byteCursor = 0
    private var unitCursor = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func units(before byteOffset: Int) -> Int {
        let target = min(max(byteOffset, 0), bytes.count)
        if target < byteCursor {
            byteCursor = 0
            unitCursor = 0
        }
        while byteCursor < target {
            let byte = bytes[byteCursor]
            if byte & 0b1100_0000 != 0b1000_0000 {
                unitCursor += byte >= 0b1111_0000 ? 2 : 1
            }
            byteCursor += 1
        }
        return unitCursor
    }
}
