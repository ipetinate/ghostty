import Foundation

/// Which characters a jump should point at.
///
/// A language server answers "where is this defined" with one range and no
/// separate name range, and servers disagree about what belongs in it: some
/// return the identifier, some the entire definition. Elixir's returns the
/// whole module, so the range that arrives for `Blog.Content.Post` is sixty
/// five lines long. Marking all of it is how a jump ends up looking like a
/// selection, which is the complaint this type answers.
///
/// So the mark is *derived* rather than taken. The rule is one sentence: the
/// first line of the range that has anything on it, trimmed, and never more
/// than a name's worth of it. That lands the mark on
/// `defmodule Blog.Content.Post do` — which is what the reader was looking
/// for, and is honest about what the server actually said, since it claims
/// nothing the range did not contain.
///
/// Arithmetic over an `NSString`, with no view and no layout manager, because
/// the boundaries are where this goes wrong: an empty range, a range at the
/// very end of the file, a range whose first line is only whitespace, a range
/// that starts in the middle of a line.
enum CodeRevealHighlight {
    /// The widest mark, in UTF-16 units.
    ///
    /// A ceiling rather than a measurement of the window, because the window
    /// is not knowable here and does not need to be: what this prevents is a
    /// single pathological line — a minified bundle, a generated table — being
    /// marked from edge to edge, and any bound well under a screenful does
    /// that. 120 is longer than every declaration a person writes and shorter
    /// than a line nobody reads.
    static let maximumLength = 120

    /// The characters to mark for a range a server gave, or nil when there is
    /// nothing worth marking.
    ///
    /// Nil rather than an empty range for the cases with no answer — a range
    /// of no length, a range past the end of the text, a range with no
    /// non-blank character in it. A mark over nothing is worse than no mark:
    /// it is a box the reader looks inside and finds empty.
    static func range(for range: NSRange, in text: NSString) -> NSRange? {
        let clipped = clip(range, in: text)
        guard clipped.length > 0 else { return nil }

        let limit = NSMaxRange(clipped)
        var cursor = clipped.location

        while cursor < limit {
            var contentsEnd = 0
            var lineEnd = 0
            text.getLineStart(
                nil,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: cursor, length: 0)
            )

            let end = min(contentsEnd, limit)
            if end > cursor,
               let trimmed = trim(NSRange(location: cursor, length: end - cursor), in: text) {
                return cap(trimmed, in: text)
            }

            guard lineEnd > cursor else { return nil }
            cursor = lineEnd
        }
        return nil
    }

    /// The range with both ends inside the text.
    ///
    /// A server describes a file it was last told about, and the reader has
    /// been typing since. A range that ran past the end used to be handed to
    /// the layout manager as it arrived.
    private static func clip(_ range: NSRange, in text: NSString) -> NSRange {
        let location = min(max(0, range.location), text.length)
        let length = min(max(0, range.length), text.length - location)
        return NSRange(location: location, length: length)
    }

    /// The same characters without the blanks at either end, or nil when that
    /// leaves nothing.
    ///
    /// Leading indentation is the reason this exists: a definition nested in a
    /// module starts at column zero of its line as far as the server is
    /// concerned, and marking the indentation draws a box that begins in empty
    /// space and reads as a misplaced one.
    private static func trim(_ range: NSRange, in text: NSString) -> NSRange? {
        var start = range.location
        var end = NSMaxRange(range)

        while start < end, isBlank(text.character(at: start)) { start += 1 }
        while end > start, isBlank(text.character(at: end - 1)) { end -= 1 }

        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    /// The range, shortened to `maximumLength` without splitting a character.
    ///
    /// `NSRange` counts UTF-16 units, and a cut that lands between the halves
    /// of a surrogate pair is a range the layout manager cannot measure. The
    /// composed sequence at the cut is what says where the nearest legal
    /// boundary below it is.
    private static func cap(_ range: NSRange, in text: NSString) -> NSRange {
        guard range.length > maximumLength else { return range }

        var end = range.location + maximumLength
        let composed = text.rangeOfComposedCharacterSequence(at: end)
        if composed.location < end, composed.location > range.location {
            end = composed.location
        }
        return NSRange(location: range.location, length: end - range.location)
    }

    /// Whether a unit is space the reader would not call part of the name.
    ///
    /// Spelled as units rather than asked of `CharacterSet`, which takes a
    /// scalar: half a surrogate pair is not a scalar, and it is never a blank
    /// either, so the question can be answered without building one.
    private static func isBlank(_ unit: unichar) -> Bool {
        switch unit {
        case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x2028, 0x2029, 0x3000:
            return true
        default:
            return false
        }
    }
}
