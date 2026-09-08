import Foundation
@testable import Ghostty
import Testing

/// What the JSON server is told about schemas, and — the invariant worth a
/// test — that the files this build calls JSON by name are files it can
/// actually complete.
///
/// Mapping `.prettierrc` to the JSON server and then never telling that
/// server what a `.prettierrc` is would be the whole feature done and none
/// of it delivered: the reader gets brace matching on a file that has a
/// published schema.
struct JSONSchemaAssociationsTests {
    /// Keyed on the **command**, not on the `json` language id. That id is
    /// one an extension may bring its own server for, and that server would
    /// be sent a notification it has no handler for — which some servers log
    /// as an error and a few refuse the connection over.
    @Test func onlyTheJSONServerIsSentAssociations() {
        func server(_ command: String, languageID: String) -> LSPServerDefinition {
            LSPServerDefinition(
                languageID: languageID,
                displayName: command,
                command: command,
                arguments: ["--stdio"],
                installHint: ""
            )
        }

        #expect(JSONSchemaAssociations.payload(
            for: server(JSONSchemaAssociations.serverCommand, languageID: "json")) != nil)
        #expect(JSONSchemaAssociations.payload(
            for: server("yaml-language-server", languageID: "yaml")) == nil)
        #expect(JSONSchemaAssociations.payload(
            for: server("typescript-language-server", languageID: "typescript")) == nil)

        /// The near miss the keying exists for: some other extension's server
        /// claiming the `json` id is sent nothing.
        #expect(JSONSchemaAssociations.payload(
            for: server("acme-json-ls", languageID: "json")) == nil)
    }

    /// The server fetches these itself, so anything but `https` would be
    /// either a request Phantom would have to answer or a schema that never
    /// loads.
    @Test func everySchemaIsAnHTTPSURL() {
        for (pattern, address) in JSONSchemaAssociations.schemasByFilePattern {
            let url = URL(string: address)

            #expect(url != nil, "\(pattern) has an unparseable schema address")
            #expect(url?.scheme == "https", "\(pattern) is not served over https")
        }
    }

    /// One array of URLs per pattern — the shape the server folds back into
    /// `{uri, fileMatch}`. A bare string per pattern parses and is then
    /// silently dropped, because the handler only reads arrays.
    @Test func thePayloadIsOneArrayPerPattern() throws {
        let object = try #require(JSONSchemaAssociations.payload.objectValue)

        #expect(object.count == JSONSchemaAssociations.schemasByFilePattern.count)
        for (pattern, value) in object {
            let addresses = try #require(value.arrayValue, "\(pattern) is not an array")
            #expect(addresses.count == 1)
            #expect(addresses.first?.stringValue == JSONSchemaAssociations.schemasByFilePattern[pattern])
        }
    }

    /// The files that prompted the feature, including the two a Vite
    /// project splits its TypeScript configuration into — which is why the
    /// pattern is `tsconfig*.json` and not a list of names somebody has to
    /// keep adding to.
    @Test func theFilesAProjectActuallyContainsAreCovered() {
        let covered = [
            "tsconfig.json", "tsconfig.app.json", "tsconfig.node.json",
            "package.json", ".prettierrc", ".eslintrc", ".babelrc", ".swcrc",
        ]

        for name in covered {
            #expect(Self.schemaPattern(matching: name) != nil, "\(name) has no schema")
        }
    }

    /// The rc files an extension may call JSON each have a schema, so the
    /// pair added in one change cannot half-rot in the next.
    static let jsonRCFiles = [
        ".prettierrc", ".babelrc", ".eslintrc", ".jscsrc", ".jshintrc", ".swcrc",
    ]

    @Test func everyNamedJSONFileHasASchema() {
        for name in Self.jsonRCFiles {
            #expect(Self.schemaPattern(matching: name) != nil, "\(name) has no schema")
        }
    }

    /// A file that is not JSON must not be handed one, and `.npmrc` is the
    /// near miss: same folder, same shape of name, INI inside.
    @Test func aFileThatIsNotJSONGetsNoSchema() {
        #expect(Self.schemaPattern(matching: ".npmrc") == nil)
        #expect(Self.schemaPattern(matching: "tsconfig.json.bak") == nil)
    }

    /// `LIKE` reads `*` and `?` as globs and everything else literally,
    /// which is close enough to what the server does with these patterns to
    /// answer "is this name covered" — the server prefixes `**/`, and every
    /// name here is a bare one.
    private static func schemaPattern(matching name: String) -> String? {
        JSONSchemaAssociations.schemasByFilePattern.keys.first { pattern in
            NSPredicate(format: "SELF LIKE %@", pattern).evaluate(with: name)
        }
    }
}
