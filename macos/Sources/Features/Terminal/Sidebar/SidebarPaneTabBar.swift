import SwiftUI

/// The panel switcher at the top of the sidebar.
///
/// Deliberately draws no opaque background of its own. The sidebar pane's
/// color comes from an AppKit layer *behind* the SwiftUI content
/// (`TerminalController.syncSidebarBackground`), and every pane in the
/// window paints that same color so the sidebar↔terminal boundary stays
/// seamless under transparency and blur. An opaque strip here would put a
/// visible band back at the top of the sidebar.
///
/// Scrolls sideways rather than truncating, the way `EditorTabBar` does, and
/// out of the same parts: `InvisibleScrollers` for a scroll view with no
/// visible knob, and `WheelScrollsHorizontally` so a plain mouse reaches the
/// tabs past the right edge.
struct SidebarPaneTabBar: View {
    @Binding var selection: SidebarPane

    @ObservedObject private var palette: ThemePalette = .shared

    private var accent: Color { palette.accent ?? .accentColor }

    /// Which panels to offer. Owned by `SidebarView`, which also decides
    /// whether this bar appears at all.
    let panes: [SidebarPane]

    /// How tall a tab is. Fixed rather than left to the label's padding
    /// because the scroll view around the row needs the same number: content
    /// taller than the viewport makes the row scroll *vertically* by a few
    /// invisible points instead of moving the tabs.
    static let tabHeight: CGFloat = 24

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(panes) { pane in
                        tab(for: pane).id(pane)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: Self.tabHeight)
                /// No `Spacer` and no `maxWidth: .infinity` on the tabs: both
                /// stretch the row to the viewport's width, so the content
                /// never overflows and a scroll view with nothing to overflow
                /// does not scroll. The row is as wide as its tabs.
                .background(alignment: .leading) {
                    InvisibleScrollers()
                    WheelScrollsHorizontally()
                }
            }
            .scrollIndicators(.automatic)
            .frame(height: Self.tabHeight)
            .onAppear { proxy.scrollTo(selection) }
            .onChange(of: selection) { pane in
                /// A panel picked by keyboard or by a command lands off the
                /// right edge on a narrow sidebar, with nothing to say the
                /// selection moved at all. No anchor: `scrollTo` then moves
                /// the least it can, and leaves the row alone when the tab is
                /// already in view.
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(pane) }
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .sidebarPaneSwitcherMenu()
    }

    private func tab(for pane: SidebarPane) -> some View {
        let isSelected = selection == pane

        return Button {
            guard selection != pane else { return }
            withAnimation(.easeOut(duration: 0.12)) { selection = pane }
        } label: {
            HStack(spacing: 5) {
                SidebarPaneIcon(pane: pane)
                Text(pane.title)
                    .font(palette.font(size: 11, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    /// The title at its full width, never an ellipsis. A tab
                    /// that can be scrolled to has no reason to hide half its
                    /// name, and a cut label the reader can neither widen nor
                    /// read is the worst of both.
                    .fixedSize()
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: Self.tabHeight)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? accent.opacity(0.22) : Color.clear)
            )
            .overlay(alignment: .bottom) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(accent)
                        .frame(height: 2)
                        .padding(.horizontal, 10)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pane.title)
        .sidebarPaneSwitcherMenu()
    }
}
