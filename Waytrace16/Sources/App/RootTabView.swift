import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("今天", systemImage: "location.fill")
                }

            TripsView()
                .tabItem {
                    Label("旅程", systemImage: "suitcase.rolling.fill")
                }

            WorldView()
                .tabItem {
                    Label("足迹", systemImage: "globe.asia.australia.fill")
                }

            StatsView()
                .tabItem {
                    Label("统计", systemImage: "chart.bar.fill")
                }

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
        }
    }
}
