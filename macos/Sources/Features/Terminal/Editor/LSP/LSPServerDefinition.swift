import Foundation

/// How to start one language server, and what to tell the user when it
/// isn't there.
///
/// Every field is data an installed extension declared. Nothing here is
/// derived from the command's name any more: this build ships no table of
/// servers, so a `switch` over command strings could only ever have
/// answered for the servers it happened to have heard of, and would have
/// answered wrongly for the one the reader actually installed.
struct LSPServerDefinition: Hashable, Sendable, Identifiable {
    /// The LSP `languageId`, spelled exactly as the specification does —
    /// it is also what goes in every `textDocument/didOpen`, so inventing a
    /// nicer name here would mean translating it back later.
    let languageID: String

    /// For the "install this" row in the UI.
    let displayName: String

    /// Looked up on the login shell's `PATH`, not launched through a shell.
    let command: String

    let arguments: [String]

    /// Almost none of these are installed on a given machine, and a server
    /// that fails to spawn is indistinguishable from one that is broken
    /// unless the UI can say *what* is missing and *how* to get it. The
    /// hint travels with the definition so no view has to keep its own
    /// table of them in sync.
    let installHint: String

    /// How to resolve `initializationOptions` for this language, absent a
    /// user override. See `LSPInitializationOptions`.
    var initializationOptionsKind: LSPInitializationOptionsKind = .none

    /// `initializationOptions` the manifest wrote out literally, as JSON
    /// text — the same shape a user's own override is stored in, so it can
    /// travel the same parse and produce the same failure message.
    ///
    /// A field on the definition rather than a lookup back into the catalog,
    /// for the reason `origin` is one: it reaches both the launch and the
    /// approval prompt, and a lookup either of them could forget is a lookup
    /// one of them eventually will.
    ///
    /// Ignored when `initializationOptionsKind` is anything but `.none`: a
    /// server that asked for a resolver asked for a value this app computes
    /// from the project, and two sources for one field is a question nobody
    /// should have to answer while reading a launch.
    var initializationOptionsJSON: String?

    /// Where this definition came from, and therefore whether starting it
    /// needs to be asked about. See `LSPServerOrigin`.
    ///
    /// A field rather than a lookup on the side because a field that
    /// travels with the value cannot be forgotten — a table consulted by
    /// language id can be, and one missed consultation is not a UI defect,
    /// it is the trust gate not running.
    var origin: LSPServerOrigin = .builtIn

    /// Which section of the Settings list this server belongs to, as the
    /// contributing manifest declared it.
    ///
    /// Stored, not computed. It used to be a `switch` over command names,
    /// which is a claim about which servers exist — and a server this build
    /// has never heard of is now the only kind there is.
    var category: LSPServerCategory = .script

    /// Official project documentation, when the manifest named one.
    var documentationURL: URL?

    /// The newest Java feature version this server is known to run on, for
    /// servers that run on a JVM at all.
    ///
    /// A ceiling, not a requirement: it exists because a server can bundle a
    /// compiler older than the JDK the developer builds with, and inheriting
    /// `JAVA_HOME` then kills it at launch. `LSPJavaRuntime` reads this to
    /// decide whether to hand the server a different JVM than the one the
    /// environment named.
    ///
    /// Nil — the default, and the answer for every server that is not on a
    /// JVM — means the environment is passed through as-is.
    var maximumJavaFeatureVersion: Int?

    var id: String { languageID }

    /// What a "not installed" message should quote back.
    var invocation: String {
        ([command] + arguments).joined(separator: " ")
    }
}
