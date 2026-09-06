import SwiftUI

/// The three editable override sections — binary, arguments, raw
/// `initializationOptions` JSON — shared by every server row in Settings.
///
/// Extracted rather than copied, because there is exactly one place a
/// user's override is written and a second pair of these `TextField`s would
/// be a second place for that write to drift. It is also the honest way to
/// give a contributed server "the same override form" without giving it an
/// Install button it has no command for.
///
/// Keyed by the server's **default** command, which is
/// `LSPServerOverrideStore`'s key and not the field being edited — see that
/// type for why the identity of "which server is this a setting for" cannot
/// be the thing the reader is changing.
struct ServerOverrideFields: View {
    let defaultCommand: String
    let defaultArguments: [String]

    @State private var override: LSPServerOverride

    init(defaultCommand: String, defaultArguments: [String]) {
        self.defaultCommand = defaultCommand
        self.defaultArguments = defaultArguments
        _override = State(
            initialValue: LSPServerOverrideStore.override(for: defaultCommand) ?? LSPServerOverride()
        )
    }

    /// Stops this server under every command it could be running as — the
    /// default, and whatever the reader has typed over it — and re-announces
    /// the open files to whatever starts next.
    private func restart() {
        let outcome = LSPRestart.restart(commands: [defaultCommand, override.command])
        restartNote = outcome.stopped == 0
            ? "Nothing was running; it will start clean."
            : "Stopped \(outcome.stopped) workspace\(outcome.stopped == 1 ? "" : "s")."
    }

    /// What the last restart did, so the button says something happened.
    ///
    /// A button that changes nothing visible reads as a broken button, and
    /// this one's whole effect is somewhere else — a server that is quietly
    /// running with different options now.
    @State private var restartNote: String?

    var body: some View {
        Group {
            Section {
                TextField("Command", text: $override.command, prompt: Text(verbatim: defaultCommand))
                TextField(
                    "Arguments",
                    text: $override.arguments,
                    prompt: Text(verbatim: defaultArguments.joined(separator: " "))
                )
            } header: {
                Text("Override")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        """
                        Blank uses the default above. Takes effect the next \
                        time this server starts for a workspace.
                        """
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    /// Here rather than only in the sentence above, because
                    /// the reader who just changed a field is the reader who
                    /// needs it applied, and the instruction they used to get
                    /// was to relaunch the app.
                    HStack(spacing: 8) {
                        Button("Restart Server") { restart() }
                        if let note = restartNote {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                TextEditor(text: $override.initializationOptionsJSON)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 120)
            } header: {
                Text("initializationOptions (JSON)")
            } footer: {
                Text(
                    """
                    Sent to the server at startup. Left blank, the \
                    extension's own `initializationOptions` are used where it \
                    declared any, and nothing where it did not.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .onChange(of: override) { value in
            LSPServerOverrideStore.set(value, for: defaultCommand)
        }
    }
}
