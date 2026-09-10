import Foundation

enum UpdatePolicy: String, CaseIterable {
    case off
    case check
    case download

    static let configKey = "auto-update"

    static let factoryDefault: UpdatePolicy = .download

    static func stored(_ value: String?) -> UpdatePolicy {
        guard let value, let policy = UpdatePolicy(rawValue: value) else { return factoryDefault }
        return policy
    }

    init(_ autoUpdate: Ghostty.Config.AutoUpdate) {
        self = UpdatePolicy(rawValue: autoUpdate.rawValue) ?? .off
    }

    var checksAutomatically: Bool { self != .off }

    var downloadsAutomatically: Bool { self == .download }
}
