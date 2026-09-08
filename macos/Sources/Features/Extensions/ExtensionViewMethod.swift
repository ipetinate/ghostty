import Foundation

/// Every method a contributed view may ask the app to perform.
///
/// The list is closed and it is short on purpose. A page has no filesystem,
/// no process and no socket of its own, so this enum is the whole of what an
/// extension's page can reach outside its own window — and a method that is
/// not here cannot be reached by asking for it under another name.
enum ExtensionViewMethod: String, CaseIterable, Equatable, Sendable {
    /// The folder the view's work is scoped to.
    case workspaceRoot = "workspace.root"

    /// The names under one folder inside that scope.
    case workspaceList = "workspace.list"

    /// The text of one file inside that scope.
    case workspaceRead = "workspace.read"

    /// The colours and fonts the app is drawing with.
    case themeRead = "theme.read"

    /// One HTTP request, performed by the app. See `ExtensionViewHTTP` for
    /// what it refuses.
    case httpRequest = "http.request"
}

/// A call from a view's page, once it has been read and checked.
enum ExtensionViewCall: Equatable, Sendable {
    case workspaceRoot
    case workspaceList(root: ExtensionViewFileScope.Root, path: String?, depth: Int)
    case workspaceRead(root: ExtensionViewFileScope.Root, path: String)
    case themeRead
    case httpRequest(ExtensionViewHTTP.Request)

    var method: ExtensionViewMethod {
        switch self {
        case .workspaceRoot: return .workspaceRoot
        case .workspaceList: return .workspaceList
        case .workspaceRead: return .workspaceRead
        case .themeRead: return .themeRead
        case .httpRequest: return .httpRequest
        }
    }
}

/// Why a call was not performed. Every case is answered to the page, so
/// each message is written for the extension author reading a console.
enum ExtensionViewRejection: Error, Equatable, Sendable {
    case notPermitted(ExtensionViewMethod)
    case unknownMethod
    case badParameters(String)
    case outOfScope(String)
    case unreadable(String)
    case refusedURL(ExtensionViewHTTP.Refusal)
    case failed(String)

    var code: String {
        switch self {
        case .notPermitted: return "not-permitted"
        case .unknownMethod: return "unknown-method"
        case .badParameters: return "bad-parameters"
        case .outOfScope: return "out-of-scope"
        case .unreadable: return "unreadable"
        case .refusedURL: return "refused-url"
        case .failed: return "failed"
        }
    }

    var message: String {
        switch self {
        case .notPermitted(let method):
            return "This view did not declare \(method.rawValue) in contributes.views[].permissions."
        case .unknownMethod:
            return "This Phantom has no such method."
        case .badParameters(let detail):
            return detail
        case .outOfScope(let path):
            return "\(path) is outside this view's workspace and its own directory."
        case .unreadable(let detail):
            return detail
        case .refusedURL(let refusal):
            return refusal.message
        case .failed(let detail):
            return detail
        }
    }
}

/// What arrived on the message handler, read without trusting any of it.
enum ExtensionViewMessage: Equatable, Sendable {
    /// The page announced that its module ran. Nothing is sent to it before
    /// this, the way `ExtensionDocumentView` waits for `ready`.
    case ready

    /// No usable call id, so there is no promise to settle and nothing to
    /// answer. Dropped rather than reported.
    case unaddressable

    case rejected(id: Int, ExtensionViewRejection)
    case accepted(id: Int, ExtensionViewCall)
}

enum ExtensionViewBridge {
    static let maxCallID = 1 << 40
    static let maxPathLength = 1024
    static let maxListDepth = 4
    static let defaultListDepth = 1

    /// Reads one message from the page, and decides whether it may run.
    ///
    /// Permission is checked here rather than at the call site so that the
    /// refusal is a value a test can assert on without a window, and so that
    /// no future method can be added that forgets the check.
    static func read(_ body: Any, permissions: Set<ExtensionViewMethod>) -> ExtensionViewMessage {
        guard let object = body as? [String: Any] else { return .unaddressable }
        if LanguageManifest.string(object["type"]) == "ready" { return .ready }

        guard let id = callID(object["id"]) else { return .unaddressable }
        guard let name = LanguageManifest.string(object["method"]) else {
            return .rejected(id: id, .badParameters("A call needs a 'method' string."))
        }
        guard let method = ExtensionViewMethod(rawValue: name) else {
            return .rejected(id: id, .unknownMethod)
        }
        guard permissions.contains(method) else {
            return .rejected(id: id, .notPermitted(method))
        }

        let params = object["params"] as? [String: Any] ?? [:]
        switch call(method, params: params) {
        case .success(let call): return .accepted(id: id, call)
        case .failure(let rejection): return .rejected(id: id, rejection)
        }
    }

    static func callID(_ value: Any?) -> Int? {
        guard let id = ExtensionIndex.integer(value), id >= 0, id <= maxCallID else { return nil }
        return id
    }

    static func call(
        _ method: ExtensionViewMethod,
        params: [String: Any]
    ) -> Result<ExtensionViewCall, ExtensionViewRejection> {
        switch method {
        case .workspaceRoot:
            return .success(.workspaceRoot)

        case .themeRead:
            return .success(.themeRead)

        case .workspaceList:
            let depth = ExtensionIndex.integer(params["depth"]) ?? defaultListDepth
            guard depth >= 1, depth <= maxListDepth else {
                return .failure(.badParameters("'depth' must be between 1 and \(maxListDepth)."))
            }
            guard let root = fileRoot(params["root"]) else {
                return .failure(.badParameters(Self.rootMessage))
            }
            if params["path"] == nil { return .success(.workspaceList(root: root, path: nil, depth: depth)) }
            guard let path = relativePath(params["path"]) else {
                return .failure(.badParameters(Self.pathMessage))
            }
            return .success(.workspaceList(root: root, path: path, depth: depth))

        case .workspaceRead:
            guard let root = fileRoot(params["root"]) else {
                return .failure(.badParameters(Self.rootMessage))
            }
            guard let path = relativePath(params["path"]) else {
                return .failure(.badParameters(Self.pathMessage))
            }
            return .success(.workspaceRead(root: root, path: path))

        case .httpRequest:
            return ExtensionViewHTTP.Request.parse(params).map(ExtensionViewCall.httpRequest)
        }
    }

    static let rootMessage = "'root' must be \"workspace\" or \"extension\"."
    static let pathMessage = "'path' must be a relative path with no '..' in it."

    /// Which of the two folders a path is resolved against. Absent means
    /// the workspace, because that is what a view is opened over.
    static func fileRoot(_ value: Any?) -> ExtensionViewFileScope.Root? {
        guard value != nil else { return .workspace }
        guard let raw = LanguageManifest.string(value) else { return nil }
        return ExtensionViewFileScope.Root(rawValue: raw)
    }

    /// A path as a page is allowed to spell it: relative, no traversal, no
    /// scalar that could make a log or a dialog say something else.
    ///
    /// Absolute paths are refused here rather than resolved and then
    /// rejected by the scope check, so that a page cannot learn where the
    /// workspace is by probing with `/`.
    static func relativePath(_ value: Any?) -> String? {
        guard let raw = LanguageManifest.string(value), raw.count <= maxPathLength else { return nil }
        guard !raw.hasPrefix("/"), !raw.hasPrefix("~"), !raw.contains("\\") else { return nil }
        guard !raw.unicodeScalars.contains(where: LanguageContribution.isUnsafeScalar) else { return nil }
        let segments = raw.split(separator: "/", omittingEmptySubsequences: true)
        guard !segments.contains("..") else { return nil }
        let named = segments.filter { $0 != "." }
        guard !named.isEmpty else { return nil }
        return named.joined(separator: "/")
    }
}
