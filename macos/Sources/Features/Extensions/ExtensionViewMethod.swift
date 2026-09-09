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

    /// One **new** file inside that scope. It refuses a path that already
    /// exists, so it cannot replace anything.
    case workspaceCreate = "workspace.create"

    /// New content for a file inside that scope that **already exists**.
    ///
    /// Two methods rather than one, and the split is the point: an author
    /// who only ever adds files asks for `workspace.create` and can never
    /// overwrite the reader's work, while an author who saves an edited file
    /// asks for `workspace.replace` and the reader sees the difference in
    /// the `permissions` list rather than inferring it.
    ///
    /// The two are disjoint. `create` refuses a path that exists and
    /// `replace` refuses one that does not, so neither is the other with a
    /// different name and a typo in a path cannot turn a save into a new
    /// file nobody asked for.
    case workspaceReplace = "workspace.replace"

    /// A folder or a file the reader picks in a system dialog. The folder,
    /// or the file's folder, becomes this view's workspace.
    case workspaceChoose = "workspace.choose"

    /// What this view remembered, per workspace. See `ExtensionViewState`.
    case stateRead = "state.read"

    /// Remembers something, per workspace.
    case stateWrite = "state.write"

    /// Tells the app this page has unsaved work, so the tab wears the
    /// editor's own dirty mark rather than a dot the page draws.
    case editorDirty = "editor.dirty"

    /// Opens an editor view **of the same extension** on a file this view
    /// could already read. See `ExtensionViewOpener`.
    case viewsOpen = "views.open"

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
    /// `workspace.create` and `workspace.replace`, which differ only in
    /// what they refuse. One case, so the parameters are read in one place
    /// and no future method can be added that reads them differently.
    case workspaceWrite(
        root: ExtensionViewFileScope.Root,
        path: String,
        text: String,
        mode: ExtensionViewFileScope.WriteMode)

    /// `directory` asks for a folder, `file` for a file. A file's folder
    /// becomes the workspace, and the file itself comes back so the page can
    /// open it.
    case workspaceChoose(kind: ChoiceKind)

    case stateRead

    /// The object to remember, as compact JSON. Text and not a dictionary,
    /// so this enum stays `Equatable` and `Sendable` — and so what leaves
    /// the parser is something the app has already read once.
    case stateWrite(String)

    case editorDirty(Bool)

    /// `viewId` as the author spells it in their own manifest — never a
    /// descriptor id, so this cannot name another extension's view.
    ///
    /// `path` names a file the calling view could already read, and the tab
    /// is **that file's** tab. The page is told which file it is drawing
    /// through `phantom.file()`.
    case viewsOpen(viewID: String, title: String?, path: String)

    case themeRead
    case httpRequest(ExtensionViewHTTP.Request)

    /// What `workspace.choose` puts in the dialog.
    enum ChoiceKind: String, CaseIterable, Equatable, Sendable {
        case directory
        case file
    }

    var method: ExtensionViewMethod {
        switch self {
        case .workspaceRoot: return .workspaceRoot
        case .workspaceList: return .workspaceList
        case .workspaceRead: return .workspaceRead
        case .workspaceWrite(_, _, _, let mode): return mode.method
        case .workspaceChoose: return .workspaceChoose
        case .stateRead: return .stateRead
        case .stateWrite: return .stateWrite
        case .editorDirty: return .editorDirty
        case .viewsOpen: return .viewsOpen
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

    /// `workspace.create` was given a path that is already taken. Its own
    /// code, so a page can ask for another name instead of showing a
    /// refusal it cannot act on.
    case exists(String)

    /// `workspace.replace` was given a path with nothing at it. Its own code
    /// for the same reason: the page's answer is to create the file, which
    /// is a different method and a different declaration.
    case absent(String)

    /// `views.open` named a view the calling extension does not declare on
    /// the editor surface. It can never name another extension's view — see
    /// `ExtensionViewOpener`.
    case unknownView(String)

    /// The reader closed the folder dialog without picking one. A refusal
    /// rather than an empty answer, so a page cannot mistake "no" for "the
    /// root of the disk".
    case cancelled

    /// `workspace.replace` from a view drawing a file, aimed at a different
    /// file. See `ExtensionViewResponder.answer`.
    case notThisFile(String)

    case unwritable(String)
    case refusedURL(ExtensionViewHTTP.Refusal)
    case failed(String)

    var code: String {
        switch self {
        case .notPermitted: return "not-permitted"
        case .unknownMethod: return "unknown-method"
        case .badParameters: return "bad-parameters"
        case .outOfScope: return "out-of-scope"
        case .unreadable: return "unreadable"
        case .exists: return "exists"
        case .absent: return "absent"
        case .unknownView: return "unknown-view"
        case .cancelled: return "cancelled"
        case .notThisFile: return "not-this-file"
        case .unwritable: return "unwritable"
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
        case .exists(let path):
            return "\(path) is already there, and workspace.create never replaces a file."
        case .absent(let path):
            return "\(path) does not exist, and workspace.replace only writes over a file that does."
        case .unknownView(let viewID):
            return "This extension declares no editor view called \"\(viewID)\"."
        case .cancelled:
            return "No folder was picked."
        case .notThisFile(let path):
            return "This view was opened on \(path) and workspace.replace writes only to that file."
        case .unwritable(let detail):
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

    /// How much text one write may carry, either method.
    ///
    /// Much smaller than what `workspace.read` will hand back. A read is
    /// bounded by what somebody already chose to put on disk; a write is
    /// bounded by nothing but this, and the files a page has any business
    /// writing — a request, a fixture, a note, a config — are kilobytes.
    static let maxWriteBytes = 256 * 1024

    static let maxViewTitleLength = ExtensionViewContribution.maxTitleLength

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

        case .workspaceChoose:
            guard let kind = choiceKind(params["kind"]) else {
                return .failure(.badParameters("'kind' must be \"directory\" or \"file\"."))
            }
            return .success(.workspaceChoose(kind: kind))

        case .stateRead:
            return .success(.stateRead)

        case .stateWrite:
            guard let object = params["state"] as? [String: Any],
                  JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(
                      withJSONObject: object, options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8)
            else { return .failure(.badParameters("'state' must be a JSON object.")) }
            guard data.count <= ExtensionViewState.maxBytes else {
                return .failure(.badParameters(
                    "'state' is \(data.count) bytes; the limit is \(ExtensionViewState.maxBytes)."))
            }
            return .success(.stateWrite(text))

        case .editorDirty:
            guard let isDirty = params["isDirty"] as? Bool else {
                return .failure(.badParameters("'isDirty' must be true or false."))
            }
            return .success(.editorDirty(isDirty))

        case .viewsOpen:
            guard let viewID = LanguageContribution.validLanguageID(params["viewId"]) else {
                return .failure(.badParameters("'viewId' must be a view id this extension declares."))
            }
            let title = LanguageManifest.displayString(params["title"])
            guard title == nil || title!.count <= maxViewTitleLength else {
                return .failure(.badParameters(
                    "'title' is longer than \(maxViewTitleLength) characters."))
            }
            guard let path = relativePath(params["path"]) else {
                return .failure(.badParameters(Self.pathMessage))
            }
            return .success(.viewsOpen(viewID: viewID, title: title, path: path))

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

        case .workspaceCreate:
            return write(params, mode: .create)

        case .workspaceReplace:
            return write(params, mode: .replace)

        case .httpRequest:
            return ExtensionViewHTTP.Request.parse(params).map(ExtensionViewCall.httpRequest)
        }
    }

    /// A folder unless the page asked for a file, because a folder is what
    /// a view's methods are bounded to.
    static func choiceKind(_ value: Any?) -> ExtensionViewCall.ChoiceKind? {
        guard value != nil, !(value is NSNull) else { return .directory }
        guard let raw = LanguageManifest.string(value) else { return nil }
        return ExtensionViewCall.ChoiceKind(rawValue: raw)
    }

    /// The parameters both write methods take, read once.
    static func write(
        _ params: [String: Any],
        mode: ExtensionViewFileScope.WriteMode
    ) -> Result<ExtensionViewCall, ExtensionViewRejection> {
        guard let root = fileRoot(params["root"]) else {
            return .failure(.badParameters(rootMessage))
        }
        guard let path = writablePath(params["path"]) else {
            return .failure(.badParameters(writePathMessage))
        }
        guard let text = params["text"] as? String else {
            return .failure(.badParameters("'text' must be a string."))
        }
        let bytes = text.utf8.count
        guard bytes <= maxWriteBytes else {
            return .failure(.badParameters(
                "'text' is \(bytes) bytes; the limit for one write is \(maxWriteBytes)."))
        }
        return .success(.workspaceWrite(root: root, path: path, text: text, mode: mode))
    }

    static let rootMessage = "'root' must be \"workspace\" or \"extension\"."
    static let pathMessage = "'path' must be a relative path with no '..' in it."
    static let writePathMessage = "'path' must be a relative path with no '..' in it, "
        + "and no part of it may begin with a '.'."

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

    /// A path a page may *write* to: `relativePath`'s rule, and one more —
    /// no part of it may begin with a dot.
    ///
    /// The dot rule is the one thing the write methods need that the read
    /// methods do not. A workspace holds `.git/hooks/pre-commit`,
    /// `.github/workflows`, `.vscode/tasks.json` and `.envrc`, each of which
    /// is a file some other program runs without being asked twice. Reading
    /// one is a page reading the repository it was opened over; writing one
    /// is a page arranging to have its own text executed later, which is not
    /// a thing either method is for.
    ///
    /// A blanket refusal rather than a list of the dangerous names. The
    /// dangerous set is not closed — any tool may start reading a dotfile of
    /// its own — so a list would need a new entry every time one does, and
    /// would be wrong in between.
    static func writablePath(_ value: Any?) -> String? {
        guard let path = relativePath(value) else { return nil }
        guard !path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) else { return nil }
        return path
    }
}
