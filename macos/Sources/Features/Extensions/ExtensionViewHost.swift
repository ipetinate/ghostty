import AppKit
import SwiftUI
import WebKit

/// The window one contributed view is drawn in.
///
/// Configured exactly the way `ExtensionDocumentView` is — an ephemeral data
/// store, no window opening, file access from file URLs, one script message
/// handler, and a navigation delegate that allows the one local page and
/// cancels everything else. The page is out of process because that is what
/// a `WKWebView` is, so nothing here needs an XPC service of its own.
struct ExtensionViewHost: NSViewRepresentable {
    struct Request: Equatable {
        let host: URL
        let base: URL
        let scope: ExtensionViewFileScope
        let permissions: Set<ExtensionViewMethod>
    }

    let request: Request
    let theme: [String: Any]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        configuration.userContentController.add(
            context.coordinator, name: ExtensionViewHostBundle.handlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsMagnification = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        #if DEBUG
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        #endif

        context.coordinator.webView = webView
        context.coordinator.load(request, theme: theme)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(request, theme: theme)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: ExtensionViewHostBundle.handlerName)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        coordinator.webView = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?

        private var loaded: Request?
        private var isReady = false
        private var themeJSON = "{}"
        private var theme: [String: Any] = [:]

        func load(_ request: Request, theme: [String: Any]) {
            loaded = request
            isReady = false
            self.theme = theme
            themeJSON = ExtensionViewerTheme.json(theme)
            webView?.loadFileURL(request.host, allowingReadAccessTo: request.base)
        }

        func update(_ request: Request, theme: [String: Any]) {
            guard let loaded, loaded.host == request.host, loaded.base == request.base else {
                load(request, theme: theme)
                return
            }
            self.loaded = request
            self.theme = theme

            let json = ExtensionViewerTheme.json(theme)
            guard json != themeJSON else { return }
            themeJSON = json
            guard isReady else { return }
            pushTheme(to: request.permissions)
        }

        /// The theme, but only to a view that declared `theme.read`.
        ///
        /// Pushed rather than asked for, because a page that follows the
        /// theme has to be told when it changes and polling for that is
        /// worse. Still gated on the declaration: the rule is that the app
        /// hands over nothing the manifest did not name, and a rule with one
        /// exception in it is a weaker rule than the one this feature
        /// claims. A view with no `theme.read` draws in its own colours.
        private func pushTheme(to permissions: Set<ExtensionViewMethod>) {
            guard permissions.contains(.themeRead) else { return }
            evaluate("window.\(ExtensionViewHostBundle.hostObjectName).setTheme(\(themeJSON))")
        }

        private func evaluate(_ script: String) {
            webView?.evaluateJavaScript(script) { _, _ in }
        }

        /// Hands the answer over as one JSON object read by a function
        /// rather than as arguments spliced into a call.
        ///
        /// The values in it are a file's contents and a server's headers.
        /// Written into the expression, a quote in either would end it and
        /// the rest would be evaluated as code.
        private func settle(id: Int, _ result: Result<Any, ExtensionViewRejection>) {
            let envelope = ExtensionViewResponder.json(id: id, result: result)
                ?? ExtensionViewResponder.json(
                    id: id, result: .failure(.failed("The answer could not be encoded.")))
            guard let envelope else { return }
            evaluate("(function (envelope) { window."
                + "\(ExtensionViewHostBundle.hostObjectName).settle(envelope.id, envelope.payload); })(\(envelope))")
        }

        func handle(_ message: ExtensionViewMessage) {
            guard let loaded else { return }

            switch message {
            case .unaddressable:
                return

            case .ready:
                isReady = true
                pushTheme(to: loaded.permissions)

            case .rejected(let id, let rejection):
                settle(id: id, .failure(rejection))

            case .accepted(let id, .httpRequest(let request)):
                Task { [weak self] in
                    let outcome = await ExtensionViewHTTPClient.perform(request)
                    self?.settle(id: id, outcome.map { $0.payload as Any })
                }

            case .accepted(let id, let call):
                settle(id: id, ExtensionViewResponder.answer(call, scope: loaded.scope, theme: theme))
            }
        }

        // MARK: WKScriptMessageHandler

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let loaded else { return }
            handle(ExtensionViewBridge.read(message.body, permissions: loaded.permissions))
        }

        // MARK: WKNavigationDelegate

        /// The one page, and nothing else.
        ///
        /// A link the reader clicks is opened in their browser and the
        /// navigation is cancelled, which is `ExtensionDocumentView`'s rule
        /// and applies the same `UntrustedURL` decision to the href. Every
        /// other navigation — a form, a frame, a second file, a redirect —
        /// is cancelled with nothing opened.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let url = navigationAction.request.url
            if navigationAction.navigationType == .linkActivated {
                if let target = ExtensionViewerMessage.openableURL(url?.absoluteString) {
                    NSWorkspace.shared.open(target)
                }
                decisionHandler(.cancel)
                return
            }

            guard navigationAction.targetFrame?.isMainFrame == true,
                  let url,
                  let loaded,
                  url.standardizedFileURL == loaded.host.standardizedFileURL
            else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        // MARK: WKUIDelegate

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            nil
        }
    }
}
