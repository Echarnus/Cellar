import AppKit
import WebKit
import CellarKit

/// GOG's OAuth sign-in, in its own window.
///
/// GOG ends the flow by redirecting to an `embed.gog.com` address carrying a one-time code. There is
/// no custom URL scheme to catch, so `ASWebAuthenticationSession` can't be used — the flow has to be
/// hosted and the navigation watched. That is the whole job of this window: show GOG's own sign-in
/// page, notice the redirect, hand back the code.
///
/// A window rather than a sheet, like Settings and Accounts: a `.sheet` inside the hosted view tree
/// is a fatal AttributeGraph cycle under `NSHostingView` (skills/swift.md). A top-level window is its
/// own view graph.
///
/// Cellar reads nothing else from the page and injects no script — the player signs in to GOG, on
/// GOG's page, and Cellar only ever sees the code GOG hands back.
final class GOGSignInWindow: NSObject, WKNavigationDelegate {
    enum Result {
        case code(String)
        case cancelled
        case failed(String)
    }

    /// Held for the window's lifetime, since nothing else owns it.
    private static var current: GOGSignInWindow?

    private var window: NSWindow!
    private var completion: (Result) -> Void
    /// Guards against reporting twice — the redirect fires and then the window closes.
    private var finished = false

    private init(completion: @escaping (Result) -> Void) {
        self.completion = completion
        super.init()
    }

    static func present(completion: @escaping (Result) -> Void) {
        // Replace any window left over from an abandoned attempt.
        current?.finish(.cancelled)
        let controller = GOGSignInWindow(completion: completion)
        controller.show()
        current = controller
    }

    private func show() {
        let configuration = WKWebViewConfiguration()
        // A fresh, non-persistent store: signing in to Cellar must not silently reuse or disturb a
        // Safari session, and nothing about the sign-in is worth keeping once the code is exchanged.
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 680),
                                configuration: configuration)
        webView.navigationDelegate = self

        let window = NSWindow(contentRect: webView.frame,
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Sign in to GOG"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = webView
        window.delegate = self
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        webView.load(URLRequest(url: GOG.authorizationURL))
    }

    // MARK: - Watching for the redirect

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { return decisionHandler(.allow) }
        // The sign-in is done the moment GOG redirects with a code — no need to load that page.
        if let code = GOG.authorizationCode(from: url.absoluteString), url.host?.contains("gog.com") == true {
            decisionHandler(.cancel)
            finish(.code(code))
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        reportLoadFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        reportLoadFailure(error)
    }

    private func reportLoadFailure(_ error: Error) {
        // A cancelled navigation is how the redirect above is stopped; it is not a failure.
        let nsError = error as NSError
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
        finish(.failed("Couldn't load GOG's sign-in page: \(error.localizedDescription)"))
    }

    private func finish(_ result: Result) {
        guard !finished else { return }
        finished = true
        window?.delegate = nil
        window?.close()
        if GOGSignInWindow.current === self { GOGSignInWindow.current = nil }
        completion(result)
    }
}

extension GOGSignInWindow: NSWindowDelegate {
    /// Closing the window is a legitimate answer, not an error — report it as cancellation so the
    /// Accounts screen shows nothing rather than a red message the player caused on purpose.
    func windowWillClose(_ notification: Notification) {
        finish(.cancelled)
    }
}
