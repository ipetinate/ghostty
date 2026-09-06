import Foundation
@testable import Ghostty
import Testing

/// Resolving a project's `tsdk` — one of the two pieces of
/// `initializationOptions` this app still builds itself, for a server whose
/// manifest asked for it by name.
///
/// `searchPath` is always passed explicitly here rather than left to
/// resolve from the login shell: a test that shells out to whatever `npm`
/// happens to be on the machine running it would pass or fail depending on
/// the developer's own setup, which is exactly the nondeterminism a test
/// exists to rule out.
@MainActor
struct LSPInitializationOptionsTests {
    private func makeDirectory() -> String {
        let directory = NSTemporaryDirectory() + "phantom-tsdk-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        return directory
    }

    /// The project's own copy wins over the global one, so a workspace that
    /// pins a version is checked against that version.
    @Test func aProjectLocalTypeScriptWinsOverTheGlobalOne() {
        let root = makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let local = root + "/node_modules/typescript/lib"
        try? FileManager.default.createDirectory(atPath: local, withIntermediateDirectories: true)

        // An empty search path means `npm` itself can never be found, so a
        // success here can only have come from the local check.
        switch LSPInitializationOptions.typeScriptSDK(root: root, searchPath: "") {
        case .success(let path): #expect(path == local)
        case .failure(let reason): Issue.record("expected the local path, got failure: \(reason)")
        }
    }

    /// Neither a local install nor a resolvable `npm` on `PATH` produces the
    /// concrete message this feature exists to show instead of silence.
    @Test func neitherLocalNorGlobalProducesTheNamedFailure() {
        let root = makeDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }

        switch LSPInitializationOptions.typeScriptSDK(root: root, searchPath: "") {
        case .success(let path): Issue.record("expected failure, got a path: \(path)")
        case .failure(let reason): #expect(reason == LSPInitializationOptions.missingTypeScriptMessage)
        }
    }

    /// The value shape the servers that read a `tsdk` specify: nested under
    /// `typescript`, not sent as a bare string.
    @Test func theValueNestsTsdkUnderTypescript() {
        let value = LSPInitializationOptions.sdkValue(tsdk: "/path/to/lib")
        #expect(value["typescript"]?["tsdk"]?.stringValue == "/path/to/lib")
    }

    // MARK: The options a manifest writes out literally

    /// The formatter flag the three `vscode-langservers-extracted` servers
    /// keep switched off, which used to be a compiled-in resolver of its own.
    ///
    /// Measured: with `{"provideFormatter": true}`, each of the three answers
    /// `initialize` with `documentFormattingProvider: true`; without it, all
    /// three say false. It is data, so after 0.17.0 the extension declaring
    /// the server writes it out and this build only has to carry it through
    /// unchanged — which is the whole path asserted here, from the manifest
    /// to the value `initialize` is sent.
    @Test func aLiteralOptionSurvivesFromTheManifestToTheValueSent() throws {
        let root = URL(fileURLWithPath: "/tmp/phantom-initoptions").appendingPathComponent("acme.json")
        let json = #"""
        {
          "schemaVersion": 1,
          "id": "acme.json",
          "name": "JSON",
          "version": "1.0.0",
          "publisher": "acme",
          "contributes": {
            "languages": [{
              "languageId": "json",
              "extensions": ["json"],
              "server": {
                "command": "vscode-json-language-server",
                "args": ["--stdio"],
                "initializationOptions": { "provideFormatter": true }
              }
            }]
          }
        }
        """#
        let manifest = try #require(LanguageManifest.parse(
            data: Data(json.utf8),
            url: root.appendingPathComponent(LanguageManifest.fileName),
            root: root,
            scope: .user
        ))

        let catalog = LanguageCatalog.resolve(manifests: [manifest], promotions: [])
        let definition = try #require(catalog.contributed.first?.serverDefinition)

        /// `.none` is what makes the literal the answer: a server that asked
        /// for a resolver asked this app to compute the value instead, and
        /// two sources for one field is a question nobody should have to
        /// answer while reading a launch.
        #expect(definition.initializationOptionsKind == .none)

        let declared = try #require(definition.initializationOptionsJSON)
        guard case .success(let value) = LSPCenter.parseInitializationOptions(declared) else {
            Issue.record("the declared options did not parse: \(declared)")
            return
        }
        #expect(value["provideFormatter"]?.boolValue == true)
    }

    /// Text that is not JSON is refused with a sentence rather than sent as
    /// nothing. A server handed nothing starts and answers wrongly; a reader
    /// told which file is unparseable can fix it.
    @Test func optionsThatAreNotJSONAreRefusedWithASentence() {
        guard case .failure(let reason) = LSPCenter.parseInitializationOptions("not json at all")
        else {
            Issue.record("unparseable text was accepted as initializationOptions")
            return
        }
        #expect(reason.contains("initializationOptions"))
    }
}
