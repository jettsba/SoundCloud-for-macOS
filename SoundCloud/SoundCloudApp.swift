//
//  SoundCloudApp.swift
//  SoundCloud
//
//  Created by Romain on 2/6/25.
//

import SwiftUI

@main
struct SoundCloudApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The main window is managed by AppDelegate so the web view (and playback)
        // survives the window being closed.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {}
            CommandGroup(replacing: .newItem) {}
        }
    }
}
