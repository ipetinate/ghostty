import SwiftUI

struct ToastHostView: View {
    @ObservedObject var center: ToastCenter

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(center.toasts) { toast in
                ToastCardView(toast: toast, center: center)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: 420, alignment: .trailing)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: center.toasts.map(\.id))
    }
}

private struct ToastCardView: View {
    let toast: PhantomToast
    @ObservedObject var center: ToastCenter

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                content
                Spacer(minLength: 0)
                if toast.isDismissable {
                    Button {
                        center.dismiss(id: toast.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1 : 0.45)
                    .accessibilityLabel("Dismiss")
                }
            }

            if let status = toast.status {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if !toast.actions.isEmpty {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    ForEach(toast.actions) { action in
                        Button(action.title) { action.run() }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .fontWeight(action.emphasis == .primary ? .semibold : .regular)
                            .foregroundStyle(
                                action.emphasis == .primary ? Color.accentColor : Color.secondary)
                    }
                }
                .disabled(toast.isBusy)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: 420, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
        )
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var content: some View {
        switch toast.content {
        case .custom(let view):
            view
        case .standard(let icons, let title, let message):
            HStack(alignment: .top, spacing: 9) {
                if !icons.isEmpty {
                    ToastIconRow(icons: icons)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    if let message {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct ToastIconRow: View {
    let icons: [PhantomToastIcon]

    private static let maximumShown = 5

    var body: some View {
        HStack(spacing: -6) {
            ForEach(icons.prefix(Self.maximumShown)) { icon in
                iconView(icon)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(0.06)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            }
            if icons.count > Self.maximumShown {
                Text(verbatim: "+\(icons.count - Self.maximumShown)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 9)
            }
        }
    }

    @ViewBuilder
    private func iconView(_ icon: PhantomToastIcon) -> some View {
        switch icon {
        case .image(let image, _):
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(2)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
