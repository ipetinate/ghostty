import AppKit
import Foundation

enum ExtensionIconSource: Sendable {
    case file(URL)
    case inline(String, Data)

    var key: String {
        switch self {
        case .file(let url): return "file:" + url.standardizedFileURL.path
        case .inline(let identity, _): return "inline:" + identity
        }
    }

    static func of(entry: ExtensionIndex.Entry, file: URL?) -> ExtensionIconSource? {
        if let file { return .file(file) }
        guard let data = entry.card?.iconData else { return nil }
        return .inline("\(entry.id)@\(entry.version)", data)
    }
}

@MainActor
final class ExtensionIconCache {
    static let shared = ExtensionIconCache()

    static let limit = 128

    private var images: [String: NSImage] = [:]
    private var failures: Set<String> = []
    private var order: [String] = []

    func image(forKey key: String) -> NSImage? {
        images[key]
    }

    func knows(_ key: String) -> Bool {
        images[key] != nil || failures.contains(key)
    }

    func remember(_ image: NSImage?, forKey key: String) {
        guard !knows(key) else { return }
        if let image {
            images[key] = image
        } else {
            failures.insert(key)
        }
        order.append(key)
        while order.count > Self.limit {
            let dropped = order.removeFirst()
            images.removeValue(forKey: dropped)
            failures.remove(dropped)
        }
    }

    func forget() {
        images.removeAll()
        failures.removeAll()
        order.removeAll()
    }
}
