import Foundation
@testable import Ghostty
import Testing

/// Which framework a `.tsx` file belongs to, which the suffix cannot say.
///
/// The whole reason this type exists is that React, Solid, Preact and Qwik
/// all write `.tsx`: one grammar, one language id, one server, and an icon
/// theme keyed by suffix that answers React for every one of them. The
/// project's dependencies are the only place the answer lives.
struct WorkspaceFrameworkTests {
    @Test func aRuntimeDependencyNamesTheFramework() {
        let manifest: [String: Any] = ["dependencies": ["solid-js": "^1.9.0"]]
        #expect(WorkspaceFramework.framework(inManifest: manifest) == .solid)
    }

    /// A template that puts the framework under the dev half is not a
    /// project that stops being written in it.
    @Test func aDevDependencyCountsToo() {
        let manifest: [String: Any] = ["devDependencies": ["solid-js": "1.9.0"]]
        #expect(WorkspaceFramework.framework(inManifest: manifest) == .solid)
    }

    @Test func angularIsSettledByItsCorePackage() {
        let manifest: [String: Any] = ["dependencies": ["@angular/core": "^20.0.0"]]
        #expect(WorkspaceFramework.framework(inManifest: manifest) == .angular)
    }

    // MARK: Withholding another framework's artwork

    /// The case the owner reported: both icon themes in this registry map
    /// eighteen suffixes each — `service.ts`, `pipe.ts`, `directive.ts` and
    /// their twins — to ids like `angular-service`, so a NestJS file wore
    /// Angular's shield. Matched on the id, not on a list of suffixes that
    /// would have to be kept in step with two third-party themes.
    @Test func anIconIDCarryingAFrameworksNameIsItsArtwork() {
        #expect(WorkspaceFramework.brands(iconID: "angular-service") == .angular)
        #expect(WorkspaceFramework.brands(iconID: "angular-pipe") == .angular)
        #expect(WorkspaceFramework.brands(iconID: "folder-angular") == .angular)
        #expect(WorkspaceFramework.brands(iconID: "solid") == .solid)
        #expect(WorkspaceFramework.brands(iconID: "typescript") == nil)
        #expect(WorkspaceFramework.brands(iconID: "folder-controller") == nil)
    }

    /// A project rejects every framework it is not, and one that says
    /// nothing rejects all of them: a `user.service.ts` with no manifest
    /// above it is a TypeScript file, and Angular's shield there is a guess
    /// dressed as a fact.
    @Test func aProjectRejectsEveryFrameworkItIsNot() {
        #expect(WorkspaceFramework.rejected(by: .angular) == [.solid])
        #expect(WorkspaceFramework.rejected(by: .solid) == [.angular])
        #expect(WorkspaceFramework.rejected(by: nil) == Set(WorkspaceFramework.allCases))
    }

    @Test func aProjectWithoutItIsNotClaimed() {
        let manifest: [String: Any] = [
            "dependencies": ["react": "^19.0.0", "react-dom": "^19.0.0"],
        ]
        #expect(WorkspaceFramework.framework(inManifest: manifest) == nil)
    }

    /// A dependency map of the wrong shape is a manifest this cannot read,
    /// and reading nothing is the right answer: the icon falls back to what
    /// the theme said, which is what happens today for every project.
    @Test func aManifestThatIsNotShapedLikeOneAnswersNothing() {
        #expect(WorkspaceFramework.framework(inManifest: ["dependencies": "solid-js"]) == nil)
        #expect(WorkspaceFramework.framework(inManifest: [:]) == nil)
    }

    /// Only the ambiguous suffixes. A `.ts` file in a Solid project is
    /// TypeScript and wears TypeScript's icon.
    @Test func onlyJSXBearingSuffixesAreClaimed() {
        #expect(WorkspaceFramework.claims(fileName: "App.tsx"))
        #expect(WorkspaceFramework.claims(fileName: "app.jsx"))
        #expect(WorkspaceFramework.claims(fileName: "COUNTER.TSX"))
        #expect(!WorkspaceFramework.claims(fileName: "store.ts"))
        #expect(!WorkspaceFramework.claims(fileName: "index.html"))
        #expect(!WorkspaceFramework.claims(fileName: "tsx"))
    }

    /// The icon id is the framework's own name, so nothing here has to know
    /// what any particular theme calls React's icon — the substitution asks
    /// only whether the theme defines an icon by this name.
    @Test func theIconIDIsTheFrameworksName() {
        #expect(WorkspaceFramework.solid.iconID == "solid")
        #expect(WorkspaceFramework.solid.dependency == "solid-js")
    }

    @Test func aManifestOnDiskIsRead() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("phantom-framework-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = directory.appendingPathComponent("package.json")
        try #"{"dependencies":{"solid-js":"^1.9.0"}}"#.write(
            to: manifest, atomically: true, encoding: .utf8)

        #expect(WorkspaceFramework.framework(inManifestAt: manifest.path) == .solid)
    }

    @Test func aFileThatIsNotJSONIsNotAManifest() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("phantom-framework-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = directory.appendingPathComponent("package.json")
        try "not json".write(to: manifest, atomically: true, encoding: .utf8)

        #expect(WorkspaceFramework.framework(inManifestAt: manifest.path) == nil)
        #expect(WorkspaceFramework.framework(inManifestAt: directory.appendingPathComponent("gone.json").path) == nil)
    }
}
