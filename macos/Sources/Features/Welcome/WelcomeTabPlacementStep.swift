import AppKit
import SwiftUI

/// The third step: where the sidebar keeps its tabs.
///
/// Two cards, and the click is the choice — there is no Apply and no Next to
/// press first. A card writes `SidebarTabBarPlacement.defaultsKey` through
/// `@AppStorage`, which is the whole of persisting it: every open window's
/// `SidebarView` reads that key, and `TerminalController` re-reads the
/// placement off `UserDefaults.didChangeNotification` to re-apply the pane's
/// width limits — the activity bar is a column *beside* the content, so the
/// pane has to grow by `SidebarWidthRule.inset(for:)` when the tabs move
/// there. A terminal window behind this one therefore follows without a
/// relaunch.
///
/// **The bars in the previews are the real bars.** `SidebarPaneTabBar` and
/// `SidebarActivityBar` each take their selection as a `Binding` and their
/// panels as a plain value, so a card can drive them from a constant without
/// reaching into the window's state — which means the accent fill, the
/// 2-point selection marker and the chip radii in the card are the ones the
/// reader will meet in the sidebar, not a second drawing of them.
///
/// Only the list *under* those bars is drawn here. The real rows are
/// `SidebarTabRow`, which needs a tab manager, a group store, a drag state and
/// an editor — it would show the reader their own terminals, in a window that
/// has none yet — so the stand-ins copy its metrics instead: a 6-point
/// corner, and the theme accent at 0.6 for the selected row and 0.12 for the
/// rest.
///
/// No keyboard shortcut is printed on this step, for the reason
/// `WelcomeBasicsStep` states.
struct WelcomeTabPlacementStep: View {
    @AppStorage(SidebarTabBarPlacement.defaultsKey)
    private var placementRaw = SidebarTabBarPlacement.top.rawValue

    @ObservedObject private var palette: ThemePalette = .shared

    private var placement: SidebarTabBarPlacement {
        SidebarTabBarPlacement(raw: placementRaw)
    }

    private var accent: Color { palette.accent ?? .accentColor }

    /// One sentence, saying what the choice is and that making it is enough.
    static let sentence = """
        Where the sidebar keeps its tabs: click a card and every open window \
        follows at once — Settings can change it again later.
        """

    static func detail(_ placement: SidebarTabBarPlacement) -> String {
        switch placement {
        case .top: return "A row of named tabs above the list."
        case .side: return "A column of icons beside the list."
        }
    }

    static let spacing: CGFloat = 14

    /// The sentence's own line, reserved so the cards below it are a height
    /// rather than whatever is left over.
    static let sentenceHeight: CGFloat = 18

    /// The cards fill the step, the way the basics step's do.
    static var cardHeight: CGFloat {
        WelcomeWindowController.size.height
            - WelcomeView.chromeHeight
            - sentenceHeight
            - spacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            Text(Self.sentence)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(
                    maxWidth: .infinity,
                    minHeight: Self.sentenceHeight,
                    alignment: .leading)

            HStack(alignment: .top, spacing: Self.spacing) {
                ForEach(SidebarTabBarPlacement.allCases) { each in
                    card(each)
                }
            }
        }
    }

    /// One card: what the option is called, one line about it, and a window
    /// wearing it.
    ///
    /// A `Button` rather than a tap gesture, so the card is one thing to the
    /// accessibility tree as well as to the mouse — the same reachability the
    /// agent cards' controls have.
    private func card(_ each: SidebarTabBarPlacement) -> some View {
        let isChosen = placement == each

        return Button {
            placementRaw = each.rawValue
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                header(each, isChosen: isChosen)

                WelcomeSidebarPreview(placement: each)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.cardHeight, alignment: .top)
            /// The agents step's card treatment, unchanged: the chosen card
            /// is the accent-tinted one with the accent border. A second way
            /// of saying "this one" in the same window would read as two
            /// different kinds of selection.
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isChosen ? accent.opacity(0.10) : Color.secondary.opacity(0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isChosen ? accent.opacity(0.45) : Color.secondary.opacity(0.16)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isChosen ? "Already where your tabs are" : each.menuTitle)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }

    /// The mark, the name, and the line. Two states of one symbol rather than
    /// a mark that appears and disappears: a card whose header changes height
    /// when it is picked moves the preview under it.
    private func header(_ each: SidebarTabBarPlacement, isChosen: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(isChosen ? accent : Color.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(each.menuTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(Self.detail(each))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }
}

/// A Phantom window the size of a card, wearing one of the two placements.
///
/// Takes no click. The bars inside it are the sidebar's own, buttons and
/// context menus included, and a card is a single choice — a reader who hit a
/// tab in the picture would switch a panel in a window that does not exist, or
/// open Settings from the activity bar's gear.
struct WelcomeSidebarPreview: View {
    let placement: SidebarTabBarPlacement

    /// Three panels rather than every one the app has.
    ///
    /// The named tabs are as wide as their names: Terminals, Files and Git
    /// come to about 233 points, which is what fits a sidebar this size
    /// without the row scrolling — and a preview whose fourth tab is cut in
    /// half reads as a rendering fault rather than as a scrollable row. The
    /// column gets the same three, because two cards showing different
    /// panels would be comparing two things at once.
    static let panes: [SidebarPane] = [.terminals, .files, .git]

    /// The sidebar's content width in the picture, before the activity bar's
    /// column is added to it. Half the real default, which is what makes the
    /// two cards show the one thing that is easy to miss: moving the tabs to
    /// the side widens the pane instead of narrowing the list.
    static let contentWidth: CGFloat = 264

    private static let titleBarHeight: CGFloat = 22

    /// A row's mark: a symbol for a shell, an agent's own brand for a session
    /// started with one. The real row draws the brand with `AgentBrandMark`,
    /// which takes the agent as a value — so the picture can wear the same
    /// mark a Claude tab does.
    enum RowMark {
        case symbol(String)
        case agent(CodingAgent)
    }

    /// What the list stands in for. Five rows rather than three: three filled
    /// a third of the picture and left it looking like a window nobody had
    /// worked in, and the shape of a sidebar in use is the whole point.
    static let rows: [(mark: RowMark, title: String)] = [
        (.symbol("terminal"), "phantom"),
        (.agent(.claude), "claude"),
        (.symbol("terminal"), "zig build"),
        (.symbol("hammer"), "dev server"),
        (.agent(.codex), "codex"),
    ]

    /// The three kinds of line a terminal shows, so the picture has the
    /// alternation a real one does rather than one tone of grey.
    private static let lines: [(text: String, tone: Tone)] = [
        ("~/phantom", .prompt),
        ("$ zig build", .command),
        ("Build Summary: 3/3 steps", .output),
        ("~/phantom", .prompt),
        ("$ git status -sb", .command),
        ("## feat/0.17.0", .output),
    ]

    private enum Tone {
        case prompt
        case command
        case output
    }

    @ObservedObject private var palette: ThemePalette = .shared

    /// Fixed, and never written to: the picture is of a sidebar showing its
    /// terminals, which is where a new reader's sidebar opens.
    @State private var selection: SidebarPane = .terminals

    private var accent: Color { palette.accent ?? .accentColor }

    private var background: Color {
        palette.background.map { Color(nsColor: $0) } ?? Color(nsColor: .textBackgroundColor)
    }

    /// Ink for the picture's own marks, over whatever the theme's background
    /// is. Read off `isLightBackground` rather than from the theme's white,
    /// which a light theme paints white.
    private var ink: Color {
        palette.isLightBackground ? Color.black : Color.white
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            HStack(spacing: 0) {
                sidebar

                Rectangle()
                    .fill(ink.opacity(0.10))
                    .frame(width: 1)

                terminal
            }
        }
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12)))
        .allowsHitTesting(false)
    }

    private var titleBar: some View {
        HStack(spacing: 6) {
            ForEach([Color.red, Color.yellow, Color.green], id: \.self) { light in
                Circle()
                    .fill(light.opacity(0.75))
                    .frame(width: 7, height: 7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.titleBarHeight)
    }

    /// The pane, at the width `SidebarWidthRule` would give it: the content's
    /// own width plus the column's, when the column is there.
    private var sidebar: some View {
        HStack(alignment: .top, spacing: 0) {
            if placement == .side {
                SidebarActivityBar(selection: $selection, panes: Self.panes)
            }

            VStack(spacing: 0) {
                if placement == .top {
                    SidebarPaneTabBar(selection: $selection, panes: Self.panes)
                }

                list

                Spacer(minLength: 0)
            }
        }
        .frame(width: SidebarWidthRule.pane(
            content: Self.contentWidth, placement: placement))
    }

    private var list: some View {
        VStack(spacing: SidebarMetrics.itemSpacing) {
            ForEach(Self.rows.indices, id: \.self) { index in
                row(Self.rows[index], isSelected: index == 0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, placement == .top ? 4 : 10)
    }

    private func row(
        _ row: (mark: RowMark, title: String),
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 6) {
            mark(row.mark)
                .frame(width: 13)

            Text(row.title)
                .font(palette.font(size: 11))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .foregroundStyle(ink.opacity(isSelected ? 0.95 : 0.7))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(accent.opacity(isSelected ? 0.6 : 0.12)))
    }

    @ViewBuilder
    private func mark(_ kind: RowMark) -> some View {
        switch kind {
        case .symbol(let symbol):
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
        case .agent(let agent):
            AgentBrandMark(agent: agent, size: 11)
        }
    }

    /// A suggestion of what the sidebar sits beside, not a terminal emulator:
    /// two short commands, and nothing wider than the narrower of the two
    /// cards can show without cutting a word.
    private var terminal: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Self.lines.indices, id: \.self) { index in
                let line = Self.lines[index]
                Text(verbatim: line.text)
                    .foregroundStyle(colour(line.tone))
            }

            Spacer(minLength: 0)
        }
        .font(.system(size: 8.5, design: .monospaced))
        .lineLimit(1)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func colour(_ tone: Tone) -> Color {
        switch tone {
        case .prompt: return accent
        case .command: return ink.opacity(0.8)
        case .output: return ink.opacity(0.55)
        }
    }
}
