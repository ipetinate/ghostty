import Foundation

enum SidebarWidthRule {
    static let minimumContent: CGFloat = 200
    static let maximumContent: CGFloat = 600
    static let defaultContent: CGFloat = 480

    static func inset(for placement: SidebarTabBarPlacement) -> CGFloat {
        switch placement {
        case .top: return 0
        case .side: return SidebarActivityBarMetrics.totalWidth
        }
    }

    static func clamp(content width: CGFloat) -> CGFloat {
        min(max(width, minimumContent), maximumContent)
    }

    static func pane(content width: CGFloat, placement: SidebarTabBarPlacement) -> CGFloat {
        clamp(content: width) + inset(for: placement)
    }

    static func content(pane width: CGFloat, placement: SidebarTabBarPlacement) -> CGFloat {
        clamp(content: width - inset(for: placement))
    }

    static func minimumPane(_ placement: SidebarTabBarPlacement) -> CGFloat {
        minimumContent + inset(for: placement)
    }

    static func maximumPane(_ placement: SidebarTabBarPlacement) -> CGFloat {
        maximumContent + inset(for: placement)
    }

    static func placement(_ defaults: UserDefaults = .standard) -> SidebarTabBarPlacement {
        SidebarTabBarPlacement(raw: defaults.string(forKey: SidebarTabBarPlacement.defaultsKey))
    }
}
