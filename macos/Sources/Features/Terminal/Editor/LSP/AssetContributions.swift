import Foundation

struct FormatterContribution: Equatable, Sendable {
    let id: String
    let name: String
    let command: String
    let arguments: [String]
    let fileExtensions: [String]
    let installHint: String
    let installPlan: ExtensionInstallPlan?
    let documentationURL: URL?

    /// What this tool asks of a project before it rewrites its files, and
    /// where it wants to be run. Empty for a tool that simply formats.
    let projectRules: FormatterProjectRules

    static let maxFormatters = 32

    /// A ceiling on the marker list. A tool with more names than this is not
    /// describing a project, and every one of them is a `stat` per directory
    /// on a walk that runs on every save.
    static let maxMarkers = 32

    static func parse(json: [String: Any]) -> FormatterContribution? {
        guard let id = validID(json["id"]) else { return nil }
        guard let command = LanguageManifest.string(json["command"]),
              LanguageServerContribution.isLaunchable(command)
        else { return nil }
        let fileExtensions = LanguageContribution.fileExtensions(from: json["extensions"])
        guard !fileExtensions.isEmpty else { return nil }

        let arguments = (json["args"] as? [Any])?
            .compactMap { $0 as? String }
            .filter { !$0.unicodeScalars.contains(where: LanguageContribution.isUnsafeScalar) }
            .prefix(LanguageServerContribution.maxArguments)
            .map { $0 } ?? []

        return FormatterContribution(
            id: id,
            name: LanguageManifest.displayString(json["name"]) ?? id,
            command: command,
            arguments: arguments,
            fileExtensions: fileExtensions,
            installHint: LanguageServerContribution.installHint(json["installHint"]),
            installPlan: ExtensionInstallPlan.parse(json["install"]),
            documentationURL: LanguageServerContribution.documentationURL(json["documentationURL"]),
            projectRules: projectRules(json: json)
        )
    }

    static func projectRules(json: [String: Any]) -> FormatterProjectRules {
        FormatterProjectRules(
            markers: markers(from: json["projectMarkers"]),
            localBinary: relativePath(json["localBinary"]),
            workingDirectory: LanguageManifest.string(json["workingDirectory"])
                .flatMap(FormatterWorkingDirectory.init(rawValue:)) ?? .file
        )
    }

    /// The markers, in the order written, dropping only the entries that
    /// cannot be looked for.
    ///
    /// Lenient one entry at a time, the way the rest of the manifest is: a
    /// list with one bad name in it loses that name, not the list.
    static func markers(from value: Any?) -> [FormatterMarker] {
        let raw = (value as? [Any]) ?? []
        return raw.compactMap(marker(from:))
            .prefix(maxMarkers)
            .map { $0 }
    }

    static func marker(from value: Any) -> FormatterMarker? {
        if let name = relativePath(value) { return .file(name) }
        guard let object = value as? [String: Any],
              let file = relativePath(object["file"]),
              let key = LanguageManifest.string(object["containsKey"]), key.count <= 64,
              !key.unicodeScalars.contains(where: LanguageContribution.isUnsafeScalar)
        else { return nil }
        return .key(named: key, inFile: file)
    }

    /// A path a walk may append to a directory it is visiting.
    ///
    /// The containment rule `LanguageContribution.containedURL` applies to the
    /// extension's own directory cannot be applied here — these resolve
    /// against the reader's project, which does not exist at parse time. So
    /// the shape is checked instead, and it is checked strictly: absolute
    /// paths, home-relative paths and any `..` segment are refused, because
    /// each of them is a manifest reaching outside the tree it was pointed at.
    static func relativePath(_ value: Any?) -> String? {
        guard let raw = LanguageManifest.string(value), raw.count <= 128 else { return nil }
        guard !raw.hasPrefix("/"), !raw.hasPrefix("~"), !raw.hasPrefix("./") else { return nil }
        guard !raw.unicodeScalars.contains(where: LanguageContribution.isUnsafeScalar) else {
            return nil
        }
        let segments = raw.split(separator: "/", omittingEmptySubsequences: false)
        guard !segments.isEmpty else { return nil }
        guard segments.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        return raw
    }

    static func validID(_ value: Any?) -> String? {
        guard let raw = LanguageManifest.string(value), raw.count <= 64 else { return nil }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_-")
        guard raw.allSatisfy(allowed.contains) else { return nil }
        return raw
    }
}

struct ThemeContribution: Equatable, Sendable {
    enum Appearance: String, Equatable, Sendable {
        case dark
        case light
    }

    let name: String
    let fileURL: URL
    let appearance: Appearance?

    static let maxThemes = 64

    static let maxBytes = 64 * 1024

    static let colorKeys: Set<String> = [
        "background", "foreground", "palette",
        "cursor-color", "cursor-text",
        "selection-background", "selection-foreground",
        "bold-color",
        "split-divider-color", "unfocused-split-fill",
        "search-background", "search-foreground",
        "search-selected-background", "search-selected-foreground",
        "window-titlebar-background", "window-titlebar-foreground",
        "macos-icon-ghost-color", "macos-icon-screen-color",
    ]

    static let behaviorKeys: Set<String> = [
        "auto-update", "auto-update-channel",
        "background-image", "bell-audio-path", "custom-shader", "gtk-custom-css",
        "macos-custom-icon",
        "clipboard-codepoint-map", "clipboard-paste-bracketed-safe",
        "clipboard-paste-protection", "clipboard-read", "clipboard-write",
        "command", "env", "initial-command", "wait-after-command", "working-directory",
        "config-default-files", "config-file", "theme",
        "enquiry-response", "title-report", "vt-kam-allowed",
        "input", "key-remap", "keybind", "macos-applescript", "macos-shortcuts",
        "link", "link-osc8", "link-url",
        "shell-integration", "shell-integration-features",
    ]

    static func parse(json: [String: Any], root: URL) -> ThemeContribution? {
        guard let name = LanguageManifest.displayString(json["name"]), name.count <= 64 else {
            return nil
        }
        guard let fileURL = LanguageContribution.containedURL(json["path"], root: root),
              isColorOnlyThemeFile(at: fileURL)
        else { return nil }

        return ThemeContribution(
            name: name,
            fileURL: fileURL,
            appearance: LanguageManifest.string(json["appearance"]).flatMap(Appearance.init(rawValue:))
        )
    }

    static func isColorOnlyThemeFile(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize, size <= maxBytes,
              let contents = try? String(contentsOf: url, encoding: .utf8)
        else { return false }
        return isColorOnly(contents)
    }

    static func isColorOnly(_ contents: String) -> Bool {
        var setsAColor = false
        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let eq = trimmed.firstIndex(of: "=") else { return false }
            let key = String(trimmed[..<eq])
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            if behaviorKeys.contains(key) { return false }
            if colorKeys.contains(key) { setsAColor = true }
        }
        return setsAColor
    }
}

struct IconThemeContribution: Equatable, Sendable {
    let name: String
    let directoryURL: URL

    static let maxIconThemes = 16

    static func parse(json: [String: Any], root: URL) -> IconThemeContribution? {
        guard let name = LanguageManifest.displayString(json["name"]), name.count <= 64 else {
            return nil
        }
        guard let directoryURL = LanguageContribution.containedURL(json["path"], root: root),
              (try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        else { return nil }
        return IconThemeContribution(name: name, directoryURL: directoryURL)
    }
}
