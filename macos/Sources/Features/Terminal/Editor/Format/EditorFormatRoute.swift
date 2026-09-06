import Foundation

/// Who formats a file: the tool the project adopted, the language server, or
/// a tool the reader asked for by hand.
///
/// Three rules, and which one applies is decided by how much the project said
/// about the tool — see `FormatterProject.Adoption`. The routing is here, away
/// from the view, because it is the part that can rewrite somebody's file in a
/// style their project rejected.
enum EditorFormatRoute {
    /// Whether the formatter resolved for this file gets to run.
    ///
    /// - Parameters:
    ///   - adoption: how much the project said about this tool.
    ///   - trigger: `.save` is the editor's own idea and gets the strict
    ///     reading; ⇧⌘F is the reader asking by hand.
    ///   - server: the status of this file's language server, or nil when no
    ///     server is configured for the language at all.
    ///   - serverFormats: whether it advertised `documentFormattingProvider`.
    ///   - handshakeTimedOut: whether the caller already waited out
    ///     `serverSettleTimeout` and the server is *still* starting.
    ///   - serverReturnedNothing: whether the server has already been asked
    ///     and came back with no edits.
    static func usesFormatter(
        adoption: FormatterProject.Adoption,
        trigger: EditorFormatTrigger,
        server: LSPServerStatus?,
        serverFormats: Bool,
        handshakeTimedOut: Bool = false,
        serverReturnedNothing: Bool = false
    ) -> Bool {
        switch adoption {
        /// The project declared this tool, so the project already answered
        /// the question. A language server formatting the file another way is
        /// the wrong answer arriving faster.
        case .adopted:
            return true

        case .unadopted:
            return usesUnadoptedFormatter(
                trigger: trigger,
                server: server,
                serverFormats: serverFormats,
                handshakeTimedOut: handshakeTimedOut)

        case .undeclared:
            return usesExternalFormatter(
                server: server,
                serverFormats: serverFormats,
                serverReturnedNothing: serverReturnedNothing)
        }
    }

    /// Whether a tool the project never declared gets the last word on ⇧⌘F.
    ///
    /// Markdown is the case it exists for. `marksman` offers no formatting at
    /// all, so a `.md` file in a repository that declares no formatter —
    /// which is most repositories, this one included — answered ⇧⌘F with
    /// "This language server doesn't offer formatting": the wrong tool named
    /// for a file whose project formats it from the command line.
    ///
    /// Only on ⇧⌘F, and that is the whole justification. A save is the
    /// editor's own idea and must respect what the project declared; ⇧⌘F is
    /// the reader, in this file, now, asking for it by hand.
    static func usesUnadoptedFormatter(
        trigger: EditorFormatTrigger,
        server: LSPServerStatus?,
        serverFormats: Bool,
        handshakeTimedOut: Bool
    ) -> Bool {
        guard trigger == .command, !serverFormats else { return false }

        /// A server still shaking hands has not said what it offers yet, and
        /// `hasCapability` answers false for "not said" exactly as it does for
        /// "does not have it". Taking the fallback here would mean that ⇧⌘F in
        /// the first seconds of a TypeScript file formatted it with the tool's
        /// defaults instead of with the server that was about to answer.
        ///
        /// Which is why the caller waits — see `waitsForServer` — and why the
        /// wait having expired is a separate fact from the server's state. A
        /// handshake that has not finished after `serverSettleTimeout` is not
        /// an answer the reader should keep being told about: the first ⇧⌘F on
        /// a Markdown file, typed while `marksman` was still loading the
        /// folder, reported "this language server doesn't offer formatting"
        /// about a server that had not yet said anything at all.
        if server == .starting, !handshakeTimedOut { return false }

        /// Every other state is a real answer, failures included. A `.md` file
        /// whose `marksman` is not installed is better served by the tool than
        /// by a sentence about `marksman`.
        return true
    }

    /// How long ⇧⌘F waits for a handshake before routing without it.
    ///
    /// Long enough for a server that is going to answer — the ones here
    /// advertise their capabilities in the first exchange, well inside this —
    /// and short enough that a reader who pressed a key does not think the key
    /// did nothing.
    static let serverSettleTimeout: TimeInterval = 3

    /// Whether to wait at all before reading the server's answer.
    ///
    /// Only for ⇧⌘F, and only while the handshake is actually in flight. A
    /// save must never stall on the network: format-on-save runs on every ⌘S,
    /// and a reader who saves during a restart would be waiting three seconds
    /// for a file they already have.
    static func waitsForServer(
        trigger: EditorFormatTrigger,
        server: LSPServerStatus?
    ) -> Bool {
        trigger == .command && server == .starting
    }

    /// Whether a formatter that asks nothing of a project gets to run.
    ///
    /// The same deference to the language server, for the same reasons: a
    /// server that formats is the project's own answer, and a server that has
    /// not finished starting has not answered at all.
    ///
    /// What is deliberately missing is the trigger. A tool the project never
    /// declared is held to ⇧⌘F because a stray globally installed one would
    /// claim files in every repository of its ecosystem, including ones
    /// formatted by something else. A tool that declares nothing is in the
    /// opposite position — it is the only formatter its language has here,
    /// which is where the language server's own formatter stands, and that
    /// one has always run on a save. Each of them is also a switch in
    /// Settings.
    /// - Parameter serverReturnedNothing: whether the server has already been
    ///   asked and came back with no edits. It lifts the deference, and only
    ///   that: a server that formats is still asked first.
    ///
    ///   Shell is why it exists. `bash-language-server` advertises formatting
    ///   and shells out to `shfmt`, so the deference below hands it the file —
    ///   and a server that cannot find `shfmt` on its own `PATH` answers with
    ///   an empty edit list while the tool sits installed and working. Asking
    ///   the tool afterwards costs one process on a path that had already
    ///   failed, and turns a sentence about a server into a formatted file.
    static func usesExternalFormatter(
        server: LSPServerStatus?,
        serverFormats: Bool,
        serverReturnedNothing: Bool = false
    ) -> Bool {
        guard !serverFormats || serverReturnedNothing else { return false }
        return server != .starting || serverReturnedNothing
    }
}
