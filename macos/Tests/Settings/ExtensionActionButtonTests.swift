import Foundation
@testable import Ghostty
import Testing

struct ExtensionActionButtonTests {
    @Test func aMissingExtensionOffersInstall() {
        let action = ExtensionActionButton.Action(state: .notInstalled)
        #expect(action == .install)
        #expect(action.title == "Install")
        #expect(action.systemImage == "arrow.down.circle")
        #expect(!action.isDestructive)
    }

    @Test func anInstalledExtensionOffersUninstall() {
        let action = ExtensionActionButton.Action(state: .installed(version: "1.2.0"))
        #expect(action == .uninstall)
        #expect(action.title == "Uninstall")
        #expect(action.systemImage == "trash")
        #expect(action.isDestructive)
    }

    @Test func anOutdatedExtensionOffersUpdate() {
        let action = ExtensionActionButton.Action(
            state: .updateAvailable(installed: "1.2.0", available: "1.3.0"))
        #expect(action == .update)
        #expect(action.title == "Update")
        #expect(action.systemImage == "arrow.triangle.2.circlepath")
        #expect(!action.isDestructive)
    }

    @Test func onlyUninstallIsDestructive() {
        let destructive = ExtensionActionButton.Action.allCases.filter(\.isDestructive)
        #expect(destructive == [.uninstall])
    }

    @Test func everyActionCarriesItsOwnSymbol() {
        let symbols = ExtensionActionButton.Action.allCases.map(\.systemImage)
        #expect(Set(symbols).count == symbols.count)
        #expect(symbols.allSatisfy { !$0.isEmpty })
    }

    @Test func everyActionCarriesItsOwnTitle() {
        let titles = ExtensionActionButton.Action.allCases.map(\.title)
        #expect(Set(titles).count == titles.count)
        #expect(titles.allSatisfy { !$0.isEmpty })
    }
}
