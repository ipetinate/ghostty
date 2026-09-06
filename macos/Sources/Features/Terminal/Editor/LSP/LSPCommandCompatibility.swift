import Foundation

/// Which files a binary may be handed at all.
///
/// This is not language knowledge, and the distinction is the reason the
/// file survived the removal of the server table. "`tsc` dies on a `.css`"
/// is a fact about one program's behaviour, not a claim about which
/// languages exist or which servers serve them.
enum LSPCommandCompatibility {
    /// The command of the TypeScript compiler when it is asked to speak LSP
    /// itself — `tsc --lsp --stdio`.
    static let nativeTypeScriptCommand = "tsc"

    /// Every file extension `tsc --lsp --stdio` will accept.
    ///
    /// **An allowlist, and it may never become a subtraction.** Measured, one
    /// `didOpen` per process: `.ts`, `.tsx`, `.js`, `.jsx`, `.mts`, `.cts` and
    /// `.json` are served; `.vue`, `.svelte`, `.astro`, `.mdx`, `.css` and a
    /// file with no extension at all each **kill the process**:
    ///
    /// ```
    /// panic: ScriptKind must be specified when parsing source file: …/probe.vue
    /// github.com/microsoft/typescript-go/internal/parser.(*Parser).initializeState
    /// ```
    ///
    /// It does not answer empty and it does not decline the document — it
    /// dies, and every other file that server was serving dies with it. That
    /// is why "everything except `.vue`" is the wrong shape: `.vue` is only
    /// the first one anybody happened to try.
    ///
    /// **This is an upstream defect, not a design limit.** A language server
    /// is supposed to decline a document it cannot parse, the way
    /// `typescript-language-server` answers `Unexpected resource …`. If
    /// `typescript-go` fixes it, this list can grow.
    static let nativeTypeScriptExtensions: Set<String> = [
        "ts", "tsx", "js", "jsx", "mts", "cts", "json",
    ]

    /// Whether a binary may be handed this file at all.
    ///
    /// Keyed on the **command**, because the fact is about the binary and is
    /// identical for every definition that names it. Nothing this build
    /// ships declares `tsc`, so today it fires for exactly two things it
    /// cannot otherwise see:
    ///
    /// - a **user override** repointing some language's command at `tsc`,
    ///   which keeps that language's own definition;
    /// - a **contributed manifest** declaring `command: "tsc"` with
    ///   `args: ["--lsp", "--stdio"]`.
    ///
    /// The usual objection to a lookup — that a call site can forget it — is
    /// answered by there being exactly one call site:
    /// `LSPCenter.resolvedPairs(forPath:)`, after the override is applied,
    /// which is the only way any definition reaches a process.
    ///
    /// The trust gate cannot cover this. It approves a *command*; it has no
    /// way to know the command panics on the file about to be opened, and a
    /// user who approved `tsc` approved a language server, not a crash.
    static func accepts(command: String, path: String) -> Bool {
        guard command == nativeTypeScriptCommand else { return true }
        return nativeTypeScriptExtensions.contains(
            (path as NSString).pathExtension.lowercased()
        )
    }
}
