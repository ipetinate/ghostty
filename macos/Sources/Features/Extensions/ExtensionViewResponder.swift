import Foundation

/// Turns a checked call into the object the page receives.
///
/// Separate from the window so the whole method surface can be asserted on
/// without a `WKWebView`: every method except `http.request` is answered
/// here, synchronously, from a scope and a theme the caller supplies.
enum ExtensionViewResponder {
    /// - Parameter boundFile: the file the view is drawing, when it is
    ///   drawing one. It **pins** `workspace.replace`: a view opened on a
    ///   file may write over that file and no other. Nil for a sidebar
    ///   panel and for a synthetic tab, which have no file to be pinned to
    ///   and keep the general capability their manifest asked for.
    static func answer(
        _ call: ExtensionViewCall,
        scope: ExtensionViewFileScope,
        theme: [String: Any],
        boundFile: ExtensionViewFile? = nil,
        state: ExtensionViewState? = nil,
        cachesDir: URL? = nil
    ) -> Result<Any, ExtensionViewRejection> {
        switch call {
        case .workspaceRoot:
            let payload: [String: Any] = [
                "workspace": scope.workspace?.path ?? NSNull(),
                "extension": scope.package.path,
            ]
            return .success(payload)

        case .themeRead:
            return .success(theme)

        case .workspaceList(let root, let path, let depth):
            do {
                let entries = try scope.list(root: root, path: path, depth: depth)
                return .success([
                    "root": root.rawValue,
                    "path": path ?? "",
                    "entries": entries.map(\.payload),
                ])
            } catch let failure as ExtensionViewFileScope.Failure {
                return .failure(failure.rejection)
            } catch {
                return .failure(.unreadable(error.localizedDescription))
            }

        case .workspaceRead(let root, let path):
            do {
                return .success([
                    "root": root.rawValue,
                    "path": path,
                    "text": try scope.read(root: root, path: path),
                ])
            } catch let failure as ExtensionViewFileScope.Failure {
                return .failure(failure.rejection)
            } catch {
                return .failure(.unreadable(error.localizedDescription))
            }

        case .workspaceWrite(let root, let path, let text, let mode):
            /// The tighter statement an editor tab can make: not "a file
            /// this extension may write" but "the file this tab is". A page
            /// drawing `api/users.bru` that saved over `api/orders.bru`
            /// would be a save the reader has no way to have asked for, and
            /// the check is a string comparison against what the app itself
            /// handed the page.
            if mode == .replace, let boundFile,
               boundFile.root != root || boundFile.path != path {
                return .failure(.notThisFile(boundFile.path))
            }

            do {
                return .success([
                    "root": root.rawValue,
                    "path": path,
                    "bytes": try scope.write(root: root, path: path, text: text, mode: mode),
                ])
            } catch let failure as ExtensionViewFileScope.Failure {
                return .failure(failure.rejection)
            } catch {
                return .failure(.unwritable(error.localizedDescription))
            }

        case .httpRequest:
            return .failure(.failed("An HTTP request is answered after it has been performed."))

        case .stateRead:
            guard let state, let cachesDir else {
                return .failure(.failed("This view has nowhere to remember things."))
            }
            return .success(["state": state.readForPage(cachesDir: cachesDir)])

        case .stateWrite(let text):
            guard let state, let cachesDir else {
                return .failure(.failed("This view has nowhere to remember things."))
            }
            guard let data = text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return .failure(.badParameters("'state' must be a JSON object.")) }
            do {
                return .success(["bytes": try state.write(object, cachesDir: cachesDir)])
            } catch let failure as ExtensionViewState.Failure {
                return .failure(failure.rejection)
            } catch {
                return .failure(.unwritable(error.localizedDescription))
            }

        case .viewsOpen, .workspaceChoose, .editorDirty:
            return .failure(.failed("This method is answered by the window that owns the view."))
        }
    }

    /// The object `window.phantomViewHost.settle` is handed, as JSON.
    ///
    /// Built through `JSONSerialization` and never by joining strings: the
    /// text in here is a file's contents and a server's headers, and a
    /// quote in either would otherwise end the expression the app is about
    /// to evaluate.
    static func json(id: Int, result: Result<Any, ExtensionViewRejection>) -> String? {
        let payload: [String: Any]
        switch result {
        case .success(let value):
            payload = ["result": value]
        case .failure(let rejection):
            payload = ["error": ["code": rejection.code, "message": rejection.message]]
        }

        let envelope: [String: Any] = ["id": id, "payload": payload]
        guard JSONSerialization.isValidJSONObject(envelope),
              let data = try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text
    }
}

extension ExtensionViewFileScope.Entry {
    var payload: [String: Any] {
        ["path": path, "name": name, "isDirectory": isDirectory, "bytes": bytes]
    }
}

extension ExtensionViewHTTP.Response {
    var payload: [String: Any] {
        [
            "status": status,
            "url": url,
            "headers": headers,
            "text": text ?? NSNull(),
            "base64": base64 ?? NSNull(),
            "bytes": bytes,
            "milliseconds": milliseconds,
        ]
    }
}
