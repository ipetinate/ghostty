import SwiftUI

/// A language's logo at a fixed size, so logos of any aspect ratio line up
/// across a list.
struct LanguageIconView: View {
    let name: String?
    var size: CGFloat = 18

    var body: some View {
        if let name {
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: LSPServerDefinition.genericLanguageSymbol)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}

extension LSPServerDefinition {
    /// The asset name of the logo this app ships for a language id, or nil
    /// when it ships none.
    ///
    /// A `static` on the definition rather than an instance property,
    /// because the caller is usually a contributed language — which is not
    /// an `LSPServerDefinition` and may have no server at all. An extension
    /// contributing `elixir` gets the generic glyph; one contributing a
    /// second opinion about `ruby` gets the Ruby logo, which is the right
    /// answer either way.
    static func iconName(forLanguageID languageID: String) -> String? {
        languageIconNames[languageID]
    }

    /// The logos this app ships, by the language ids they are drawn for.
    ///
    /// A dictionary rather than a `switch` so the set can be enumerated: a
    /// name that is not in `Assets.xcassets` draws nothing — no crash, no
    /// warning, an 18-point hole in a row — and the only way to catch that
    /// is to ask the bundle for every name this can return.
    ///
    /// Several ids share one image on purpose. The four TypeScript and
    /// JavaScript ids are one language family with one logo between them,
    /// and `scss` and `less` are drawn as CSS because neither ships a mark a
    /// reader would recognise at 18 points.
    static let languageIconNames: [String: String] = [
        "typescript": "Lang-ts-js",
        "typescriptreact": "Lang-ts-js",
        "javascript": "Lang-ts-js",
        "javascriptreact": "Lang-ts-js",
        "vue": "Lang-vue",
        "swift": "Lang-swift",
        "kotlin": "Lang-kotlin",
        "python": "Lang-python",
        "rust": "Lang-rust",
        "go": "Lang-go",
        "zig": "Lang-zig",
        "json": "Lang-json",
        "yaml": "Lang-yaml",
        "toml": "Lang-toml",
        "shellscript": "Lang-bash",
        "html": "Lang-html",
        "css": "Lang-css",
        "scss": "Lang-css",
        "less": "Lang-css",
        "java": "Lang-java",
        "c": "Lang-c",
        "cpp": "Lang-cpp",
        "terraform": "Lang-terraform",
        "php": "Lang-php",
        "ruby": "Lang-ruby",
        "markdown": "Lang-markdown",
    ]

    /// Drawn for a language this app ships no logo for, which after 0.17.0
    /// is every language an extension can contribute.
    static let genericLanguageSymbol = "chevron.left.forwardslash.chevron.right"
}
