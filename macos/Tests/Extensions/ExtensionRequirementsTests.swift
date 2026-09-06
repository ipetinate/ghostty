import Foundation
@testable import Ghostty
import Testing

struct ExtensionRequirementsTests {
    private static let root = URL(fileURLWithPath: "/tmp/phantom-tests/acme.tools")

    private func manifest(contributes: String) -> LanguageManifest {
        LanguageManifest.parse(
            data: Data(#"""
            { "schemaVersion": 1, "id": "acme.tools", "contributes": { \#(contributes) } }
            """#.utf8),
            url: Self.root.appendingPathComponent(LanguageManifest.fileName),
            root: Self.root,
            scope: .user)!
    }

    private func requirements(
        _ contributes: String,
        managers: Set<ExtensionPackageManager> = [.brew, .npm],
        present: [String: String] = [:]
    ) -> [ExtensionRequirement] {
        ExtensionRequirements.requirements(
            in: manifest(contributes: contributes),
            managers: managers,
            locate: { present[$0] })
    }

    private static let luaServer = #"""
    "languages": [
      {
        "languageId": "lua", "extensions": ["lua"],
        "server": {
          "command": "lua-language-server",
          "install": {
            "commands": [
              { "manager": "brew", "command": "brew install lua-language-server" },
              { "manager": "npm", "command": "npm install -g lua-language-server" }
            ],
            "documentationURL": "https://luals.github.io/wiki/"
          }
        }
      }
    ]
    """#

    @Test func aProgramThatIsNotOnPathIsMissing() {
        let found = requirements(Self.luaServer)
        #expect(found.count == 1)
        #expect(found[0].program == "lua-language-server")
        #expect(found[0].neededBy == "Language server")
        #expect(found[0].isInstalled == false)
        #expect(found[0].resolvedPath == nil)
        #expect(found[0].install?.command == "brew install lua-language-server")
        #expect(found[0].documentationURL?.absoluteString == "https://luals.github.io/wiki/")
    }

    @Test func aProgramOnPathReportsWhereItWasFound() {
        let found = requirements(
            Self.luaServer,
            present: ["lua-language-server": "/opt/homebrew/bin/lua-language-server"])
        #expect(found[0].isInstalled)
        #expect(found[0].resolvedPath == "/opt/homebrew/bin/lua-language-server")
    }

    @Test func oneProgramNamedTwiceIsOneRow() {
        let found = requirements(#"""
        "languages": [
          {
            "languageId": "ts", "extensions": ["ts"],
            "server": {
              "command": "deno",
              "install": { "commands": [{ "manager": "brew", "command": "brew install deno" }] }
            }
          }
        ],
        "formatters": [
          { "id": "deno-fmt", "command": "deno", "extensions": ["ts"] }
        ]
        """#)
        #expect(found.count == 1)
        #expect(found[0].program == "deno")
        #expect(found[0].needs == [.languageServer, .formatter])
        #expect(found[0].neededBy == "Language server, Formatter")
        #expect(found[0].install?.command == "brew install deno")
    }

    @Test func theRowsFollowServersThenFormattersThenAgents() {
        let found = requirements(#"""
        "languages": [
          { "languageId": "lua", "extensions": ["lua"], "server": { "command": "lua-language-server" } }
        ],
        "formatters": [
          { "id": "stylua", "command": "stylua", "extensions": ["lua"] }
        ],
        "agents": [
          { "agentId": "gemini", "name": "Gemini CLI", "command": "gemini" }
        ]
        """#)
        #expect(found.map(\.program) == ["lua-language-server", "stylua", "gemini"])
        #expect(found.map(\.neededBy) == ["Language server", "Formatter", "Agent"])
    }

    @Test func anAgentTakesItsCommandFromTheAgentInstallPlan() {
        let found = requirements(#"""
        "agents": [
          {
            "agentId": "gemini", "name": "Gemini CLI", "command": "gemini",
            "install": {
              "commands": ["npm install -g @google/gemini-cli"],
              "documentationURL": "https://example.com/gemini"
            }
          }
        ]
        """#)
        #expect(found.count == 1)
        #expect(found[0].install?.command == "npm install -g @google/gemini-cli")
        #expect(found[0].documentationURL?.absoluteString == "https://example.com/gemini")
    }

    @Test func theOfferedCommandIsTheOneThisMachineCanRun() {
        #expect(requirements(Self.luaServer, managers: [.brew]).first?.install?.manager == .brew)
        #expect(requirements(Self.luaServer, managers: [.npm]).first?.install?.manager == .npm)
        #expect(requirements(Self.luaServer, managers: [.npm, .brew]).first?.install?.manager == .brew)
    }

    @Test func noManagerHereLeavesTheDocumentationAndNoCommand() {
        let found = requirements(Self.luaServer, managers: [.cargo, .pipx])
        #expect(found[0].install == nil)
        #expect(found[0].documentationURL?.absoluteString == "https://luals.github.io/wiki/")
    }

    @Test func noManagerAtAllLeavesTheDocumentationAndNoCommand() {
        let found = requirements(Self.luaServer, managers: [])
        #expect(found[0].install == nil)
        #expect(found[0].documentationURL != nil)
    }

    @Test func aContributionWithoutAPlanStillPointsAtItsOwnPage() {
        let found = requirements(#"""
        "languages": [
          {
            "languageId": "lua", "extensions": ["lua"],
            "server": {
              "command": "lua-language-server",
              "installHint": "brew install lua-language-server",
              "documentationURL": "https://luals.github.io/"
            }
          }
        ]
        """#)
        #expect(found[0].install == nil)
        #expect(found[0].documentationURL?.absoluteString == "https://luals.github.io/")
    }

    @Test func anExtensionThatNeedsNothingHasNoRows() {
        #expect(requirements(#""themes": []"#).isEmpty)
    }

    @Test func theBadgeNamesOneProgramAndCountsMore() {
        let one = ExtensionRequirement(
            program: "lua-language-server", needs: [.languageServer],
            resolvedPath: nil, install: nil, documentationURL: nil)
        let other = ExtensionRequirement(
            program: "stylua", needs: [.formatter],
            resolvedPath: nil, install: nil, documentationURL: nil)

        #expect(ExtensionStore.requirementsBadge([]) == nil)
        #expect(ExtensionStore.requirementsBadge([one]) == "Needs lua-language-server")
        #expect(ExtensionStore.requirementsBadge([one, other]) == "Needs 2 programs")
    }
}
