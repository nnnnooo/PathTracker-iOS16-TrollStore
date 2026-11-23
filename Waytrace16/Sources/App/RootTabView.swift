import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("今天", systemImage: "location.fill")
                }

            WorldView()
                .tabItem {
                    Label("足迹", systemImage: "globe.asia.australia.fill")
                }

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
        }
    }
}
