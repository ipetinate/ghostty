import Foundation

/// Performs the one request `ExtensionViewHTTP` allowed, and nothing the
/// reader is signed in to comes with it.
///
/// The session is ephemeral, its cookie storage and its credential storage
/// are taken away rather than merely unused, and no redirect is followed. So
/// a request the page composed is a request to the host the page named, with
/// the headers the page named, and no third party learns anything from it
/// that the page did not already know.
enum ExtensionViewHTTPClient {
    /// Every refusal and every limit `ExtensionViewHTTP` declares, applied
    /// to one request.
    ///
    /// The URL gate is applied here again rather than trusted from the
    /// parse, because between the parse and the send is where a redirect
    /// would have changed the host — and refusing to follow one is what
    /// makes that impossible instead of merely unlikely.
    static func perform(
        _ request: ExtensionViewHTTP.Request,
        allowingPrivateNetwork: Bool = ExtensionViewHTTP.allowsPrivateNetwork,
        session: URLSession = shared
    ) async -> Result<ExtensionViewHTTP.Response, ExtensionViewRejection> {
        if let refusal = ExtensionViewHTTP.refusal(for: request.url, allowingPrivateNetwork: allowingPrivateNetwork) {
            return .failure(.refusedURL(refusal))
        }

        let started = Date()
        let outgoing = urlRequest(request)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: outgoing)
        } catch let error as URLError where error.code == .cancelled {
            return .failure(.failed("The response is larger than \(ExtensionViewHTTP.maxResponseBytes) bytes."))
        } catch {
            return .failure(.failed(error.localizedDescription))
        }

        guard let http = response as? HTTPURLResponse else {
            return .failure(.failed("The server did not answer over HTTP."))
        }
        guard data.count <= ExtensionViewHTTP.maxResponseBytes else {
            return .failure(.failed("The response is \(data.count) bytes; the limit is "
                + "\(ExtensionViewHTTP.maxResponseBytes)."))
        }
        return .success(answer(http, data: data, milliseconds: Date().timeIntervalSince(started)))
    }

    static func urlRequest(_ request: ExtensionViewHTTP.Request) -> URLRequest {
        var outgoing = URLRequest(
            url: request.url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: ExtensionViewHTTP.timeout
        )
        outgoing.httpMethod = request.method
        outgoing.httpShouldHandleCookies = false
        outgoing.allowsCellularAccess = true
        outgoing.allowsConstrainedNetworkAccess = true
        outgoing.allowsExpensiveNetworkAccess = true
        for (name, value) in request.headers.sorted(by: { $0.key < $1.key }) {
            outgoing.setValue(value, forHTTPHeaderField: name)
        }
        if let body = request.body {
            outgoing.httpBody = Data(body.utf8)
        }
        return outgoing
    }

    /// The body as text when it decodes as UTF-8, otherwise as base64.
    ///
    /// Never both, and never a lossy string: a page that asked for a PNG
    /// gets bytes it can put in a `data:` URL, and a page that asked for
    /// JSON gets a string it can parse. A string with replacement
    /// characters in it would be neither.
    static func answer(_ http: HTTPURLResponse, data: Data, milliseconds: TimeInterval) -> ExtensionViewHTTP.Response {
        let text = String(data: data, encoding: .utf8)
        return ExtensionViewHTTP.Response(
            status: http.statusCode,
            url: http.url?.absoluteString ?? "",
            headers: headers(of: http),
            text: text,
            base64: text == nil ? data.base64EncodedString() : nil,
            bytes: data.count,
            milliseconds: Int((milliseconds * 1000).rounded())
        )
    }

    static func headers(of http: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (name, value) in http.allHeaderFields {
            guard let name = name as? String, let value = value as? String else { continue }
            guard !name.unicodeScalars.contains(where: LanguageContribution.isUnsafeScalar) else { continue }
            headers[name.lowercased()] = String(value.prefix(ExtensionViewHTTP.maxHeaderLength))
        }
        return headers
    }

    /// The session every contributed view shares.
    ///
    /// One rather than one per view: the configuration carries no state a
    /// view could leave behind for the next, because there is no cookie
    /// store, no credential store and no cache to leave it in.
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpAdditionalHeaders = [:]
        configuration.timeoutIntervalForRequest = ExtensionViewHTTP.timeout
        configuration.timeoutIntervalForResource = ExtensionViewHTTP.timeout
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.waitsForConnectivity = false
        return URLSession(
            configuration: configuration,
            delegate: ExtensionViewHTTPDelegate(),
            delegateQueue: nil
        )
    }()
}

/// Refuses the two things a server can do to a request after it has been
/// checked: move it somewhere else, and ask who is sending it.
final class ExtensionViewHTTPDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    /// **No redirect is ever followed.** A 3xx is handed to the page as a
    /// 3xx with its `Location` header, and whether to ask for that URL is
    /// then a second call, which goes through the URL gate again. Following
    /// one here would let a host the gate allowed send the app to one it
    /// refuses.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    /// No credential, ever — not the keychain's, not a client certificate,
    /// not the reader's. A server that asks gets the default handling, which
    /// for a challenge with nothing to answer it with is a 401 the page can
    /// read.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(.performDefaultHandling, nil)
    }

    /// Cancels a transfer whose declared length is already over the limit,
    /// rather than buffering it to find out.
    ///
    /// A server that declares no length, or lies about it, is bounded by
    /// `ExtensionViewHTTP.timeout` and by the check on the bytes actually
    /// received. Naming that gap rather than implying there is none.
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard response.expectedContentLength > Int64(ExtensionViewHTTP.maxResponseBytes) else {
            completionHandler(.allow)
            return
        }
        completionHandler(.cancel)
    }
}
