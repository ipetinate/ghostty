import Combine
import Foundation

struct ExtensionRequirement: Identifiable, Equatable, Sendable {
    enum Need: String, Equatable, Sendable, CaseIterable {
        case languageServer
        case formatter
        case agent

        var title: String {
            switch self {
            case .languageServer: return "Language server"
            case .formatter: return "Formatter"
            case .agent: return "Agent"
            }
        }
    }

    let program: String
    let needs: [Need]
    let resolvedPath: String?
    let install: ExtensionInstallCommand?
    let documentationURL: URL?

    var id: String { program }

    var isInstalled: Bool { resolvedPath != nil }

    var neededBy: String {
        needs.map(\.title).joined(separator: ", ")
    }
}

enum ExtensionRequirements {
    struct Program: Equatable, Sendable {
        let name: String
        let needs: [ExtensionRequirement.Need]
        let plan: ExtensionInstallPlan?
        let documentationURL: URL?
    }

    static func programs(in manifest: LanguageManifest) -> [Program] {
        var order: [String] = []
        var needs: [String: [ExtensionRequirement.Need]] = [:]
        var plans: [String: ExtensionInstallPlan] = [:]
        var documentation: [String: URL] = [:]

        func note(
            _ name: String,
            _ need: ExtensionRequirement.Need,
            plan: ExtensionInstallPlan?,
            documentationURL: URL?
        ) {
            if needs[name] == nil {
                order.append(name)
                needs[name] = []
            }
            if !needs[name]!.contains(need) { needs[name]!.append(need) }
            if plans[name] == nil, let plan { plans[name] = plan }
            if documentation[name] == nil {
                documentation[name] = plan?.documentationURL ?? documentationURL
            }
        }

        for language in manifest.languages {
            guard let server = language.server else { continue }
            note(
                server.command, .languageServer,
                plan: server.installPlan, documentationURL: server.documentationURL)
        }
        for server in manifest.servers {
            note(
                server.command, .languageServer,
                plan: server.installPlan, documentationURL: server.documentationURL)
        }
        for formatter in manifest.formatters {
            note(
                formatter.command, .formatter,
                plan: formatter.installPlan, documentationURL: formatter.documentationURL)
        }
        for agent in manifest.agents {
            note(
                agent.launchCommand, .agent,
                plan: manifest.agentInstallPlans[agent.id],
                documentationURL: agent.installation.documentation)
        }

        return order.map {
            Program(
                name: $0,
                needs: needs[$0] ?? [],
                plan: plans[$0],
                documentationURL: documentation[$0])
        }
    }

    static func requirements(
        _ programs: [Program],
        managers: Set<ExtensionPackageManager>,
        locate: (String) -> String?
    ) -> [ExtensionRequirement] {
        programs.map { program in
            ExtensionRequirement(
                program: program.name,
                needs: program.needs,
                resolvedPath: locate(program.name),
                install: program.plan?.command(managers: managers),
                documentationURL: program.documentationURL)
        }
    }

    static func requirements(
        in manifest: LanguageManifest,
        managers: Set<ExtensionPackageManager>,
        locate: (String) -> String?
    ) -> [ExtensionRequirement] {
        requirements(programs(in: manifest), managers: managers, locate: locate)
    }

    static func probe(directory: URL) -> [ExtensionRequirement] {
        guard let manifest = LanguageManifest.load(directory: directory, scope: .user) else {
            return []
        }
        let programs = self.programs(in: manifest)
        guard !programs.isEmpty else { return [] }

        let searchPath = LoginEnvironment.executableSearchPath()
        let managers = Set(
            ExtensionPackageManager.allCases.filter {
                LSPProcess.locate($0.command, searchPath: searchPath) != nil
            })

        return requirements(programs, managers: managers) {
            LSPProcess.locate($0, searchPath: searchPath)
        }
    }
}

@MainActor
final class ExtensionRequirementsModel: ObservableObject {
    @Published private(set) var requirements: [ExtensionRequirement] = []
    @Published private(set) var hasProbed = false

    private var directory: URL?
    private var isProbing = false
    private var probeRequestedAgain = false

    var missing: [ExtensionRequirement] { requirements.filter { !$0.isInstalled } }

    var hasMissing: Bool { !missing.isEmpty }

    func load(directory: URL?) {
        guard directory != self.directory else { return }
        self.directory = directory
        requirements = []
        hasProbed = directory == nil
        guard directory != nil else { return }
        refresh()
    }

    func noteAvailabilityChanged() {
        LoginEnvironment.invalidate()
        refresh()
    }

    private func refresh() {
        guard let directory else { return }
        guard !isProbing else {
            probeRequestedAgain = true
            return
        }
        isProbing = true

        Task { [weak self] in
            let found = await Task.detached(priority: .utility) {
                ExtensionRequirements.probe(directory: directory)
            }.value

            guard let self else { return }
            self.isProbing = false

            let isCurrent = self.directory == directory
            if isCurrent {
                self.hasProbed = true
                self.requirements = found
            }

            guard !isCurrent || self.probeRequestedAgain else { return }
            self.probeRequestedAgain = false
            self.refresh()
        }
    }
}
