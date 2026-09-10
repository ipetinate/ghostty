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

    static func with(checks: Bool, downloads: Bool) -> UpdatePolicy {
        guard checks else { return .off }
        return downloads ? .download : .check
    }

    var checksAutomatically: Bool { self != .off }

    var downloadsAutomatically: Bool { self == .download }
}
