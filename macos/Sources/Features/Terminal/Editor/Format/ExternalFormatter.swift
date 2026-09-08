import Foundation

/// A formatter that is a command, for a language nothing else in this editor
/// formats.
///
/// The gap it fills is real and was measured rather than assumed: a language
/// server is asked what it offers, and several answer nothing. `pyright` has
/// no formatter at all, by design, and says so in its own documentation.
/// Shell is the same story one step removed — `bash-language-server`
/// advertises formatting and shells out to `shfmt`, so a machine without
/// `shfmt` has a server that says yes and does nothing.
///
/// Every value of this type is built from a `contributes.formatters` entry:
/// there is no compiled-in table left, so an extension is the only thing that
/// can put a tool in front of a reader. What the tool asks of a project before
/// it rewrites its files — a configuration that has to exist, a copy installed
/// into the project, a directory to run in — is `projectRules`, declared in
/// that same manifest entry.
struct ExternalFormatter: Identifiable, Hashable, Sendable {
    /// The language, spelled as its LSP `languageId` where there is a server
    /// for it. It is also the settings key, so it does not change.
    let id: String

    /// The language, as a person says it.
    let languageName: String

    /// The tool, as its own project spells it.
    let displayName: String

    let command: String

    /// Arguments as the tool wants them, with `$FILE` where it wants the name
    /// of the file being formatted.
    ///
    /// The name matters even though the text arrives on stdin: it is how these
    /// tools find their own configuration — `ruff` reads the `pyproject.toml`
    /// above the file, `stylua` reads `stylua.toml` — and how `shfmt` tells
    /// bash from zsh. It is the same reason Prettier is handed
    /// `--stdin-filepath`.
    let arguments: [String]

    /// What the tool is asked to format, lowercased and without the dot.
    let extensions: Set<String>

    let installHint: String

    /// Anything a reader should know before switching it on. Nil for the ones
    /// that simply format.
    let note: String?

    var provenance: ExtensionProvenance?

    /// What the project has to say before this runs, and where it runs.
    ///
    /// Empty means the tool asks for nothing and is run wherever the file is,
    /// which is the answer for a manifest that declares no rules at all.
    var projectRules = FormatterProjectRules()

    var origin: LSPServerOrigin {
        provenance.map(LSPServerOrigin.manifest) ?? .builtIn
    }

    /// What the project has to say before this tool rewrites its files.
    func project(forFile path: String) -> FormatterProject {
        FormatterProject.discover(forFile: path, rules: projectRules)
    }

    /// The arguments for one file: `$FILE` replaced, everything else as
    /// written.
    func arguments(for path: String) -> [String] {
        arguments.map { $0 == Self.filePlaceholder ? path : $0 }
    }

    static let filePlaceholder = "$FILE"

    /// The command line as a person would type it, for the settings row.
    var invocation: String {
        ([command] + arguments).joined(separator: " ")
    }
}
