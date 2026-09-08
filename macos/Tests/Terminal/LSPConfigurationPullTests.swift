import Foundation
@testable import Ghostty
import Testing

/// The answer to `workspace/configuration`, which is how a server that
/// reads nothing from `initialize` gets its settings.
///
/// The reason this exists: `vscode-eslint-language-server` reads `validate`,
/// `run`, `codeAction` and `format` from this pull and from nowhere else, so
/// while the app answered a null per item it linted nothing — and said
/// nothing about why, because a null is a truthful "no configuration".
struct LSPConfigurationPullTests {
    private let settings = #"""
    {"eslint":{"codeAction":{"disableRuleComment":{"enable":true}},"format":false,"run":"onType","validate":"on"}}
    """#

    private func item(section: String?) -> LSPValue {
        guard let section else { return .object([:]) }
        return .object(["section": .string(section)])
    }

    @Test func aSectionAnswersWithWhatTheManifestPutUnderIt() throws {
        let answer = LSPCenter.configuration(for: [item(section: "eslint")], settings: settings)
        let values = try #require(answer.arrayValue)
        #expect(values.count == 1)
        #expect(values[0]["validate"]?.stringValue == "on")
        #expect(values[0]["format"]?.boolValue == false)
    }

    /// A dotted section is a path into the object, which is what the
    /// protocol says and what several servers ask for.
    @Test func aDottedSectionWalksIntoTheObject() throws {
        let answer = LSPCenter.configuration(
            for: [item(section: "eslint.codeAction.disableRuleComment")],
            settings: settings
        )
        let values = try #require(answer.arrayValue)
        #expect(values[0]["enable"]?.boolValue == true)
    }

    /// An item with no section asks for the whole object.
    @Test func anItemWithNoSectionGetsEverything() throws {
        let answer = LSPCenter.configuration(for: [item(section: nil)], settings: settings)
        let values = try #require(answer.arrayValue)
        #expect(values[0]["eslint"]?["run"]?.stringValue == "onType")
    }

    /// One value per item, in the order asked — a server matches them up by
    /// position and a short array is a protocol error.
    @Test func everyItemGetsOneAnswerInOrder() throws {
        let answer = LSPCenter.configuration(
            for: [item(section: "eslint"), item(section: "prettier"), item(section: "eslint.run")],
            settings: settings
        )
        let values = try #require(answer.arrayValue)
        #expect(values.count == 3)
        #expect(values[1] == .null)
        #expect(values[2].stringValue == "onType")
    }

    /// **Null, not an empty object.** Those are different answers to a
    /// server, and inventing the second is how a client makes a server
    /// disable a feature it would otherwise have defaulted on.
    @Test func aSectionNobodyDeclaredStaysNull() throws {
        let answer = LSPCenter.configuration(for: [item(section: "eslint.nodePath")], settings: settings)
        let values = try #require(answer.arrayValue)
        #expect(values[0] == .null)
    }

    @Test func aServerThatDeclaredNothingGetsTheOldAnswer() throws {
        let answer = LSPCenter.configuration(
            for: [item(section: "eslint"), item(section: "other")],
            settings: nil
        )
        #expect(answer == .array([.null, .null]))
    }

    /// Text that is not an object cannot say what any section holds, and
    /// answering a null per item is the honest fallback — never a crash and
    /// never a guess.
    @Test func settingsThatCannotBeReadFallBackToNull() throws {
        #expect(LSPCenter.configuration(for: [item(section: "eslint")], settings: "not json")
            == .array([.null]))
    }

    @Test func askingForNothingAnswersWithNothing() {
        #expect(LSPCenter.configuration(for: [], settings: settings) == .array([]))
    }
}
