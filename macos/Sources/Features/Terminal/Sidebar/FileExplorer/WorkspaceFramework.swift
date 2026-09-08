import Foundation

/// Which framework a project builds its JSX with, when that changes what a
/// file should look like.
///
/// **A `.tsx` file does not say who compiles it.** The suffix is the same for
/// React, Solid, Preact and Qwik — one grammar, one language id, one language
/// server — so an icon theme, whose tables are keyed by name and suffix and
/// nothing else, has no way to tell them apart and answers React for all of
/// them. The project does say, in its dependencies, and that is the only
/// place the answer lives.
///
/// Deliberately not a language: nothing here changes how a file is parsed,
/// highlighted or served. It changes one drawing.
enum WorkspaceFramework: String, CaseIterable, Sendable {
    case solid
    case angular

    /// The dependency that settles it.
    var dependency: String {
        switch self {
        case .solid: return "solid-js"
        case .angular: return "@angular/core"
        }
    }

    /// The icon id a theme has to define for this to show. A theme that does
    /// not define it keeps its own answer — this never draws a blank.
    ///
    /// Only asked for a framework that has an icon of its own to offer. The
    /// other direction — a framework whose artwork must be *withheld* — is
    /// `brand`.
    var iconID: String { rawValue }

    /// The word a theme puts in an icon id when the artwork is this
    /// framework's own.
    ///
    /// Both themes in this registry name them that way: Material and Symbols
    /// each map eighteen suffixes — `service.ts`, `component.ts`, `pipe.ts`,
    /// `directive.ts`, `guard.ts`, `interceptor.ts`, `module.ts`,
    /// `resolver.ts` and their `.js` and `.dart` twins — to ids like
    /// `angular-service` and `angular-pipe`. So a NestJS `user.service.ts`
    /// wore Angular's shield, because the suffix is the same and the theme
    /// has no way to ask whose it is.
    ///
    /// Matched on the id rather than on a list of suffixes on purpose: a
    /// list would have to be kept in step with two third-party themes and
    /// would still miss the next suffix they add.
    var brand: String { rawValue }

    /// The suffixes this can speak *for*, by offering its own icon. A `.ts`
    /// file in a Solid project is TypeScript and wears TypeScript's icon;
    /// only the JSX-bearing ones are ambiguous in the first place.
    ///
    /// Withholding another framework's artwork is not limited to these —
    /// that applies to any suffix a theme has branded. See `brands(iconID:)`.
    static let claimedExtensions: Set<String> = ["tsx", "jsx"]

    /// Whether this file is one whose artwork a framework may decide.
    static func claims(fileName: String) -> Bool {
        let suffix = (fileName as NSString).pathExtension.lowercased()
        return claimedExtensions.contains(suffix)
    }

    /// Whether this icon id is one framework's own artwork.
    static func brands(iconID: String) -> WorkspaceFramework? {
        let lowered = iconID.lowercased()
        return allCases.first { lowered.contains($0.brand) }
    }

    /// The brands a project may not wear, which is every framework it is
    /// not. A project that says nothing rejects all of them: a file called
    /// `user.service.ts` in a repository with no manifest above it is a
    /// TypeScript file, and drawing Angular's shield on it is a guess
    /// dressed as a fact.
    static func rejected(by framework: WorkspaceFramework?) -> Set<WorkspaceFramework> {
        Set(allCases).subtracting(framework.map { [$0] } ?? [])
    }

    /// The framework of the project holding `path`, or nil.
    ///
    /// Answered from the nearest `package.json` walking up, which is the
    /// same shape `FormatterProject.discover` uses to find a tool's config
    /// and a companion server uses to find its marker. `node_modules` would
    /// be cheaper to stat and would answer nothing before an install; the
    /// manifest is what the project says about itself.
    @MainActor
    static func of(path: String) -> WorkspaceFramework? {
        let directory = (path as NSString).deletingLastPathComponent
        if let cached = cache[directory] { return cached }
        let found = search(from: directory)
        cache[directory] = found
        return found
    }

    /// Cached per directory for the life of the process, and never
    /// invalidated: a project does not change framework while somebody reads
    /// it, and the alternative is parsing a manifest for every row of the
    /// explorer on every redraw. Editing `package.json` needs a relaunch to
    /// show, which is the trade this makes.
    ///
    /// Main actor because every caller is a view drawing a row, which is
    /// also what makes a plain dictionary enough.
    @MainActor
    private static var cache: [String: WorkspaceFramework?] = [:]

    private static func search(from directory: String) -> WorkspaceFramework? {
        var current = directory
        var depth = 0
        while depth < maximumDepth, current != "/", !current.isEmpty {
            let manifest = (current as NSString).appendingPathComponent("package.json")
            if FileManager.default.fileExists(atPath: manifest),
               let found = framework(inManifestAt: manifest) {
                return found
            }
            let parent = (current as NSString).deletingLastPathComponent
            guard parent != current else { break }
            current = parent
            depth += 1
        }
        return nil
    }

    /// Deep enough for a package inside a monorepo, bounded so a path with
    /// no manifest above it cannot walk to the root of the disk on every
    /// uncached lookup.
    private static let maximumDepth = 12

    static func framework(inManifestAt path: String) -> WorkspaceFramework? {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return framework(inManifest: json)
    }

    /// Pure, so the rule can be exercised without a directory tree.
    ///
    /// `dependencies` and `devDependencies` both count. A framework is
    /// usually a runtime dependency, but a template that puts it under the
    /// dev half is not a project that stops being written in it.
    static func framework(inManifest json: [String: Any]) -> WorkspaceFramework? {
        for key in ["dependencies", "devDependencies"] {
            guard let declared = json[key] as? [String: Any] else { continue }
            for framework in allCases where declared[framework.dependency] != nil {
                return framework
            }
        }
        return nil
    }
}
