import SwiftUI

/// Whether a server's binary was found, and whether anything is running it,
/// as a labelled badge.
struct LSPStatusBadge: View {
    let status: LSPServerStatusSnapshot
    var detailed = false

    private var color: Color {
        switch status.state {
        case .running: return .green
        case .starting: return .orange
        case .error: return .red
        case .installed: return .blue
        case .unknown, .notInstalled: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.systemImage)
                .foregroundStyle(color)
            Text(status.label)
                .foregroundStyle(detailed ? .primary : (color == .secondary ? .secondary : color))
            if detailed, status.activeWorkspaceCount > 0 {
                // `verbatim` for the same reason the dev-server chip uses it:
                // interpolating a number into a `Text` goes through
                // `LocalizedStringKey`, which formats it for the locale — the
                // count would read "1.000" past a thousand, the way a port
                // number once read "4.201". The escaping was doubled here, so
                // the expression itself was being printed on screen.
                Text(verbatim: "· \(status.activeWorkspaceCount) workspace"
                    + (status.activeWorkspaceCount == 1 ? "" : "s"))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .help(statusHelp)
    }

    private var statusHelp: String {
        if case .error(let message) = status.state { return message }
        return status.label
    }
}
