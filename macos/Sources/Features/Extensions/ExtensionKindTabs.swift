import SwiftUI

struct ExtensionKindTabs: View {
    enum Style {
        case form
        case compact

        var rowSpacing: CGFloat {
            switch self {
            case .form: return 8
            case .compact: return 6
            }
        }

        var labelSpacing: CGFloat {
            switch self {
            case .form: return 5
            case .compact: return 4
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .form: return 10
            case .compact: return 11
            }
        }

        var titleSize: CGFloat {
            switch self {
            case .form: return 11
            case .compact: return 11
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .form: return 10
            case .compact: return 9
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .form: return 5
            case .compact: return 5
            }
        }
    }

    @Binding var selection: ExtensionCatalogFilter.Kind
    let counts: [ExtensionCatalogFilter.Kind: Int]
    var style: Style = .form

    @ObservedObject private var palette: ThemePalette = .shared

    private var accent: Color { palette.accent ?? .accentColor }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: style.rowSpacing) {
                ForEach(ExtensionCatalogFilter.Kind.allCases) { kind in
                    tab(kind)
                }
            }
            .padding(.vertical, 1)
            /// `.scrollIndicators(.hidden)` alone left a permanent grey band
            /// under the row, wider than the tabs are tall: with scroll bars
            /// set to always show, AppKit gives the scroll view a *legacy*
            /// scroller, which takes a strip of layout for itself and pays no
            /// attention to what SwiftUI asked for. The same pair the editor's
            /// tab strip uses settles it — no knob at all, and a plain wheel
            /// still reaches a tab past the right edge.
            .background(alignment: .leading) {
                InvisibleScrollers()
                WheelScrollsHorizontally()
            }
        }
        .scrollIndicators(.hidden)
    }

    private func tab(_ kind: ExtensionCatalogFilter.Kind) -> some View {
        let count = counts[kind] ?? 0
        let isSelected = selection == kind

        return Button {
            selection = kind
        } label: {
            label(kind, count: count, isSelected: isSelected)
                .opacity(count == 0 && !isSelected ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .help(tooltip(kind, count: count))
    }

    private func tooltip(_ kind: ExtensionCatalogFilter.Kind, count: Int) -> String {
        kind.title + " — " + String(count)
    }

    private func title(_ kind: ExtensionCatalogFilter.Kind, isSelected: Bool) -> some View {
        let weight: Font.Weight = isSelected ? .semibold : .regular
        switch style {
        case .form:
            return Text(verbatim: kind.title)
                .font(.system(size: style.titleSize, weight: weight))
        case .compact:
            return Text(verbatim: kind.title)
                .font(palette.font(size: style.titleSize, weight: weight))
        }
    }

    private func label(
        _ kind: ExtensionCatalogFilter.Kind,
        count: Int,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: style.labelSpacing) {
            Image(systemName: kind.systemImage)
                .font(.system(size: style.iconSize, weight: .medium))
            title(kind, isSelected: isSelected)
                .lineLimit(1)
                .fixedSize()
            Text(verbatim: String(count))
                .font(.system(size: style.titleSize - 1).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .background(
            Capsule().fill(isSelected ? accent.opacity(0.22) : Color.secondary.opacity(0.1))
        )
        .contentShape(Capsule())
    }
}
