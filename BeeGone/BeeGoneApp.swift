import SwiftUI

@main
struct BeeGoneApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 640, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 800, height: 640)
    }
}
