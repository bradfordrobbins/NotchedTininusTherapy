import SwiftUI

@main
struct TininusNotchApp: App {
    @State private var settings = AppSettings()
    @State private var listeningLog = ListeningLog()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(listeningLog)
        }
        #if os(macOS)
        .defaultSize(width: 760, height: 840)
        #endif
    }
}
