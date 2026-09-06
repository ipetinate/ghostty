import Foundation

enum ExtensionPackageManager: String, CaseIterable, Sendable, Hashable {
    case brew
    case npm
    case pnpm
    case yarn
    case cargo
    case gem
    case pipx
    case go
    case dotnet
    case nix

    var command: String { rawValue }

    var displayName: String {
        switch self {
        case .brew: return "Homebrew"
        case .npm: return "npm"
        case .pnpm: return "pnpm"
        case .yarn: return "Yarn"
        case .cargo: return "Cargo"
        case .gem: return "RubyGems"
        case .pipx: return "pipx"
        case .go: return "Go"
        case .dotnet: return ".NET"
        case .nix: return "Nix"
        }
    }
}

struct ExtensionInstallCommand: Equatable, Sendable {
    let manager: ExtensionPackageManager
    let command: String
    let uninstall: String?
}

struct ExtensionInstallPlan: Equatable, Sendable {
    let commands: [ExtensionInstallCommand]
    let documentationURL: URL?

    static let forbiddenFragments = ["curl", "|", "sudo", ";", "&&", "&", "$(", "`", "<", ">"]

    static let maxCommands = 8

    static let maxCommandLength = 256

    func command(managers available: Set<ExtensionPackageManager>) -> ExtensionInstallCommand? {
        commands.first { available.contains($0.manager) }
    }

    static func parse(_ value: Any?) -> ExtensionInstallPlan? {
        guard let json = value as? [String: Any] else { return nil }

        let commands = (json["commands"] as? [Any] ?? [])
            .prefix(maxCommands)
            .compactMap(installCommand)

        let documentationURL = LanguageServerContribution.documentationURL(json["documentationURL"])
        guard !commands.isEmpty || documentationURL != nil else { return nil }

        return ExtensionInstallPlan(commands: commands, documentationURL: documentationURL)
    }

    static func installCommand(_ value: Any) -> ExtensionInstallCommand? {
        if let raw = value as? String {
            return command(raw, declared: nil, uninstall: nil)
        }
        guard let json = value as? [String: Any] else { return nil }
        return command(
            LanguageManifest.string(json["command"]),
            declared: LanguageManifest.string(json["manager"]),
            uninstall: LanguageManifest.string(json["uninstall"]))
    }

    private static func command(
        _ raw: String?,
        declared: String?,
        uninstall: String?
    ) -> ExtensionInstallCommand? {
        guard let raw else { return nil }
        guard let manager = manager(declared: declared, command: raw) else { return nil }
        guard let command = runnable(raw, manager: manager) else { return nil }
        return ExtensionInstallCommand(
            manager: manager,
            command: command,
            uninstall: uninstall.flatMap { runnable($0, manager: manager) })
    }

    private static func manager(
        declared: String?,
        command: String
    ) -> ExtensionPackageManager? {
        if let declared { return ExtensionPackageManager(rawValue: declared) }
        let first = command.split(separator: " ").first.map(String.init) ?? ""
        return ExtensionPackageManager(rawValue: first)
    }

    private static func runnable(_ raw: String, manager: ExtensionPackageManager) -> String? {
        let command = raw.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty, command.count <= maxCommandLength,
              command.hasPrefix(manager.command + " "),
              !command.unicodeScalars.contains(where: LanguageContribution.isUnsafeScalar),
              !forbiddenFragments.contains(where: command.contains)
        else { return nil }
        return command
    }
}
