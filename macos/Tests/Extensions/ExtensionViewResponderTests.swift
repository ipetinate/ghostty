import Foundation
@testable import Ghostty
import Testing

struct ExtensionViewResponderTests {
    private func scope() throws -> ExtensionViewFileScope {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("responder-" + UUID().uuidString, isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let package = root.appendingPathComponent("package", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data("get {}".utf8).write(to: workspace.appendingPathComponent("users.bru"))
        return ExtensionViewFileScope(workspace: workspace, package: package)
    }

    private func object(_ result: Result<Any, ExtensionViewRejection>) throws -> [String: Any] {
        let text = try #require(ExtensionViewResponder.json(id: 7, result: result))
        let decoded = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try #require(decoded as? [String: Any])
    }

    @Test func namesBothFoldersItWillRead() throws {
        let scope = try scope()
        let answer = ExtensionViewResponder.answer(.workspaceRoot, scope: scope, theme: [:])
        let payload = try #require((try? answer.get()) as? [String: Any])

        #expect(payload["workspace"] as? String == scope.workspace?.path)
        #expect(payload["extension"] as? String == scope.package.path)
    }

    @Test func aViewWithNoWorkspaceSaysSo() throws {
        let scope = try scope()
        let without = ExtensionViewFileScope(workspace: nil, package: scope.package)
        let answer = ExtensionViewResponder.answer(.workspaceRoot, scope: without, theme: [:])
        let payload = try #require((try? answer.get()) as? [String: Any])

        #expect(payload["workspace"] is NSNull)
    }

    @Test func readAnswersTheTextAndThePathItRead() throws {
        let scope = try scope()
        let answer = ExtensionViewResponder.answer(
            .workspaceRead(root: .workspace, path: "users.bru"), scope: scope, theme: [:])
        let payload = try #require((try? answer.get()) as? [String: Any])

        #expect(payload["text"] as? String == "get {}")
        #expect(payload["path"] as? String == "users.bru")
        #expect(payload["root"] as? String == "workspace")
    }

    @Test func theThemeIsHandedOverAsItIs() throws {
        let theme: [String: Any] = ["scheme": "dark", "colors": ["bg": "#101010"]]
        let answer = ExtensionViewResponder.answer(.themeRead, scope: try scope(), theme: theme)
        let payload = try #require((try? answer.get()) as? [String: Any])

        #expect(payload["scheme"] as? String == "dark")
    }

    /// The envelope the bridge reads: an id, and either a result or an error
    /// with a code and a sentence. Never both.
    @Test func aRefusalIsAnErrorWithACode() throws {
        let payload = try object(.failure(.notPermitted(.httpRequest)))
        let inner = try #require(payload["payload"] as? [String: Any])
        let error = try #require(inner["error"] as? [String: Any])

        #expect(payload["id"] as? Int == 7)
        #expect(error["code"] as? String == "not-permitted")
        #expect((error["message"] as? String)?.contains("http.request") == true)
        #expect(inner["result"] == nil)
    }

    /// A quote or a newline in a file's contents cannot end the expression
    /// the app evaluates, because the contents travel as JSON rather than
    /// spliced into a call.
    @Test func hostileTextSurvivesTheRoundTrip() throws {
        let nasty = "\");alert(1);//\n\u{2028}\"quoted\"\\"
        let payload = try object(.success(["text": nasty]))
        let inner = try #require(payload["payload"] as? [String: Any])
        let result = try #require(inner["result"] as? [String: Any])

        #expect(result["text"] as? String == nasty)
    }

    @Test func aResultThatIsNotJSONIsAnErrorRatherThanNothing() {
        #expect(ExtensionViewResponder.json(id: 1, result: .success(Date())) == nil)
    }

    @Test func anHTTPAnswerCarriesEveryFieldThePageReads() throws {
        let response = ExtensionViewHTTP.Response(
            status: 201, url: "https://api.example.com/v1", headers: ["content-type": "application/json"],
            text: "{}", base64: nil, bytes: 2, milliseconds: 42)
        let payload = response.payload

        #expect(payload["status"] as? Int == 201)
        #expect(payload["text"] as? String == "{}")
        #expect(payload["base64"] is NSNull)
        #expect(payload["milliseconds"] as? Int == 42)
        #expect(JSONSerialization.isValidJSONObject(payload))
    }

    /// A view that did not declare `theme.read` is never handed the theme:
    /// the app hands over nothing the manifest did not name, and a rule with
    /// one exception in it is weaker than the one this feature claims.
    @Test func theThemeIsAMethodLikeAnyOther() {
        #expect(ExtensionViewMethod.allCases.contains(.themeRead))
        #expect(ExtensionViewBridge.read(["id": 1, "method": "theme.read"], permissions: [])
            == .rejected(id: 1, .notPermitted(.themeRead)))
    }

    /// The one method this type does not answer, named rather than silently
    /// returning nothing.
    @Test func anHTTPRequestIsNotAnsweredHere() throws {
        let request = try #require(try? ExtensionViewHTTP.Request.parse(["url": "https://api.example.com"]).get())
        let answer = ExtensionViewResponder.answer(.httpRequest(request), scope: try scope(), theme: [:])
        #expect((try? answer.get()) == nil)
    }

    // MARK: The file an editor tab is pinned to

    /// The tighter statement an editor tab can make: not "a file this
    /// extension may write" but "the file this tab is".
    @Test func replaceWritesOnlyToTheFileTheViewWasOpenedOn() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("get {}".utf8).write(to: directory.appendingPathComponent("users.bru"))
        try Data("post {}".utf8).write(to: directory.appendingPathComponent("orders.bru"))

        let scope = ExtensionViewFileScope(workspace: directory, package: directory)
        let bound = ExtensionViewFile(root: .workspace, path: "users.bru")

        let ownFile = ExtensionViewResponder.answer(
            .workspaceWrite(root: .workspace, path: "users.bru", text: "get { }", mode: .replace),
            scope: scope, theme: [:], boundFile: bound)
        #expect(!ownFile.isFailure)
        #expect(try scope.read(root: .workspace, path: "users.bru") == "get { }")

        let otherFile = ExtensionViewResponder.answer(
            .workspaceWrite(root: .workspace, path: "orders.bru", text: "owned", mode: .replace),
            scope: scope, theme: [:], boundFile: bound)
        if case .failure(let rejection) = otherFile {
            #expect(rejection == .notThisFile("users.bru"))
            #expect(rejection.code == "not-this-file")
        } else {
            Issue.record("a write to another file was allowed")
        }
        #expect(try scope.read(root: .workspace, path: "orders.bru") == "post {}")
    }

    /// The pin is on `replace` alone. `create` cannot write over anything,
    /// so pinning it would stop a page saving a new document beside the one
    /// it is showing without closing any hole.
    @Test func createIsNotPinnedToTheOpenedFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("get {}".utf8).write(to: directory.appendingPathComponent("users.bru"))
        let scope = ExtensionViewFileScope(workspace: directory, package: directory)
        let bound = ExtensionViewFile(root: .workspace, path: "users.bru")

        let answer = ExtensionViewResponder.answer(
            .workspaceWrite(root: .workspace, path: "orders.bru", text: "post {}", mode: .create),
            scope: scope, theme: [:], boundFile: bound)
        #expect(!answer.isFailure)
    }

    /// A page with no file behind it keeps the general capability its
    /// manifest asked for: there is no file to be pinned to.
    @Test func aViewWithNoFileIsNotPinned() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("get {}".utf8).write(to: directory.appendingPathComponent("users.bru"))
        let scope = ExtensionViewFileScope(workspace: directory, package: directory)

        let answer = ExtensionViewResponder.answer(
            .workspaceWrite(root: .workspace, path: "users.bru", text: "get { }", mode: .replace),
            scope: scope, theme: [:], boundFile: nil)
        #expect(!answer.isFailure)
    }
}
