import Combine
import SwiftUI

/// One panel the sidebar can show.
///
/// The sidebar started out only able to list terminals. This enum is the
/// seam that lets it hold more: adding a panel is a case here plus a branch
/// in `SidebarView.paneContent` and, if it needs its own titlebar buttons,
/// one in `SidebarTitlebarChrome`. Nothing in the AppKit hierarchy
/// (`TerminalController.makeSidebarSplitView`) has to change.
///
enum SidebarPane: String, CaseIterable, Identifiable, Codable {
    case terminals
    case files
    case git
    case worktrees
    case extensions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminals: return "Terminals"
        case .files: return "Files"
        case .git: return "Git"
        case .worktrees: return "Worktrees"
        case .extensions: return "Extensions"
        }
    }

    /// SF Symbol for the tab bar, or nil for a panel that ships its own
    /// artwork (see `SidebarPaneIcon`) — git and worktrees both do.
    var symbol: String? {
        switch self {
        case .terminals: return "terminal"
        case .files: return "folder"
        case .git: return nil
        case .worktrees: return nil
        case .extensions: return "puzzlepiece"
        }
    }

    /// Terminals is the sidebar's reason to exist, so it can't be turned
    /// off; the rest are opt-out.
    var canBeHidden: Bool { self != .terminals }

    var defaultsKey: String? {
        switch self {
        case .terminals: return nil
        case .files: return "SidebarShowFilesPane"
        case .git: return "SidebarShowGitPane"
        case .worktrees: return "SidebarShowWorktreesPane"
        case .extensions: return "SidebarShowExtensionsPane"
        }
    }

    var isEnabled: Bool {
        guard let defaultsKey else { return true }
        return UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    /// The panels to actually offer, in tab order.
    static var enabled: [SidebarPane] {
        allCases.filter(\.isEnabled)
    }

    /// With only terminals left there is nothing to switch between, so the
    /// tab bar hides itself entirely and the sidebar goes back to being the
    /// plain terminal list it started as.
    static var showsTabBar: Bool {
        enabled.count > 1
    }
}

enum SidebarTabBarPlacement: String, CaseIterable, Identifiable {
    case top
    case side

    static let defaultsKey = "SidebarTabBarPlacement"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: return "Top"
        case .side: return "Side"
        }
    }

    var menuTitle: String {
        switch self {
        case .top: return "Tabs at the Top"
        case .side: return "Tabs at the Side"
        }
    }

    init(raw: String?) {
        self = raw.flatMap(Self.init(rawValue:)) ?? .top
    }
}

/// A panel's icon, whether it comes from SF Symbols or the asset catalog.
struct SidebarPaneIcon: View {
    let pane: SidebarPane
    var size: CGFloat = 10

    var body: some View {
        if let symbol = pane.symbol {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
        } else if pane == .worktrees {
            WorktreeIcon(size: size + 2)
        } else {
            GitIcon(size: size + 1)
        }
    }
}

@MainActor
final class SidebarPaneVisibility: ObservableObject {
    static let shared = SidebarPaneVisibility()

    @Published private(set) var enabled: [SidebarPane]

    private var subscription: AnyCancellable?

    init() {
        enabled = SidebarPane.enabled
        subscription = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .map { _ in SidebarPane.enabled }
            .removeDuplicates()
            .sink { [weak self] panes in
                MainActor.assumeIsolated { self?.update(panes) }
            }
    }

    func isEnabled(_ pane: SidebarPane) -> Bool {
        enabled.contains(pane)
    }

    func binding(for pane: SidebarPane) -> Binding<Bool> {
        Binding(
            get: { pane.isEnabled },
            set: { value in
                guard let key = pane.defaultsKey else { return }
                UserDefaults.standard.set(value, forKey: key)
            }
        )
    }

    private func update(_ panes: [SidebarPane]) {
        guard enabled != panes else { return }
        enabled = panes
    }
}

struct SidebarPaneSwitcherMenu: View {
    enum Entry: Equatable, Identifiable {
        case placement(SidebarTabBarPlacement)
        case separator
        case pane(SidebarPane, canToggle: Bool)

        var id: String {
            switch self {
            case .placement(let placement): return "placement." + placement.rawValue
            case .separator: return "separator"
            case .pane(let pane, _): return "pane." + pane.rawValue
            }
        }
    }

    static var entries: [Entry] {
        SidebarTabBarPlacement.allCases.map(Entry.placement)
            + [.separator]
            + SidebarPane.allCases.map { .pane($0, canToggle: $0.canBeHidden) }
    }

    @ObservedObject private var visibility: SidebarPaneVisibility = .shared

    @AppStorage(SidebarTabBarPlacement.defaultsKey)
    private var placementRaw = SidebarTabBarPlacement.top.rawValue

    var body: some View {
        ForEach(Self.entries) { entry in
            item(entry)
        }
    }

    @ViewBuilder
    private func item(_ entry: Entry) -> some View {
        switch entry {
        case .placement(let placement):
            Toggle(placement.menuTitle, isOn: placementBinding(placement))
        case .separator:
            Divider()
        case .pane(let pane, let canToggle):
            Toggle(pane.title, isOn: visibility.binding(for: pane))
                .disabled(!canToggle)
        }
    }

    private func placementBinding(_ placement: SidebarTabBarPlacement) -> Binding<Bool> {
        Binding(
            get: { SidebarTabBarPlacement(raw: placementRaw) == placement },
            set: { isOn in
                guard isOn else { return }
                placementRaw = placement.rawValue
            }
        )
    }
}

extension View {
    func sidebarPaneSwitcherMenu() -> some View {
        contextMenu { SidebarPaneSwitcherMenu() }
    }
}
