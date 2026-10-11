import SwiftUI

import AppKit

/// `swift run` starts a bare executable that is not a foreground app, so keystrokes
/// stay in the terminal. Promote it to a regular app and make its window key.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct BruceMacOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @StateObject private var location = LocationProvider()
    var body: some Scene {
        WindowGroup("Bruce Studios") {
            RootView()
                .environment(model)
                .frame(width: Theme.windowSize.width, height: Theme.windowSize.height)
                .lightCanvas()
                .onAppear { location.model = model; if model.isLoggedIn { location.requestIfNeeded() } }
                .onChange(of: model.session) { _, s in if s != nil { location.requestIfNeeded() } }
        }
        .windowResizability(.contentSize)
    }
}

