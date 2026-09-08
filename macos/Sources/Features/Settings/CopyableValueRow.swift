import SwiftUI

/// A labelled value with a Copy button beside it, for the strings a reader
/// is meant to paste into a terminal rather than read.
struct CopyableValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(value)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            CopyButton(text: value, label: "Copy command")
        }
    }
}
