import Foundation

/// One `contributes.grammars[]` entry: a TextMate grammar an extension ships.
///
/// This is the whole of how a language gets coloured now. There is no
/// compiled-in lexer to fall back to, so a language with no grammar installed
/// is plain text, and a grammar that fails to parse costs the extension that
/// grammar and nothing else.
struct GrammarContribution: Equatable, Sendable {
    let scopeName: String

    /// The grammar file, already proven to be inside the extension's own
    /// directory.
    let fileURL: URL

    /// The language this grammar colours, when it colours a whole language.
    /// A grammar that exists only to be included by others has none.
    let languageID: String?

    /// Scope name → language id, for the pieces of another language this one
    /// embeds. Read by the tokenizer to pick the grammar an embedded region
    /// is lexed with.
    let embeddedLanguages: [String: String]

    /// Scope names this grammar injects itself into.
    let injectTo: [String]

    static let maxGrammars = 32
    static let maxBytes = 4 * 1024 * 1024
    static let maxEmbedded = 64
    static let maxInjectTo = 16

    static func parse(json: [String: Any], root: URL) -> GrammarContribution? {
        guard let scopeName = LanguageManifest.string(json["scopeName"]),
              Self.isScopeName(scopeName),
              let fileURL = LanguageContribution.containedURL(json["path"], root: root),
              fileURL.pathExtension.lowercased() == "json"
        else { return nil }

        let languageID = LanguageManifest.string(json["languageId"]).flatMap { LanguageManifest.validID($0) }

        var embedded: [String: String] = [:]
        if let raw = json["embeddedLanguages"] as? [String: Any] {
            for (scope, value) in raw.prefix(maxEmbedded) {
                guard Self.isScopeName(scope),
                      let id = LanguageManifest.string(value),
                      let valid = LanguageManifest.validID(id)
                else { continue }
                embedded[scope] = valid
            }
        }

        let injectTo = ((json["injectTo"] as? [Any]) ?? [])
            .prefix(maxInjectTo)
            .compactMap { LanguageManifest.string($0) }
            .filter(Self.isScopeName)

        return GrammarContribution(
            scopeName: scopeName,
            fileURL: fileURL,
            languageID: languageID,
            embeddedLanguages: embedded,
            injectTo: injectTo
        )
    }

    /// `source.lua`, `text.html.basic`: dotted lower-case words, nothing else.
    static func isScopeName(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else { return false }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "+") }
        }
    }
}
