import AppKit
import SwiftUI

/// The welcome window's five steps.
///
/// Hero, then what the app does, then where the sidebar's tabs go, then the
/// theme, then the agents — with the agents last because that step is the one
/// that installs things on the machine *and* has a plan to tick, and a reader
/// who has just met this app should know what an agent hook is before being
/// offered six of them. It is also the only step with a way past it that does
/// nothing: Skip.
///
/// The placement step sits third because it is a choice about this window's
/// own shape, made against the sidebar the step before it has just named — and
/// because it takes effect on the click rather than on Finish, so it has
/// nothing to do with the agents step's plan.
///
/// The theme step sits fourth, beside it, because the two are the same kind of
/// question: what this window is to look like. It is the later of the pair
/// because it is the one that needs the network — the placement step can
/// answer offline, and putting the reachable choice first means an offline
/// reader has already made one before meeting anything that can fail.
struct WelcomeView: View {
    let close: () -> Void

    /// Everything around a step's own content: the header, the bottom bar,
    /// their rules, and the padding a step sits in. Named here because the
    /// steps size themselves against it — see `WelcomeBasicsStep.cardHeight`.
    static let chromeHeight: CGFloat = 132

    /// Internal rather than private so the order, and each step's own name,
    /// can be held by a test.
    enum Step: Int, CaseIterable {
        case hero
        case basics
        case layout
        case theme
        case agents

        /// What the header calls this step, beside the app's name. Nil for
        /// the hero, which *is* the name.
        var title: String? {
            switch self {
            case .hero: return nil
            case .basics: return "What this app does"
            case .layout: return "Where the tabs go"
            case .theme: return "Your theme and icons"
            case .agents: return "Your agents"
            }
        }

        /// The step behind this one, or nil for the first. Read by the bottom
        /// bar to decide whether there is a Back button at all.
        var previous: Step? { Step(rawValue: rawValue - 1) }
    }

    @State private var step: Step = .hero
    @Namespace private var hero

    @ObservedObject private var availability = AgentAvailability.shared
    @ObservedObject private var palette: ThemePalette = .shared

    @State private var hooks: [CodingAgent: Bool] = [:]
    @State private var registrations: [CodingAgent: Bool] = [:]
    /// What each switched-on agent is going to get. Absent means switched off.
    ///
    /// Per agent, because the row of checkboxes this replaced said one thing
    /// for everybody and the cards said another — a reader looking at six
    /// cards, each listing three things, could not tell which of the two
    /// Finish would obey.
    @State private var selection: [CodingAgent: WelcomeSetupPlan.Selection] = [:]

    /// One install run per agent, made when that agent's first install starts.
    @State private var runs: [CodingAgent: PackageInstallRun] = [:]

    /// What Finish could not do. Non-empty keeps the window open: a failure
    /// behind a window that has already closed is a failure nobody sees.
    @State private var failures: [String] = []

    /// Whether the switches have been seeded from the machine. Once, so a probe
    /// answering later never moves a switch the reader has touched.
    @State private var didSeed = false

    @State private var showsAtLaunch = WelcomeShownRecord.showsAtLaunch

    /// The theme step's choice, held here rather than in the step: Next is a
    /// button in this window's bottom bar, and going on is what installs the
    /// theme. See `WelcomeThemeSelection`.
    @StateObject private var themeSelection = WelcomeThemeSelection()

    /// That step's other choice, held here for the same reason. Two models
    /// rather than one because they install two unrelated extensions and
    /// either can fail on its own — see `WelcomeIconPackSelection`.
    @StateObject private var iconPackSelection = WelcomeIconPackSelection()

    private var accent: Color { palette.accent ?? .accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if step == .hero {
                heroStep
            } else {
                header
                Divider()
                content

                /// Takes the slack, so the steps start at the top and the bar
                /// stays at the bottom. Without it the whole column is centred
                /// in the window's fixed height and both list steps float, with
                /// dead space above the header and below the buttons.
                Spacer(minLength: 0)
            }
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            availability.refresh()
            availability.startWatchingPath()
            refreshAgentState()
        }
        .onChange(of: availability.hasProbed) { _ in seedChoicesIfNeeded() }
    }

    // MARK: Step one

    private var heroStep: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            ghosttyIconImage()
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: 128)
                .matchedGeometryEffect(id: "mark", in: hero)

            VStack(spacing: 8) {
                Text(Phantom.name)
                    .font(.system(size: 30, weight: .semibold))
                    .matchedGeometryEffect(id: "title", in: hero)

                Text("""
                    A terminal that keeps your agents, your worktrees and your \
                    diffs in one window.
                    """)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
    }

    /// What the hero becomes: the same two things, small, in the corner.
    private var header: some View {
        HStack(spacing: 10) {
            ghosttyIconImage()
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: 28)
                .matchedGeometryEffect(id: "mark", in: hero)

            Text(Phantom.name)
                .font(.system(size: 15, weight: .semibold))
                .matchedGeometryEffect(id: "title", in: hero)

            if let title = step.title {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: Steps two to five

    @ViewBuilder
    private var content: some View {
        switch step {
        case .hero:
            EmptyView()
        case .basics:
            WelcomeBasicsStep()
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        case .layout:
            WelcomeTabPlacementStep()
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        case .theme:
            WelcomeThemeStep(selection: themeSelection, packs: iconPackSelection)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        case .agents:
            agentsStep
        }
    }

    private var agentsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("""
                    Turn on the agents you use, then tick what each one gets — \
                    they do not have to match. Everything here is reversible in \
                    Settings.
                    """)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                /// Three columns in a window 1100 wide leaves each card around
                /// 350 points, which is what its five controls need: the hooks,
                /// the MCP server and the three places a button can go, each a
                /// labelled checkbox rather than a chip.
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 12), count: 3),
                    spacing: 12
                ) {
                    ForEach(CodingAgent.allCases, id: \.self) { agent in
                        card(for: agent)
                    }
                }

                Divider().padding(.vertical, 2)

                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(AgentInstallPlan.signInNote)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if !failures.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(failures, id: \.self) { failure in
                            Text(failure)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private func card(for agent: CodingAgent) -> some View {
        WelcomeAgentCard(
            agent: agent,
            state: state(of: agent),
            selection: selection[agent],
            onSelect: { step, wanted in
                var current = selection[agent] ?? .everything
                if wanted { current.steps.insert(step) } else { current.steps.remove(step) }
                selection[agent] = current
            },
            onSelectSurface: { surface, wanted in
                var current = selection[agent] ?? .everything
                if wanted {
                    current.surfaces.insert(surface)
                    current.steps.insert(.buttons)
                } else {
                    current.surfaces.remove(surface)
                    /// The parent line is a summary of its places, so the last
                    /// place going off takes the step with it.
                    if current.surfaces.isEmpty { current.steps.remove(.buttons) }
                }
                selection[agent] = current
            },
            path: availability.path(for: agent),
            hasProbed: availability.hasProbed,
            isChosen: selection[agent]?.isEmpty == false,
            onChoose: { wanted in
                /// On asks for everything the agent does not have; off asks for
                /// nothing, which is how the panel says "take it apart" —
                /// `items` reads the difference between that and what the agent
                /// has today.
                selection[agent] = wanted ? .everything : WelcomeSetupPlan.Selection()
            },
            install: AgentInstallPlan.command(
                for: agent, managers: availability.availableManagers),
            documentation: AgentInstallPlan.documentation[agent],
            onInstall: { command in start(command, for: agent) },
            run: run(for: agent))
    }

    // MARK: The bottom bar

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle("Show at startup", isOn: Binding(
                get: { showsAtLaunch },
                set: { value in
                    showsAtLaunch = value
                    WelcomeShownRecord.setShowsAtLaunch(value)
                }))
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .help("Also available under Help, and in Settings → General.")

            Spacer(minLength: 8)

            dots

            Spacer(minLength: 8)

            buttons
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(Step.allCases, id: \.rawValue) { each in
                Circle()
                    .fill(each == step ? accent : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            if let previous = step.previous {
                Button("Back") { advance(to: previous) }
                    .keyboardShortcut("[", modifiers: .command)
            }
            forward
        }
    }

    /// Going back never undoes what a step did. Every step here writes either
    /// a preference the next launch reads or a theme already applied, and each
    /// of those is idempotent, so leaving and returning costs a reader
    /// nothing and hides nothing they had chosen.
    @ViewBuilder
    private var forward: some View {
        switch step {
        case .hero:
            Button("Start") { advance(to: .basics) }
                .keyboardShortcut(.defaultAction)
        case .basics:
            Button("Next") { advance(to: .layout) }
                .keyboardShortcut(.defaultAction)
        case .layout:
            Button("Next") { advance(to: .theme) }
                .keyboardShortcut(.defaultAction)
        case .theme:
            /// Going on is what installs the chosen theme and the chosen icon
            /// pack, and it does not wait for either: a reader on a slow line
            /// must still be able to leave, and the step is honest about a
            /// download that fails afterwards because it writes nothing until
            /// one succeeds.
            ///
            /// Two calls rather than one, in the order the step reads: each
            /// answers only for its own choice, and one that has nothing left
            /// to do returns without touching the network.
            Button("Next") {
                themeSelection.goOn()
                iconPackSelection.goOn()
                advance(to: .agents)
            }
            .keyboardShortcut(.defaultAction)
        case .agents:
            Button("Skip", action: close)
            Button("Finish", action: finish)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Doing it

    private func advance(to next: Step) {
        withAnimation(.easeInOut(duration: 0.28)) { step = next }
    }

    /// Applies what the summary said, one action at a time, and reports each
    /// one that failed by name.
    ///
    /// The window closes only when everything worked. Every installer here is
    /// idempotent, so pressing Finish again after a failure is the repair.
    private func finish() {
        let work = WelcomeSetupPlan.items(selection: selection, state: agentState)

        var failed: [String] = []
        for item in work {
            guard let reason = perform(item) else { continue }
            failed.append(reason)
        }

        refreshAgentState()
        failures = failed
        if failed.isEmpty { close() }
    }

    /// Nil when it worked, otherwise the sentence to show.
    ///
    /// Both directions. The removals go through the same installers' own
    /// `uninstall` and `remove`, which are what the Settings panes call — so
    /// there is one way out of each of these and this is not a second one.
    private func perform(_ item: WelcomeSetupPlan.Item) -> String? {
        let removing = item.direction == .remove

        switch item.step {
        case .hooks:
            guard let agent = AgentHooksRegistration.agents.first(where: { $0.id == item.agent })
            else { return nil }
            guard !(removing ? agent.uninstall() : agent.install()) else { return nil }
            let what = removing ? "removing the hooks failed" : "hooks failed"
            return "\(agent.name): \(what)\(agent.lastError().map { " — \($0)" } ?? "")"

        case .mcp:
            guard let agent = MCPServerRegistration.agents.first(where: { $0.id == item.agent })
            else { return nil }
            guard !(removing ? agent.remove() : agent.register()) else { return nil }
            let what = removing ? "removing the MCP entry failed" : "MCP entry failed"
            return "\(agent.name): \(what)\(agent.lastError().map { " — \($0)" } ?? "")"

        case .buttons:
            /// Only the places the card named. Writing all three either way
            /// would move a button somebody had deliberately set the other way.
            ///
            /// `false` rather than removing the key: absent means "the default
            /// for this agent", which for Claude Code is *on* — so deleting the
            /// key would switch the button back on instead of off.
            for surface in item.surfaces {
                UserDefaults.standard.set(
                    !removing, forKey: AgentButtonDefaults.key(surface, item.agent))
            }
            return nil
        }
    }

    private func start(_ command: AgentInstallCommand, for agent: CodingAgent) {
        run(for: agent).run(command.command) { worked in
            guard worked else { return }
            availability.noteAvailabilityChanged()
        }
    }

    // MARK: State

    private var agentState: [CodingAgent: WelcomeSetupPlan.AgentState] {
        Dictionary(uniqueKeysWithValues: CodingAgent.allCases.map { ($0, state(of: $0)) })
    }

    private func state(of agent: CodingAgent) -> WelcomeSetupPlan.AgentState {
        let shown = AgentButtonSurface.allCases.filter { surface in
            UserDefaults.standard.object(
                forKey: AgentButtonDefaults.key(surface, agent)) as? Bool
                ?? AgentButtonDefaults.isShown(agent)
        }

        return WelcomeSetupPlan.AgentState(
            hooksInstalled: hooks[agent] ?? false,
            mcpRegistered: registrations[agent] ?? false,
            buttonsShown: Set(shown))
    }

    private var summary: String {
        WelcomeSetupPlan.summary(selection: selection, state: agentState)
    }

    private func refreshAgentState() {
        hooks = AgentHooksRegistration.status()
        registrations = MCPServerRegistration.status()
    }

    /// The agents on this machine start switched on, once the probe has said
    /// which those are — and only once, so an install finishing later never
    /// moves a switch somebody has since touched.
    private func seedChoicesIfNeeded() {
        guard availability.hasProbed, !didSeed else { return }
        didSeed = true

        for agent in CodingAgent.allCases {
            let current = state(of: agent)

            if availability.isInstalled(agent) {
                /// The suggestion, for an agent that is here: all of it. What
                /// it already has then produces no work, and what it does not
                /// is what Finish adds.
                selection[agent] = .everything
                continue
            }

            /// Not installed, but configured — hooks from a machine that had it
            /// once, a button somebody switched on. The card starts by asking
            /// for exactly what is there, so nothing is removed by a panel the
            /// reader only opened to look at.
            let existing = WelcomeSetupPlan.Selection(
                steps: Set(WelcomeSetupPlan.Step.allCases.filter { current.has($0) }),
                surfaces: current.buttonsShown)
            if !existing.isEmpty { selection[agent] = existing }
        }
    }

    private func run(for agent: CodingAgent) -> PackageInstallRun {
        if let existing = runs[agent] { return existing }
        let made = PackageInstallRun()
        runs[agent] = made
        return made
    }
}
