import Foundation
import GhosttyKit

/// One compiled Oniguruma pattern.
///
/// The grammar engine cannot use `NSRegularExpression`. TextMate grammars are
/// written in Oniguruma's dialect and lean on three things ICU does not give:
/// a backreference in an `end` pattern that refers to a group captured by the
/// matching `begin`, `\G` to anchor a continuation where the last match
/// stopped, and lookbehind. Oniguruma is already linked into the binary for
/// terminal link detection, so this is a bridge rather than a dependency.
///
/// **Offsets here are UTF-8 byte offsets, not UTF-16.** Oniguruma searches
/// bytes, and converting per match would cost more than it saves. The caller
/// holds the line as bytes and converts once, when it emits tokens.
///
/// **Not thread-safe.** A handle owns the buffer its matches are written
/// into, so two threads searching one instance overwrite each other. Compile
/// one per thread.
final class OnigRegex {
    let pattern: String

    /// Group count including group zero, which is the whole match.
    let captureCount: Int

    private let handle: ghostty_regex_t
    private var captures: [Int64]

    init?(pattern: String) {
        let length = pattern.utf8.count
        guard let handle = pattern.withCString({ ghostty_regex_new($0, UInt(length)) }) else { return nil }

        self.pattern = pattern
        self.handle = handle
        self.captureCount = max(Int(ghostty_regex_capture_count(handle)), 1)
        self.captures = Array(repeating: -1, count: self.captureCount * 2)
    }

    deinit {
        ghostty_regex_free(handle)
    }

    /// Searches from `start` to the end of `text`, and reports whether it
    /// matched. The whole buffer is passed rather than the slice being
    /// searched so that `^`, `\G` and lookbehind see their real context.
    ///
    /// Read the result with ``range(of:)``. Each search overwrites the last.
    func search(_ text: UnsafeRawBufferPointer, from start: Int) -> Bool {
        guard start >= 0, start <= text.count else { return false }
        guard let base = text.baseAddress else { return searchEmpty() }
        let found = base.withMemoryRebound(to: CChar.self, capacity: text.count) { pointer in
            captures.withUnsafeMutableBufferPointer { buffer in
                ghostty_regex_search(
                    handle,
                    pointer,
                    UInt(text.count),
                    UInt(start),
                    buffer.baseAddress,
                    UInt(captureCount))
            }
        }
        return found > 0
    }

    /// The byte range one group of the last match covered, or nil when that
    /// group took part in no match.
    func range(of group: Int) -> Range<Int>? {
        guard group >= 0, group < captureCount else { return nil }
        let start = captures[group * 2]
        let end = captures[group * 2 + 1]
        guard start >= 0, end >= start else { return nil }
        return Int(start)..<Int(end)
    }

    /// An empty buffer has no base address to hand Oniguruma, and a blank
    /// line is not a case a tokenizer may skip: a rule anchored with `^$`
    /// has to be able to match one.
    private func searchEmpty() -> Bool {
        var byte: UInt8 = 0
        return withUnsafeMutableBytes(of: &byte) { buffer in
            guard let base = buffer.baseAddress else { return false }
            return base.withMemoryRebound(to: CChar.self, capacity: 0) { pointer in
                captures.withUnsafeMutableBufferPointer { output in
                    ghostty_regex_search(handle, pointer, 0, 0, output.baseAddress, UInt(captureCount))
                } > 0
            }
        }
    }

    func search(_ text: [UInt8], from start: Int = 0) -> Bool {
        text.withUnsafeBytes { search($0, from: start) }
    }

    /// Every group of the first match at or after `start`, group zero first,
    /// with nil for a group that took part in no match.
    ///
    /// Allocates, so it is for tests and for the rare one-shot caller. A
    /// tokenizer uses ``search(_:from:)`` and ``range(of:)``.
    func firstMatch(in text: String, from start: Int = 0) -> [Range<Int>?]? {
        let bytes = Array(text.utf8)
        guard search(bytes, from: start) else { return nil }
        return (0..<captureCount).map { range(of: $0) }
    }
}
