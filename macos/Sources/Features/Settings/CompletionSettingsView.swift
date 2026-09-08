import SwiftUI

/// The completion preferences, as one section of the Editor pane.
///
/// A `View` whose body is a `Section` rather than a screen of its own.
/// This used to be the detail half of the Language Servers list, reached
/// through an entry that showed itself only when the search text matched
/// one of four hardcoded words — a settings screen you had to already
/// know about in order to find. It belongs with the rest of the editor's
/// settings, and that list no longer exists to hide it.
///
/// The three globals are `@AppStorage`, which is what makes them live: a
/// change here lands in `UserDefaults` immediately, and every other reader
/// of the same key — including `EditorPaneView`, which folds them into the
/// `CodeEditorConfiguration` handed to the engine — is republished by the
/// same write. The per-language table cannot be, because `@AppStorage` has
/// no dictionary, so those rows go through `CompletionSettingsStore` and
/// tell the screen themselves.
struct CompletionSettingsSection: View {
    /// Read here rather than handed in. It used to be a parameter so that
    /// the two halves of the Language Servers screen could not disagree
    /// about which extensions exist; that screen is gone, and the resolver
    /// is the same singleton either way.
    @ObservedObject private var languages = LanguageResolver.shared

    @AppStorage(CompletionSettingsStore.enabledKey) private var isEnabled = true
    @AppStorage(CompletionSettingsStore.bufferWordsKey) private var usesBufferWords = true
    @AppStorage(CompletionSettingsStore.delayKey)
    private var delayRaw = CompletionDelay.default.rawValue

    /// Bumped by every per-language write, purely to re-run `body`.
    ///
    /// The rows read `CompletionSettingsStore` through a computed `Binding`
    /// rather than through `@AppStorage`, and a plain `UserDefaults` write
    /// publishes nothing — so without this a switch would move under the
    /// pointer and snap back on the next redraw.
    @State private var revision = 0

    /// Folded away until asked for. Two dozen languages is the longest
    /// list in this pane and the one least often wanted: the answer for
    /// nearly everybody is the three rows above it.
    @State private var showsLanguages = false

    var body: some View {
        Section {
            /// "Suggest Completions", not "Suggest as You Type". This switch
            /// is the master — off, even an explicit request answers nothing
            /// — and its old name described the narrower behaviour instead,
            /// the one the Assistance section above now carries a switch
            /// for. Two rows in one pane both reading "as you type" is a
            /// reader choosing between them by guessing.
            Toggle("Suggest Completions", isOn: $isEnabled)
                .toggleStyle(.switch)

            Picker("Ask for Suggestions", selection: $delayRaw) {
                ForEach(CompletionDelay.allCases) { option in
                    Text(verbatim: Self.title(for: option)).tag(option.rawValue)
                }
            }
            .disabled(!isEnabled)

            Toggle("Include Words from the File", isOn: $usesBufferWords)
                .toggleStyle(.switch)
                .disabled(!isEnabled)

            DisclosureGroup(isExpanded: $showsLanguages) {
                ForEach(rows) { row in
                    Toggle(isOn: binding(for: row.languageID)) {
                        Text(verbatim: row.title)
                    }
                    .toggleStyle(.switch)
                    .disabled(!isEnabled)
                }

                if rows.isEmpty {
                    Text("No extension is installed, so there is no language to switch. The three settings above apply to every file.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if hasStoredPreferences {
                    Button("Follow Defaults for All Languages") {
                        CompletionSettingsStore.clearLanguagePreferences()
                        revision += 1
                    }
                }
            } label: {
                LabeledContent("By Language") {
                    Text(verbatim: languageSummary)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Completion")
        } footer: {
            Text("""
            With Suggest Completions off, nothing opens the list — not a \
            trigger character, not an explicit request. Nothing below can \
            bring it back; that switch is the master.

            A pause coalesces a burst of typing into one request instead of \
            one per character. A trigger character — a dot, usually — and an \
            explicit request both skip it, because each is already a pause. \
            Words from the file are what still completes when no server is \
            installed for a language, and they rank below anything a server \
            said.

            A language nobody has touched is not stored at all: it follows \
            this build's default, so the default can change without \
            overwriting a choice you made. Only the languages Phantom can \
            complete for are listed.
            """)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The picker's own label, adjective and milliseconds together.
    ///
    /// The number used to sit in a read-only row underneath, which restated
    /// the choice above it and — being the one control in the group nothing
    /// disabled — stayed lit after the master switch went off. A
    /// parenthesis carries the same fact without a row, and "Immediately"
    /// needs no number to say what it means.
    private static func title(for option: CompletionDelay) -> String {
        option == .immediate ? option.title : "\(option.title) (\(option.detail))"
    }

    /// What the folded row admits without being opened. The count of
    /// switched-off languages is the only part worth a glance; which they
    /// are is what opening it is for.
    private var languageSummary: String {
        let disabled = CompletionSettingsStore.byLanguage.values.filter { !$0 }.count
        guard disabled > 0 else { return "All Languages" }
        return disabled == 1 ? "1 Language Off" : "\(disabled) Languages Off"
    }

    /// Reads the store on every evaluation rather than caching, so a value
    /// written by the button below is the one drawn.
    ///
    /// The getter does not name `revision`, and does not need to: mutating
    /// a `@State` invalidates the view that owns it whether or not the old
    /// value was read, so `body` re-runs, this `Binding` is rebuilt, and
    /// the getter runs again against the store.
    private func binding(for languageID: String) -> Binding<Bool> {
        Binding(
            get: {
                CompletionSettingsStore.preference(forLanguage: languageID)
                    ?? CompletionSettingsStore.languageDefault
            },
            set: { newValue in
                CompletionSettingsStore.setEnabled(newValue, forLanguage: languageID)
                revision += 1
            }
        )
    }

    private var hasStoredPreferences: Bool {
        !CompletionSettingsStore.byLanguage.isEmpty
    }

    // MARK: The list

    /// One row per language id the installed extensions contribute, sorted
    /// by the name on screen.
    ///
    /// There is no compiled-in half any more: every language this app knows
    /// how to complete for arrives in an extension, so the installed catalog
    /// is the whole list. An empty one is a real answer — nothing installed,
    /// nothing to switch — and says so rather than showing a blank group.
    ///
    /// Deduplicated by language id, the active contribution winning: two
    /// extensions claiming one language resolve to one of them, and two
    /// switches for one answer would be wrong whichever way they were set.
    private var rows: [LanguageCompletionRow] {
        var seen: Set<String> = []
        let contributed = languages.catalog.contributed
        return (contributed.filter(\.isActive) + contributed.filter { !$0.isActive })
            .filter { seen.insert($0.language.languageID).inserted }
            .map {
                LanguageCompletionRow(
                    languageID: $0.language.languageID,
                    title: $0.language.displayName)
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

/// One switchable language.
private struct LanguageCompletionRow: Identifiable {
    let languageID: String
    let title: String

    var id: String { languageID }
}
