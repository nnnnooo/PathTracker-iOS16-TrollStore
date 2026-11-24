import SwiftUI

@main
struct Waytrace16App: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var store: DataStore
    @StateObject private var tagger: PlaceTagger
    @StateObject private var engine: LocationEngine
    @StateObject private var chinaStore = ChinaRegionsStore.shared

    init() {
        let store = DataStore()
        let tagger = PlaceTagger(store: store)
        let engine = LocationEngine(store: store, tagger: tagger)
        _store = StateObject(wrappedValue: store)
        _tagger = StateObject(wrappedValue: tagger)
        _engine = StateObject(wrappedValue: engine)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .environmentObject(tagger)
                .environmentObject(engine)
                .environmentObject(chinaStore)
                .onAppear {
                    tagger.enqueue()
                }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                engine.refreshState()
                tagger.enqueue()
            case .background:
                engine.persistNow()
            default:
                break
            }
        }
    }
}
