import Foundation
@testable import Ghostty
import Testing

/// The two tools that act on a language server.
///
/// Scope worth stating: restarting one really restarts it, and the cooldown
/// clock is private to the enum, so neither is driven from here. What is
/// covered is everything that decides *whether* and *what* — naming a server,
/// the refusals, and the sentence the reader is asked to approve.
@MainActor
struct MCPLanguageServerToolsTests {
    // MARK: What is on offer

    @Test func theToolsAreRestartAndConfigure() {
        let names = MCPLanguageServerTools.all.map(\.tool.name)
        #expect(names == ["restart_language_server", "configure_language_server"])
    }

    @Test func theyReachTheClientThroughTheRegistry() {
        let registered = Set(MCPToolRegistry.all.map(\.tool.name))
        for handler in MCPLanguageServerTools.all {
            #expect(registered.contains(handler.tool.name))
        }
    }

    @Test func eachNamesWhatItCannotDoWithout() {
        let required = MCPLanguageServerTools.all.reduce(into: [String: [JSONValue]]()) {
            $0[$1.tool.name] = $1.tool.schema.object?["required"]?.array
        }

        #expect(required["restart_language_server"] == [.string("server")])
        #expect(
            required["configure_language_server"]
                == [.string("server"), .string("initialization_options")])
    }

    /// The description is what decides whether a tool is reached for at the
    /// right moment, and this one has a consequence a caller must know before
    /// it calls: the setting is not scoped to the project it is working in.
    @Test func configureSaysItAppliesEverywhere() {
        let handler = MCPLanguageServerTools.all.first {
            $0.tool.name == "configure_language_server"
        }!

        #expect(handler.tool.description.contains("every project"))
    }

    @Test func restartSaysHowOftenItMayBeCalled() {
        let handler = MCPLanguageServerTools.all.first {
            $0.tool.name == "restart_language_server"
        }!

        #expect(handler.tool.description.contains("per minute"))
    }

    // MARK: Naming a server

    private var contributedLua: LSPServerDefinition {
        LSPServerDefinition(
            languageID: "lua",
            displayName: "Lua (acme)",
            command: "lua-language-server",
            arguments: ["--stdio"],
            installHint: "brew install lua-language-server",
            origin: .manifest(ExtensionProvenance(
                extensionID: "acme.lua",
                digest: "0",
                manifestPath: "/Users/x/.config/phantom/extensions/acme.lua/extension.json",
                scope: .user
            ))
        )
    }

    private var contributedGo: LSPServerDefinition {
        LSPServerDefinition(
            languageID: "go",
            displayName: "gopls (acme)",
            command: "gopls",
            arguments: [],
            installHint: "go install golang.org/x/tools/gopls@latest",
            origin: .manifest(ExtensionProvenance(
                extensionID: "acme.go",
                digest: "1",
                manifestPath: "/Users/x/.config/phantom/extensions/acme.go/extension.json",
                scope: .user
            ))
        )
    }

    /// The list is passed in rather than read off `LanguageResolver`, and
    /// that is the point of the `among:` half of the interface existing: the
    /// answer must not depend on which extensions the machine running the
    /// suite happens to have installed, which after 0.17.0 is the only thing
    /// the singular form could report.
    private var installed: [LSPServerDefinition] {
        MCPLanguageServerTools.knownServers(contributed: [contributedLua, contributedGo])
    }

    /// Both spellings, because `list_language_servers` reports both and a
    /// model handed two strings will use either.
    @Test func aServerIsFoundByItsNameOrItsCommand() {
        #expect(
            MCPLanguageServerTools.server("Lua (acme)", among: installed)?.command
                == "lua-language-server")
        #expect(
            MCPLanguageServerTools.server("lua-language-server", among: installed)?.command
                == "lua-language-server")
    }

    /// The name is prose in the interface. Refusing it over a capital letter
    /// would be a refusal about nothing.
    @Test func theNameIsMatchedWithoutRegardForCase() {
        #expect(
            MCPLanguageServerTools.server("LUA (ACME)", among: installed)?.command
                == "lua-language-server")
    }

    @Test func anUnknownNameIsNotFound() {
        #expect(MCPLanguageServerTools.server("not-a-server-anybody-has", among: installed) == nil)
    }

    /// The language id is tried last, so a name that is also some other
    /// server's language id still means the name.
    @Test func aServerIsAlsoFoundByTheLanguageItServes() {
        #expect(MCPLanguageServerTools.server("lua", among: installed) == contributedLua)
        #expect(MCPLanguageServerTools.server("go", among: installed) == contributedGo)
    }

    @Test func theNameWinsOverALanguageIDThatSpellsTheSame() {
        let named = LSPServerDefinition(
            languageID: "python", displayName: "lua", command: "pyright-langserver",
            arguments: [], installHint: ""
        )
        let servers = MCPLanguageServerTools.knownServers(contributed: [named, contributedLua])

        #expect(MCPLanguageServerTools.server("lua", among: servers) == named)
    }

    /// One entry per distinct binary. Two extensions shipping the same
    /// command would otherwise report one process twice, and a model reading
    /// the list has no way to tell that is one thing.
    @Test func oneCommandIsListedOnce() {
        let twin = LSPServerDefinition(
            languageID: "lua", displayName: "Lua", command: "lua-language-server",
            arguments: [], installHint: ""
        )
        let servers = MCPLanguageServerTools.knownServers(contributed: [twin, contributedLua])

        #expect(servers == [twin])
    }

    /// Every server a caller can name came from an extension, so the listing
    /// says which one — but `built-in` is still answered for a definition
    /// that carries no provenance, rather than left to a crash.
    @Test func theListingSaysWhereEachServerCameFrom() {
        let anonymous = LSPServerDefinition(
            languageID: "lua", displayName: "Lua", command: "lua-language-server",
            arguments: [], installHint: ""
        )

        #expect(MCPLanguageServerTools.origin(of: anonymous) == "built-in")
        #expect(MCPLanguageServerTools.origin(of: contributedLua) == "extension:acme.lua")
    }

    /// A refusal that only says "no such server" leaves the caller guessing at
    /// spellings, so it lists what there is.
    @Test func theRefusalNamesTheServersThatExist() {
        let reason = MCPLanguageServerTools.unknownServer("nonsense", among: installed)

        #expect(reason.contains("list_language_servers"))
        #expect(reason.contains("Lua (acme)"))
        #expect(reason.contains("gopls (acme)"))
    }

    // MARK: What the reader is asked to approve

    /// Both sides of the change. "Set initializationOptions" says nothing
    /// about what is being replaced.
    @Test func theQuestionShowsWhatItIsNowAndWhatItWouldBecome() {
        let sentence = MCPLanguageServerTools.diff(contributedLua, to: "{\"plugins\":[]}")

        #expect(sentence.contains("Lua (acme)"))
        #expect(sentence.contains("Now:"))
        #expect(sentence.contains("Proposed:"))
        #expect(sentence.contains("{\"plugins\":[]}"))
    }

    /// Going back to the default is a change too, and reads as harmless until
    /// you know the default is what made the server work at all.
    @Test func goingBackToTheDefaultIsSaidInWords() {
        let sentence = MCPLanguageServerTools.diff(contributedLua, to: "")

        #expect(sentence.contains("this app's own default"))
    }

    // MARK: The third capability

    @Test func configureIsItsOwnCapability() {
        #expect(MCPPermission.Capability.configure.title.contains("language server"))
        #expect(MCPPermission.Capability.allCases.contains(.configure))
    }

    /// A grant to type into a shell must not carry a grant to rewrite the
    /// app's configuration.
    @Test func aGrantToRunDoesNotAnswerARequestToConfigure() {
        let tab = UUID()
        let run = MCPPermission.Grant(capability: .run, scope: .all, surface: nil, group: nil)

        let asked = MCPPermission.Request(capability: .configure, surface: tab, group: nil)

        #expect(MCPPermission.isAllowed(asked, by: [run]) == false)
    }

    @Test func aGrantToConfigureAnswersOne() {
        let tab = UUID()
        let grant = MCPPermission.Grant(
            capability: .configure, scope: .tab, surface: tab, group: nil)

        let asked = MCPPermission.Request(capability: .configure, surface: tab, group: nil)

        #expect(MCPPermission.isAllowed(asked, by: [grant]))
    }

    /// The reach in the sheet is about who may ask again, not about what the
    /// change touches, so the stakes have to say the change is app-wide.
    @Test func theStakesSayTheChangeIsNotLocal() {
        let text = MCPPermissionPrompt.informative(for: .configure)

        #expect(text.contains("every project"))
        #expect(text.contains("Settings"))
    }

    /// Read months later by somebody who does not remember answering.
    @Test func theRevokeListNamesWhatWasAllowed() {
        #expect(MCPGrantPhrase.capability(.configure).contains("language server"))
    }
}
