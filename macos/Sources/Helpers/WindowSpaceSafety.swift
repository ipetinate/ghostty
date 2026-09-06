import AppKit

enum WindowSpaceSafety {
    enum Order: String {
        case front
        case frontRegardless
        case keyAndFront
    }

    enum CallSite: String {
        case restoreReveal = "restore reveal"
        case restoreFocus = "restore focus"
        case appKitRestoreFocus = "appkit restore focus"
        case reopenRescue = "reopen rescue"
        case selectRescue = "select rescue"
        case surfaceFocusRequest = "surface focus request"
    }

    static func mayOrderFront(appIsActive: Bool, isOnActiveSpace: Bool) -> Bool {
        appIsActive || isOnActiveSpace
    }

    static func resolve(
        _ requested: Order,
        appIsActive: Bool,
        isOnActiveSpace: Bool
    ) -> Order? {
        guard mayOrderFront(appIsActive: appIsActive, isOnActiveSpace: isOnActiveSpace) else {
            return nil
        }
        guard appIsActive else { return .front }
        return requested
    }

    @discardableResult
    static func orderFront(
        _ window: NSWindow,
        _ requested: Order = .keyAndFront,
        from callSite: CallSite
    ) -> Bool {
        orderFront(window, requested, from: callSite, appIsActive: NSApp.isActive)
    }

    @discardableResult
    static func orderFront(
        _ window: NSWindow,
        _ requested: Order,
        from callSite: CallSite,
        appIsActive: Bool
    ) -> Bool {
        let isOnActiveSpace = window.isOnActiveSpace
        let state = "window=\(window.windowNumber) active=\(appIsActive) "
            + "onActiveSpace=\(isOnActiveSpace) wanted=\(requested.rawValue)"

        guard let order = resolve(
            requested,
            appIsActive: appIsActive,
            isOnActiveSpace: isOnActiveSpace
        ) else {
            WindowBreadcrumbs.note("\(callSite.rawValue): refused — \(state)")
            return false
        }

        WindowBreadcrumbs.note("\(callSite.rawValue): ordering front — \(state) doing=\(order.rawValue)")

        switch order {
        case .front:
            window.orderFront(nil)
        case .frontRegardless:
            window.orderFrontRegardless()
        case .keyAndFront:
            window.makeKeyAndOrderFront(nil)
        }

        return true
    }
}
