import Foundation

/// How the engine colours a fenced block of code, whose label is whatever the
/// author of the document typed.
///
/// A function rather than a highlighter, because one document holds fences in
/// several languages and no label is known until the document is parsed. The
/// document language gets a plain `GrammarHighlighter` instead — one file, one
/// answer, resolved once by the host.
///
/// **Which grammar a label names is a fact about what the host installed, so
/// the host answers it.** A fence label is not a language id: it is an alias,
/// a file extension, or a word naming no language at all, and resolving it
/// means reading a catalog built out of manifests on disk. An engine that did
/// that could never be extracted, and it would take the validation standing
/// between a file on disk and a grammar that runs with it. `EditorEngineBoundaryTests`
/// is the rule; this type is the seam that keeps it.
struct FenceHighlighting {
    private let resolve: (String?) -> GrammarHighlighter

    /// Every fence plain.
    ///
    /// The honest answer for a host that installed no grammars, and the
    /// default so that no engine call site has to invent one — a fence drawn
    /// uncoloured still shows its text.
    static let plain = FenceHighlighting { _ in .plain }

    init(_ resolve: @escaping (String?) -> GrammarHighlighter) {
        self.resolve = resolve
    }

    /// - Parameter label: nil for a fence that named nothing, which draws
    ///   uncoloured rather than guessing at a language. Wrong colours read as
    ///   a bug in the file being described.
    func highlighter(forFenceLabel label: String?) -> GrammarHighlighter {
        resolve(label)
    }
}
