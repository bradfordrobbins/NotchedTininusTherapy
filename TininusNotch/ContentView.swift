import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ListeningLog.self) private var listeningLog
    @Environment(\.scenePhase) private var scenePhase
    @State private var sineEngine = SineToneEngine()
    @State private var player: TherapyPlayer?
    @State private var selectedTab = AppTab.findFrequency

    var body: some View {
        TabView(selection: $selectedTab) {
            FindFrequencyView(sineEngine: sineEngine)
                .tabItem {
                    Label("Find Frequency", systemImage: "waveform.path")
                }
                .tag(AppTab.findFrequency)

            Group {
                if let player {
                    TherapyPlayerView(player: player)
                } else {
                    ProgressView()
                }
            }
            .tabItem {
                Label("Therapy Music", systemImage: "music.note.list")
            }
            .tag(AppTab.therapy)

            ListeningUsageView()
                .tabItem {
                    Label("Listening", systemImage: "calendar")
                }
                .tag(AppTab.usage)
        }
        .onAppear {
            if player == nil {
                player = TherapyPlayer(settings: settings, listeningLog: listeningLog)
            }
        }
        .onChange(of: selectedTab) { _, tab in
            switch tab {
            case .findFrequency:
                player?.pause()
            case .therapy, .usage:
                sineEngine.stop()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                player?.flushListening()
            }
        }
    }
}

private enum AppTab: Hashable {
    case findFrequency
    case therapy
    case usage
}

#Preview {
    ContentView()
        .environment(AppSettings())
        .environment(ListeningLog())
}
