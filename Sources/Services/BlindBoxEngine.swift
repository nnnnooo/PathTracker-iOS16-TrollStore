import Foundation
import CoreLocation

struct BoardingPass: Identifiable, Codable, Hashable {
    var id: UUID
    var placeID: String
    var placeName: String
    var region: String
    var reason: String
    var suggestion: String
    var distanceKm: Double?
    var drawnAt: Date

    init(
        id: UUID = UUID(),
        placeID: String,
        placeName: String,
        region: String,
        reason: String,
        suggestion: String,
        distanceKm: Double?,
        drawnAt: Date = Date()
    ) {
        self.id = id
        self.placeID = placeID
        self.placeName = placeName
        self.region = region
        self.reason = reason
        self.suggestion = suggestion
        self.distanceKm = distanceKm
        self.drawnAt = drawnAt
    }
}

@MainActor
final class BlindBoxStore: ObservableObject {
    static let shared = BlindBoxStore()

    @Published private(set) var savedPasses: [BoardingPass] = []

    private let key = "wt16.blindbox.passes"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([BoardingPass].self, from: data) {
            self.savedPasses = decoded
        }
    }

    func save(_ pass: BoardingPass) {
        guard !savedPasses.contains(where: { $0.placeID == pass.placeID }) else { return }
        savedPasses.insert(pass, at: 0)
        persist()
    }

    func remove(id: UUID) {
        savedPasses.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(savedPasses) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

enum BlindBoxEngine {
    enum Horizon: String, CaseIterable, Identifiable {
        case dayTrip, weekend, shortHoliday, longHoliday
        var id: String { rawValue }

        var title: String {
            switch self {
            case .dayTrip: return "周边一天"
            case .weekend: return "一个周末"
            case .shortHoliday: return "小长假"
            case .longHoliday: return "长假远行"
            }
        }

        var maxKm: Double? {
            switch self {
            case .dayTrip: return 300
            case .weekend: return 900
            case .shortHoliday: return 2600
            case .longHoliday: return nil
            }
        }
    }

    enum Vibe: String, CaseIterable, Identifiable {
        case any, relax, active, culture, city, wild
        var id: String { rawValue }

        var title: String {
            switch self {
            case .any: return "都行"
            case .relax: return "放空看水"
            case .active: return "出点汗"
            case .culture: return "看老东西"
            case .city: return "人间烟火"
            case .wild: return "奔向旷野"
            }
        }

        var matchingKind: MustSeePlace.Kind? {
            switch self {
            case .any: return nil
            case .relax: return .water
            case .active: return .mountain
            case .culture: return .heritage
            case .city: return .city
            case .wild: return .wild
            }
        }
    }

    static func draw(
        horizon: Horizon,
        vibe: Vibe,
        userLocation: CLLocation?,
        visitedIDs: Set<String>,
        wishIDs: Set<String>,
        excludingPlaceID: String?
    ) -> BoardingPass? {
        let unvisited = MustSee.allPlaces.filter { !visitedIDs.contains($0.id) && $0.id != excludingPlaceID }
        guard !unvisited.isEmpty else { return nil }

        var pool = unvisited
        if let kind = vibe.matchingKind {
            let vibeFiltered = pool.filter { $0.kind == kind }
            if !vibeFiltered.isEmpty { pool = vibeFiltered }
        }

        if let maxKm = horizon.maxKm, let loc = userLocation {
            let near = pool.filter { $0.location.distance(from: loc) / 1000.0 <= maxKm }
            if !near.isEmpty {
                pool = near
            } else {
                // Fallback to closest 12 unvisited places
                pool = Array(pool.sorted { $0.location.distance(from: loc) < $1.location.distance(from: loc) }.prefix(12))
            }
        }

        // Favor wish-list items slightly
        let weighted: [MustSeePlace] = pool.flatMap { place in
            wishIDs.contains(place.id) ? [place, place, place] : [place]
        }
        guard let picked = weighted.randomElement() else { return nil }

        let distKm: Double? = userLocation.map { picked.location.distance(from: $0) / 1000.0 }
        let reason: String
        if wishIDs.contains(picked.id) {
            reason = "它一直在你的「想去」清单里等着你。"
        } else if let km = distKm, km < 350 {
            reason = "离你只有 \(Int(km.rounded())) 公里，可你还没去过。"
        } else if visitedIDs.isEmpty {
            reason = "把它作为你点亮「此生必去」的第一盏灯吧。"
        } else {
            reason = "\(picked.region)的经典目的地，适合换个风景走走。"
        }

        let suggestion: String
        switch picked.kind {
        case .water: suggestion = "建议日落前一小时抵达水边，光线最柔和；留半天慢慢发呆。"
        case .mountain: suggestion = "早起避开人流，穿舒适防滑鞋，留意山间温差与天气变化。"
        case .heritage: suggestion = "放慢脚步听一段历史讲解，避开正午高峰，在清晨或黄昏看光影。"
        case .city: suggestion = "挑一条老街无目的地散步两小时，吃一顿当地人排队的馆子。"
        case .wild: suggestion = "预留充裕交通时间，抬头看云与星空，记得带好防风保暖衣物。"
        }

        return BoardingPass(
            placeID: picked.id,
            placeName: picked.name,
            region: picked.region,
            reason: reason,
            suggestion: suggestion,
            distanceKm: distKm
        )
    }
}
