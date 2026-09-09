import SwiftUI

struct SidebarActivityBar: View {
    @Binding var selection: SidebarPane

    let items: [SidebarPaneItem]

    @ObservedObject private var palette: ThemePalette = .shared

    private var accent: Color { palette.accent ?? .accentColor }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(items) { item in
                chip(for: item)
            }
            Spacer(minLength: 0)
            settings
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .frame(width: SidebarActivityBarMetrics.totalWidth)
        .contentShape(Rectangle())
        .sidebarPaneSwitcherMenu()
    }

    /// Settings, at the far end of the bar.
    ///
    /// The tab bar at the top has the window's chrome beside it to reach
    /// Settings from. This column has nothing, so the gesture the reader
    /// expects has to live here, and the bottom is where every editor that
    /// wears this shape puts it.
    private var settings: some View {
        Button {
            _ = NSApp.sendAction(#selector(AppDelegate.openConfig(_:)), to: nil, from: nil)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: SidebarActivityBarMetrics.iconSize - 2))
                .foregroundStyle(Color.secondary)
                .frame(width: SidebarActivityBarMetrics.width, height: SidebarActivityBarMetrics.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Settings")
        .padding(.bottom, 8)
    }

    private func chip(for item: SidebarPaneItem) -> some View {
        let isSelected = selection == item.pane

        return Button {
            guard selection != item.pane else { return }
            withAnimation(.easeOut(duration: 0.12)) { selection = item.pane }
        } label: {
            SidebarPaneIcon(item: item, size: SidebarActivityBarMetrics.iconSize)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(width: SidebarActivityBarMetrics.width, height: SidebarActivityBarMetrics.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.title)
        .background(
            RoundedRectangle(cornerRadius: SidebarIconChipMetrics.cornerRadius)
                .fill(isSelected ? accent.opacity(0.22) : Color.clear)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1)
                    .fill(accent)
                    .frame(width: 2)
                    .padding(.vertical, 7)
            }
        }
        .sidebarPaneSwitcherMenu()
    }
}

enum SidebarActivityBarMetrics {
    static let width: CGFloat = 34
    static let height: CGFloat = 30
    static let iconSize: CGFloat = 16
    static let totalWidth: CGFloat = width + 12
}
