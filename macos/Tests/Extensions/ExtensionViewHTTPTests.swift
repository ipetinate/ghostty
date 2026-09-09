import Foundation
@testable import Ghostty
import Testing

struct ExtensionViewHTTPTests {
    private func refusal(_ raw: String, allowingPrivateNetwork: Bool = false) -> ExtensionViewHTTP.Refusal? {
        guard let url = URL(string: raw) else {
            Issue.record("not a URL: \(raw)")
            return nil
        }
        return ExtensionViewHTTP.refusal(for: url, allowingPrivateNetwork: allowingPrivateNetwork)
    }

    @Test func onlyHTTPAndHTTPS() {
        #expect(refusal("https://api.example.com/v1") == nil)
        #expect(refusal("http://api.example.com/v1") == nil)
        #expect(refusal("file:///etc/passwd") == .scheme("file"))
        #expect(refusal("data:text/plain,hello") == .scheme("data"))
        #expect(refusal("ftp://example.com") == .scheme("ftp"))
        #expect(refusal("phantom-extension://x/y") == .scheme("phantom-extension"))
    }

    @Test func noCredentialsInTheURL() {
        #expect(refusal("https://root:hunter2@api.example.com") == .credentialsInURL)
        #expect(refusal("https://root@api.example.com") == .credentialsInURL)
    }

    /// Refused with the switch on as well as off, by every extension, always.
    @Test func theMetadataEndpointIsRefusedUnconditionally() {
        for allowed in [false, true] {
            #expect(refusal("http://169.254.169.254/latest/meta-data/", allowingPrivateNetwork: allowed)
                == .metadataEndpoint("169.254.169.254"))
            #expect(refusal("http://metadata/computeMetadata/v1/", allowingPrivateNetwork: allowed)
                == .metadataEndpoint("metadata"))
            #expect(refusal("http://metadata.google.internal/x", allowingPrivateNetwork: allowed)
                == .metadataEndpoint("metadata.google.internal"))
            #expect(refusal("http://[fd00:ec2::254]/latest/", allowingPrivateNetwork: allowed)
                == .metadataEndpoint("fd00:ec2::254"))
        }
    }

    @Test func reservedRangesAreRefusedUnconditionally() {
        for allowed in [false, true] {
            #expect(refusal("http://0.0.0.0/", allowingPrivateNetwork: allowed) == .reservedAddress("0.0.0.0"))
            #expect(refusal("http://239.1.2.3/", allowingPrivateNetwork: allowed) == .reservedAddress("239.1.2.3"))
            #expect(refusal("http://[::]/", allowingPrivateNetwork: allowed) == .reservedAddress("::"))
            #expect(refusal("http://[ff02::1]/", allowingPrivateNetwork: allowed) == .reservedAddress("ff02::1"))
        }
    }

    /// The reader's decision, and the reason the HTTP client can talk to an
    /// API being developed on this machine at all.
    @Test func thisMachineAndItsNetworkAreTheReadersDecision() {
        let local = [
            "http://localhost:3000/", "http://127.0.0.1:8080/", "http://[::1]:8080/",
            "http://10.1.2.3/", "http://172.16.0.5/", "http://192.168.1.10/",
            "http://100.64.0.1/", "http://printer.local/", "http://[fd12::1]/",
            "http://[fe80::1]/", "http://api.localhost/",
        ]
        for raw in local {
            #expect(refusal(raw) != nil)
            #expect(refusal(raw, allowingPrivateNetwork: true) == nil)
        }
    }

    /// An IPv4-mapped literal is classified by the address it maps, so
    /// `::ffff:127.0.0.1` cannot be used to spell loopback past the check.
    @Test func anIPv4MappedLiteralIsTheAddressItMaps() {
        #expect(refusal("http://[::ffff:127.0.0.1]/") == .privateAddress("::ffff:127.0.0.1"))
        #expect(refusal("http://[::ffff:169.254.169.254]/") == .metadataEndpoint("::ffff:169.254.169.254"))
    }

    @Test func aTrailingDotIsTheSameName() {
        #expect(refusal("http://localhost./") == .privateAddress("localhost."))
        #expect(refusal("http://metadata./") == .metadataEndpoint("metadata."))
    }

    @Test func aHostThatIsNotAnAddressAndNotSpecialIsOrdinary() {
        #expect(ExtensionViewHTTP.addressClass(ofHost: "api.example.com") == .ordinary)
        #expect(ExtensionViewHTTP.addressClass(ofHost: "127.0.0.1.example.com") == .ordinary)
        #expect(ExtensionViewHTTP.addressClass(ofHost: "1.2.3.4") == .ordinary)
    }

    // MARK: The request

    @Test func onlyTheMethodsInTheList() {
        for method in ExtensionViewHTTP.methods {
            let parsed = ExtensionViewHTTP.Request.parse(["url": "https://api.example.com", "method": method])
            #expect((try? parsed.get()) != nil)
        }
        let refused = ExtensionViewHTTP.Request.parse(["url": "https://api.example.com", "method": "TRACE"])
        #expect((try? refused.get()) == nil)
    }

    @Test func aMethodIsUppercasedAndDefaultsToGET() {
        #expect((try? ExtensionViewHTTP.Request.parse(["url": "https://x.example.com", "method": "post"]).get())?.method
            == "POST")
        #expect((try? ExtensionViewHTTP.Request.parse(["url": "https://x.example.com"]).get())?.method == "GET")
    }

    /// A field name a page could use to split a header, or a header Phantom
    /// writes itself, is refused rather than dropped: an author whose
    /// `Content-Length` is ignored has written a request that does not do
    /// what the code says.
    @Test func refusesAHeaderItWillNotSend() {
        let hostile: [[String: Any]] = [
            ["headers": ["Host": "elsewhere.example.com"]],
            ["headers": ["Content-Length": "0"]],
            ["headers": ["Transfer-Encoding": "chunked"]],
            ["headers": ["Proxy-Authorization": "Basic x"]],
            ["headers": ["X-Bad\r\nInjected": "1"]],
            ["headers": ["X-Bad": "value\r\nX-Injected: 1"]],
            ["headers": ["X-Bad": 7]],
            ["headers": "Authorization: x"],
        ]
        for params in hostile {
            var json: [String: Any] = ["url": "https://api.example.com"]
            for (key, value) in params { json[key] = value }
            #expect((try? ExtensionViewHTTP.Request.parse(json).get()) == nil)
        }

        let fine = ExtensionViewHTTP.Request.parse([
            "url": "https://api.example.com",
            "headers": ["Authorization": "Bearer abc", "Content-Type": "application/json"],
        ])
        #expect((try? fine.get())?.headers.count == 2)
    }

    @Test func aGetCarriesNoBody() {
        #expect((try? ExtensionViewHTTP.Request.parse(["url": "https://x.example.com", "body": "{}"]).get()) == nil)
        #expect((try? ExtensionViewHTTP.Request.parse(
            ["url": "https://x.example.com", "method": "POST", "body": "{}"]).get())?.body == "{}")
        #expect((try? ExtensionViewHTTP.Request.parse(
            ["url": "https://x.example.com", "method": "POST", "body": 7]).get()) == nil)
    }

    @Test func aURLIsAStringWithNothingHiddenInIt() {
        #expect((try? ExtensionViewHTTP.Request.parse(["url": "https://x.example.com/\u{202E}"]).get()) == nil)
        #expect((try? ExtensionViewHTTP.Request.parse(
            ["url": String(repeating: "a", count: 8192)]).get()) == nil)
        #expect((try? ExtensionViewHTTP.Request.parse([:]).get()) == nil)
    }

    // MARK: The answer

    @Test func aTextBodyIsTextAndBinaryIsBase64() throws {
        let response = try #require(HTTPURLResponse(
            url: URL(string: "https://api.example.com/v1")!, statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]))

        let text = ExtensionViewHTTPClient.answer(response, data: Data("{\"ok\":true}".utf8), milliseconds: 0.12)
        #expect(text.text == "{\"ok\":true}")
        #expect(text.base64 == nil)
        #expect(text.status == 200)
        #expect(text.headers["content-type"] == "application/json")
        #expect(text.milliseconds == 120)

        let binary = ExtensionViewHTTPClient.answer(
            response, data: Data([0xFF, 0xFE, 0x00, 0x01]), milliseconds: 0)
        #expect(binary.text == nil)
        #expect(binary.base64 == Data([0xFF, 0xFE, 0x00, 0x01]).base64EncodedString())
    }

    /// A 3xx is an answer, not a hop: the page is handed the status and the
    /// `Location`, and asking for it is a second call through the same gate.
    @Test func aRedirectIsAnAnswer() throws {
        let response = try #require(HTTPURLResponse(
            url: URL(string: "https://api.example.com/old")!, statusCode: 302,
            httpVersion: "HTTP/1.1", headerFields: ["Location": "http://169.254.169.254/latest/"]))
        let answer = ExtensionViewHTTPClient.answer(response, data: Data(), milliseconds: 0)
        #expect(answer.status == 302)
        #expect(answer.headers["location"] == "http://169.254.169.254/latest/")

        #expect(refusal("http://169.254.169.254/latest/") == .metadataEndpoint("169.254.169.254"))
    }
}
