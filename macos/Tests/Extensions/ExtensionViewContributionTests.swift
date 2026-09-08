import Foundation
@testable import Ghostty
import Testing

struct ExtensionViewContributionTests {
    /// A package on disk with an entry, a stylesheet and an icon in it.
    private func package() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("view-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("views", isDirectory: true), withIntermediateDirectories: true)
        try Data("export default 1".utf8).write(to: root.appendingPathComponent("views/http.js"))
        try Data(":root {}".utf8).write(to: root.appendingPathComponent("views/http.css"))
        try Data("png".utf8).write(to: root.appendingPathComponent("views/http.png"))
        return root
    }

    private func entry(_ overrides: [String: Any] = [:]) -> [String: Any] {
        var json: [String: Any] = [
            "viewId": "http",
            "title": "HTTP",
            "icon": "views/http.png",
            "entry": "views/http.js",
        ]
        for (key, value) in overrides { json[key] = value }
        return json
    }

    @Test func readsTheFourFieldsItNeeds() throws {
        let root = try package()
        let parsed = ExtensionViewContribution.parse(json: entry(["style": "views/http.css"]), root: root)

        #expect(parsed?.viewID == "http")
        #expect(parsed?.title == "HTTP")
        #expect(parsed?.icon.lastPathComponent == "http.png")
        #expect(parsed?.entry.lastPathComponent == "http.js")
        #expect(parsed?.style?.lastPathComponent == "http.css")
    }

    @Test func refusesAnEntryThatIsNotAScript() throws {
        let root = try package()
        #expect(ExtensionViewContribution.parse(json: entry(["entry": "views/http.png"]), root: root) == nil)
        #expect(ExtensionViewContribution.parse(json: entry(["entry": "extension.json"]), root: root) == nil)
    }

    /// The whole point of `LanguageContribution.containedURL`: a path that
    /// climbs out of the extension costs the contribution, and reads nothing.
    @Test func refusesAPathThatLeavesThePackage() throws {
        let root = try package()
        #expect(ExtensionViewContribution.parse(json: entry(["entry": "../elsewhere/http.js"]), root: root) == nil)
        #expect(ExtensionViewContribution.parse(json: entry(["entry": "/etc/passwd.js"]), root: root) == nil)
        #expect(ExtensionViewContribution.parse(json: entry(["icon": "~/icon.png"]), root: root) == nil)
    }

    /// An icon is a file, never a symbol name — the one field a third party
    /// must not be able to fill with a name SwiftUI may not resolve.
    @Test func refusesAnIconThatIsNotAnImage() throws {
        let root = try package()
        #expect(ExtensionViewContribution.parse(json: entry(["icon": "views/http.js"]), root: root) == nil)
        #expect(ExtensionViewContribution.parse(json: entry(["icon": "puzzlepiece"]), root: root) == nil)
    }

    @Test func bothPlacementsWhenTheFileNamesNone() throws {
        let root = try package()
        #expect(ExtensionViewContribution.parse(json: entry(), root: root)?.placements
            == Set(ExtensionViewContribution.Placement.allCases))
        #expect(ExtensionViewContribution.parse(json: entry(["placements": ["sidebar"]]), root: root)?.placements
            == [.sidebar])
        #expect(ExtensionViewContribution.parse(json: entry(["placements": ["nowhere"]]), root: root)?.placements
            == Set(ExtensionViewContribution.Placement.allCases))
    }

    /// A method name this build does not know is dropped, so a manifest
    /// written for a later Phantom keeps the half this one understands.
    @Test func keepsOnlyThePermissionsThisBuildHas() throws {
        let root = try package()
        let parsed = ExtensionViewContribution.parse(
            json: entry(["permissions": ["workspace.read", "http.request", "process.spawn", 7]]), root: root)
        #expect(parsed?.permissions == [.workspaceRead, .httpRequest])
    }

    @Test func noPermissionsIsNoPermissions() throws {
        let root = try package()
        #expect(ExtensionViewContribution.parse(json: entry(), root: root)?.permissions == [])
    }

    @Test func manifestReadsViewsAndCountsTheKeyAsKnown() throws {
        let root = try package()
        let manifest = LanguageManifest.parse(
            json: [
                "schemaVersion": 1,
                "id": "ipetinate.bruno",
                "name": "Bruno",
                "contributes": ["views": [entry(["permissions": ["http.request"]])]],
            ],
            digest: "d", url: root.appendingPathComponent("extension.json"), root: root, scope: .user)

        #expect(manifest.views.count == 1)
        #expect(manifest.views.first?.permissions == [.httpRequest])
        #expect(!manifest.unrecognizedFields.contains("contributes.views"))
    }

    /// A file written against rules this build does not have contributes no
    /// view, the same way it contributes no server.
    @Test func aManifestForALaterPhantomContributesNoView() throws {
        let root = try package()
        let manifest = LanguageManifest.parse(
            json: [
                "schemaVersion": 99,
                "id": "ipetinate.bruno",
                "name": "Bruno",
                "contributes": ["views": [entry()]],
            ],
            digest: "d", url: root.appendingPathComponent("extension.json"), root: root, scope: .user)

        #expect(manifest.views.isEmpty)
    }
}
