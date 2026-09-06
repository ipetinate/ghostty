import Foundation
@testable import Ghostty
import Testing

struct ExtensionInstallPlanTests {
    private static let root = URL(fileURLWithPath: "/tmp/phantom-tests/acme.lua")

    private func parse(_ json: String) -> LanguageManifest? {
        LanguageManifest.parse(
            data: Data(json.utf8),
            url: Self.root.appendingPathComponent(LanguageManifest.fileName),
            root: Self.root,
            scope: .user)
    }

    private func server(_ block: String, schemaVersion: Int = 1) -> LanguageServerContribution? {
        parse(#"""
        {
          "schemaVersion": \#(schemaVersion), "id": "acme.lua",
          "contributes": {
            "languages": [
              {
                "languageId": "lua", "extensions": ["lua"],
                "server": { "command": "lua-language-server", \#(block) }
              }
            ]
          }
        }
        """#)?.languages.first?.server
    }

    private func plan(_ install: String) -> ExtensionInstallPlan? {
        server(#""install": \#(install)"#)?.installPlan
    }

    private static let luaInstall = #"""
    {
      "commands": [
        { "manager": "brew", "command": "brew install lua-language-server", "uninstall": "brew uninstall lua-language-server" },
        { "manager": "npm", "command": "npm install -g lua-language-server" }
      ],
      "documentationURL": "https://luals.github.io/wiki/"
    }
    """#

    @Test func aServerBlockCarriesEveryCommandInOrder() {
        let plan = plan(Self.luaInstall)
        #expect(plan?.commands.count == 2)
        #expect(plan?.commands.first?.manager == .brew)
        #expect(plan?.commands.first?.command == "brew install lua-language-server")
        #expect(plan?.commands.first?.uninstall == "brew uninstall lua-language-server")
        #expect(plan?.commands.last?.manager == .npm)
        #expect(plan?.commands.last?.uninstall == nil)
        #expect(plan?.documentationURL?.absoluteString == "https://luals.github.io/wiki/")
    }

    @Test func everyManagerTheFormatNamesIsReadable() {
        let managers = [
            "brew install x", "npm install -g x", "pnpm add -g x", "yarn global add x",
            "cargo install x", "gem install x", "pipx install x", "go install x@latest",
            "dotnet tool install -g x", "nix profile install nixpkgs#x",
        ]
        for command in managers {
            let first = String(command.split(separator: " ")[0])
            let parsed = plan(#"{ "commands": [{ "manager": "\#(first)", "command": "\#(command)" }] }"#)
            #expect(parsed?.commands.first?.command == command, "\(command)")
            #expect(parsed?.commands.first?.manager.rawValue == first, "\(command)")
        }
    }

    @Test func aFormatterTakesTheSameBlock() {
        let manifest = parse(#"""
        {
          "schemaVersion": 1, "id": "acme.lua",
          "contributes": {
            "formatters": [
              {
                "id": "stylua", "command": "stylua", "extensions": ["lua"],
                "install": { "commands": [{ "manager": "cargo", "command": "cargo install stylua" }] }
              }
            ]
          }
        }
        """#)
        #expect(manifest?.formatters.first?.installPlan?.commands.first?.manager == .cargo)
    }

    private func agentPlan(_ install: String) -> ExtensionInstallPlan? {
        parse(#"""
        {
          "schemaVersion": 1, "id": "acme.lua",
          "contributes": {
            "agents": [
              { "agentId": "gemini", "name": "Gemini CLI", "command": "gemini", "install": \#(install) }
            ]
          }
        }
        """#)?.agentInstallPlans["gemini"]
    }

    @Test func anAgentTakesTheObjectForm() {
        let plan = agentPlan(#"{ "commands": [{ "manager": "npm", "command": "npm install -g @google/gemini-cli" }] }"#)
        #expect(plan?.commands.first?.manager == .npm)
        #expect(plan?.commands.first?.command == "npm install -g @google/gemini-cli")
    }

    @Test func anAgentKeepsTheOlderArrayOfStrings() {
        let plan = agentPlan(#"""
        {
          "commands": ["brew install gemini-cli", "pnpm add -g @google/gemini-cli"],
          "documentationURL": "https://example.com/gemini"
        }
        """#)
        #expect(plan?.commands.count == 2)
        #expect(plan?.commands.first?.manager == .brew)
        #expect(plan?.commands.last?.manager == .pnpm)
        #expect(plan?.documentationURL?.absoluteString == "https://example.com/gemini")
    }

    @Test func aStringWhoseFirstWordIsNoManagerIsDropped() {
        let plan = agentPlan(#"{ "commands": ["installer install gemini", "npm install -g gemini"] }"#)
        #expect(plan?.commands.map(\.command) == ["npm install -g gemini"])
    }

    @Test func aCommandThatDoesNotStartWithItsManagerIsDropped() {
        let plan = plan(#"""
        {
          "commands": [
            { "manager": "brew", "command": "npm install -g evil" },
            { "manager": "npm", "command": "npm install -g lua-language-server" }
          ]
        }
        """#)
        #expect(plan?.commands.map(\.command) == ["npm install -g lua-language-server"])
    }

    @Test func aManagerThisBuildDoesNotKnowIsDropped() {
        #expect(plan(#"{ "commands": [{ "manager": "apt", "command": "apt install lua" }] }"#) == nil)
    }

    @Test func everyForbiddenFragmentCostsItsOwnCommand() {
        let refused = [
            "brew install curl-thing",
            "brew install x | sh",
            "brew install sudo-x",
            "brew install x; rm -rf /",
            "brew install x && rm -rf /",
            "brew install x & rm -rf /",
            "brew install $(whoami)",
            "brew install `whoami`",
            "brew install x < /etc/passwd",
            "brew install x > /tmp/out",
        ]
        for command in refused {
            let parsed = plan(#"""
            {
              "commands": [
                { "manager": "brew", "command": "\#(command)" },
                { "manager": "npm", "command": "npm install -g lua-language-server" }
              ]
            }
            """#)
            #expect(parsed?.commands.map(\.command) == ["npm install -g lua-language-server"], "\(command)")
        }
    }

    @Test func aRejectedUninstallCostsOnlyItself() {
        let plan = plan(#"""
        { "commands": [{ "manager": "brew", "command": "brew install x", "uninstall": "brew uninstall x; rm -rf /" }] }
        """#)
        #expect(plan?.commands.first?.command == "brew install x")
        #expect(plan?.commands.first?.uninstall == nil)
    }

    @Test func aCommandLongerThanTheCapIsDropped() {
        let long = "brew install " + String(repeating: "a", count: ExtensionInstallPlan.maxCommandLength)
        #expect(plan(#"{ "commands": [{ "manager": "brew", "command": "\#(long)" }] }"#) == nil)
    }

    @Test func noMoreCommandsThanTheCapAreRead() {
        let commands = (0..<(ExtensionInstallPlan.maxCommands + 4))
            .map { #"{ "manager": "brew", "command": "brew install pkg\#($0)" }"# }
            .joined(separator: ", ")
        #expect(plan(#"{ "commands": [\#(commands)] }"#)?.commands.count == ExtensionInstallPlan.maxCommands)
    }

    @Test func aManifestWithNoBlockKeepsItsInstallHint() {
        let server = server(#""installHint": "brew install lua-language-server""#)
        #expect(server?.installHint == "brew install lua-language-server")
        #expect(server?.installPlan == nil)
    }

    @Test func aBlockWithOnlyAPageIsStillWorthShowing() {
        let plan = plan(#"{ "documentationURL": "https://luals.github.io/wiki/" }"#)
        #expect(plan?.commands.isEmpty == true)
        #expect(plan?.documentationURL != nil)
    }

    @Test func aBlockWithNothingReadableIsNoPlan() {
        #expect(plan(#"{ "commands": [{ "manager": "apt", "command": "apt install x" }] }"#) == nil)
        #expect(plan(#"{}"#) == nil)
        #expect(plan(#""brew install x""#) == nil)
    }

    @Test func aDocumentationPageMustBeHTTP() {
        #expect(plan(#"{ "documentationURL": "file:///etc/passwd" }"#) == nil)
    }

    @Test func aSchemaThisBuildCannotReadContributesNoPlan() {
        #expect(server(#""install": \#(Self.luaInstall)"#, schemaVersion: 2) == nil)
    }

    @Test func theFirstCommandWhoseManagerIsHereIsTheOneOffered() {
        let plan = plan(Self.luaInstall)
        #expect(plan?.command(managers: [.brew, .npm])?.manager == .brew)
        #expect(plan?.command(managers: [.npm])?.manager == .npm)
        #expect(plan?.command(managers: [.cargo]) == nil)
        #expect(plan?.command(managers: []) == nil)
    }
}
