import Foundation
@testable import Ghostty
import Testing

/// Deciding that a project adopted a formatter, which copy of it to run, and
/// where to run it.
///
/// Two different tools are put through the same three keys, because the point
/// of the type is that it names none of them. The first is shaped like a
/// JavaScript formatter — many configuration names, a manifest key, a binary
/// under `node_modules` — and the second like a Ruby one, with a single
/// configuration file and a `bin/` binary. The walk is tested against trees
/// built here, because the interesting cases are all about where it *stops*: a
/// walk that runs one directory too far starts formatting files using a
/// stranger's settings.
struct FormatterProjectTests {
    // MARK: Two tools, one set of keys

    /// Shaped like a JavaScript formatter's manifest entry.
    static let webRules = FormatterProjectRules(
        markers: [
            .file(".toolrc"),
            .file(".toolrc.json"),
            .file("tool.config.mjs"),
            .key(named: "tool", inFile: "package.json"),
            .key(named: "tool", inFile: "package.yaml"),
        ],
        localBinary: "node_modules/.bin/tool",
        workingDirectory: .marker
    )

    /// A different tool, a different ecosystem, the same three keys.
    static let gemRules = FormatterProjectRules(
        markers: [.file(".rubocop.yml"), .key(named: "rubocop", inFile: "Gemfile.yaml")],
        localBinary: "bin/rubocop",
        workingDirectory: .workspace
    )

    /// The important negative, and the reason `projectMarkers` exists. A
    /// repository that formats with `rustfmt` or `gofmt` must not have a tool
    /// from somewhere else rewrite its files just because one is installed on
    /// this machine.
    @Test func aProjectThatDeclaresNothingIsUnadopted() throws {
        let root = try makeRoot()
        try makeRepository(at: root)
        let file = try makeFile(at: root.appendingPathComponent("src/main.ts"))

        for rules in [Self.webRules, Self.gemRules] {
            let project = FormatterProject.discover(
                forFile: file.path, rules: rules, homeDirectory: unreachableHome)

            #expect(project.adoption == .unadopted)
        }
    }

    /// A tool that asks for nothing is in the opposite position: it is the
    /// only formatter its language has here, and it runs without any project
    /// saying so. That is the four compiled-in ones, and it is what an empty
    /// value has to mean for them to keep working.
    @Test func aToolThatDeclaresNothingIsUndeclared() throws {
        let root = try makeRoot()
        let file = try makeFile(at: root.appendingPathComponent("main.py"))

        let project = FormatterProject.discover(
            forFile: file.path, rules: FormatterProjectRules(), homeDirectory: unreachableHome)

        #expect(project.adoption == .undeclared)
        #expect(project.workingDirectory == file.deletingLastPathComponent().path)
    }

    /// A marker with no local binary is a project that expects a globally
    /// installed tool.
    @Test func aMarkerAloneIsEnough() throws {
        let root = try makeRoot()
        try makeRepository(at: root)
        _ = try write("{}", to: root.appendingPathComponent(".toolrc"))
        let file = try makeFile(at: root.appendingPathComponent("src/main.ts"))

        let project = FormatterProject.discover(
            forFile: file.path, rules: Self.webRules, homeDirectory: unreachableHome)

        #expect(project.markerPath == root.appendingPathComponent(".toolrc").path)
        #expect(project.rootPath == root.path)
        #expect(project.adoption == .adopted)
    }

    /// A tool installed into the project with no configuration is a project
    /// relying on the tool's defaults, which is a supported way to use one.
    /// The repository root is *inspected* and then stopped at, not stopped at
    /// before being read — an off-by-one that would miss what almost every
    /// real project has.
    @Test func aLocalBinaryAloneIsEnough() throws {
        let root = try makeRoot()
        try makeRepository(at: root)
        let binary = try write(
            "#!/bin/sh\n",
            to: root.appendingPathComponent("node_modules/.bin/tool"),
            executable: true)
        let file = try makeFile(at: root.appendingPathComponent("src/main.ts"))

        let project = FormatterProject.discover(
            forFile: file.path, rules: Self.webRules, homeDirectory: unreachableHome)

        #expect(project.localBinaryPath == binary.path)
        #expect(project.markerPath == nil)
        #expect(project.adoption == .adopted)
    }

    /// A local binary that is not executable is a broken or half-installed
    /// tree, not an installation.
    @Test func aNonExecutableLocalBinaryIsNotABinary() throws {
        let root = try makeRoot()
        try makeRepository(at: root)
        _ = try write("", to: root.appendingPathComponent("node_modules/.bin/tool"))
        let file = try makeFile(at: root.appendingPathComponent("src/main.ts"))

        let project = FormatterProject.discover(
            forFile: file.path, rules: Self.webRules, homeDirectory: unreachableHome)

        #expect(project.localBinaryPath == nil)
        #expect(project.adoption == .unadopted)
    }

    /// The second tool, same walk, its own names.
    @Test func adifferentToolFindsItsOwnMarkerAndBinary() throws {
        let root = try makeRoot()
        try makeRepository(at: root)
        let marker = try write("Style/X:\n", to: root.appendingPathComponent(".rubocop.yml"))
        let binary = try write(
            "#!/bin/sh\n", to: root.appendingPathComponent("bin/rubocop"), executable: true)
        let file = try makeFile(at: root.appendingPathComponent("app/models/user.rb"))

        let project = FormatterProject.discover(
            forFile: file.path, rules: Self.gemRules, homeDirectory: unreachableHome)

        #expect(project.markerPath == marker.path)
        #expect(project.localBinaryPath == binary.path)
        #expect(project.adoption == .adopted)
    }

    /// One tool's marker says nothing about another tool.
    @Test func oneToolsMarkerDoesNotAdoptTheOther() throws {
        let root = try makeRoot()
        try makeRepository(at: root)
        _ = try write("{}", to: root.appendingPathComponent(".toolrc"))
        let file = try makeFile(at: root.appendingPathComponent("app/models/user.rb"))

        let project = FormatterProject.discover(
            forFile: file.path, rules: Self.gemRules, homeDirectory: unreachableHome)

        #expect(project.adoption == .unadopted)
    }

    // MARK: The key inside a manifest

    @Test func aManifestCarryingTheKeyIsAMarker() throws {
        let root = try makeRoot()
        try makeRepository(at: root)
        let manifest = try write(
            #"{"name":"x","tool":{"semi":false}}"#,
            to: root.appendingPathComponent("package.json"))
        let file = try makeFile(at: root.appendingPathComponent("index.js"))

        let project = FormatterProject.discover(
            forFile: file.path, rules: Self.webRules, homeDirectory: unreachableHome)

        #expect(project.markerPath == manifest.path)
    }

    /// The value is legally a string naming another file, and that counts too.
    /// What is being asked is whether the author declared the tool here.
    @Test func theValueIsNotInspected() throws {
        let root = try makeRoot()
        try makeRepository(at: root)
        _ = try write(
            #"{"tool":"./my-config.json"}"#, to: root.appendingPathComponent("package.json"))
        let file = try makeFile(at: root.appendingPathComponent("index.js"))

        #expect(
            FormatterProject.discover(
                forFile: file.path, rules: Self.webRules, homeDirectory: unreachableHome
            ).adoption == .adopted)
    }

    /// Nearly every JavaScript project has a `package.json`. Treating its mere
    /// presence as adoption would format every Node repository on the machine.
    @Test func aManifestWithoutTheKeyIsNotAMarker() throws {
        let root = try makeRoot()
        try makeRepository(at: root)
        _ = try write(
            #"{"name":"x","devDependencies":{"eslint":"^9"}}"#,
            to: root.appendingPathComponent("package.json"))
        let file = try makeFile(at: root.appendingPathComponent("index.js"))

        let project = FormatterProject.discover(
            forFile: file.path, rules: Self.webRules, homeDirectory: unreachableHome)

        #expect(project.markerPath == nil)
        #expect(project.adoption == .unadopted)
    }

    /// A file somebody is mid-edit on. Guessing at a broken one is how a
    /// formatter starts running where it was not wanted.
    @Test func aMalformedManifestIsNotAMarker() throws {
        let root = try makeRoot()
        try makeRepository(at: root)
        _ = try write(#"{"tool": {"#, to: root.appendingPathComponent("package.json"))
        let file = try makeFile(at: root.appendingPathComponent("index.js"))

        #expect(
            FormatterProject.discover(
                forFile: file.path, rules: Self.webRules, homeDirectory: unreachableHome
            ).adoption == .unadopted)
    }

    /// A manifest in a format nothing here parses answers "no", which leaves
    /// the file alone instead of having something else reformat it.
    @Test func aManifestInAnUnreadableFormatIsNotAMarker() throws {
        let root = try makeRoot()
        _ = try write("[tool]\nsemi = false\n", to: root.appendingPathComponent("Cargo.toml"))

        #expect(
            !FormatterProject.declares(
                "tool", inFileAt: root.appendingPathComponent("Cargo.toml").path))
    }

    // MARK: The key inside a YAML manifest

    @Test func aTopLevelKeyInYAMLDeclaresTheProject() throws {
        let root = try makeRoot()
        let manifest = try write(
            "name: x\ntool:\n  semi: false\n", to: root.appendingPathComponent("package.yaml"))

        #expect(FormatterProject.declares("tool", inFileAt: manifest.path))
    }

    /// The distinction JSON gives for free: a dev dependency is indented under
    /// another key, and it is not a declaration that this project is
    /// configured here. Reading it as one would reformat files in a repository
    /// that merely has the tool in its lockfile.
    @Test func adependencyIsNotADeclaration() throws {
        let root = try makeRoot()
        let manifest = try write(
            "name: x\ndevDependencies:\n  tool: ^3.6.0\n  eslint: ^9\n",
            to: root.appendingPathComponent("package.yaml"))

        #expect(!FormatterProject.declares("tool", inFileAt: manifest.path))
    }

    @Test(arguments: [
        "tool:",
        "tool: {}",
        "tool :",
        "\"tool\":",
        "'tool':",
    ])
    func theShapesThatCount(line: String) {
        #expect(FormatterProject.declaresTopLevelKey("tool", in: line), "\(line)")
    }

    @Test(arguments: [
        "  tool:",
        "\ttool:",
        "toolrc:",
        "tool",
        "my-tool:",
        "# tool:",
    ])
    func theShapesThatDoNot(line: String) {
        #expect(!FormatterProject.declaresTopLevelKey("tool", in: line), "\(line)")
    }

    /// The order the manifest wrote is the order of preference, so a project
    /// carrying both reports the one the tool itself would prefer.
    @Test func theFirstDeclaredMarkerWins() throws {
        let root = try makeRoot()
        _ = try write(#"{"tool":{}}"#, to: root.appendingPathComponent("package.json"))
        _ = try write("tool:\n", to: root.appendingPathComponent("package.yaml"))

        #expect(
            FormatterProject.marker(in: root, rules: Self.webRules)
                == root.appendingPathComponent("package.json").path)
    }

    // MARK: The walk

    /// The monorepo shape: the package declares the configuration, the root
    /// holds the hoisted binary. Stopping at whichever came first would report
    /// only one of them, and which one would depend on the layout.
    @Test func theMarkerAndTheBinaryAreCollectedOnOnePass() throws {
        let root = try makeRoot()
        try makeRepository(at: root)
        let binary = try write(
            "#!/bin/sh\n",
            to: root.appendingPathComponent("node_modules/.bin/tool"),
            executable: true)
        let package = root.appendingPathComponent("packages/app")
        let marker = try write("{}", to: package.appendingPathComponent(".toolrc.json"))
        let file = try makeFile(at: package.appendingPathComponent("src/main.ts"))

        let project = FormatterProject.discover(
            forFile: file.path, rules: Self.webRules, homeDirectory: unreachableHome)

        #expect(project.markerPath == marker.path)
        #expect(project.localBinaryPath == binary.path)
        #expect(project.rootPath == root.path)
    }

    /// The nearer marker is the one that describes this file.
    @Test func theNearestMarkerWins() throws {
        let root = try makeRoot()
        try makeRepository(at: root)
        _ = try write("{}", to: root.appendingPathComponent(".toolrc"))
        let package = root.appendingPathComponent("packages/app")
        let nearer = try write("{}", to: package.appendingPathComponent(".toolrc"))
        let file = try makeFile(at: package.appendingPathComponent("main.ts"))

        #expect(
            FormatterProject.discover(
                forFile: file.path, rules: Self.webRules, homeDirectory: unreachableHome
            ).markerPath == nearer.path)
    }

    /// A configuration outside the repository was not written for a file its
    /// author has never seen.
    @Test func theWalkStopsAtTheRepositoryRoot() throws {
        let outer = try makeRoot()
        _ = try write("{}", to: outer.appendingPathComponent(".toolrc"))
        let repository = outer.appendingPathComponent("repo")
        try makeRepository(at: repository)
        let file = try makeFile(at: repository.appendingPathComponent("src/main.ts"))

        let project = FormatterProject.discover(
            forFile: file.path, rules: Self.webRules, homeDirectory: unreachableHome)

        #expect(project.markerPath == nil)
        #expect(project.rootPath == repository.path)
    }

    /// `.git` is a *file* in a worktree or a submodule — the checkouts people
    /// do parallel work in. Requiring a directory would walk straight past
    /// them into whatever is above.
    @Test func aWorktreeWhoseGitIsAFileStillStopsTheWalk() throws {
        let outer = try makeRoot()
        _ = try write("{}", to: outer.appendingPathComponent(".toolrc"))
        let worktree = outer.appendingPathComponent("wt")
        _ = try write(
            "gitdir: /somewhere/.git/worktrees/wt\n", to: worktree.appendingPathComponent(".git"))
        let file = try makeFile(at: worktree.appendingPathComponent("src/main.ts"))

        let project = FormatterProject.discover(
            forFile: file.path, rules: Self.webRules, homeDirectory: unreachableHome)

        #expect(project.markerPath == nil)
        #expect(project.rootPath == worktree.path)
    }

    /// Outside a repository the walk still has to stop somewhere, and the
    /// directories above `~` are shared — on a work machine, not always the
    /// user's. A configuration up there would decide how to rewrite their
    /// buffer.
    @Test func theWalkStopsAtHome() throws {
        let outer = try makeRoot()
        _ = try write("{}", to: outer.appendingPathComponent(".toolrc"))
        let home = outer.appendingPathComponent("home")
        let file = try makeFile(at: home.appendingPathComponent("scratch/main.ts"))

        let project = FormatterProject.discover(
            forFile: file.path, rules: Self.webRules, homeDirectory: home.path)

        #expect(project.markerPath == nil)
        #expect(project.rootPath == home.path)
    }

    /// Home is inspected before it stops the walk, same as a repository root.
    @Test func aMarkerInHomeItselfIsFound() throws {
        let home = try makeRoot()
        let marker = try write("{}", to: home.appendingPathComponent(".toolrc"))
        let file = try makeFile(at: home.appendingPathComponent("scratch/main.ts"))

        #expect(
            FormatterProject.discover(
                forFile: file.path, rules: Self.webRules, homeDirectory: home.path
            ).markerPath == marker.path)
    }

    /// Neither boundary reachable: the walk still terminates, and reports that
    /// it never found a root rather than pretending `/` was one.
    @Test func aWalkWithNoBoundaryStillTerminates() throws {
        let root = try makeRoot()
        let file = try makeFile(at: root.appendingPathComponent("a/b/main.ts"))

        let project = FormatterProject.discover(
            forFile: file.path, rules: Self.webRules, homeDirectory: unreachableHome)

        #expect(project.rootPath == nil)
        #expect(project.adoption == .unadopted)
    }

    /// The path is arbitrary user input, so the walk is bounded independently
    /// of what it finds.
    @Test func theDepthLimitStopsTheWalk() throws {
        let root = try makeRoot()
        try makeRepository(at: root)
        _ = try write("{}", to: root.appendingPathComponent(".toolrc"))
        let file = try makeFile(at: root.appendingPathComponent("a/b/c/main.ts"))

        let shallow = FormatterProject.discover(
            forFile: file.path, rules: Self.webRules, homeDirectory: unreachableHome,
            maximumDepth: 2)

        #expect(shallow.markerPath == nil)
        #expect(shallow.rootPath == nil)

        let full = FormatterProject.discover(
            forFile: file.path, rules: Self.webRules, homeDirectory: unreachableHome)

        #expect(full.markerPath != nil)
    }

    /// A tool that declares nothing pays for no `stat` calls at all — the
    /// walk is skipped, which is what keeps the compiled-in four as cheap as
    /// they were.
    @Test func aToolThatDeclaresNothingSkipsTheWalk() throws {
        let root = try makeRoot()
        try makeRepository(at: root)
        let file = try makeFile(at: root.appendingPathComponent("a/b/main.py"))

        let project = FormatterProject.discover(
            forFile: file.path, rules: FormatterProjectRules(), homeDirectory: unreachableHome)

        #expect(project.rootPath == nil)
        #expect(project.markerPath == nil)
    }

    // MARK: Where the tool runs

    /// Beside the marker, so that a `plugins` entry resolves relative to the
    /// configuration that named it, and a monorepo package that formats
    /// differently from its root is not run from the root.
    @Test func theMarkerDirectoryIsTheWorkingDirectory() throws {
        let root = try makeRoot()
        try makeRepository(at: root)
        let package = root.appendingPathComponent("packages/app")
        _ = try write("{}", to: package.appendingPathComponent(".toolrc"))
        let file = try makeFile(at: package.appendingPathComponent("main.ts"))

        #expect(
            FormatterProject.discover(
                forFile: file.path, rules: Self.webRules, homeDirectory: unreachableHome
            ).workingDirectory == package.path)
    }

    @Test func theWorkspaceIsTheWorkingDirectoryForAToolThatAsksForIt() throws {
        let root = try makeRoot()
        try makeRepository(at: root)
        _ = try write("Style/X:\n", to: root.appendingPathComponent(".rubocop.yml"))
        let file = try makeFile(at: root.appendingPathComponent("app/models/user.rb"))

        #expect(
            FormatterProject.discover(
                forFile: file.path, rules: Self.gemRules, homeDirectory: unreachableHome
            ).workingDirectory == root.path)
    }

    /// Nothing found, so nothing to be beside. The file's own directory is the
    /// fallback rather than nowhere: running a formatter from wherever the app
    /// happens to be is never the better answer.
    @Test func theFilesDirectoryIsTheFallback() throws {
        let root = try makeRoot()
        let file = try makeFile(at: root.appendingPathComponent("a/main.ts"))

        for rules in [Self.webRules, Self.gemRules] {
            let project = FormatterProject.discover(
                forFile: file.path, rules: rules, homeDirectory: unreachableHome)

            #expect(project.workingDirectory == file.deletingLastPathComponent().path)
        }
    }

    // MARK: Building trees

    /// A home that no temporary tree is ever under, so the tests that are not
    /// about the home boundary are not accidentally about it.
    private var unreachableHome: String { "/nonexistent-home-\(UUID().uuidString)" }

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phantom-formatter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeRepository(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent(".git"), withIntermediateDirectories: true)
    }

    private func makeFile(at url: URL) throws -> URL {
        try write("const a = 1;\n", to: url)
    }

    @discardableResult
    private func write(_ contents: String, to url: URL, executable: Bool = false) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        if executable {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        return url
    }
}

/// Reading the three keys out of a manifest.
///
/// The parse is where a third-party file stops being text, so the shapes that
/// must not survive it are pinned here: a path that climbs out of the tree it
/// is resolved against, and a working directory nobody implements.
struct FormatterProjectRulesParsingTests {
    private func rules(_ json: [String: Any]) -> FormatterProjectRules {
        FormatterContribution.projectRules(json: json)
    }

    @Test func theThreeKeysAreRead() {
        let parsed = rules([
            "projectMarkers": [
                ".prettierrc",
                ["file": "package.json", "containsKey": "prettier"],
            ],
            "localBinary": "node_modules/.bin/prettier",
            "workingDirectory": "marker",
        ])

        #expect(parsed.markers == [
            .file(".prettierrc"),
            .key(named: "prettier", inFile: "package.json"),
        ])
        #expect(parsed.localBinary == "node_modules/.bin/prettier")
        #expect(parsed.workingDirectory == .marker)
    }

    /// A manifest that says none of it describes a tool that simply formats,
    /// which is what every entry in the compiled-in table is.
    @Test func anEmptyManifestAsksForNothing() {
        let parsed = rules([:])

        #expect(parsed.markers.isEmpty)
        #expect(parsed.localBinary == nil)
        #expect(parsed.workingDirectory == .file)
        #expect(!parsed.declaresAdoption)
        #expect(!parsed.needsWalk)
    }

    /// These resolve against the reader's project, not against the extension's
    /// own directory, so the containment check the rest of the manifest gets
    /// cannot be applied. The shape is checked instead, and strictly.
    @Test(arguments: [
        "/etc/passwd",
        "~/.ssh/id_rsa",
        "../../../usr/bin/tool",
        "node_modules/../../tool",
        "./tool",
        "",
        "a//b",
    ])
    func aPathThatClimbsOutIsRefused(path: String) {
        #expect(rules(["localBinary": path]).localBinary == nil, "\(path)")
        #expect(rules(["projectMarkers": [path]]).markers.isEmpty, "\(path)")
    }

    /// Lenient one entry at a time, the way the rest of the manifest is: a
    /// list with one bad name in it loses that name, not the list.
    @Test func oneBadMarkerCostsThatMarker() {
        let parsed = rules(["projectMarkers": [".toolrc", "/etc/passwd", 7, [:], ".toolrc.json"]])

        #expect(parsed.markers == [.file(".toolrc"), .file(".toolrc.json")])
    }

    @Test func aMarkerObjectNeedsBothHalves() {
        #expect(rules(["projectMarkers": [["file": "package.json"]]]).markers.isEmpty)
        #expect(rules(["projectMarkers": [["containsKey": "tool"]]]).markers.isEmpty)
    }

    /// An unknown working directory falls back to the file's own rather than
    /// costing the whole contribution, which is how the rest of the manifest
    /// treats a field it cannot read.
    @Test func anUnknownWorkingDirectoryFallsBack() {
        #expect(rules(["workingDirectory": "elsewhere"]).workingDirectory == .file)
        #expect(rules(["workingDirectory": 7]).workingDirectory == .file)
    }

    @Test func theMarkerListIsBounded() {
        let many = (0..<(FormatterContribution.maxMarkers * 2)).map { ".toolrc\($0)" }

        #expect(rules(["projectMarkers": many]).markers.count == FormatterContribution.maxMarkers)
    }

    /// The keys ride on the contribution the catalog builds a runnable
    /// formatter from, so a manifest that declares them reaches the runner.
    @Test func theKeysSurviveIntoTheContribution() throws {
        let contribution = try #require(FormatterContribution.parse(json: [
            "id": "tool",
            "name": "Tool",
            "command": "tool",
            "extensions": ["ts"],
            "projectMarkers": [".toolrc"],
            "localBinary": "node_modules/.bin/tool",
            "workingDirectory": "workspace",
        ]))

        #expect(contribution.projectRules.markers == [.file(".toolrc")])
        #expect(contribution.projectRules.localBinary == "node_modules/.bin/tool")
        #expect(contribution.projectRules.workingDirectory == .workspace)
    }
}
