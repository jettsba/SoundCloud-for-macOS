//
//  PlayerController.swift
//  SoundCloud
//

import AppKit
import IOKit
import WebKit

final class PlayerController: NSObject {
    let webView: WKWebView
    var onPageColorChange: ((NSColor) -> Void)?

    private var popups: [NSWindow] = []
    private var playbackActivity: NSObjectProtocol?
    private var nowPlaying: NowPlaying?

    override init() {
        let configuration = WKWebViewConfiguration()
        // Use the default (persistent) data store so cookies persist between launches.
        configuration.websiteDataStore = .default()
        // Sign-in providers such as Google refuse to work in a web view without a browser user agent.
        configuration.applicationNameForUserAgent = "Version/\(PlayerController.safariVersion) Safari/605.1.15"
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        // Keep timers and network running while the window is hidden or closed,
        // otherwise the audio buffer starves and playback goes silent.
        configuration.preferences.inactiveSchedulingPolicy = .none

        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        nowPlaying = NowPlaying { [weak self] action, value in
            let argument = value.map { ", \($0)" } ?? ""
            self?.webView.evaluateJavaScript("window.desktopPlayer?.command('\(action)'\(argument))")
        }

        if let url = Bundle.main.url(forResource: "Player", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            configuration.userContentController.addUserScript(script)
        }
        configuration.userContentController.add(self, name: "player")

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: URL(string: "https://soundcloud.com")!))

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    @objc private func systemWillSleep() {
        suspend()
    }

    // Closing the lid only turns the display off at first; the system may not sleep for a while.
    // Screens going off on their own (idle timeout) should not stop the music.
    @objc private func screensDidSleep() {
        if PlayerController.isLidClosed {
            suspend()
        }
    }

    @objc private func didWake() {
        webView.evaluateJavaScript("window.desktopPlayer?.wake()")
    }

    private func suspend() {
        webView.evaluateJavaScript("window.desktopPlayer?.suspend()")
    }

    private func setPlaying(_ playing: Bool) {
        if playing, playbackActivity == nil {
            playbackActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Playing audio"
            )
        } else if !playing, let activity = playbackActivity {
            ProcessInfo.processInfo.endActivity(activity)
            playbackActivity = nil
        }
    }

    private static func track(from value: Any?) -> NowPlaying.Track? {
        guard let info = value as? [String: Any],
              let title = info["title"] as? String, !title.isEmpty else { return nil }
        return NowPlaying.Track(
            title: title,
            artist: info["artist"] as? String ?? "",
            album: info["album"] as? String ?? "",
            artwork: info["artwork"] as? String ?? "",
            duration: (info["duration"] as? NSNumber)?.doubleValue ?? 0,
            position: (info["position"] as? NSNumber)?.doubleValue ?? 0
        )
    }

    private static func color(from rgb: [Double]) -> NSColor? {
        guard rgb.count == 3 else { return nil }
        return NSColor(srgbRed: rgb[0] / 255, green: rgb[1] / 255, blue: rgb[2] / 255, alpha: 1)
    }

    private static var isLidClosed: Bool {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0 else { return false }
        defer { IOObjectRelease(rootDomain) }
        let state = IORegistryEntryCreateCFProperty(rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return state?.takeRetainedValue() as? Bool ?? false
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

extension PlayerController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.webView === webView,
              let body = message.body as? [String: Any] else { return }
        if let color = (body["color"] as? [Double]).flatMap(PlayerController.color(from:)) {
            onPageColorChange?(color)
        }
        if let playing = body["playing"] as? Bool {
            setPlaying(playing)
            nowPlaying?.update(track: PlayerController.track(from: body["track"]), playing: playing)
        }
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
