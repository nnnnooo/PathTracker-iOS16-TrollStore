import Foundation
import SwiftUI
import CoreLocation
import MapKit

struct TrackChunk: Identifiable, Hashable, Sendable {
    var id: UUID
    var startDate: Date
    var endDate: Date
    var distance: Double
    var pointCount: Int
    var minLatitude: Double
    var maxLatitude: Double
    var minLongitude: Double
    var maxLongitude: Double
    var modeRaw: String
    var pointsData: Data

    init(id: UUID = UUID(), points: [TrackPoint], mode: MovementMode) {
        self.id = id
        self.startDate = points.first?.timestamp ?? Date()
        self.endDate = points.last?.timestamp ?? Date()
        self.pointCount = points.count
        self.distance = TrackPoint.distance(of: points)
        self.modeRaw = mode.rawValue
        self.minLatitude = points.map(\.latitude).min() ?? 0
        self.maxLatitude = points.map(\.latitude).max() ?? 0
        self.minLongitude = points.map(\.longitude).min() ?? 0
        self.maxLongitude = points.map(\.longitude).max() ?? 0
        self.pointsData = TrackCodec.encode(points)
    }

    init(
        id: UUID,
        startDate: Date,
        endDate: Date,
        distance: Double,
        pointCount: Int,
        minLatitude: Double,
        maxLatitude: Double,
        minLongitude: Double,
        maxLongitude: Double,
        modeRaw: String,
        pointsData: Data
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.distance = distance
        self.pointCount = pointCount
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
        self.modeRaw = modeRaw
        self.pointsData = pointsData
    }

    var mode: MovementMode { MovementMode(rawValue: modeRaw) ?? .unknown }

    var points: [TrackPoint] {
        TrackCodec.decode(pointsData)
    }

    var duration: TimeInterval {
        max(0, endDate.timeIntervalSince(startDate))
    }
}

enum TagState: Int, Sendable {
    case pending = 0
    case tagged = 1
    case failed = 2
}

struct Stay: Identifiable, Hashable, Sendable {
    var id: UUID
    var arrival: Date
    var departure: Date?
    var latitude: Double
    var longitude: Double
    var sampleCount: Int

    var placeName: String?
    var categoryRaw: String?
    var street: String?
    var city: String?
    var region: String?
    var country: String?
    var countryCode: String?
    var isLandmark: Bool
    var tagStateRaw: Int

    var customName: String?
    var note: String?
    var sourceRaw: String?
    var timeZoneID: String?

    init(
        id: UUID = UUID(),
        arrival: Date,
        departure: Date? = nil,
        coordinate: CLLocationCoordinate2D,
        sampleCount: Int = 1,
        sourceRaw: String? = nil
    ) {
        self.id = id
        self.arrival = arrival
        self.departure = departure
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.sampleCount = sampleCount
        self.isLandmark = false
        self.tagStateRaw = TagState.pending.rawValue
        self.sourceRaw = sourceRaw
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    var tagState: TagState {
        get { TagState(rawValue: tagStateRaw) ?? .pending }
        set { tagStateRaw = newValue.rawValue }
    }

    var displayName: String {
        customName ?? placeName ?? street ?? city ?? "未知地点"
    }

    var subtitle: String? {
        let parts = [city, country].compactMap { $0 }.removingDuplicates()
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var duration: TimeInterval {
        max(0, (departure ?? Date()).timeIntervalSince(arrival))
    }

    var category: PlaceCategory {
        PlaceCategory(rawValue: categoryRaw)
    }

    var isFromPhotos: Bool {
        sourceRaw == PhotoFootprints.source
    }
}

enum MovementMode: String, CaseIterable, Sendable {
    case walking, running, cycling, automotive, subway, flying, unknown

    var title: String {
        switch self {
        case .walking: return "步行"
        case .running: return "跑步"
        case .cycling: return "骑行"
        case .automotive: return "乘车"
        case .subway: return "地铁"
        case .flying: return "飞行"
        case .unknown: return "移动"
        }
    }

    var symbol: String {
        switch self {
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .automotive: return "car.fill"
        case .subway: return "tram.fill.tunnel"
        case .flying: return "airplane"
        case .unknown: return "location.north.line.fill"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .walking: return .systemGreen
        case .running: return .systemMint
        case .cycling: return .systemOrange
        case .automotive: return .systemBlue
        case .subway: return .systemPurple
        case .flying: return .systemCyan
        case .unknown: return .systemTeal
        }
    }

    var color: Color {
        Color(uiColor)
    }
}

enum PlaceCategory: Equatable, Sendable {
    case home, school, work
    case food, cafe, nightlife, shopping
    case landmark, museum, park, nature, entertainment, sports
    case transport, airport, hotel, health, other

    static let chosenRawValues: Set<String> = ["home", "school", "work", "mall", "restaurant"]

    init(rawValue: String?) {
        guard let rawValue else { self = .other; return }
        switch rawValue {
        case "home": self = .home
        case "school": self = .school
        case "work": self = .work
        case "mall": self = .shopping
        case "restaurant": self = .food
        case "sight", "MKPOICategoryLandmark", "MKPOICategoryCastle", "MKPOICategoryFortress":
            self = .landmark
        default:
            self = PlaceCategory(MKPointOfInterestCategory(rawValue: rawValue))
        }
    }

    init(_ category: MKPointOfInterestCategory) {
        switch category {
        case .restaurant, .bakery, .foodMarket, .brewery, .winery: self = .food
        case .cafe: self = .cafe
        case .nightlife: self = .nightlife
        case .store: self = .shopping
        case .museum, .library: self = .museum
        case .park, .amusementPark, .zoo, .aquarium: self = .park
        case .nationalPark, .beach, .campground: self = .nature
        case .theater, .movieTheater, .stadium: self = .entertainment
        case .fitnessCenter: self = .sports
        case .publicTransport, .parking, .gasStation, .marina: self = .transport
        case .airport: self = .airport
        case .hotel: self = .hotel
        case .hospital, .pharmacy: self = .health
        case .school, .university: self = .school
        default:
            if category.rawValue == "MKPOICategoryLandmark" || category.rawValue == "MKPOICategoryNationalMonument" {
                self = .landmark
            } else {
                self = .other
            }
        }
    }

    static let landmarkCategories: [MKPointOfInterestCategory] = [
        .museum, .nationalPark, .park,
        .amusementPark, .zoo, .aquarium, .beach, .stadium, .theater,
    ]

    static let utilityCategories: Set<MKPointOfInterestCategory> = [
        .atm, .parking, .gasStation,
    ]

    static func isSight(_ category: MKPointOfInterestCategory?) -> Bool {
        guard let category else { return false }
        return landmarkCategories.contains(category)
            || category.rawValue == "MKPOICategoryLandmark"
            || category.rawValue == "MKPOICategoryNationalMonument"
            || category.rawValue == "MKPOICategoryScenicView"
    }

    static func rankingScore(_ category: MKPointOfInterestCategory?, distance: CLLocationDistance) -> Double {
        let handicap: Double
        switch category {
        case .museum, .nationalPark, .zoo, .aquarium, .stadium, .theater: handicap = 60
        case .park, .beach: handicap = 90
        case .amusementPark: handicap = 150
        default:
            if category?.rawValue == "MKPOICategoryLandmark" || category?.rawValue == "MKPOICategoryNationalMonument" {
                handicap = 0
            } else {
                handicap = 120
            }
        }
        return distance + handicap
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .school: return "graduationcap.fill"
        case .work: return "briefcase.fill"
        case .food: return "fork.knife"
        case .cafe: return "cup.and.saucer.fill"
        case .nightlife: return "wineglass.fill"
        case .shopping: return "bag.fill"
        case .landmark: return "building.columns.fill"
        case .museum: return "building.columns"
        case .park: return "tree.fill"
        case .nature: return "mountain.2.fill"
        case .entertainment: return "theatermasks.fill"
        case .sports: return "figure.run"
        case .transport: return "tram.fill"
        case .airport: return "airplane"
        case .hotel: return "bed.double.fill"
        case .health: return "cross.case.fill"
        case .other: return "mappin"
        }
    }

    var tint: Color {
        switch self {
        case .home: return .blue
        case .school, .work: return .indigo
        case .food: return .orange
        case .cafe: return .brown
        case .nightlife: return .purple
        case .shopping: return .pink
        case .landmark, .museum: return .yellow
        case .park, .nature: return .green
        case .entertainment: return .purple
        case .sports: return .mint
        case .transport, .airport: return .teal
        case .hotel: return .cyan
        case .health: return .red
        case .other: return .gray
        }
    }
}

extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum Formatters {
    static func distance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters.rounded())) m"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(1, Int(seconds / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 {
            return "\(hours)小时\(minutes)分"
        } else if hours > 0 {
            return "\(hours)小时"
        }
        return "\(minutes)分钟"
    }

    static func timeHM(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func dayTitle(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = cal.isDate(date, equalTo: Date(), toGranularity: .year) ? "M月d日" : "yyyy年M月d日"
        return f.string(from: date)
    }

    static func weekdaySubtitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年 · EEEE"
        return f.string(from: date)
    }
}
