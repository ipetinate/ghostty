import Foundation
@testable import Ghostty
import Testing

struct ExtensionViewHostBundleTests {
    private struct Staged {
        let descriptor: ExtensionViewDescriptor
        let root: URL
        let package: URL
    }

    private func staged(withStyle: Bool = true, entry: String = "export default 1") throws -> Staged {
        let fileManager = FileManager.default
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("host-" + UUID().uuidString, isDirectory: true)
        let package = temporary.appendingPathComponent("package", isDirectory: true)
        let root = temporary.appendingPathComponent("cache", isDirectory: true)
        try fileManager.createDirectory(at: package.appendingPathComponent("views", isDirectory: true),
                                        withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(entry.utf8).write(to: package.appendingPathComponent("views/http.js"))
        try Data(":root {}".utf8).write(to: package.appendingPathComponent("views/http.css"))
        try Data("png".utf8).write(to: package.appendingPathComponent("views/http.png"))

        let contribution = ExtensionViewContribution(
            viewID: "http",
            title: "HTTP",
            icon: package.appendingPathComponent("views/http.png"),
            entry: package.appendingPathComponent("views/http.js"),
            style: withStyle ? package.appendingPathComponent("views/http.css") : nil,
            placements: [.sidebar, .topBar],
            permissions: [.httpRequest]
        )
        return Staged(
            descriptor: ExtensionViewDescriptor(
                extensionID: "ipetinate.bruno", extensionName: "Bruno",
                root: package, contribution: contribution),
            root: root,
            package: package)
    }

    @Test func stagesThePageBesideTheBundleItLoads() throws {
        let subject = try staged()
        let host = try ExtensionViewHostBundle.stage(subject.descriptor, root: subject.root)
        let directory = host.deletingLastPathComponent()

        #expect(host.lastPathComponent == ExtensionViewHostBundle.hostFileName)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)) == [
            ExtensionViewHostBundle.hostFileName,
            ExtensionViewHostBundle.bridgeFileName,
            ExtensionViewHostBundle.entryFileName,
            ExtensionViewHostBundle.styleFileName,
        ])
        #expect(try String(contentsOf: directory.appendingPathComponent(ExtensionViewHostBundle.entryFileName),
                           encoding: .utf8) == "export default 1")
    }

    /// Nothing of the extension's own directory is in the staged directory,
    /// which is the whole reason for staging: `allowingReadAccessTo` grants a
    /// directory, so the directory has to hold only what the page may read.
    @Test func stagesNothingElseFromThePackage() throws {
        let subject = try staged()
        try Data("secret".utf8).write(to: subject.package.appendingPathComponent("token.txt"))

        let host = try ExtensionViewHostBundle.stage(subject.descriptor, root: subject.root)
        let names = try FileManager.default.contentsOfDirectory(atPath: host.deletingLastPathComponent().path)
        #expect(!names.contains("token.txt"))
        #expect(!names.contains("views"))
    }

    @Test func aViewWithNoStylesheetLinksNone() throws {
        let subject = try staged(withStyle: false)
        let host = try ExtensionViewHostBundle.stage(subject.descriptor, root: subject.root)
        let page = try String(contentsOf: host, encoding: .utf8)

        #expect(!page.contains(ExtensionViewHostBundle.styleFileName))
        #expect(!FileManager.default.fileExists(
            atPath: host.deletingLastPathComponent()
                .appendingPathComponent(ExtensionViewHostBundle.styleFileName).path))
    }

    @Test func thePageCarriesThePolicyAndLoadsTheBridgeFirst() throws {
        let subject = try staged()
        let host = try ExtensionViewHostBundle.stage(subject.descriptor, root: subject.root)
        let page = try String(contentsOf: host, encoding: .utf8)

        #expect(page.contains(ExtensionViewHostBundle.contentSecurityPolicy))
        #expect(page.contains("default-src 'none'"))

        let bridge = try #require(page.range(of: ExtensionViewHostBundle.bridgeFileName))
        let entry = try #require(page.range(of: ExtensionViewHostBundle.entryFileName))
        #expect(bridge.lowerBound < entry.lowerBound)
    }

    /// Nothing in the policy names an `http` or `https` source, at any
    /// directive. That is what makes `http.request` the only way out.
    @Test func thePolicyNamesNoNetworkSource() {
        #expect(!ExtensionViewHostBundle.contentSecurityPolicy.contains("http:"))
        #expect(!ExtensionViewHostBundle.contentSecurityPolicy.contains("https:"))
        #expect(!ExtensionViewHostBundle.contentSecurityPolicy.contains("*"))
        #expect(!ExtensionViewHostBundle.contentSecurityPolicy.contains("unsafe-inline"))
        #expect(!ExtensionViewHostBundle.contentSecurityPolicy.contains("unsafe-eval"))
    }

    @Test func restagesOnlyWhenTheBytesChanged() throws {
        let subject = try staged()
        let host = try ExtensionViewHostBundle.stage(subject.descriptor, root: subject.root)
        let entry = host.deletingLastPathComponent()
            .appendingPathComponent(ExtensionViewHostBundle.entryFileName)
        let first = try #require((try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate)

        _ = try ExtensionViewHostBundle.stage(subject.descriptor, root: subject.root)
        #expect((try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate == first)

        try Data("export default 2".utf8).write(to: subject.package.appendingPathComponent("views/http.js"))
        _ = try ExtensionViewHostBundle.stage(subject.descriptor, root: subject.root)
        #expect(try String(contentsOf: entry, encoding: .utf8) == "export default 2")
    }

    /// A view that stops shipping a stylesheet must not keep the one from
    /// the version that did.
    @Test func dropsAFileThePackageNoLongerShips() throws {
        let subject = try staged()
        _ = try ExtensionViewHostBundle.stage(subject.descriptor, root: subject.root)

        let without = try staged(withStyle: false)
        let moved = ExtensionViewDescriptor(
            extensionID: subject.descriptor.extensionID,
            extensionName: subject.descriptor.extensionName,
            root: without.package,
            contribution: without.descriptor.contribution)
        let host = try ExtensionViewHostBundle.stage(moved, root: subject.root)

        #expect(!Set(try FileManager.default.contentsOfDirectory(atPath: host.deletingLastPathComponent().path))
            .contains(ExtensionViewHostBundle.styleFileName))
    }

    @Test func refusesABundleOverTheLimit() throws {
        let subject = try staged(
            entry: String(repeating: "x", count: ExtensionViewHostBundle.maxBundleBytes + 1))
        #expect(throws: (any Error).self) {
            try ExtensionViewHostBundle.stage(subject.descriptor, root: subject.root)
        }
    }

    /// Two pairs must never name one directory. `<id>-<view>` would let
    /// `a-b` + `c` and `a` + `b-c` collide, because an extension id may hold
    /// a dash.
    @Test func onePairIsOneDirectory() throws {
        let subject = try staged()
        let contribution = subject.descriptor.contribution
        let first = ExtensionViewHostBundle.directory(
            for: ExtensionViewDescriptor(extensionID: "a-b", extensionName: "", root: subject.package,
                                         contribution: contribution),
            root: subject.root)
        let second = ExtensionViewHostBundle.directory(
            for: ExtensionViewDescriptor(extensionID: "a", extensionName: "", root: subject.package,
                                         contribution: contribution),
            root: subject.root)
        #expect(first.standardizedFileURL != second.standardizedFileURL)
    }

    // MARK: The registry

    @Test func aViewIsOneDescriptorPerExtension() throws {
        let subject = try staged()
        let installed = InstalledExtension(
            id: "ipetinate.bruno", name: "Bruno", version: "1.1.0", root: subject.package,
            views: [subject.descriptor.contribution])

        let descriptors = ExtensionViewRegistry.descriptors(in: [installed])
        #expect(descriptors.count == 1)
        #expect(descriptors.first?.id == "ipetinate.bruno/http")
        #expect(descriptors.first?.title == "HTTP")
    }

    @Test func aPaneCarriesTheViewItDraws() throws {
        let subject = try staged()
        let pane = SidebarPane.view(subject.descriptor.id)

        #expect(pane.contributedViewID == "ipetinate.bruno/http")
        #expect(pane.canBeHidden)
        #expect(pane.defaultsKey == "SidebarShowExtensionView.ipetinate.bruno/http")
        #expect(SidebarPane.terminals.contributedViewID == nil)
        #expect(SidebarPane.git.contributedViewID == nil)
        #expect(!SidebarPane.builtIns.contains(pane))
    }

    @Test func aContributedPaneWearsItsOwnArtwork() throws {
        let subject = try staged()
        let item = SidebarPaneItem(subject.descriptor)

        #expect(item.artwork == subject.descriptor.icon)
        #expect(item.title == "HTTP")
        #expect(SidebarPaneItem(.git).artwork == nil)
    }
}
