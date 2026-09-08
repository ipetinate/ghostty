import Foundation
@testable import Ghostty
import Testing

struct ExtensionViewBridgeTests {
    private let all = Set(ExtensionViewMethod.allCases)

    @Test func readyNeedsNoPermissionAndNoCallID() {
        #expect(ExtensionViewBridge.read(["type": "ready"], permissions: []) == .ready)
    }

    @Test func aMessageWithNoUsableCallIDIsDropped() {
        #expect(ExtensionViewBridge.read("ready", permissions: all) == .unaddressable)
        #expect(ExtensionViewBridge.read(["method": "workspace.root"], permissions: all) == .unaddressable)
        #expect(ExtensionViewBridge.read(["id": -1, "method": "workspace.root"], permissions: all) == .unaddressable)
        #expect(ExtensionViewBridge.read(["id": "7", "method": "workspace.root"], permissions: all) == .unaddressable)
    }

    /// The check the whole design rests on: a method the manifest did not
    /// declare is refused before its parameters are even read.
    @Test func anUndeclaredMethodIsRefused() {
        let message = ExtensionViewBridge.read(
            ["id": 1, "method": "http.request", "params": ["url": "https://example.com"]],
            permissions: [.workspaceRead])
        #expect(message == .rejected(id: 1, .notPermitted(.httpRequest)))
    }

    @Test func aMethodThisBuildDoesNotHaveIsRefusedByName() {
        #expect(ExtensionViewBridge.read(["id": 1, "method": "process.spawn"], permissions: all)
            == .rejected(id: 1, .unknownMethod))
        #expect(ExtensionViewBridge.read(["id": 1, "method": "WORKSPACE.READ"], permissions: all)
            == .rejected(id: 1, .unknownMethod))
    }

    @Test func theTwoMethodsWithNoParametersAreAccepted() {
        #expect(ExtensionViewBridge.read(["id": 1, "method": "workspace.root"], permissions: all)
            == .accepted(id: 1, .workspaceRoot))
        #expect(ExtensionViewBridge.read(["id": 2, "method": "theme.read"], permissions: all)
            == .accepted(id: 2, .themeRead))
    }

    @Test func aPathIsRelativeWithNoTraversalInIt() {
        #expect(ExtensionViewBridge.relativePath("api/users.bru") == "api/users.bru")
        #expect(ExtensionViewBridge.relativePath("./api//users.bru") == "api/users.bru")
        #expect(ExtensionViewBridge.relativePath(".") == nil)
        #expect(ExtensionViewBridge.relativePath("/etc/passwd") == nil)
        #expect(ExtensionViewBridge.relativePath("~/.ssh/id_rsa") == nil)
        #expect(ExtensionViewBridge.relativePath("api/../../secret") == nil)
        #expect(ExtensionViewBridge.relativePath("api\\users.bru") == nil)
        #expect(ExtensionViewBridge.relativePath("api/\u{202E}bru") == nil)
        #expect(ExtensionViewBridge.relativePath(String(repeating: "a", count: 2048)) == nil)
        #expect(ExtensionViewBridge.relativePath(7) == nil)
    }

    @Test func readNeedsAPathAndListDoesNot() {
        #expect(ExtensionViewBridge.read(["id": 1, "method": "workspace.read"], permissions: all)
            == .rejected(id: 1, .badParameters(ExtensionViewBridge.pathMessage)))
        #expect(
            ExtensionViewBridge.read(
                ["id": 2, "method": "workspace.read", "params": ["path": "api/users.bru"]], permissions: all)
                == .accepted(id: 2, .workspaceRead(root: .workspace, path: "api/users.bru")))
        #expect(ExtensionViewBridge.read(["id": 3, "method": "workspace.list"], permissions: all)
            == .accepted(id: 3, .workspaceList(root: .workspace, path: nil,
                                               depth: ExtensionViewBridge.defaultListDepth)))
    }

    /// An absent root means the workspace, because that is what a view is
    /// opened over. A root that is neither of the two is a bad call rather
    /// than a silent fallback.
    @Test func theRootIsOneOfTwoFolders() {
        #expect(
            ExtensionViewBridge.read(
                ["id": 1, "method": "workspace.read", "params": ["root": "extension", "path": "views/http.js"]],
                permissions: all)
                == .accepted(id: 1, .workspaceRead(root: .package, path: "views/http.js")))
        #expect(
            ExtensionViewBridge.read(
                ["id": 2, "method": "workspace.read", "params": ["root": "/", "path": "x"]], permissions: all)
                == .rejected(id: 2, .badParameters(ExtensionViewBridge.rootMessage)))
    }

    @Test func aWalkIsBoundedInDepth() {
        #expect(
            ExtensionViewBridge.read(
                ["id": 1, "method": "workspace.list", "params": ["depth": 9]], permissions: all)
                == .rejected(id: 1, .badParameters("'depth' must be between 1 and \(ExtensionViewBridge.maxListDepth).")))
        #expect(
            ExtensionViewBridge.read(
                ["id": 2, "method": "workspace.list", "params": ["depth": 0]], permissions: all)
                == .rejected(id: 2, .badParameters("'depth' must be between 1 and \(ExtensionViewBridge.maxListDepth).")))
    }

    /// The write method's own spelling rule, on top of `relativePath`: no
    /// part of a path may begin with a dot, so a page cannot create
    /// `.git/hooks/pre-commit` or `.github/workflows/run.yml`.
    @Test func aWritablePathHasNoDotPartInIt() {
        #expect(ExtensionViewBridge.writablePath("api/users.bru") == "api/users.bru")
        #expect(ExtensionViewBridge.writablePath("./api/users.bru") == "api/users.bru")
        #expect(ExtensionViewBridge.writablePath(".git/hooks/pre-commit") == nil)
        #expect(ExtensionViewBridge.writablePath("api/.hidden.bru") == nil)
        #expect(ExtensionViewBridge.writablePath(".envrc") == nil)
        #expect(ExtensionViewBridge.writablePath("/etc/passwd") == nil)
        #expect(ExtensionViewBridge.writablePath("api/../../secret") == nil)
    }

    @Test func aWriteNeedsAPathAndText() {
        #expect(
            ExtensionViewBridge.read(
                ["id": 1, "method": "workspace.create", "params": ["text": "x"]], permissions: all)
                == .rejected(id: 1, .badParameters(ExtensionViewBridge.writePathMessage)))
        #expect(
            ExtensionViewBridge.read(
                ["id": 2, "method": "workspace.create", "params": ["path": "new.bru"]], permissions: all)
                == .rejected(id: 2, .badParameters("'text' must be a string.")))
        #expect(
            ExtensionViewBridge.read(
                ["id": 3, "method": "workspace.replace", "params": ["path": "new.bru", "text": 7]],
                permissions: all)
                == .rejected(id: 3, .badParameters("'text' must be a string.")))
        #expect(
            ExtensionViewBridge.read(
                ["id": 4, "method": "workspace.create",
                 "params": ["root": "extension", "path": "notes/new.txt", "text": "hello"]],
                permissions: all)
                == .accepted(id: 4, .workspaceWrite(
                    root: .package, path: "notes/new.txt", text: "hello", mode: .create)))
        #expect(
            ExtensionViewBridge.read(
                ["id": 5, "method": "workspace.replace",
                 "params": ["path": "api/users.bru", "text": "get {\n  url: https://x\n}"]],
                permissions: all)
                == .accepted(id: 5, .workspaceWrite(
                    root: .workspace, path: "api/users.bru",
                    text: "get {\n  url: https://x\n}", mode: .replace)))
    }

    @Test func aWriteIsBoundedInSize() {
        let text = String(repeating: "a", count: ExtensionViewBridge.maxWriteBytes + 1)
        for method in ["workspace.create", "workspace.replace"] {
            let message = ExtensionViewBridge.read(
                ["id": 1, "method": method, "params": ["path": "new.bru", "text": text]],
                permissions: all)
            #expect(message == .rejected(id: 1, .badParameters(
                "'text' is \(text.utf8.count) bytes; the limit for one write is "
                    + "\(ExtensionViewBridge.maxWriteBytes).")))
        }
    }

    /// Each write method is its own declaration, spelled the way the author
    /// spells it. Declaring one is not declaring the other: an extension
    /// that only adds files can never write over one.
    @Test func eachWriteMethodIsItsOwnDeclaration() {
        #expect(ExtensionViewMethod.workspaceCreate.rawValue == "workspace.create")
        #expect(ExtensionViewMethod.workspaceReplace.rawValue == "workspace.replace")

        let creator: Set<ExtensionViewMethod> = [.workspaceRead, .workspaceCreate]
        #expect(
            ExtensionViewBridge.read(
                ["id": 1, "method": "workspace.replace", "params": ["path": "a.bru", "text": "x"]],
                permissions: creator)
                == .rejected(id: 1, .notPermitted(.workspaceReplace)))
        #expect(
            ExtensionViewBridge.read(
                ["id": 2, "method": "workspace.create", "params": ["path": "a.bru", "text": "x"]],
                permissions: creator)
                == .accepted(id: 2, .workspaceWrite(
                    root: .workspace, path: "a.bru", text: "x", mode: .create)))

        let replacer: Set<ExtensionViewMethod> = [.workspaceRead, .workspaceReplace]
        #expect(
            ExtensionViewBridge.read(
                ["id": 3, "method": "workspace.create", "params": ["path": "a.bru", "text": "x"]],
                permissions: replacer)
                == .rejected(id: 3, .notPermitted(.workspaceCreate)))
    }

    /// The mode a call carries is what names it back, so a call cannot be
    /// built for one method and answered as the other.
    @Test func theModeNamesTheMethodItCameFrom() {
        for mode in ExtensionViewFileScope.WriteMode.allCases {
            let call = ExtensionViewCall.workspaceWrite(
                root: .workspace, path: "a.bru", text: "x", mode: mode)
            #expect(call.method == mode.method)
        }
        #expect(ExtensionViewFileScope.WriteMode.create.method == .workspaceCreate)
        #expect(ExtensionViewFileScope.WriteMode.replace.method == .workspaceReplace)
    }

    @Test func aViewsOpenCallNeedsAViewIDAndTakesAPath() {
        #expect(
            ExtensionViewBridge.read(["id": 1, "method": "views.open"], permissions: all)
                == .rejected(id: 1, .badParameters(
                    "'viewId' must be a view id this extension declares.")))

        /* A view is opened on a file, so a call with no path is a call
         * with nothing to open. */
        #expect(
            ExtensionViewBridge.read(
                ["id": 2, "method": "views.open", "params": ["viewId": "http"]], permissions: all)
                == .rejected(id: 2, .badParameters(ExtensionViewBridge.pathMessage)))

        #expect(
            ExtensionViewBridge.read(
                ["id": 3, "method": "views.open",
                 "params": ["viewId": "http", "title": "List users", "path": "api/users.bru"]],
                permissions: all)
                == .accepted(id: 3, .viewsOpen(
                    viewID: "http", title: "List users", path: "api/users.bru")))
    }

    @Test func aViewsOpenPathFollowsTheReadRule() {
        for bad in ["/etc/passwd", "~/.ssh/id_rsa", "api/../../secret", "api\\users.bru"] {
            #expect(
                ExtensionViewBridge.read(
                    ["id": 1, "method": "views.open",
                     "params": ["viewId": "http", "path": bad]],
                    permissions: all)
                    == .rejected(id: 1, .badParameters(ExtensionViewBridge.pathMessage)))
        }
    }

    @Test func aViewsOpenTitleIsBounded() {
        let title = String(repeating: "a", count: ExtensionViewBridge.maxViewTitleLength + 1)
        #expect(
            ExtensionViewBridge.read(
                ["id": 1, "method": "views.open", "params": ["viewId": "http", "title": title]],
                permissions: all)
                == .rejected(id: 1, .badParameters(
                    "'title' is longer than \(ExtensionViewBridge.maxViewTitleLength) characters.")))
    }

    /// The methods that act on the window are refused by the responder, the
    /// way `http.request` is: they are answered where the window is.
    @Test func theWindowMethodsAreNotAnsweredByTheResponder() {
        let scope = ExtensionViewFileScope(
            workspace: nil, package: URL(fileURLWithPath: "/tmp/bruno"))
        let calls: [ExtensionViewCall] = [
            .workspaceChoose(kind: .directory),
            .viewsOpen(viewID: "http", title: nil, path: "a.bru"),
            .editorDirty(true),
        ]
        for call in calls {
            #expect(ExtensionViewResponder.answer(call, scope: scope, theme: [:]).isFailure)
        }
    }

    @Test func aChoiceIsAFolderUnlessThePageAsksForAFile() {
        #expect(
            ExtensionViewBridge.read(["id": 1, "method": "workspace.choose"], permissions: all)
                == .accepted(id: 1, .workspaceChoose(kind: .directory)))
        #expect(
            ExtensionViewBridge.read(
                ["id": 2, "method": "workspace.choose", "params": ["kind": "file"]],
                permissions: all)
                == .accepted(id: 2, .workspaceChoose(kind: .file)))
        #expect(
            ExtensionViewBridge.read(
                ["id": 3, "method": "workspace.choose", "params": ["kind": "volume"]],
                permissions: all)
                == .rejected(id: 3, .badParameters("'kind' must be \"directory\" or \"file\".")))
    }

    /// The state a view remembers is an object, bounded, and the page may
    /// not write a key the app owns.
    @Test func stateIsABoundedObjectWithNoReservedKeys() {
        #expect(
            ExtensionViewBridge.read(
                ["id": 1, "method": "state.write", "params": ["state": ["path": "api"]]],
                permissions: all)
                == .accepted(id: 1, .stateWrite("{\"path\":\"api\"}")))
        #expect(
            ExtensionViewBridge.read(
                ["id": 2, "method": "state.write", "params": ["state": "text"]], permissions: all)
                == .rejected(id: 2, .badParameters("'state' must be a JSON object.")))

        let big = ["a": String(repeating: "x", count: ExtensionViewState.maxBytes)]
        let message = ExtensionViewBridge.read(
            ["id": 3, "method": "state.write", "params": ["state": big]], permissions: all)
        #expect(message != .accepted(id: 3, .stateWrite("")))
        if case .rejected(_, let rejection) = message {
            #expect(rejection.code == "bad-parameters")
        } else {
            Issue.record("an oversized state was accepted")
        }
    }

    @Test func aDirtyCallNeedsABoolean() {
        #expect(
            ExtensionViewBridge.read(
                ["id": 1, "method": "editor.dirty", "params": ["isDirty": true]], permissions: all)
                == .accepted(id: 1, .editorDirty(true)))
        #expect(
            ExtensionViewBridge.read(
                ["id": 2, "method": "editor.dirty", "params": ["isDirty": "yes"]], permissions: all)
                == .rejected(id: 2, .badParameters("'isDirty' must be true or false.")))
    }

    @Test func everyRejectionCarriesACodeAndASentence() {
        let rejections: [ExtensionViewRejection] = [
            .notPermitted(.httpRequest), .unknownMethod, .badParameters("no"),
            .outOfScope("/etc"), .unreadable("gone"), .exists("new.bru"), .absent("gone.bru"),
            .unwritable("read-only"), .unknownView("http"), .cancelled,
            .notThisFile("api/users.bru"), .refusedURL(.noHost), .failed("timed out"),
        ]
        for rejection in rejections {
            #expect(!rejection.code.isEmpty)
            #expect(!rejection.message.isEmpty)
        }
    }
}

extension Result {
    var isFailure: Bool {
        switch self {
        case .success: return false
        case .failure: return true
        }
    }
}
