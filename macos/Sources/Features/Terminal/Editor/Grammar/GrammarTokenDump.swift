import Foundation

#if DEBUG
/// Writes the kinds the editor would paint a file with, for comparison
/// against another implementation of the same grammars.
///
/// Set `PHANTOM_TOKEN_DUMP` to a colon-separated list of files and
/// `PHANTOM_TOKEN_DUMP_OUT` to where the report goes. Each line is a line
/// number, the text of one painted span and the kind, tab separated. Spans
/// the theme leaves plain are left out, because those are the ones the
/// editor does not paint.
enum GrammarTokenDump {
    @MainActor
    static func runIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard let input = environment["PHANTOM_TOKEN_DUMP"],
              let output = environment["PHANTOM_TOKEN_DUMP_OUT"]
        else { return }

        var report: [String] = []
        for path in input.split(separator: ":").map(String.init) {
            report.append("== " + path)
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
                report.append("!! unreadable")
                continue
            }
            let name = (path as NSString).lastPathComponent
            let highlighter = LanguageResolver.shared.highlighter(forFileName: name)
            if highlighter.isPlain {
                report.append("!! no grammar")
                continue
            }
            report.append(contentsOf: rows(of: text, by: highlighter))
        }
        try? report.joined(separator: "\n").write(toFile: output, atomically: true, encoding: .utf8)
    }

    private static func rows(of text: String, by highlighter: GrammarHighlighter) -> [String] {
        let content = text as NSString
        let whole = NSRange(location: 0, length: content.length)
        var starts: [Int] = [0]
        content.enumerateSubstrings(in: whole, options: [.byLines, .substringNotRequired]) { _, _, enclosing, _ in
            starts.append(NSMaxRange(enclosing))
        }

        return highlighter.tokens(in: text, range: whole).compactMap { token in
            let piece = content.substring(with: token.range)
            guard !piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let index = starts.lastIndex { $0 <= token.range.location } ?? 0
            let start = token.range.location - starts[index]
            return "\(index + 1)\t\(start)\t\(start + token.range.length)\t\(token.kind)"
        }
    }
}
#endif
