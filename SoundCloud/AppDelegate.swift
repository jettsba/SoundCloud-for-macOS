//
//  AppDelegate.swift
//  SoundCloud
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let player = PlayerController()
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SoundCloud"
        window.isReleasedWhenClosed = false
        window.contentView = player.webView
        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
