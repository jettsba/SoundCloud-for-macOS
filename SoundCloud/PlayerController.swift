//
//  PlayerController.swift
//  SoundCloud
//

import AppKit
import WebKit

final class PlayerController: NSObject {
    let webView: WKWebView

    private var popups: [NSWindow] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        // Use the default (persistent) data store so cookies persist between launches.
        configuration.websiteDataStore = .default()
        // Sign-in providers such as Google refuse to work in a web view without a browser user agent.
        configuration.applicationNameForUserAgent = "Version/\(PlayerController.safariVersion) Safari/605.1.15"
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        if let url = Bundle.main.url(forResource: "Player", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            configuration.userContentController.addUserScript(script)
        }

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: URL(string: "https://soundcloud.com")!))
    }

    private static var safariVersion: String {
        let info = NSDictionary(contentsOfFile: "/Applications/Safari.app/Contents/Info.plist")
        return info?["CFBundleShortVersionString"] as? String ?? "18.0"
    }

    private static func isSoundCloud(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host == "soundcloud.com" || host.hasSuffix(".soundcloud.com")
    }
}

extension PlayerController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("Navigation error: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("Provisional navigation error: \(error.localizedDescription)")
    }
}

extension PlayerController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // Links with target="_blank": SoundCloud pages stay in the app, everything else goes to the browser.
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            if PlayerController.isSoundCloud(url) {
                self.webView.load(navigationAction.request)
            } else {
                NSWorkspace.shared.open(url)
            }
            return nil
        }

        // window.open() popups, used by Google / Apple / Facebook sign-in.
        // The popup must be created with the given configuration so it can talk back to its opener.
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.uiDelegate = self
        popup.autoresizingMask = [.width, .height]

        let width = windowFeatures.width?.doubleValue ?? 500
        let height = windowFeatures.height?.doubleValue ?? 650
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = popup
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        popups.append(window)

        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        popups.first { $0.contentView === webView }?.close()
    }
}

extension PlayerController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        popups.removeAll { $0 === window }
    }
}
