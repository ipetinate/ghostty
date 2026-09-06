import Foundation

/// Everything a run of an external formatter can do other than produce
/// formatted text.
enum ExternalFormatterFailure: Error, Equatable, Sendable {
    /// The tool is not installed: not in the login shell's `PATH`, and not at
    /// the path the reader pointed the setting at.
    case notFound(tool: String, hint: String)

    case launchFailed(tool: String, reason: String)

    case timedOut(tool: String, seconds: TimeInterval)

    /// It ran and refused. `message` is what it said, which for these tools is
    /// nearly always a parse error with a line and column in it.
    case failed(tool: String, status: Int32, message: String)
}

extension ExternalFormatterFailure: LocalizedError {
    /// A sentence for a banner. Named tools, because "the formatter failed"
    /// leaves the reader guessing which of the several this editor can run
    /// they are being told about.
    var reason: String {
        switch self {
        case .notFound(let tool, let hint):
            return "\(tool) isn't installed. \(hint)"
        case .launchFailed(let tool, let reason):
            return "\(tool) didn't launch: \(reason)"
        case .timedOut(let tool, let seconds):
            return "\(tool) didn't answer within \(Int(seconds))s"
        case .failed(let tool, _, let message):
            return "\(tool): \(Self.banner(from: message))"
        }
    }

    /// The conformance exists for one reason: `localizedDescription`.
    ///
    /// A Swift enum that is only an `Error` bridges to an `NSError` whose
    /// description is *"The operation couldn't be completed."* followed by
    /// the runtime's own tag for the case — a number that decodes to nothing.
    /// Any presenter reaching for `localizedDescription`, which is the obvious
    /// thing to reach for, would therefore replace the tool's diagnosis with
    /// it. Answering here means no call site has to know that.
    var errorDescription: String? { reason }
}

extension ExternalFormatterFailure {
    /// An alert can hold a diagnosis. It cannot hold a terminal.
    ///
    /// Measured against a real refusal rather than assumed. Around the
    /// sentence that says what is actually wrong, a formatter prints two
    /// kinds of padding: the code frame under a parse error, and — when a
    /// configuration asks for a plugin that will not load — a stack trace,
    /// twenty frames of the tool's own bundle. Both are shaped by a
    /// monospaced column that an alert does not have, and the trace is long
    /// enough to push the sentence out of sight entirely.
    ///
    /// What survives is kept whole rather than cut to the first line, because
    /// a bad configuration announces itself across three: `Invalid
    /// configuration for file "…":` on its own names no fault. The cap is
    /// there for the case nobody has measured yet — a plugin free to print an
    /// essay.
    static var maximumBannerLines: Int { 4 }

    static func banner(from message: String) -> String {
        let kept = message
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(Self.withoutErrorMarker)
            .filter { !$0.allSatisfy(\.isWhitespace) && !Self.isFrame($0) }
            .prefix(maximumBannerLines)

        /// Nothing left means the shape was one this has never seen, and a
        /// wall of text beats an empty banner.
        return kept.isEmpty
            ? message.trimmingCharacters(in: .whitespacesAndNewlines)
            : kept.joined(separator: "\n")
    }

    /// The `[error] ` prefix a tool puts on every line it writes, including
    /// continuation and blank ones.
    static func withoutErrorMarker(_ line: Substring) -> Substring {
        guard line.hasPrefix("[error]") else { return line }
        let rest = line.dropFirst("[error]".count)
        return rest.hasPrefix(" ") ? rest.dropFirst() : rest
    }

    /// A line that is scaffolding rather than sentence: a code frame's
    /// gutter (`  1 | const a = 1`, `> 3 | }`, `    | ^`) or a stack frame.
    static func isFrame(_ line: Substring) -> Bool {
        let indented = line.first == " " || line.first == "\t"
        var rest = line.drop { $0 == " " || $0 == "\t" }
        if indented, rest.hasPrefix("at ") { return true }

        if rest.hasPrefix(">") { rest = rest.dropFirst().drop { $0 == " " } }
        if rest.hasPrefix("|") { return true }

        let gutter = rest.prefix(while: \.isNumber)
        guard !gutter.isEmpty else { return false }
        return rest.dropFirst(gutter.count).drop { $0 == " " }.hasPrefix("|")
    }
}

/// Runs one external formatter over a buffer.
///
/// stdin rather than the file on disk: the buffer is what the reader is
/// looking at and it may never have been saved in this state. The path still
/// goes along as an argument, because it is how these tools find their own
/// configuration.
enum ExternalFormatterRunner {
    /// Generous, because a contributed formatter can be a whole runtime
    /// starting cold — the project's own copy, loading every plugin its
    /// configuration asks for, on the first save after the editor opened.
    /// Bounded, because this sits between ⌘S and the file being written.
    ///
    /// It used to be five, on the grounds that every tool here was a single
    /// static binary. That stopped being true when a formatter became
    /// something an extension contributes.
    static let defaultTimeout: TimeInterval = 10

    /// The formatted text, or nil when nothing should change.
    ///
    /// Blocking; background tasks only.
    ///
    /// - Throws: `ExternalFormatterFailure`.
    static func format(
        _ text: String,
        filePath: String,
        formatter: ExternalFormatter,
        searchPath: String,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval = defaultTimeout
    ) throws -> String? {
        guard let binary = locate(formatter.command, searchPath: searchPath) else {
            throw ExternalFormatterFailure.notFound(
                tool: formatter.displayName, hint: formatter.installHint)
        }

        return try run(
            text,
            filePath: filePath,
            formatter: formatter,
            binary: binary,
            workingDirectory: workingDirectory,
            environment: environment,
            timeout: timeout)
    }

    /// The same run, told where the project wants it: the tool the project
    /// installed into itself when there is one, in the directory the tool
    /// asked for.
    ///
    /// - Throws: `ExternalFormatterFailure`.
    static func format(
        _ text: String,
        filePath: String,
        formatter: ExternalFormatter,
        in project: FormatterProject,
        searchPath: String,
        environment: [String: String]? = nil,
        timeout: TimeInterval = defaultTimeout
    ) throws -> String? {
        guard let binary = locate(formatter, in: project, searchPath: searchPath) else {
            throw ExternalFormatterFailure.notFound(
                tool: formatter.displayName, hint: formatter.installHint)
        }

        return try run(
            text,
            filePath: filePath,
            formatter: formatter,
            binary: binary,
            workingDirectory: project.workingDirectory,
            environment: environment,
            timeout: timeout)
    }

    private static func run(
        _ text: String,
        filePath: String,
        formatter: ExternalFormatter,
        binary: String,
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval = defaultTimeout
    ) throws -> String? {
        let run = ShellCommand.runResult(
            binary,
            formatter.arguments(for: filePath),
            cwd: workingDirectory,
            environment: environment,
            stdin: Data(text.utf8),
            timeout: timeout
        )

        if let reason = run.launchFailure {
            throw ExternalFormatterFailure.launchFailed(
                tool: formatter.displayName, reason: reason)
        }

        return try result(
            status: run.status,
            stdout: run.stdout,
            stderr: run.stderr,
            tool: formatter.displayName,
            timeout: timeout)
    }

    /// Which copy of the tool to run, and by a wide margin the project's own.
    ///
    /// A repository pins a version in its lockfile precisely so that
    /// everyone's saves produce the same diff, and reformatting with whatever
    /// major version happens to be on this machine's `PATH` would put a
    /// stranger's line breaks into every file the reader touches.
    static func locate(
        _ formatter: ExternalFormatter,
        in project: FormatterProject,
        searchPath: String
    ) -> String? {
        if let local = project.localBinaryPath { return local }
        return locate(formatter.command, searchPath: searchPath)
    }

    /// An absolute path is taken as written — a reader who typed one is
    /// pointing at a binary the `PATH` may not hold. Everything else is looked
    /// up the way the language servers are.
    static func locate(_ command: String, searchPath: String) -> String? {
        if command.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: command) ? command : nil
        }
        return LSPProcess.locate(command, searchPath: searchPath)
    }

    /// Reads a finished run, with `status == nil` meaning it was killed at the
    /// deadline.
    ///
    /// **The order is the whole of it:** the status is checked first, and
    /// only then whether anything came back. A formatter handed a file with a
    /// syntax error in it — which is what a buffer is halfway through a
    /// function — exits non-zero and prints nothing on stdout. An
    /// implementation that read stdout first would answer "the file is now
    /// empty" every time somebody saved mid-edit.
    ///
    /// Empty output on a *successful* exit is then still read as no change
    /// rather than as an empty file. Declining to blank somebody's buffer is
    /// the safe direction to be wrong in.
    static func result(
        status: Int32?,
        stdout: String,
        stderr: String,
        tool: String,
        timeout: TimeInterval = defaultTimeout
    ) throws -> String? {
        guard let status else {
            throw ExternalFormatterFailure.timedOut(tool: tool, seconds: timeout)
        }

        guard status == 0 else {
            throw ExternalFormatterFailure.failed(
                tool: tool,
                status: status,
                message: message(stdout: stdout, stderr: stderr, tool: tool))
        }

        return stdout.isEmpty ? nil : stdout
    }

    /// stderr first: that is where the parse error with the line number is.
    /// stdout is the fallback for the tools that print their complaint there.
    private static func message(stdout: String, stderr: String, tool: String) -> String {
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !err.isEmpty { return err }
        let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !out.isEmpty { return out }
        return "\(tool) failed without saying why."
    }
}
