import AppKit
import Foundation

@MainActor
enum SuggestionToasts {
    private static var askedForIndex = false
    private static let runner = PackageInstallRun()

    static func offerLanguageSupport(for url: URL, to center: ToastCenter) {
        let fileName = url.lastPathComponent
        let suffix = ExtensionIndex.Entry.normalizedFileType((fileName as NSString).pathExtension)
        guard !suffix.isEmpty else { return }
        guard LanguageResolver.shared.languageID(forFileName: fileName) == nil else { return }

        let id = "language-support:" + suffix
        guard !center.wasDismissed(id: id), !center.isShowing(id: id) else { return }

        let store = ExtensionStore.shared
        guard let index = store.index else {
            requestIndexOnce()
            return
        }

        let installed = Set(store.installed.map(\.id))
        let candidates = ExtensionSuggestions.candidates(
            forFileName: fileName, in: index, installed: installed)
        guard !candidates.isEmpty else { return }

        let title: String
        let message: String?
        if candidates.count == 1 {
            title = "Install \(candidates[0].name) for .\(suffix) files"
            message = candidates[0].summary.isEmpty ? nil : candidates[0].summary
        } else {
            title = "\(candidates.count) extensions support .\(suffix) files"
            message = candidates.prefix(3).map(\.name).joined(separator: ", ")
        }

        var actions: [PhantomToastAction] = [
            PhantomToastAction(id: "install", title: installTitle(candidates), emphasis: .primary) {
                install(candidates, from: id, to: center)
            }
        ]
        if candidates.count > 1 {
            actions.append(PhantomToastAction(id: "settings", title: "Settings") {
                center.dismiss(id: id)
                openSettings()
            })
        }

        center.present(
            .standard(
                id: id,
                icons: ExtensionSuggestions.icons(for: candidates),
                title: title,
                message: message,
                actions: actions))
    }

    static func offerProjectSuggestions(near directory: URL, to center: ToastCenter) {
        guard let file = ProjectSuggestionsFile.find(startingAt: directory) else { return }

        let id = "project-suggestions:" + file.root.path
        guard !center.wasDismissed(id: id), !center.isShowing(id: id) else { return }

        let store = ExtensionStore.shared
        guard let index = store.index else {
            requestIndexOnce()
            return
        }

        let installed = Set(store.installed.map(\.id))
        let entries = ExtensionSuggestions.entries(
            ids: file.extensionIDs, in: index, installed: installed)
        guard !entries.isEmpty else { return }

        center.present(
            .standard(
                id: id,
                icons: ExtensionSuggestions.icons(for: entries),
                title: "\(file.root.lastPathComponent) suggests \(entries.count) "
                    + (entries.count == 1 ? "extension" : "extensions"),
                message: file.message ?? entries.prefix(4).map(\.name).joined(separator: ", "),
                actions: [
                    PhantomToastAction(id: "install", title: installTitle(entries), emphasis: .primary) {
                        install(entries, from: id, to: center)
                    }
                ]))
    }

    private static func installTitle(_ entries: [ExtensionIndex.Entry]) -> String {
        entries.count == 1 ? "Install" : "Install all"
    }

    private static func install(
        _ entries: [ExtensionIndex.Entry],
        from toastID: String,
        to center: ToastCenter
    ) {
        Task {
            let store = ExtensionStore.shared
            for (offset, entry) in entries.enumerated() {
                center.update(id: toastID) {
                    $0.status = entries.count == 1
                        ? "Installing \(entry.name)…"
                        : "Installing \(entry.name) — \(offset + 1) of \(entries.count)"
                }
                await store.install(entry)
            }

            center.withdraw(id: toastID)

            let failed = entries.filter { store.errors[$0.id] != nil }
            if !failed.isEmpty {
                center.present(
                    .standard(
                        id: toastID + ":failed",
                        icons: ExtensionSuggestions.icons(for: failed),
                        title: failed.count == 1
                            ? "\(failed[0].name) did not install"
                            : "\(failed.count) extensions did not install",
                        message: store.errors[failed[0].id],
                        actions: [
                            PhantomToastAction(id: "settings", title: "Settings") {
                                center.dismiss(id: toastID + ":failed")
                                openSettings()
                            }
                        ]))
                return
            }

            let installed = entries.filter { store.errors[$0.id] == nil }
            for entry in installed {
                await store.refreshRequirements(id: entry.id)
                offerMissingPrograms(for: entry, to: center)
            }
        }
    }

    private static func offerMissingPrograms(
        for entry: ExtensionIndex.Entry,
        to center: ToastCenter
    ) {
        guard let missing = ExtensionStore.shared.pendingRequirements[entry.id], !missing.isEmpty
        else { return }

        let id = "requirements:" + entry.id
        guard !center.wasDismissed(id: id) else { return }

        let names = missing.map(\.program).joined(separator: ", ")
        var actions: [PhantomToastAction] = []

        if let runnable = missing.first(where: { $0.install != nil }), let command = runnable.install {
            actions.append(
                PhantomToastAction(id: "run", title: "Install \(runnable.program)", emphasis: .primary) {
                    center.update(id: id) { $0.status = "Running \(command.command)" }
                    runner.run(command.command) { _ in
                        center.update(id: id) { $0.status = nil }
                        Task {
                            await ExtensionStore.shared.refreshRequirements(id: entry.id)
                            center.withdraw(id: id)
                            offerMissingPrograms(for: entry, to: center)
                        }
                    }
                })
        }

        if let documentation = missing.compactMap(\.documentationURL).first {
            actions.append(
                PhantomToastAction(id: "docs", title: "Docs") {
                    NSWorkspace.shared.open(documentation)
                })
        }

        center.present(
            .standard(
                id: id,
                icons: [.symbol("terminal")],
                title: "\(entry.name) still needs \(names)",
                message: missing.map(\.neededBy).joined(separator: ", ")
                    + ", not found on your PATH.",
                actions: actions))
    }

    private static func openSettings() {
        guard let delegate = NSApp.delegate as? AppDelegate else { return }
        SettingsWindowController.shared.show(ghostty: delegate.ghostty)
    }

    private static func requestIndexOnce() {
        guard !askedForIndex else { return }
        askedForIndex = true
        Task { await ExtensionStore.shared.refresh() }
    }
}
