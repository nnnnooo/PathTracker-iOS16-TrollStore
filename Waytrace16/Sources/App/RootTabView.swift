import SwiftUI
import UIKit

enum RootTab: Int, Hashable {
    case today = 0
    case world = 1
    case chinaMap = 2
    case trips = 3
    case stats = 4
}

struct RootTabView: View {
    @State private var selectedTab: RootTab = .today
    @State private var showingSettings = false

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(showingSettings: $showingSettings)
                .tabItem {
                    Label("今天", systemImage: "point.topleft.down.curvedto.point.filled.bottomright.up")
                }
                .tag(RootTab.today)

            WorldView(showingSettings: $showingSettings, selectedTab: $selectedTab)
                .tabItem {
                    Label("足迹", systemImage: "globe.asia.australia.fill")
                }
                .tag(RootTab.world)

            ChinaLightUpTabView(showingSettings: $showingSettings)
                .tabItem {
                    Label("省市县", systemImage: "map.fill")
                }
                .tag(RootTab.chinaMap)

            TripsView(showingSettings: $showingSettings)
                .tabItem {
                    Label("旅程", systemImage: "suitcase.fill")
                }
                .tag(RootTab.trips)

            StatsView(showingSettings: $showingSettings)
                .tabItem {
                    Label("统计", systemImage: "chart.bar.xaxis")
                }
                .tag(RootTab.stats)
        }
        .onChange(of: selectedTab) { _ in
            UISelectionFeedbackGenerator().selectionChanged()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}
