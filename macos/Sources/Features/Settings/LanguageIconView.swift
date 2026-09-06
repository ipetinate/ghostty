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
            Image(systemName: "chevron.left.forwardslash.chevron.right")
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
        let base: String
        switch languageID {
        case "typescript", "typescriptreact", "javascript", "javascriptreact":
            base = "ts-js"
        case "vue": base = "vue"
        case "swift": base = "swift"
        case "kotlin": base = "kotlin"
        case "python": base = "python"
        case "rust": base = "rust"
        case "go": base = "go"
        case "zig": base = "zig"
        case "json": base = "json"
        case "yaml": base = "yaml"
        case "toml": base = "toml"
        case "shellscript": base = "bash"
        case "html": base = "html"
        case "css", "scss", "less": base = "css"
        case "java": base = "java"
        case "c": base = "c"
        case "cpp": base = "cpp"
        case "terraform": base = "terraform"
        case "php": base = "php"
        case "ruby": base = "ruby"
        case "markdown": base = "markdown"
        default: return nil
        }
        return "Lang-\(base)"
    }
}
