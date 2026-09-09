import Foundation

/// The one method that lets a contributed view reach the network, and the
/// rules it reaches it under.
///
/// The page itself cannot open a socket: its policy is
/// `default-src 'none'` with no `connect-src`, so `fetch` and
/// `XMLHttpRequest` are dead in it. It asks the app instead, which is what
/// makes an HTTP client possible without loosening that policy — and what
/// makes this file the most dangerous one in the feature, because the app
/// has the reach the page was denied.
///
/// So the app is narrower than a browser, not wider:
///
/// * `http` and `https` only. No `file:`, no `data:`, no custom scheme, so
///   the method cannot be turned into a file reader.
/// * No credentials in the URL, no cookie store, no keychain, no client
///   certificate. Nothing the reader is signed in to is attached.
/// * No redirect is followed. A 3xx comes back as a 3xx with its
///   `Location`, so a public URL cannot bounce the app onto a private one.
/// * The link-local metadata range and the reserved ranges are refused
///   outright, at any time, by anybody.
/// * Loopback and the private ranges are refused too, unless the reader has
///   switched `ExtensionViewHTTP.allowsPrivateNetwork` on. It is off by
///   default: an extension from a store must not be able to talk to
///   whatever is listening on this machine because the reader opened its
///   window.
///
/// One gap is worth naming rather than hiding: the check is on the host as
/// written, so a public name whose DNS answer points into a private range
/// is not caught here. Closing that means checking the address the socket
/// actually connected to, which `URLSession` reports only after the request
/// has been sent.
enum ExtensionViewHTTP {
    struct Request: Equatable, Sendable {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: String?
    }

    struct Response: Equatable, Sendable {
        let status: Int
        let url: String
        let headers: [String: String]

        /// UTF-8 text when the body is text, otherwise nil and `base64` is
        /// filled instead. A page that asked for a PNG gets bytes it can
        /// put in a `data:` URL rather than a string with holes in it.
        let text: String?
        let base64: String?
        let bytes: Int
        let milliseconds: Int
    }

    enum Refusal: Equatable, Sendable {
        case scheme(String)
        case noHost
        case credentialsInURL
        case metadataEndpoint(String)
        case reservedAddress(String)
        case privateAddress(String)

        var message: String {
            switch self {
            case .scheme(let scheme):
                return "\(scheme) is not a scheme this method will request; use http or https."
            case .noHost:
                return "The URL has no host."
            case .credentialsInURL:
                return "The URL carries a user name or a password; put them in a header instead."
            case .metadataEndpoint(let host):
                return "\(host) is a host metadata endpoint, which no extension may request."
            case .reservedAddress(let host):
                return "\(host) is a reserved address."
            case .privateAddress(let host):
                return "\(host) is on this machine or its private network. "
                    + "Switch on \(ExtensionViewHTTP.allowsPrivateNetworkKey) to permit it."
            }
        }
    }

    enum AddressClass: Equatable, Sendable {
        case ordinary
        case metadata
        case reserved
        case privateNetwork
    }

    static let methods: Set<String> = ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]

    /// Headers the app writes itself, or that describe a connection this
    /// method does not let the page have an opinion about.
    static let deniedHeaders: Set<String> = [
        "host", "content-length", "connection", "keep-alive", "proxy-authorization",
        "proxy-connection", "te", "trailer", "transfer-encoding", "upgrade",
    ]

    static let maxHeaders = 32
    static let maxHeaderLength = 4096
    static let maxURLLength = 4096
    static let maxRequestBodyBytes = 1024 * 1024
    static let maxResponseBytes = 4 * 1024 * 1024
    static let timeout: TimeInterval = 30

    static let allowsPrivateNetworkKey = "ExtensionViewHTTPAllowsPrivateNetwork"

    static var allowsPrivateNetwork: Bool {
        UserDefaults.standard.bool(forKey: allowsPrivateNetworkKey)
    }

    // MARK: The URL gate

    static func refusal(for url: URL, allowingPrivateNetwork: Bool) -> Refusal? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .scheme(url.scheme ?? "a URL with no scheme")
        }
        guard url.user == nil, url.password == nil else { return .credentialsInURL }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return .noHost }

        switch addressClass(ofHost: host) {
        case .ordinary: return nil
        case .metadata: return .metadataEndpoint(host)
        case .reserved: return .reservedAddress(host)
        case .privateNetwork: return allowingPrivateNetwork ? nil : .privateAddress(host)
        }
    }

    /// Classifies a host as written. Names first, then literals, because a
    /// name is what a manifest and a `.bru` file actually carry.
    static func addressClass(ofHost host: String) -> AddressClass {
        if let octets = ipv4Octets(host) { return addressClass(ofIPv4: octets) }
        if let classified = ipv6Class(host) { return classified }
        return addressClass(ofName: host)
    }

    static func addressClass(ofName name: String) -> AddressClass {
        let trimmed = name.hasSuffix(".") ? String(name.dropLast()) : name
        if trimmed == "metadata" || trimmed.hasSuffix(".internal") { return .metadata }
        if trimmed == "localhost" || trimmed.hasSuffix(".localhost") { return .privateNetwork }
        if trimmed == "ip6-localhost" || trimmed == "ip6-loopback" { return .privateNetwork }
        if trimmed.hasSuffix(".local") || trimmed.hasSuffix(".home.arpa") { return .privateNetwork }
        return .ordinary
    }

    static func addressClass(ofIPv4 octets: [Int]) -> AddressClass {
        switch octets[0] {
        case 0, 224...255: return .reserved
        case 127, 10: return .privateNetwork
        case 169 where octets[1] == 254: return .metadata
        case 172 where (16...31).contains(octets[1]): return .privateNetwork
        case 192 where octets[1] == 168: return .privateNetwork
        case 192 where octets[1] == 0 && octets[2] == 0: return .privateNetwork
        case 100 where (64...127).contains(octets[1]): return .privateNetwork
        case 198 where (18...19).contains(octets[1]): return .privateNetwork
        default: return .ordinary
        }
    }

    static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            guard let value = Int(part), value <= 255 else { return nil }
            return value
        }
        return octets.count == 4 ? octets : nil
    }

    /// Nil when the host is not an IPv6 literal.
    ///
    /// Only the first hextet is inspected, which is all the prefixes that
    /// matter here need: `::1` and `::` are exact, unique-local is
    /// `fc00::/7`, link-local is `fe80::/10` and multicast is `ff00::/8`.
    /// An IPv4-mapped address is classified by the address it maps.
    static func ipv6Class(_ host: String) -> AddressClass? {
        let bare = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
        guard bare.contains(":") else { return nil }
        let zoneless = bare.split(separator: "%", maxSplits: 1).first.map(String.init) ?? bare

        if zoneless == "::" { return .reserved }
        if zoneless == "::1" { return .privateNetwork }
        if zoneless == "fd00:ec2::254" { return .metadata }

        if let mapped = zoneless.split(separator: ":").last.map(String.init), let octets = ipv4Octets(mapped) {
            return addressClass(ofIPv4: octets)
        }

        guard let first = zoneless.split(separator: ":").first.map(String.init), !first.isEmpty else {
            return .reserved
        }
        if first.hasPrefix("ff") { return .reserved }
        if first.hasPrefix("fc") || first.hasPrefix("fd") { return .privateNetwork }
        if let value = Int(first, radix: 16), (0xfe80...0xfebf).contains(value) { return .privateNetwork }
        return .ordinary
    }
}

extension ExtensionViewHTTP.Request {
    static func parse(_ params: [String: Any]) -> Result<Self, ExtensionViewRejection> {
        guard let raw = LanguageManifest.string(params["url"]), raw.count <= ExtensionViewHTTP.maxURLLength,
              !raw.unicodeScalars.contains(where: LanguageContribution.isUnsafeScalar),
              let url = URL(string: raw)
        else { return .failure(.badParameters("'url' must be an absolute http or https URL.")) }

        let method = (LanguageManifest.string(params["method"]) ?? "GET").uppercased()
        guard ExtensionViewHTTP.methods.contains(method) else {
            return .failure(.badParameters(
                "'method' must be one of \(ExtensionViewHTTP.methods.sorted().joined(separator: ", "))."))
        }

        switch headers(params["headers"]) {
        case .failure(let rejection):
            return .failure(rejection)
        case .success(let headers):
            var body: String?
            if let raw = params["body"] {
                guard let text = raw as? String, text.utf8.count <= ExtensionViewHTTP.maxRequestBodyBytes else {
                    return .failure(.badParameters(
                        "'body' must be a string of at most \(ExtensionViewHTTP.maxRequestBodyBytes) bytes."))
                }
                body = text
            }
            guard method != "GET" && method != "HEAD" || body == nil else {
                return .failure(.badParameters("A \(method) carries no body."))
            }
            return .success(Self(method: method, url: url, headers: headers, body: body))
        }
    }

    static func headers(_ value: Any?) -> Result<[String: String], ExtensionViewRejection> {
        guard let value else { return .success([:]) }
        guard let object = value as? [String: Any] else {
            return .failure(.badParameters("'headers' must be an object of strings."))
        }
        guard object.count <= ExtensionViewHTTP.maxHeaders else {
            return .failure(.badParameters("'headers' holds more than \(ExtensionViewHTTP.maxHeaders) fields."))
        }

        var headers: [String: String] = [:]
        for (name, raw) in object {
            guard let text = raw as? String,
                  isFieldName(name),
                  text.count <= ExtensionViewHTTP.maxHeaderLength,
                  !text.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f })
            else { return .failure(.badParameters("'headers' has a field this method will not send: \(name)")) }
            guard !ExtensionViewHTTP.deniedHeaders.contains(name.lowercased()) else {
                return .failure(.badParameters("\(name) is set by Phantom and cannot be sent by a view."))
            }
            headers[name] = text
        }
        return .success(headers)
    }

    /// A token as RFC 9110 defines one, which is narrower than what
    /// `URLRequest` would accept and excludes every scalar that could split
    /// a header or start a new one.
    static func isFieldName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 128 else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-.^_`|~")
        return name.allSatisfy(allowed.contains)
    }
}
