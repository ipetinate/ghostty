import AppKit
import Foundation

enum ExtensionSuggestions {
    static func candidates(
        forFileName fileName: String,
        in index: ExtensionIndex?,
        installed: Set<String>
    ) -> [ExtensionIndex.Entry] {
        guard let index else { return [] }
        let suffix = ExtensionIndex.Entry.normalizedFileType(
            (fileName as NSString).pathExtension)
        guard !suffix.isEmpty else { return [] }

        let byFileType = index.extensions.filter {
            !installed.contains($0.id) && $0.fileTypes.contains(suffix)
        }
        guard byFileType.isEmpty else { return byFileType }

        return index.extensions.filter {
            !installed.contains($0.id)
                && $0.contributes.contains(where: contributesLanguageSupport)
                && $0.languages.contains(suffix)
        }
    }

    static func entries(
        ids: [String],
        in index: ExtensionIndex?,
        installed: Set<String>
    ) -> [ExtensionIndex.Entry] {
        guard let index else { return [] }
        let wanted = ids.filter { !installed.contains($0) }
        guard !wanted.isEmpty else { return [] }
        let byID = Dictionary(index.extensions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return wanted.compactMap { byID[$0] }
    }

    static func icons(for entries: [ExtensionIndex.Entry]) -> [PhantomToastIcon] {
        entries.compactMap { entry in
            guard let source = ExtensionIconSource.of(entry: entry, file: nil),
                  case .inline(_, let data) = source,
                  let image = NSImage(data: data)
            else { return .symbol("puzzlepiece.extension") }
            return .image(image, id: entry.id)
        }
    }

    private static func contributesLanguageSupport(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered == "languages" || lowered == "grammars" || lowered == "languageservers"
    }
}

struct ProjectSuggestionsFile {
    static let relativePath = ".phantom/suggestions.json"
    static let maximumBytes = 64 * 1024

    let root: URL
    let extensionIDs: [String]
    let message: String?

    static func find(startingAt directory: URL, stoppingAbove ceiling: URL? = nil) -> ProjectSuggestionsFile? {
        var current = directory.standardizedFileURL
        let stop = (ceiling ?? URL(fileURLWithPath: NSHomeDirectory())).standardizedFileURL
        var visited = 0

        while visited < 24 {
            if let found = load(projectRoot: current) { return found }
            guard current.path != stop.path, current.path != "/" else { return nil }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            guard parent.path != current.path else { return nil }
            current = parent
            visited += 1
        }
        return nil
    }

    static func load(projectRoot: URL) -> ProjectSuggestionsFile? {
        let url = projectRoot.appendingPathComponent(relativePath)
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              size <= maximumBytes,
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let ids = (json["extensions"] as? [Any] ?? [])
            .compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !ids.isEmpty else { return nil }

        let message = (json["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProjectSuggestionsFile(
            root: projectRoot.standardizedFileURL,
            extensionIDs: Array(ids.prefix(24)),
            message: (message?.isEmpty ?? true) ? nil : message)
    }
}
