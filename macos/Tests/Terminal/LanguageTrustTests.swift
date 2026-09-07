import Foundation
@testable import Ghostty
import Testing

/// The trust model, as a function.
///
/// Nothing here goes near a `Process`, a window or `UserDefaults` — that is
/// the reason `LanguageTrust.verdict(for:record:)` takes the resolved path
/// and the workspace root as values instead of looking them up. A gate whose
/// policy can only be exercised by launching something is a gate nobody
/// tests.
@Suite(.serialized)
struct LanguageTrustTests {
    private static let provenance = ExtensionProvenance(
        extensionID: "acme.elixir",
        digest: "aa11",
        manifestPath: "/Users/x/.config/phantom/extensions/acme.elixir/extension.json",
        scope: .user
    )

    private func subject(
        digest: String = "aa11",
        command: String = "elixir-ls",
        resolvedPath: String = "/opt/homebrew/bin/elixir-ls",
        workspaceRoot: String? = "/Users/x/project",
        provenance: ExtensionProvenance = LanguageTrustTests.provenance
    ) -> LanguageTrust.Subject {
        LanguageTrust.Subject(
            origin: .manifest(provenance),
            digest: digest,
            command: command,
            resolvedPath: resolvedPath,
            workspaceRoot: workspaceRoot
        )
    }

    private func record(
        decision: LanguageTrustRecord.Decision = .allowed,
        digest: String = "aa11",
        command: String = "elixir-ls",
        resolvedPath: String = "/opt/homebrew/bin/elixir-ls",
        manifestPath: String = LanguageTrustTests.provenance.manifestPath,
        recordVersion: Int = LanguageTrustStore.currentRecordVersion
    ) -> LanguageTrustRecord {
        LanguageTrustRecord(
            recordVersion: recordVersion,
            digest: digest,
            command: command,
            resolvedPath: resolvedPath,
            manifestPath: manifestPath,
            decision: decision,
            decidedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: The compiled-in case

    /// The registry is not asked about. This is also what makes the field on
    /// `LSPServerDefinition` safe to default: a definition that never says
    /// where it came from is treated as one of ours, and all twenty-five of
    /// ours are.
    @Test func aBuiltInServerIsAllowedWithoutAsking() {
        let builtIn = LanguageTrust.Subject(
            origin: .builtIn,
            digest: "",
            command: "typescript-language-server",
            resolvedPath: "/usr/local/bin/typescript-language-server",
            workspaceRoot: "/Users/x/project"
        )
        #expect(LanguageTrust.verdict(for: builtIn, record: nil) == .allow)
    }

    // MARK: Installing is the consent

    /// The rule this whole type turns on: an extension nobody has refused
    /// runs, because putting it in the extensions directory is the answer.
    @Test func anExtensionWithNoRecordIsAllowed() {
        #expect(LanguageTrust.verdict(for: subject(), record: nil) == .allow)
    }

    @Test func anExplicitAllowanceIsHonoured() {
        #expect(LanguageTrust.verdict(for: subject(), record: record()) == .allow)
    }

    // MARK: What used to invalidate an approval

    /// Four rules used to send the reader back to a dialog: rewritten
    /// manifest bytes, a different command, a manifest that moved, a command
    /// that resolved somewhere new. Each of them is a thing an ordinary
    /// update does, and the answer to all four is now the same.
    @Test func changedManifestBytesDoNotStopIt() {
        #expect(
            LanguageTrust.verdict(for: subject(digest: "bb22"), record: record(digest: "aa11"))
                == .allow
        )
    }

    @Test func aChangedCommandDoesNotStopIt() {
        #expect(
            LanguageTrust.verdict(
                for: subject(command: "elixir-ls-next"),
                record: record(command: "elixir-ls")
            ) == .allow
        )
    }

    @Test func aMovedManifestDoesNotStopIt() {
        #expect(
            LanguageTrust.verdict(
                for: subject(),
                record: record(manifestPath: "/somewhere/else/extension.json")
            ) == .allow
        )
    }

    @Test func aCommandThatNowResolvesElsewhereDoesNotStopIt() {
        #expect(
            LanguageTrust.verdict(
                for: subject(resolvedPath: "/usr/local/bin/elixir-ls"),
                record: record(resolvedPath: "/opt/homebrew/bin/elixir-ls")
            ) == .allow
        )
    }

    // MARK: Refusal

    @Test func aRefusalIsRemembered() {
        #expect(
            LanguageTrust.verdict(for: subject(), record: record(decision: .refused))
                == .deny(.refusedByUser(at: Date(timeIntervalSince1970: 1_700_000_000)))
        )
    }

    /// Deliberately *not* re-asked when the manifest changes. Otherwise
    /// touching the file would earn another prompt, and an author who can
    /// prompt at will only has to wait for a distracted moment.
    @Test func aRefusalSurvivesTheManifestChanging() {
        #expect(
            LanguageTrust.verdict(
                for: subject(digest: "bb22"),
                record: record(decision: .refused, digest: "aa11")
            ) == .deny(.refusedByUser(at: Date(timeIntervalSince1970: 1_700_000_000)))
        )
    }

    // MARK: Hardenings, which no answer overrides

    /// Plenty of shells put `./node_modules/.bin` on `PATH`, so a manifest
    /// can name an innocent command and rely on a freshly-cloned repository
    /// to supply it. Approving the name would approve whatever the repo
    /// shipped, so this is refused rather than asked — and refused even for
    /// an extension the user already approved.
    @Test func aCommandResolvingInsideTheWorkspaceIsRefusedEvenWhenApproved() {
        let inside = "/Users/x/project/node_modules/.bin/elixir-ls"
        #expect(
            LanguageTrust.verdict(
                for: subject(resolvedPath: inside),
                record: record(resolvedPath: inside)
            ) == .deny(.commandInsideWorkspace(path: inside))
        )
    }

    @Test func aCommandOutsideTheWorkspaceIsFine() {
        #expect(LanguageTrust.verdict(for: subject(), record: record()) == .allow)
    }

    /// A workspace of `/` is not a repository that shipped anything, and
    /// treating it as one would deny every server for a loose file.
    @Test func traversalCannotHideAWorkspacePath() {
        let sneaky = "/Users/x/project/../project/node_modules/.bin/elixir-ls"
        #expect(LanguageTrust.isInside(sneaky, root: "/Users/x/project"))
        #expect(!LanguageTrust.isInside("/Users/x/project-other/bin/ls", root: "/Users/x/project"))
        #expect(!LanguageTrust.isInside("/usr/bin/ls", root: "/"))
    }

    /// Already refused at parse time. Checked again because this is the last
    /// point before a process exists, and a defence that lives at one layer
    /// is one refactor from living at none.
    @Test func aShellShapedCommandIsRefusedAtTheGateToo() {
        #expect(
            LanguageTrust.verdict(
                for: subject(command: "elixir-ls; rm -rf ~"),
                record: record(command: "elixir-ls; rm -rf ~")
            ) == .deny(.unsafeCommand)
        )
    }

    /// A bundled manifest was never asked about either, and still is not.
    @Test func aBundledManifestIsAllowed() {
        let bundled = ExtensionProvenance(
            extensionID: "phantom.elixir",
            digest: "cc33",
            manifestPath: "/Applications/Phantom.app/Contents/Resources/extensions/x/extension.json",
            scope: .bundled
        )
        #expect(LanguageTrust.verdict(for: subject(provenance: bundled), record: nil) == .allow)
    }

    // MARK: The record

    /// The record a refusal writes carries the identity and the decision.
    /// The command and the path it would have resolved to are left empty
    /// rather than guessed: nothing compares them, and there is no launch to
    /// read them from — the reader refused the extension in Settings.
    @Test func aRefusalRecordsTheIdentityAndTheDecision() {
        withCleanTrustDefaults {
            LanguageTrustStore.refuse(
                extensionID: Self.provenance.extensionID,
                digest: Self.provenance.digest,
                manifestPath: Self.provenance.manifestPath
            )
            let written = LanguageTrustStore.record(for: Self.provenance.extensionID)
            #expect(written?.recordVersion == LanguageTrustStore.currentRecordVersion)
            #expect(written?.digest == "aa11")
            #expect(written?.manifestPath == Self.provenance.manifestPath)
            #expect(written?.decision == .refused)
            #expect(written?.command == "")
            #expect(written?.resolvedPath == "")
            #expect(LanguageTrust.verdict(for: subject(), record: written) != .allow)
        }
    }

    private func withCleanTrustDefaults(_ body: () -> Void) {
        let key = LanguageTrustStore.defaultsKey
        let stored = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer {
            if let stored {
                UserDefaults.standard.set(stored, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        body()
    }
}

@Suite(.serialized)
struct LanguageTrustStoreTests {
    private func withCleanDefaults(_ body: () -> Void) {
        let keys = [LanguageTrustStore.defaultsKey, LanguagePromotionStore.defaultsKey]
        let stored = keys.map { UserDefaults.standard.object(forKey: $0) }
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        defer {
            for (key, value) in zip(keys, stored) {
                if let value {
                    UserDefaults.standard.set(value, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        body()
    }

    private func record(
        decision: LanguageTrustRecord.Decision = .allowed,
        recordVersion: Int = LanguageTrustStore.currentRecordVersion
    ) -> LanguageTrustRecord {
        LanguageTrustRecord(
            recordVersion: recordVersion,
            digest: "aa11",
            command: "elixir-ls",
            resolvedPath: "/opt/homebrew/bin/elixir-ls",
            manifestPath: "/Users/x/.config/phantom/extensions/acme.elixir/extension.json",
            decision: decision,
            decidedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @Test func withNothingStoredThereIsNoRecord() {
        withCleanDefaults {
            #expect(LanguageTrustStore.record(for: "acme.elixir") == nil)
        }
    }

    @Test func aSavedRecordReadsBackAsIs() {
        withCleanDefaults {
            let saved = record()
            LanguageTrustStore.set(saved, for: "acme.elixir")
            #expect(LanguageTrustStore.record(for: "acme.elixir") == saved)
        }
    }

    /// A record this build cannot decode reads as **absent**, and absent now
    /// means allowed, because installing the extension was the consent. The
    /// verdict is asserted here and not only the store's answer: the
    /// direction matters, and it is the reason a field that changes what a
    /// *refusal* covers has to come with a version bump.
    @Test func aRecordFromALaterVersionReadsAsAbsentAndTheExtensionRuns() {
        withCleanDefaults {
            LanguageTrustStore.set(
                record(recordVersion: LanguageTrustStore.currentRecordVersion + 1),
                for: "acme.elixir"
            )
            #expect(LanguageTrustStore.record(for: "acme.elixir") == nil)

            let subject = LanguageTrust.Subject(
                origin: .manifest(ExtensionProvenance(
                    extensionID: "acme.elixir",
                    digest: "aa11",
                    manifestPath: "/x/extension.json",
                    scope: .user
                )),
                digest: "aa11",
                command: "elixir-ls",
                resolvedPath: "/opt/homebrew/bin/elixir-ls",
                workspaceRoot: nil
            )
            #expect(
                LanguageTrust.verdict(
                    for: subject,
                    record: LanguageTrustStore.record(for: "acme.elixir")
                ) == .allow
            )
        }
    }

    @Test func garbageInTheKeyIsNotARecord() {
        withCleanDefaults {
            UserDefaults.standard.set(
                Data("not json".utf8),
                forKey: LanguageTrustStore.defaultsKey
            )
            #expect(LanguageTrustStore.record(for: "acme.elixir") == nil)
            #expect(LanguageTrustStore.all.isEmpty)
        }
    }

    @Test func recordsForDifferentExtensionsAreIndependent() {
        withCleanDefaults {
            LanguageTrustStore.set(record(decision: .allowed), for: "acme.elixir")
            LanguageTrustStore.set(record(decision: .refused), for: "other.gleam")

            #expect(LanguageTrustStore.record(for: "acme.elixir")?.decision == .allowed)
            #expect(LanguageTrustStore.record(for: "other.gleam")?.decision == .refused)
        }
    }

    /// The only way back from a refusal, and it is reachable from Settings
    /// alone — never from an extension.
    @Test func forgettingClearsARefusal() {
        withCleanDefaults {
            LanguageTrustStore.set(record(decision: .refused), for: "acme.elixir")
            LanguageTrustStore.forget("acme.elixir")
            #expect(LanguageTrustStore.record(for: "acme.elixir") == nil)
        }
    }

    /// An extension with no usable id has nowhere for a decision to live,
    /// and writing one under an empty key would be a decision that applies
    /// to every such extension at once.
    @Test func anEmptyIdentityIsNotWritable() {
        withCleanDefaults {
            LanguageTrustStore.set(record(), for: "")
            #expect(LanguageTrustStore.all.isEmpty)
        }
    }

    /// Keyed by extension id, which is what makes one answer cover every
    /// language and every program the extension contributes.
    @Test func aRefusalIsWrittenUnderTheExtensionIdentity() {
        withCleanDefaults {
            LanguageTrustStore.refuse(
                extensionID: "acme.elixir",
                digest: "aa11",
                manifestPath: "/x/extension.json"
            )

            let stored = LanguageTrustStore.record(for: "acme.elixir")
            #expect(stored?.decision == .refused)
            #expect(stored?.manifestPath == "/x/extension.json")
            #expect(LanguageTrustStore.record(for: "other.gleam") == nil)
        }
    }

    // MARK: Promotion

    @Test func promotionsRoundTripAndAreScopedToOneLanguage() {
        withCleanDefaults {
            #expect(!LanguagePromotionStore.isPromoted(
                extensionID: "acme.pack",
                languageID: "elixir"
            ))

            LanguagePromotionStore.setPromoted(
                true,
                extensionID: "acme.pack",
                languageID: "elixir"
            )

            #expect(LanguagePromotionStore.isPromoted(
                extensionID: "acme.pack",
                languageID: "elixir"
            ))
            #expect(!LanguagePromotionStore.isPromoted(
                extensionID: "acme.pack",
                languageID: "gleam"
            ))

            LanguagePromotionStore.setPromoted(
                false,
                extensionID: "acme.pack",
                languageID: "elixir"
            )
            #expect(LanguagePromotionStore.all.isEmpty)
        }
    }
}
