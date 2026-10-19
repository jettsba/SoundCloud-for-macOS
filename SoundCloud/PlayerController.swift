//
//  PlayerController.swift
//  SoundCloud
//

import AppKit
import WebKit

final class PlayerController: NSObject {
    let webView: WKWebView

    override init() {
        let configuration = WKWebViewConfiguration()
        // Use the default (persistent) data store so cookies persist between launches.
        configuration.websiteDataStore = .default()

        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        webView.navigationDelegate = self
        webView.load(URLRequest(url: URL(string: "https://soundcloud.com")!))
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
