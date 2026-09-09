import Foundation

/// The three or four files one contributed view is served from, staged
/// outside the extension so the page's read access can be a directory that
/// holds nothing else.
///
/// A page is loaded with `loadFileURL(host, allowingReadAccessTo: directory)`
/// and that grant is a whole directory, so the directory has to be ours. The
/// extension's own folder is not: it holds the manifest, the grammars and
/// whatever else the author shipped, and a page granted read access to it
/// could pull all of it in through `img-src file:` alone.
///
/// So the entry and its stylesheet are copied into a directory of their own,
/// beside a generated `host.html` and the bridge script. Copied rather than
/// symlinked: a symlink would resolve out of the grant, which is the one
/// thing the grant is for.
enum ExtensionViewHostBundle {
    enum Failure: Error, Equatable {
        case unreadableEntry(String)
        case oversized(String, bytes: Int)
        case copy(String)

        var message: String {
            switch self {
            case .unreadableEntry(let name):
                return "The view's entry file could not be read: \(name)."
            case .oversized(let name, let bytes):
                return "\(name) is \(bytes) bytes; the limit for a view's bundle is "
                    + "\(ExtensionViewHostBundle.maxBundleBytes)."
            case .copy(let reason):
                return "The view could not be prepared: \(reason)"
            }
        }
    }

    static let directoryName = "views"
    static let hostFileName = "host.html"
    static let bridgeFileName = "bridge.js"
    static let entryFileName = "view.js"
    static let styleFileName = "view.css"

    /// The name the page posts its calls to.
    ///
    /// Deliberately not `ExtensionDocumentView.Coordinator.handlerName`. The
    /// two pages speak different protocols, and a name they shared would let
    /// a message written for one arrive at the other's reader.
    static let handlerName = "phantomView"

    /// The object the bridge hangs the app's answers off, and the one name a
    /// page's own code must not take.
    static let hostObjectName = "phantomViewHost"

    /// The whole bundle, entry plus stylesheet.
    ///
    /// A view is one bundled script. Four megabytes is a large one — every
    /// framework this is meant to carry, with its runtime inlined, fits well
    /// inside it — and it is copied on open, so it is also a cost.
    static let maxBundleBytes = 4 * 1024 * 1024

    /// The same policy `macos/Resources/extension-viewer/viewer.html`
    /// carries, and for the same reasons.
    ///
    /// Nothing here names an `http` or `https` source, at any directive, so
    /// the page cannot reach the network by any means it has: `fetch` and
    /// `XMLHttpRequest` against a remote host are refused before a socket is
    /// opened, an `<img>` off a CDN does not load, and a webfont does not
    /// arrive. That is the whole reason `http.request` exists as a method
    /// the app performs — see `ExtensionViewHTTP`.
    ///
    /// `connect-src file:` is kept because it is what lets a page read an
    /// asset it shipped beside its own script. Such a request answers
    /// **status 0** rather than 200, so loading code has to accept 0.
    static let contentSecurityPolicy = "default-src 'none'; script-src 'self'; style-src 'self'; "
        + "img-src file: data:; media-src file:; font-src 'self'; connect-src file:; "
        + "base-uri 'none'; form-action 'none'; frame-src 'none'; object-src 'none'"

    static func root(cachesDir: URL) -> URL {
        ExtensionPreviewCache.root(cachesDir: cachesDir)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    /// One directory per view, nested rather than joined.
    ///
    /// `<extension id>/<view id>` and not `<extension id>-<view id>`: an
    /// extension id may hold a dash, so the joined form lets two different
    /// pairs name one directory.
    static func directory(for descriptor: ExtensionViewDescriptor, root: URL) -> URL {
        root.appendingPathComponent(descriptor.extensionID, isDirectory: true)
            .appendingPathComponent(descriptor.contribution.viewID, isDirectory: true)
    }

    static func host(in directory: URL) -> URL {
        directory.appendingPathComponent(hostFileName)
    }

    /// Stages the view, and answers the page to load.
    ///
    /// Reuses a directory whose staged copies are byte for byte what the
    /// extension now ships, which is the common case: opening a view a
    /// second time copies nothing. An author who rebuilds their bundle gets
    /// a restage on the next open, because the comparison is against the
    /// bytes rather than against a version string they may not have bumped.
    static func stage(_ descriptor: ExtensionViewDescriptor, root: URL) throws -> URL {
        let directory = directory(for: descriptor, root: root)
        let contribution = descriptor.contribution
        let html = Data(page(hasStyle: contribution.style != nil).utf8)

        var wanted: [String: Data] = [
            hostFileName: html,
            bridgeFileName: Data(bridge.utf8),
            entryFileName: try read(contribution.entry),
        ]
        if let style = contribution.style {
            wanted[styleFileName] = try read(style)
        }

        let total = wanted.values.reduce(0) { $0 + $1.count }
        guard total <= maxBundleBytes else {
            throw Failure.oversized(contribution.entry.lastPathComponent, bytes: total)
        }

        if isStaged(wanted, in: directory) { return host(in: directory) }
        try write(wanted, to: directory)
        return host(in: directory)
    }

    static func read(_ url: URL) throws -> Data {
        guard let data = try? Data(contentsOf: url), data.count <= maxBundleBytes else {
            throw Failure.unreadableEntry(url.lastPathComponent)
        }
        return data
    }

    /// True when the directory holds exactly these files with exactly these
    /// bytes. A file left over from a version that shipped a stylesheet and
    /// no longer does fails this, so the restage drops it.
    static func isStaged(_ wanted: [String: Data], in directory: URL) -> Bool {
        let fileManager = FileManager.default
        let present = Set(
            ((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? [])
                .filter { !$0.hasPrefix(".") }
        )
        guard present == Set(wanted.keys) else { return false }
        return wanted.allSatisfy { name, data in
            (try? Data(contentsOf: directory.appendingPathComponent(name))) == data
        }
    }

    static func write(_ wanted: [String: Data], to directory: URL) throws {
        let fileManager = FileManager.default
        let parent = directory.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(
            ExtensionPreviewCache.stagingPrefix + UUID().uuidString, isDirectory: true)
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            for (name, data) in wanted.sorted(by: { $0.key < $1.key }) {
                try data.write(to: staging.appendingPathComponent(name), options: .atomic)
            }
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
            }
            try fileManager.moveItem(at: staging, to: directory)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw Failure.copy(error.localizedDescription)
        }
    }

    /// The page, with the policy in a `<meta>` the way the document viewer
    /// carries it.
    ///
    /// The bridge is a classic script and the view is a module, so the
    /// bridge is defined before the view's first line runs — no ordering for
    /// an author to get wrong, and no inline script, which the policy would
    /// refuse anyway.
    static func page(hasStyle: Bool) -> String {
        let stylesheet = hasStyle ? "\n    <link rel=\"stylesheet\" href=\"\(styleFileName)\" />" : ""
        return """
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8" />
            <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <title>Phantom extension view</title>
            <script src="\(bridgeFileName)"></script>
            <script type="module" src="\(entryFileName)"></script>\(stylesheet)
          </head>
          <body>
            <div id="root"></div>
          </body>
        </html>
        """
    }

    /// `window.phantom`, as the page sees it.
    ///
    /// Written here rather than shipped as a resource because it is the
    /// other half of `ExtensionViewBridge.read` and
    /// `ExtensionViewHost.Coordinator.settle`: the shape of a call, the
    /// shape of an answer and the two names above are one contract, and a
    /// contract split across a Swift file and a vendored directory drifts.
    static let bridge = """
    (function () {
      var pending = new Map();
      var nextCall = 1;
      var theme = null;
      var listeners = [];
      var file = null;
      var fileListeners = [];
      var saveHandler = null;

      function post(message) {
        window.webkit.messageHandlers.\(handlerName).postMessage(message);
      }

      function settle(id, payload) {
        var entry = pending.get(id);
        if (entry === undefined) return;
        pending.delete(id);
        if (payload && payload.error) {
          var failure = new Error(String(payload.error.message || 'The call was refused.'));
          failure.code = String(payload.error.code || 'failed');
          entry.reject(failure);
          return;
        }
        entry.resolve(payload ? payload.result : null);
      }

      function setTheme(next) {
        theme = next;
        for (var index = 0; index < listeners.length; index += 1) {
          try {
            listeners[index](theme);
          } catch (error) {
            void error;
          }
        }
      }

      function setFile(next) {
        file = next;
        for (var index = 0; index < fileListeners.length; index += 1) {
          try {
            fileListeners[index](file);
          } catch (error) {
            void error;
          }
        }
      }

      function requestSave() {
        if (saveHandler === null) return;
        try {
          saveHandler();
        } catch (error) {
          void error;
        }
      }

      window.phantom = {
        call: function (method, params) {
          var id = nextCall;
          nextCall += 1;
          return new Promise(function (resolve, reject) {
            pending.set(id, { resolve: resolve, reject: reject });
            post({ id: id, method: String(method), params: params || {} });
          });
        },
        workspaceRoot: function () {
          return window.phantom.call('workspace.root', {});
        },
        list: function (params) {
          return window.phantom.call('workspace.list', params || {});
        },
        read: function (params) {
          return window.phantom.call('workspace.read', params || {});
        },
        create: function (params) {
          return window.phantom.call('workspace.create', params || {});
        },
        replace: function (params) {
          return window.phantom.call('workspace.replace', params || {});
        },
        request: function (params) {
          return window.phantom.call('http.request', params || {});
        },
        choose: function (params) {
          return window.phantom.call('workspace.choose', params || {});
        },
        open: function (params) {
          return window.phantom.call('views.open', params || {});
        },
        theme: function () {
          return theme;
        },
        onTheme: function (listener) {
          listeners.push(listener);
          if (theme !== null) listener(theme);
        },
        file: function () {
          return file;
        },
        onFile: function (listener) {
          fileListeners.push(listener);
          if (file !== null) listener(file);
        },
        state: function () {
          return window.phantom.call('state.read', {});
        },
        remember: function (state) {
          return window.phantom.call('state.write', { state: state || {} });
        },
        dirty: function (isDirty) {
          return window.phantom.call('editor.dirty', { isDirty: isDirty === true });
        },
        onSave: function (handler) {
          saveHandler = handler;
        },
      };

      window.\(hostObjectName) = {
        settle: settle,
        setTheme: setTheme,
        setFile: setFile,
        requestSave: requestSave,
      };

      post({ type: 'ready' });
    })();
    """
}
