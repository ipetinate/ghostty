import Foundation
@testable import Ghostty
import Testing

/// What a server says when it will not volunteer a file's problems.
///
/// The payloads below came off a live `vscode-eslint-language-server` 4.10.0
/// over stdio, against a flat-config TypeScript project, and not from the
/// specification. The specification permits several shapes and says nothing
/// about which ones servers send; the ones they send are the ones a client
/// has to read, and this server's shape is the reason pull diagnostics exist
/// in this app at all — it answers `textDocument/diagnostic` and calls
/// `sendDiagnostics` nowhere.
struct LSPDiagnosticCapabilityTests {
    /// Verbatim from that server's `initialize` result.
    private let eslint: LSPValue = [
        "textDocumentSync": [
            "openClose": .bool(true),
            "change": .integer(2),
        ],
        "executeCommandProvider": [
            "commands": .array([.string("eslint.applyAllFixes")]),
        ],
        "diagnosticProvider": [
            "identifier": .string("eslint"),
            "interFileDependencies": .bool(false),
            "workspaceDiagnostics": .bool(false),
        ],
        "codeActionProvider": [
            "codeActionKinds": .array([.string("quickfix"), .string("source.fixAll.eslint")]),
        ],
    ]

    @Test func theObjectFormIsReadWhole() {
        let capability = LSPDiagnosticCapability(eslint)

        #expect(capability.isDeclared)
        #expect(capability.identifier == "eslint")
        #expect(capability.interFileDependencies == false)
        #expect(capability.workspaceDiagnostics == false)
    }

    /// A server that never mentioned diagnostics pushes them, and asking it
    /// to pull is a request it will answer with an error.
    @Test func aServerThatSaidNothingDoesNotPull() {
        let capability = LSPDiagnosticCapability([
            "hoverProvider": .bool(true),
            "completionProvider": ["triggerCharacters": .array([.string(".")])],
        ])

        #expect(capability == .none)
        #expect(capability.isDeclared == false)
    }

    /// The subtree, handed in by mistake, must not read as a server that
    /// offers everything. Same guard as `LSPCompletionCapability`: this
    /// takes the whole `capabilities` object.
    @Test func theProviderSubtreeAloneIsNotACapability() {
        #expect(LSPDiagnosticCapability(["identifier": .string("eslint")]) == .none)
    }

    @Test func nilIsAServerThatIsNotRunning() {
        #expect(LSPDiagnosticCapability(nil) == .none)
    }

    /// An explicit `false` is a refusal, not a declaration with no fields.
    @Test func aRefusalIsNotADeclaration() {
        #expect(LSPDiagnosticCapability(["diagnosticProvider": .bool(false)]).isDeclared == false)
    }

    /// The specification gives this capability as an object, so a bare
    /// `true` is not a shape to expect — but reading it as a refusal would
    /// classify a server that pulls as one that pushes, which is silence.
    @Test func abareTrueDeclaresWithNoFields() {
        let capability = LSPDiagnosticCapability(["diagnosticProvider": .bool(true)])

        #expect(capability.isDeclared)
        #expect(capability.identifier == nil)
        #expect(capability.interFileDependencies == false)
        #expect(capability.workspaceDiagnostics == false)
    }

    /// The two flags that change what this client does with the answer.
    /// `interFileDependencies` is what makes a change to one file re-pull
    /// the others.
    @Test func theInterFileFlagsAreReadFromTheProvider() {
        let capability = LSPDiagnosticCapability([
            "diagnosticProvider": [
                "identifier": .string("rustAnalyzer"),
                "interFileDependencies": .bool(true),
                "workspaceDiagnostics": .bool(true),
            ],
        ])

        #expect(capability.identifier == "rustAnalyzer")
        #expect(capability.interFileDependencies)
        #expect(capability.workspaceDiagnostics)
    }

    /// A provider object with nothing in it still declares the feature.
    /// Every field of `DiagnosticOptions` is optional except the two
    /// booleans, and a server that omits those is asking for the defaults.
    @Test func anEmptyProviderObjectStillDeclares() {
        let capability = LSPDiagnosticCapability(["diagnosticProvider": .object([:])])

        #expect(capability.isDeclared)
        #expect(capability.identifier == nil)
    }
}

/// Reading a `textDocument/diagnostic` report.
///
/// The full report below is the one that came back for a four-line
/// TypeScript file with one unused constant in it, from the same live
/// server. The `unchanged` and `relatedDocuments` shapes are the
/// specification's, since that server sends neither: it answers `full` with
/// no `resultId` at all, which is a permission the protocol grants and a
/// real server uses.
struct LSPDiagnosticReportTests {
    private let full: LSPValue = [
        "kind": .string("full"),
        "items": .array([[
            "message": .string("'unusedThing' is assigned a value but never used."),
            "severity": .integer(1),
            "source": .string("eslint"),
            "range": [
                "start": ["line": .integer(0), "character": .integer(6)],
                "end": ["line": .integer(0), "character": .integer(17)],
            ],
            "code": .string("@typescript-eslint/no-unused-vars"),
            "codeDescription": [
                "href": .string("https://typescript-eslint.io/rules/no-unused-vars"),
            ],
        ]]),
    ]

    @Test func aFullReportCarriesItsItems() throws {
        let report = try #require(LSPDiagnosticReport(full))

        #expect(report.document.isUnchanged == false)
        #expect(report.document.items.count == 1)
        #expect(report.related.isEmpty)
    }

    /// Measured: this server sends no `resultId`, so it can never answer
    /// `unchanged` and every pull costs it a whole file's lint. A client
    /// that required the field would drop its every report.
    @Test func aFullReportNeedNotCarryAResultID() throws {
        let report = try #require(LSPDiagnosticReport(full))

        #expect(report.document.resultId == nil)
    }

    /// The item is kept unparsed **and** parses, which is the pair the
    /// store needs: the parsed one draws the underline, the raw one travels
    /// with a `textDocument/codeAction` request as the problem to fix.
    @Test func theRawItemsSurviveIntoTheStore() throws {
        let report = try #require(LSPDiagnosticReport(full))
        let raw = try #require(report.document.items.first)

        #expect(raw["code"]?.stringValue == "@typescript-eslint/no-unused-vars")

        let parsed = try #require(LSPDiagnostic(raw))
        #expect(parsed.severity == .error)
        #expect(parsed.source == "eslint")
        #expect(parsed.range.start.character == 6)
    }

    /// An `unchanged` report is not an empty file. It carries no items
    /// because the client is meant to keep the ones it has, and reading it
    /// as a clear file erases every underline in the document.
    @Test func anUnchangedReportCarriesNoItemsAndSaysSo() throws {
        let report = try #require(LSPDiagnosticReport([
            "kind": .string("unchanged"),
            "resultId": .string("42"),
        ]))

        #expect(report.document.isUnchanged)
        #expect(report.document.items.isEmpty)
        #expect(report.document.resultId == "42")
    }

    /// The token that makes the next pull cheap, taken from either kind.
    @Test func theResultIDIsReadFromAFullReportToo() throws {
        let report = try #require(LSPDiagnosticReport([
            "kind": .string("full"),
            "resultId": .string("7"),
            "items": .array([]),
        ]))

        #expect(report.document.resultId == "7")
        #expect(report.document.isUnchanged == false)
    }

    /// A `full` report with an empty array **is** a clear file, and is the
    /// answer a server gives after the last problem is fixed. It must not
    /// be confused with `unchanged`.
    @Test func aFullReportWithNoItemsClearsTheFile() throws {
        let report = try #require(LSPDiagnosticReport([
            "kind": .string("full"),
            "items": .array([]),
        ]))

        #expect(report.document.isUnchanged == false)
        #expect(report.document.items.isEmpty)
    }

    /// Claimed in `relatedDocumentSupport`, so it is read: a server whose
    /// rules span files answers a pull about the edited file with the
    /// problems that edit created in another one.
    @Test func relatedDocumentsAreReadPerFile() throws {
        let report = try #require(LSPDiagnosticReport([
            "kind": .string("full"),
            "resultId": .string("a1"),
            "items": .array([]),
            "relatedDocuments": [
                "file:///w/importer.ts": [
                    "kind": .string("full"),
                    "resultId": .string("b2"),
                    "items": .array([[
                        "message": .string("Module has no exported member 'gone'."),
                        "severity": .integer(1),
                        "range": [
                            "start": ["line": .integer(2), "character": .integer(9)],
                            "end": ["line": .integer(2), "character": .integer(13)],
                        ],
                    ]]),
                ],
                "file:///w/untouched.ts": [
                    "kind": .string("unchanged"),
                    "resultId": .string("c3"),
                ],
            ],
        ]))

        #expect(report.related.count == 2)

        let importer = try #require(report.related["file:///w/importer.ts"])
        #expect(importer.isUnchanged == false)
        #expect(importer.items.count == 1)
        #expect(importer.resultId == "b2")

        let untouched = try #require(report.related["file:///w/untouched.ts"])
        #expect(untouched.isUnchanged)
        #expect(untouched.items.isEmpty)
    }

    /// One unreadable related document does not cost the report the rest of
    /// them, nor the file it was actually about.
    @Test func anUnreadableRelatedDocumentIsDroppedAlone() throws {
        let report = try #require(LSPDiagnosticReport([
            "kind": .string("full"),
            "items": .array([]),
            "relatedDocuments": [
                "file:///w/good.ts": ["kind": .string("unchanged"), "resultId": .string("k")],
                "file:///w/bad.ts": ["items": .array([])],
            ],
        ]))

        #expect(report.related.count == 1)
        #expect(report.related["file:///w/good.ts"] != nil)
    }

    /// A report with no kind is not a report. Reading it as `full` would
    /// clear a file's problems on the strength of a field nobody parsed,
    /// and reading it as `unchanged` would keep problems the server may
    /// have just resolved.
    @Test func areportWithoutAKindIsRefused() {
        #expect(LSPDiagnosticReport(["items": .array([])]) == nil)
        #expect(LSPDiagnosticReport(.null) == nil)
    }

    /// A kind this client has not heard of is refused for the same reason.
    /// The protocol has two and adding a third is not this client's guess
    /// to make.
    @Test func anUnknownKindIsRefused() {
        #expect(LSPDiagnosticReport(["kind": .string("partial")]) == nil)
    }
}

/// The client's half: what this app tells a server it can do about
/// diagnostics, and what it puts in a code-action request.
struct LSPPullDiagnosticsWiringTests {
    /// Announced because it is implemented. A server reading no
    /// `textDocument.diagnostic` block may decline to offer the feature at
    /// all, which for a server that pushes nothing is a file with no
    /// problems ever.
    @Test func theClientAnnouncesThatItPulls() throws {
        let diagnostic = try #require(
            LSPCenter.clientCapabilities["textDocument"]?["diagnostic"]
        )

        #expect(diagnostic["relatedDocumentSupport"]?.boolValue == true)
        #expect(diagnostic["dynamicRegistration"]?.boolValue == false)
    }

    /// Claimed because `workspace/diagnostic/refresh` is answered and
    /// acted on. A server told `false` stops looking for a way to say its
    /// rules changed.
    @Test func theClientAnnouncesThatItAcceptsARefresh() throws {
        let workspace = try #require(LSPCenter.clientCapabilities["workspace"])

        #expect(workspace["diagnostics"]?["refreshSupport"]?.boolValue == true)
    }

    /// The block survives the merge with the transport's own minimum, which
    /// declares no diagnostic support of any kind.
    @Test func theTransportsOwnCapabilitiesDoNotShadowTheBlock() {
        #expect(LSPProcess.defaultCapabilities["textDocument"]?["diagnostic"] == nil)
        #expect(LSPCenter.clientCapabilities["textDocument"]?["diagnostic"] != nil)
    }

    /// `only` absent and `only: []` are different questions. Absent asks
    /// for whatever the server has; the empty list asks for actions of no
    /// kind, and a server that filters on it faithfully answers nothing.
    @Test func noKindFilterMeansTheFieldIsAbsent() {
        let context = LSPCodeAction.context(diagnostics: [])

        #expect(context["only"] == nil)
        #expect(context["diagnostics"]?.arrayValue?.isEmpty == true)
    }

    /// Measured: `vscode-eslint-language-server` 4.10.0 computes its
    /// whole-file fix only when `context.only` names `source.fixAll` or
    /// `source.fixAll.eslint`, and offers per-problem quick fixes
    /// otherwise. Without the field the fix-all action cannot be reached.
    @Test func aRequestedKindTravelsInTheContext() {
        let context = LSPCodeAction.context(
            diagnostics: [],
            only: [LSPCodeAction.fixAllKind]
        )

        #expect(context["only"] == .array([.string("source.fixAll")]))
    }

    /// The protocol's hierarchical parent rather than one server's leaf, so
    /// one ask reaches a server that matches by prefix and the ESLint
    /// server, which special-cases this exact string.
    @Test func theFixAllKindIsTheProtocolsParent() {
        #expect(LSPCodeAction.fixAllKind == "source.fixAll")
        #expect(LSPCenter.codeActionKinds.contains(LSPCodeAction.fixAllKind))
    }

    /// The diagnostics keep travelling when a kind is named. A server that
    /// filters by kind still matches a quick fix to the problem under the
    /// caret by the fields only the raw item carries.
    @Test func theDiagnosticsSurviveAKindFilter() {
        let raw: LSPValue = ["code": .string("no-unused-vars")]
        let context = LSPCodeAction.context(diagnostics: [raw], only: ["quickfix"])

        #expect(context["diagnostics"] == .array([raw]))
        #expect(context["only"] == .array([.string("quickfix")]))
    }
}
