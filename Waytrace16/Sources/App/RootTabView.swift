import SwiftUI

struct RootTabView: View {
    @State private var showingSettings = false

    var body: some View {
        TabView {
            TodayView(showingSettings: $showingSettings)
                .tabItem {
                    Label("今天", systemImage: "point.topright.filled.arrow.triangle.backward.to.point.bottomleft.scurvepath")
                }

            WorldView(showingSettings: $showingSettings)
                .tabItem {
                    Label("足迹", systemImage: "globe.asia.australia.fill")
                }

            TripsView(showingSettings: $showingSettings)
                .tabItem {
                    Label("旅程", systemImage: "suitcase.rolling.fill")
                }

            StatsView(showingSettings: $showingSettings)
                .tabItem {
                    Label("统计", systemImage: "chart.bar.xaxis")
                }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}
