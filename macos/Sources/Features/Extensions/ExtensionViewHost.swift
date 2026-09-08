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

        /// Which views this page may open, and why it cannot open another
        /// extension's. See `ExtensionViewOpener`.
        let opener: ExtensionViewOpener

        /// The file this view is drawing, handed to the page once it is
        /// ready. Nil for a sidebar panel.
        let file: ExtensionViewFile?

        /// Where `state.read` and `state.write` keep this view's answers.
        let state: ExtensionViewState

        let cachesDir: URL

        /// Rises by one each time the reader presses ⌘S on this tab. Not a
        /// flag: a second press has to reach the page too, and a flag that
        /// was already true would compare equal and send nothing.
        let saveTicket: Int

    }

    let request: Request
    let theme: [String: Any]

    /// What to do with a folder the reader picked, which is state of the
    /// *view* rather than of the window — see `ExtensionViewSurface`.
    let onChoose: (URL) -> Void

    /// What the page says about its unsaved work, for the tab's own dirty
    /// mark.
    let onDirty: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChoose: onChoose, onDirty: onDirty)
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
        context.coordinator.window = { webView.window }
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

        /// The window to hang the folder dialog off, read at call time. A
        /// sheet needs the window the page is actually in, and a view moved
        /// between windows by a tab drag is in a different one than it
        /// started in.
        var window: () -> NSWindow? = { nil }

        private let onChoose: (URL) -> Void
        private let onDirty: (Bool) -> Void
        private var loaded: Request?
        private var isReady = false
        private var themeJSON = "{}"
        private var theme: [String: Any] = [:]
        private var isChoosing = false
        private var servedTicket = 0

        init(onChoose: @escaping (URL) -> Void, onDirty: @escaping (Bool) -> Void) {
            self.onChoose = onChoose
            self.onDirty = onDirty
        }

        func load(_ request: Request, theme: [String: Any]) {
            loaded = request
            isReady = false
            servedTicket = request.saveTicket
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
            serveSaveTicket(request.saveTicket)

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
                pushFile(loaded.file)
                servedTicket = loaded.saveTicket

            case .rejected(let id, let rejection):
                settle(id: id, .failure(rejection))

            case .accepted(let id, .httpRequest(let request)):
                Task { [weak self] in
                    let outcome = await ExtensionViewHTTPClient.perform(request)
                    self?.settle(id: id, outcome.map { $0.payload as Any })
                }

            case .accepted(let id, .viewsOpen(let viewID, _, let path)):
                settle(id: id, open(viewID: viewID, path: path, in: loaded))

            case .accepted(let id, .workspaceChoose(let kind)):
                choose(id: id, kind: kind)

            case .accepted(let id, .editorDirty(let isDirty)):
                onDirty(isDirty)
                settle(id: id, .success(["isDirty": isDirty]))

            case .accepted(let id, let call):
                settle(id: id, ExtensionViewResponder.answer(
                    call, scope: loaded.scope, theme: theme, boundFile: loaded.file,
                    state: loaded.state, cachesDir: loaded.cachesDir))
            }
        }

        /// Which file this page is drawing, pushed the way the theme is.
        ///
        /// Pushed rather than fetched because it is known before the page's
        /// first line runs and a page that had to ask for it would render
        /// once with nothing. Not gated on a declaration: it is the app
        /// naming the page's own tab, and the page already has to be able to
        /// read the file it was opened for.
        private func pushFile(_ file: ExtensionViewFile?) {
            guard let file,
                  let json = try? JSONSerialization.data(
                      withJSONObject: file.payload, options: [.sortedKeys]),
                  let text = String(data: json, encoding: .utf8)
            else { return }
            evaluate("window.\(ExtensionViewHostBundle.hostObjectName).setFile(\(text))")
        }

        /// Opens one of this extension's own editor views on a file.
        ///
        /// The path is resolved through this view's own scope, so a page can
        /// only ever open a file it could already read, and the app then
        /// opens it the way any gesture opens a file — the tab is the
        /// file's.
        ///
        /// The descriptor is resolved through `ExtensionViewOpener`, which
        /// builds the id from the extension this page belongs to — so a
        /// `viewId` naming somebody else's view resolves to nothing rather
        /// than to theirs.
        private func open(
            viewID: String,
            path: String,
            in request: Request
        ) -> Result<Any, ExtensionViewRejection> {
            guard let resolved = request.opener.target(viewID),
                  ExtensionViewRegistry.shared.descriptor(id: resolved) != nil
            else { return .failure(.unknownView(viewID)) }

            do {
                let url = try request.scope.file(root: .workspace, path: path)
                guard ExtensionViewTabs.open(url, with: resolved) else {
                    return .failure(.failed("The file could not be opened."))
                }
                return .success(["view": resolved, "tab": url.path])
            } catch let failure as ExtensionViewFileScope.Failure {
                return .failure(failure.rejection)
            } catch {
                return .failure(.unreadable(error.localizedDescription))
            }
        }

        /// Asks the page to save, when the reader pressed ⌘S.
        ///
        /// One way. The app cannot save for the page — only the page knows
        /// what its buffer holds — so ⌘S is a message, not a command with a
        /// result. A page that does not answer leaves the tab's dirty mark
        /// where it was, and the reader can press again; nothing times out
        /// and nothing is written on the page's behalf.
        private func serveSaveTicket(_ ticket: Int) {
            guard ticket != servedTicket else { return }
            servedTicket = ticket
            guard isReady else { return }
            evaluate("window.\(ExtensionViewHostBundle.hostObjectName).requestSave()")
        }

        /// Asks the reader for a folder, in the system dialog.
        ///
        /// The one method whose answer is a folder the app had no claim on a
        /// moment earlier, and it is the reader who picks it in a panel the
        /// page cannot draw, cannot pre-fill and cannot read. Everything
        /// after that is unchanged: the folder becomes the scope's base and
        /// every path is still proved against it twice.
        ///
        /// One panel at a time. A page that called this in a loop would
        /// otherwise stack sheets on the reader's window, which is a way to
        /// make a window unusable without being refused anything.
        private func choose(id: Int, kind: ExtensionViewCall.ChoiceKind) {
            guard !isChoosing else {
                settle(id: id, .failure(.failed("A dialog is already open.")))
                return
            }

            let wantsFile = kind == .file
            let panel = NSOpenPanel()
            panel.canChooseFiles = wantsFile
            panel.canChooseDirectories = !wantsFile
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = !wantsFile
            panel.prompt = wantsFile ? "Use File" : "Use Folder"
            panel.message = wantsFile
                ? "Pick a file for this extension's view to work from."
                : "Pick the folder this extension's view should work in."

            isChoosing = true
            let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                guard let self else { return }
                isChoosing = false
                guard response == .OK, let url = panel.url else {
                    settle(id: id, .failure(.cancelled))
                    return
                }

                /// A file's **folder** becomes the workspace, because that
                /// is what a view's methods are bounded to. The file itself
                /// comes back beside it, named the way the page may name it
                /// once the folder is in place.
                let workspace = wantsFile ? url.deletingLastPathComponent() : url
                onChoose(workspace)

                var answer: [String: Any] = ["workspace": workspace.path]
                if wantsFile { answer["path"] = url.lastPathComponent }
                settle(id: id, .success(answer))
            }

            if let window = window() {
                panel.beginSheetModal(for: window, completionHandler: finish)
            } else {
                finish(panel.runModal())
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
