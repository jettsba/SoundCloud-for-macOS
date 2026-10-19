//
//  MainWindowController.swift
//  SoundCloud
//

import AppKit
import WebKit

final class MainWindowController: NSWindowController {
    private let webView: WKWebView
    private let icon = NSImageView(image: NSApp.applicationIconImage)
    private let colorKey = "PageBackgroundColor"

    init(player: PlayerController) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SoundCloud"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("MainWindow")

        webView = player.webView
        super.init(window: window)

        // The web view stays transparent until SoundCloud has rendered, so the window
        // shows its background color and the app icon instead of a white flash.
        let container = NSView()
        webView.alphaValue = 0
        for view in [webView, icon] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        container.addSubview(icon)
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 96),
            icon.heightAnchor.constraint(equalToConstant: 96),
        ])

        window.contentView = container
        apply(color: savedColor ?? defaultColor)

        player.onPageColorChange = { [weak self] color in
            self?.apply(color: color)
            self?.save(color: color)
            self?.revealPage()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.revealPage()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func apply(color: NSColor) {
        guard let window else { return }
        window.backgroundColor = color
        let isDark = (color.usingColorSpace(.sRGB)?.brightnessComponent ?? 0) < 0.5
        window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    private func revealPage() {
        guard icon.superview != nil, webView.alphaValue == 0 else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            webView.animator().alphaValue = 1
        }, completionHandler: { [icon] in
            icon.removeFromSuperview()
        })
    }

    private var defaultColor: NSColor {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? NSColor(srgbRed: 18 / 255, green: 18 / 255, blue: 18 / 255, alpha: 1) : .white
    }

    private var savedColor: NSColor? {
        guard let components = UserDefaults.standard.array(forKey: colorKey) as? [CGFloat], components.count == 3 else { return nil }
        return NSColor(srgbRed: components[0], green: components[1], blue: components[2], alpha: 1)
    }

    private func save(color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return }
        UserDefaults.standard.set([rgb.redComponent, rgb.greenComponent, rgb.blueComponent], forKey: colorKey)
    }
}
