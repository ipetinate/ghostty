import SwiftUI

struct ExtensionRequirementsSection: View {
    let requirements: [ExtensionRequirement]
    let onRunFinished: () -> Void

    @StateObject private var run = PackageInstallRun()
    @State private var running: String?
    @State private var lastRun: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Requirements")
                    .font(.headline)
                Text(verbatim: summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(requirements.enumerated()), id: \.element.id) { index, requirement in
                    if index > 0 { Divider() }
                    row(requirement)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.04))
            )
        }
    }

    private var missingCount: Int { requirements.filter { !$0.isInstalled }.count }

    private var summary: String {
        missingCount == 1
            ? "1 program this extension needs is not installed"
            : "\(missingCount) programs this extension needs are not installed"
    }

    private func row(_ requirement: ExtensionRequirement) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: requirement.isInstalled ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(requirement.isInstalled ? Color.green : Color.orange)
                .font(.system(size: 13))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: requirement.program)
                        .font(.system(size: 12, design: .monospaced))
                    Text(verbatim: requirement.neededBy)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                state(requirement)

                if running == requirement.program {
                    progress
                } else if running == nil, lastRun == requirement.program, let failure = run.failure {
                    Text(verbatim: failure)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            control(requirement)
        }
    }

    @ViewBuilder
    private func state(_ requirement: ExtensionRequirement) -> some View {
        if let path = requirement.resolvedPath {
            HStack(spacing: 5) {
                Text("Installed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        } else if let install = requirement.install {
            HStack(spacing: 5) {
                Text("Missing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: install.command)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        } else {
            Text(verbatim: unavailableReason(requirement))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func unavailableReason(_ requirement: ExtensionRequirement) -> String {
        requirement.documentationURL == nil
            ? "Missing. This extension says nothing about how to install it."
            : "Missing. No package manager this extension offers is installed here."
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let fraction = run.progress {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 120)
                    Text(verbatim: percentage(fraction))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                    Text("Installing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(run.recentOutput, id: \.self) { line in
                Text(verbatim: line)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.top, 2)
    }

    private func percentage(_ fraction: Double) -> String {
        String(Int((fraction * 100).rounded())) + "%"
    }

    @ViewBuilder
    private func control(_ requirement: ExtensionRequirement) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            if !requirement.isInstalled, running != requirement.program,
               let install = requirement.install {
                Button("Install") { start(install, for: requirement.program) }
                    .controlSize(.small)
                    .disabled(run.isRunning)
                    .help("Runs \(install.command) in a terminal with your login environment")
            }
            if let url = requirement.documentationURL {
                Link("Documentation", destination: url)
                    .font(.caption)
            }
        }
    }

    private func start(_ install: ExtensionInstallCommand, for program: String) {
        guard !run.isRunning else { return }
        running = program
        lastRun = program
        run.run(install.command) { _ in
            running = nil
            onRunFinished()
        }
    }
}
