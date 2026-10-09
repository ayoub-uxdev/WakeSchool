import Foundation
import SwiftUI
import WebKit

struct PronoteENTLoginWebView: UIViewRepresentable {
    let url: URL
    let mobileURL: URL
    let mobileUUID: String
    let onLogin: (String, String) -> Void
    let onHostChange: (String) -> Void
    let onError: (String) -> Void

    static func loginURLs(
        from value: String,
        accountKind: PronoteAccountKind
    ) throws -> (bootstrapURL: URL, mobileURL: URL) {
        let directURL: URL
        do {
            directURL = try PronoteHTTPTransport.normalizeDirectURL(
                value,
                accountKind: accountKind
            )
        } catch {
            throw PronoteENTLoginError.invalidURL
        }
        guard directURL.scheme?.lowercased() == "https" else {
            throw PronoteENTLoginError.invalidURL
        }

        let rootURL = PronoteHTTPTransport.rootURL(from: directURL)
        var mobileComponents = URLComponents(
            url: directURL,
            resolvingAgainstBaseURL: false
        )
        mobileComponents?.queryItems = [URLQueryItem(name: "fd", value: "1")]
        guard let mobileURL = mobileComponents?.url else {
            throw PronoteENTLoginError.invalidURL
        }

        var components = URLComponents(url: rootURL, resolvingAgainstBaseURL: false)
        components?.path = rootURL.appendingPathComponent("InfoMobileApp.json").path
        components?.queryItems = [
            URLQueryItem(name: "id", value: "0D264427-EEFC-4810-A9E9-346942A862A4")
        ]
        guard let bootstrapURL = components?.url else {
            throw PronoteENTLoginError.invalidURL
        }
        return (bootstrapURL, mobileURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            expectedHost: mobileURL.host?.lowercased() ?? "",
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
                source: mobileHookScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        controller.addUserScript(
            WKUserScript(
                source: documentScript,
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

    private var mobileHookScript: String {
        """
        window.hookAccesDepuisAppli = function() {
          const deviceUUID = "\(mobileUUID)";
          if (this && typeof this.passerEnModeValidationAppliMobile === "function") {
            this.passerEnModeValidationAppliMobile(
              "",
              deviceUUID,
              "",
              "",
              JSON.stringify({ model: "iPhone", platform: "ios" })
            );
          }
        };
        """
    }

    private var documentScript: String {
        """
        (() => {
          const deviceUUID = "\(mobileUUID)";
          let mobileLoginRequested = false;
          let loginReported = false;
          const handler = window.webkit?.messageHandlers?.pronoteENTLogin;

          const prepareMobileLogin = () => {
            const bodyText = document.body?.innerText?.trim();
            if (bodyText) {
              try {
                const response = JSON.parse(bodyText);
                const casToken = response?.CAS?.jetonCAS;
                const expires = new Date(Date.now() + 5 * 60 * 1000).toUTCString();
                const languageExpires = new Date(
                  Date.now() + 365 * 24 * 60 * 60 * 1000
                ).toUTCString();

                if (casToken) {
                  document.cookie = "appliMobile=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/";
                  document.cookie = "validationAppliMobile=" + casToken + "; expires=" + expires + "; path=/; SameSite=Lax; Secure";
                  document.cookie = "uuidAppliMobile=" + deviceUUID + "; expires=" + expires + "; path=/; SameSite=Lax; Secure";
                } else {
                  document.cookie = "appliMobile=1; expires=" + expires + "; path=/; SameSite=Lax; Secure";
                }
                document.cookie = "ielang=1036; expires=" + languageExpires + "; path=/; SameSite=Lax; Secure";
                window.location.replace("\(mobileURL.absoluteString)");
                return true;
              } catch (_) {}
            }
            return false;
          };

          const inspectLogin = () => {
            if (!handler || loginReported) return;
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
              try {
                api.passerEnModeValidationAppliMobile(
                  "",
                  deviceUUID,
                  "",
                  "",
                  JSON.stringify({ model: "iPhone", platform: "ios" })
                );
                mobileLoginRequested = true;
              } catch (_) {}
            }
          };

          if (prepareMobileLogin()) return;
          window.setInterval(() => {
            if (prepareMobileLogin()) return;
            inspectLogin();
          }, 750);
          inspectLogin();
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
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
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
            guard (error as NSError).code != NSURLErrorCancelled else { return }
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
