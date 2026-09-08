import SwiftUI

/// The three things a reader may say about how one server is launched: which
/// binary, which arguments, and what `initializationOptions` to send.
///
/// **Two sections, returned side by side and never wrapped.** A `Group` of
/// `Section`s stops being sections the moment a modifier lands on it, and a
/// `Form` then draws one opaque view: the headers survive, the fields inside
/// do not. That is not a hypothetical — it shipped, and the override fields
/// were invisible while their headers still read "Override". Every modifier
/// here attaches to a single `Section` for that reason.
///
/// The stored value is re-read whenever `defaultCommand` changes rather than
/// only at init, which is what lets one form show a different server without
/// the caller giving this view a new identity.
struct ServerOverrideFields: View {
    let defaultCommand: String
    let defaultArguments: [String]

    @State private var override = LSPServerOverride()
    @State private var loaded: String?

    /// What the last restart did, so the button says something happened.
    ///
    /// A button that changes nothing visible reads as a broken button, and
    /// this one's whole effect is somewhere else — a server that is quietly
    /// running with different options now.
    @State private var restartNote: String?

    /// Stops this server under every command it could be running as — the
    /// default, and whatever the reader has typed over it — and re-announces
    /// the open files to whatever starts next.
    private func restart() {
        let outcome = LSPRestart.restart(commands: [defaultCommand, override.command])
        restartNote = outcome.stopped == 0
            ? "Nothing was running; it will start clean."
            : "Stopped \(outcome.stopped) workspace\(outcome.stopped == 1 ? "" : "s")."
    }

    private func load() {
        override = LSPServerOverrideStore.override(for: defaultCommand) ?? LSPServerOverride()
        loaded = defaultCommand
        restartNote = nil
    }

    /// Persists only what the reader typed. The load above assigns to the same
    /// state this watches, and writing that back would store a value nobody
    /// entered over one somebody did.
    private func persist(_ value: LSPServerOverride) {
        guard loaded == defaultCommand else { return }
        LSPServerOverrideStore.set(value, for: defaultCommand)
    }

    var body: some View {
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
        .task(id: defaultCommand) { load() }
        .onChange(of: override) { value in persist(value) }

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
}
