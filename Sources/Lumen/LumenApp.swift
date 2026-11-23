import SwiftUI

@main
struct LumenApp: App {
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
