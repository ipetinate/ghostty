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

    @Test func everyRejectionCarriesACodeAndASentence() {
        let rejections: [ExtensionViewRejection] = [
            .notPermitted(.httpRequest), .unknownMethod, .badParameters("no"),
            .outOfScope("/etc"), .unreadable("gone"), .refusedURL(.noHost), .failed("timed out"),
        ]
        for rejection in rejections {
            #expect(!rejection.code.isEmpty)
            #expect(!rejection.message.isEmpty)
        }
    }
}
