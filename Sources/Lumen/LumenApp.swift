import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Un exécutable SwiftPM n'est pas un .app : on force l'app à passer au premier plan.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct LumenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = GameLibrary()
    @StateObject private var input = ControllerInput()

    var body: some Scene {
        WindowGroup {
            XMBView()
                .environmentObject(library)
                .environmentObject(input)
                .frame(minWidth: 1280, minHeight: 540)
                .onAppear { input.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 3440, height: 1440)
    }
}
