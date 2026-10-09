import Foundation
import SwiftUI
import WebKit

struct PronoteENTLoginWebView: UIViewRepresentable {
    let url: URL
    let mobileUUID: String
    let onLogin: (String, String) -> Void
    let onHostChange: (String) -> Void
    let onError: (String) -> Void

    static func loginURL(from value: String) throws -> URL {
        guard let components = URLComponents(
            string: value.trimmingCharacters(in: .whitespacesAndNewlines)
        ),
        components.scheme?.lowercased() == "https",
        components.host != nil,
        let url = components.url else {
            throw PronoteENTLoginError.invalidURL
        }
        return url
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            expectedHost: url.host?.lowercased() ?? "",
            onLogin: onLogin,
            onHostChange: onHostChange,
            onError: onError
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "pronoteENTLogin")
        controller.addUserScript(
            WKUserScript(
                source: loginStateScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(
            forName: "pronoteENTLogin"
        )
        uiView.navigationDelegate = nil
    }

    private var loginStateScript: String {
        """
        (() => {
          const deviceUUID = "\(mobileUUID)";
          let mobileLoginRequested = false;
          let loginReported = false;
          const handler = window.webkit?.messageHandlers?.pronoteENTLogin;
          if (!handler) return;

          const inspectLogin = () => {
            if (loginReported) return;
            const state = window.loginState;
            if (state && state.status === 0 &&
                typeof state.login === "string" && state.login.length > 0 &&
                typeof state.mdp === "string" && state.mdp.length > 0) {
              loginReported = true;
              handler.postMessage({ login: state.login, token: state.mdp });
              return;
            }

            const api = window.GInterface;
            if (!mobileLoginRequested && api &&
                typeof api.passerEnModeValidationAppliMobile === "function") {
              mobileLoginRequested = true;
                api.passerEnModeValidationAppliMobile(
                  "",
                  deviceUUID,
                  "",
                  "",
                  JSON.stringify({ model: "iPhone", platform: "ios" })
                );
            }
          };

          window.hookAccesDepuisAppli = inspectLogin;
          inspectLogin();
          window.setInterval(inspectLogin, 750);
        })();
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let expectedHost: String
        private let onLogin: (String, String) -> Void
        private let onHostChange: (String) -> Void
        private let onError: (String) -> Void
        private var hasReportedLogin = false
        private var hasReportedError = false

        init(
            expectedHost: String,
            onLogin: @escaping (String, String) -> Void,
            onHostChange: @escaping (String) -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.expectedHost = expectedHost
            self.onLogin = onLogin
            self.onHostChange = onHostChange
            self.onError = onError
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard !hasReportedLogin,
                  message.frameInfo.isMainFrame,
                  message.frameInfo.securityOrigin.host.lowercased() == expectedHost,
                  let payload = message.body as? [String: String],
                  let username = payload["login"],
                  let token = payload["token"],
                  !username.isEmpty,
                  !token.isEmpty else {
                return
            }

            hasReportedLogin = true
            onLogin(username, token)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let scheme = navigationAction.request.url?.scheme?.lowercased() else {
                decisionHandler(.cancel)
                return
            }
            guard scheme == "https" else {
                if scheme == "http" {
                    report(PronoteENTLoginError.insecureRedirect.localizedDescription)
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            if let host = webView.url?.host {
                onHostChange(host)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            report(error)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            report(error)
        }

        private func report(_ error: Error) {
            report(error.localizedDescription)
        }

        private func report(_ message: String) {
            guard !hasReportedError else { return }
            hasReportedError = true
            onError(message)
        }
    }
}

private enum PronoteENTLoginError: Error, LocalizedError {
    case invalidURL
    case insecureRedirect

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Saisis une adresse HTTPS valide vers le PRONOTE de ton établissement."
        case .insecureRedirect:
            return "La connexion ENT a tenté d’ouvrir une page non sécurisée (HTTP). Connexion interrompue."
        }
    }
}
