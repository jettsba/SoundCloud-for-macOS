//
//  AppDelegate.swift
//  SoundCloud
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let player = PlayerController()
    private var windowController: MainWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = MainWindowController(player: player)
        windowController.showWindow(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            windowController.showWindow(nil)
        }
        return true
    }
}
