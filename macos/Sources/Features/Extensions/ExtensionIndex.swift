import Foundation

struct ExtensionIndex: Equatable, Sendable {
    /// How often an extension's release assets were downloaded from GitHub,
    /// as the registry's build step folded them into the index.
    ///
    /// GitHub has counted every one of those downloads since the first
    /// release, so the number is retroactive and needs nothing from this
    /// app: no request, no token, no report of its own installs. An index
    /// built before the registry started writing the key carries none, which
    /// is why the whole value is optional rather than a zero.
    struct Downloads: Equatable, Sendable {
        let total: Int
        let current: Int
    }

    struct Entry: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let version: String
        let publisher: String
        let summary: String
        let homepage: URL?
        let minimumPhantomVersion: String?
        let contributes: [String]
        let languages: [String]
        let downloadURL: URL
        let sha256: String
        let bytes: Int
        var downloads: Downloads?
        var card: ExtensionCard?
        var categories: [String] = []
    }

    let generatedAt: Date?
    let repository: URL?
    let extensions: [Entry]
}

extension ExtensionIndex {
    enum ParseError: Error, Equatable {
        case notAnObject
        case missingSchemaVersion
        case unsupportedSchemaVersion(String)

        var message: String {
            switch self {
            case .notAnObject:
                return "its index is not a JSON object"
            case .missingSchemaVersion:
                return "its index declares no schema version"
            case .unsupportedSchemaVersion(let declared):
                return "its index uses schema version \(declared), which this Phantom cannot read"
            }
        }
    }

    static let currentSchemaVersion = 1

    static let maxBytes = 4 * 1024 * 1024

    static let maxArchiveBytes = 64 * 1024 * 1024

    static let maxEntries = 2048

    static func parse(_ data: Data) throws -> ExtensionIndex {
        guard data.count <= maxBytes,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { throw ParseError.notAnObject }

        guard let declared = json["schemaVersion"] else { throw ParseError.missingSchemaVersion }
        guard integer(declared) == currentSchemaVersion else {
            throw ParseError.unsupportedSchemaVersion(String(describing: declared))
        }

        let rawEntries = json["extensions"] as? [Any] ?? []
        var seen: Set<String> = []
        let entries = rawEntries
            .prefix(maxEntries)
            .compactMap { $0 as? [String: Any] }
            .compactMap(Entry.parse)
            .filter { seen.insert($0.id).inserted }

        return ExtensionIndex(
            generatedAt: date(json["generatedAt"]),
            repository: LanguageServerContribution.documentationURL(json["repository"]),
            extensions: entries
        )
    }

    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        guard CFGetTypeID(number as CFTypeRef) != CFBooleanGetTypeID() else { return nil }
        return Int(exactly: number.doubleValue)
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = LanguageManifest.string(value) else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }
}

extension ExtensionIndex.Entry {
    static let maxListItems = 64

    static func parse(_ json: [String: Any]) -> ExtensionIndex.Entry? {
        guard let id = LanguageManifest.validID(json["id"]),
              let name = LanguageManifest.displayString(json["name"]),
              let version = LanguageManifest.string(json["version"]),
              SemanticVersion.isValid(version),
              let publisher = LanguageManifest.displayString(json["publisher"]),
              let download = json["download"] as? [String: Any],
              let downloadURL = secureURL(download["url"]),
              let sha256 = digest(download["sha256"]),
              let bytes = ExtensionIndex.integer(download["bytes"]),
              bytes > 0, bytes <= ExtensionIndex.maxArchiveBytes
        else { return nil }

        return ExtensionIndex.Entry(
            id: id,
            name: name,
            version: version,
            publisher: publisher,
            summary: LanguageManifest.displayString(json["description"]) ?? "",
            homepage: LanguageServerContribution.documentationURL(json["homepage"]),
            minimumPhantomVersion: LanguageManifest.string(json["phantom"])
                .flatMap { SemanticVersion.isValid($0) ? $0 : nil },
            contributes: displayList(json["contributes"]),
            languages: languageList(json["languages"]),
            downloadURL: downloadURL,
            sha256: sha256,
            bytes: bytes,
            downloads: downloads(json["downloads"]),
            card: (json["card"] as? [String: Any]).flatMap(ExtensionCard.parse),
            categories: displayList(json["categories"])
        )
    }

    /// Reads the entry's download counts, and refuses anything but two
    /// counts that could be counts: a negative total, or one this build
    /// cannot read, leaves the entry with none, and the store then shows
    /// nothing rather than a number it made up.
    static func downloads(_ value: Any?) -> ExtensionIndex.Downloads? {
        guard let json = value as? [String: Any],
              let total = ExtensionIndex.integer(json["total"]),
              total >= 0
        else { return nil }
        let current = ExtensionIndex.integer(json["current"]) ?? 0
        return ExtensionIndex.Downloads(total: total, current: max(0, min(current, total)))
    }

    static func secureURL(_ value: Any?) -> URL? {
        guard let url = LanguageServerContribution.documentationURL(value),
              url.scheme?.lowercased() == "https"
        else { return nil }
        return url
    }

    static func digest(_ value: Any?) -> String? {
        guard let raw = LanguageManifest.string(value)?.lowercased(), raw.count == 64 else { return nil }
        guard raw.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { return nil }
        return raw
    }

    private static func displayList(_ value: Any?) -> [String] {
        let raw = (value as? [Any]) ?? []
        var seen: Set<String> = []
        return raw
            .compactMap { LanguageManifest.displayString($0) }
            .filter { seen.insert($0).inserted }
            .prefix(maxListItems)
            .map { $0 }
    }

    private static func languageList(_ value: Any?) -> [String] {
        let raw = (value as? [Any]) ?? []
        var seen: Set<String> = []
        return raw
            .compactMap { LanguageContribution.validLanguageID($0) }
            .filter { seen.insert($0).inserted }
            .prefix(maxListItems)
            .map { $0 }
    }
}
