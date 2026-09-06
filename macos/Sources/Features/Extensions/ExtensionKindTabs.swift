import SwiftUI

struct ExtensionKindTabs: View {
    enum Style {
        case form
        case compact
    }

    @Binding var selection: ExtensionCatalogFilter.Kind
    let counts: [ExtensionCatalogFilter.Kind: Int]
    var style: Style = .form

    @ObservedObject private var palette: ThemePalette = .shared

    private var accent: Color { palette.accent ?? .accentColor }

    var body: some View {
        switch style {
        case .form:
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(ExtensionCatalogFilter.Kind.allCases) { kind in
                        tab(kind)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
        case .compact:
            HStack(spacing: 2) {
                ForEach(ExtensionCatalogFilter.Kind.allCases) { kind in
                    tab(kind)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func tab(_ kind: ExtensionCatalogFilter.Kind) -> some View {
        let count = counts[kind] ?? 0
        let isSelected = selection == kind

        return Button {
            selection = kind
        } label: {
            label(kind, count: count, isSelected: isSelected)
                .opacity(count == 0 ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .help(tooltip(kind, count: count))
    }

    private func tooltip(_ kind: ExtensionCatalogFilter.Kind, count: Int) -> String {
        kind.title + " — " + String(count)
    }

    @ViewBuilder
    private func label(
        _ kind: ExtensionCatalogFilter.Kind,
        count: Int,
        isSelected: Bool
    ) -> some View {
        switch style {
        case .form:
            HStack(spacing: 4) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 10, weight: .medium))
                Text(verbatim: kind.title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                Text(verbatim: String(count))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isSelected ? accent.opacity(0.22) : Color.secondary.opacity(0.1))
            )
            .contentShape(Capsule())
        case .compact:
            Image(systemName: kind.systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .sidebarIconChip()
                .background(
                    RoundedRectangle(cornerRadius: SidebarIconChipMetrics.cornerRadius)
                        .fill(isSelected ? accent.opacity(0.22) : Color.clear)
                )
        }
    }
}
