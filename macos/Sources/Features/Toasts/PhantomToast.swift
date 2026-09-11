import SwiftUI

enum PhantomToastContent {
    case standard(icons: [PhantomToastIcon], title: String, message: String?)
    case custom(AnyView)
}

enum PhantomToastIcon: Identifiable {
    case image(NSImage, id: String)
    case symbol(String)

    var id: String {
        switch self {
        case .image(_, let id): return id
        case .symbol(let name): return "symbol:" + name
        }
    }
}

struct PhantomToastAction: Identifiable {
    enum Emphasis {
        case primary
        case secondary
    }

    let id: String
    let title: String
    let emphasis: Emphasis
    let run: @MainActor () -> Void

    init(
        id: String,
        title: String,
        emphasis: Emphasis = .secondary,
        run: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.title = title
        self.emphasis = emphasis
        self.run = run
    }
}

struct PhantomToast: Identifiable {
    enum Dismissal {
        case sticky
        case after(TimeInterval)
    }

    let id: String
    var content: PhantomToastContent
    var actions: [PhantomToastAction]
    var dismissal: Dismissal
    var isDismissable: Bool
    var status: String?

    init(
        id: String,
        content: PhantomToastContent,
        actions: [PhantomToastAction] = [],
        dismissal: Dismissal = .sticky,
        isDismissable: Bool = true,
        status: String? = nil
    ) {
        self.id = id
        self.content = content
        self.actions = actions
        self.dismissal = dismissal
        self.isDismissable = isDismissable
        self.status = status
    }

    static func standard(
        id: String,
        icons: [PhantomToastIcon] = [],
        title: String,
        message: String? = nil,
        actions: [PhantomToastAction] = [],
        dismissal: Dismissal = .sticky
    ) -> PhantomToast {
        PhantomToast(
            id: id,
            content: .standard(icons: icons, title: title, message: message),
            actions: actions,
            dismissal: dismissal)
    }

    var isBusy: Bool { status != nil }
}
