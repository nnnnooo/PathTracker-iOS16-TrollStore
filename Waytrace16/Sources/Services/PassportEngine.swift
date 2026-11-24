import Foundation
import SwiftUI
import CoreLocation

// MARK: - Passport Theme

enum PassportTheme: String, CaseIterable, Identifiable {
    case burgundy, navy, forest, obsidian

    var id: String { rawValue }

    var title: String {
        switch self {
        case .burgundy: return "酒红"
        case .navy: return "藏青"
        case .forest: return "墨绿"
        case .obsidian: return "夜黑"
        }
    }

    var leather: Color {
        switch self {
        case .burgundy: return Color(red: 0.37, green: 0.08, blue: 0.13)
        case .navy: return Color(red: 0.07, green: 0.13, blue: 0.29)
        case .forest: return Color(red: 0.09, green: 0.24, blue: 0.18)
        case .obsidian: return Color(red: 0.09, green: 0.09, blue: 0.10)
        }
    }

    // Aliases kept for WorldView compatibility
    var coverColor: Color { leather }

    var foilColor: Color {
        switch self {
        case .navy: return Color(red: 0.85, green: 0.88, blue: 0.93)
        case .obsidian: return Color(red: 0.89, green: 0.81, blue: 0.62)
        default: return Color(red: 0.88, green: 0.75, blue: 0.44)
        }
    }

    var foilGradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .navy:
            colors = [Color(red: 0.93, green: 0.94, blue: 0.96), Color(red: 0.64, green: 0.68, blue: 0.75), Color(red: 0.97, green: 0.98, blue: 1)]
        case .obsidian:
            colors = [Color(red: 0.95, green: 0.88, blue: 0.70), Color(red: 0.74, green: 0.64, blue: 0.45), Color(red: 0.97, green: 0.91, blue: 0.74)]
        default:
            colors = [Color(red: 0.93, green: 0.80, blue: 0.50), Color(red: 0.75, green: 0.58, blue: 0.30), Color(red: 0.95, green: 0.84, blue: 0.56)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var emblem: String {
        switch self {
        case .burgundy: return "globe.asia.australia.fill"
        case .navy: return "safari.fill"
        case .forest: return "mountain.2.fill"
        case .obsidian: return "moon.stars.fill"
        }
    }

    var paperColor: Color {
        switch self {
        case .burgundy: return Color(red: 0.965, green: 0.945, blue: 0.895)
        case .navy: return Color(red: 0.94, green: 0.955, blue: 0.97)
        case .forest: return Color(red: 0.95, green: 0.955, blue: 0.915)
        case .obsidian: return Color(red: 0.955, green: 0.948, blue: 0.935)
        }
    }

    var guilloche: Color {
        switch self {
        case .burgundy: return Color(red: 0.86, green: 0.82, blue: 0.72)
        case .navy: return Color(red: 0.72, green: 0.79, blue: 0.89)
        case .forest: return Color(red: 0.74, green: 0.83, blue: 0.72)
        case .obsidian: return Color(red: 0.80, green: 0.77, blue: 0.74)
        }
    }

    var printed: Color {
        switch self {
        case .burgundy: return Color(red: 0.25, green: 0.22, blue: 0.30)
        case .navy: return Color(red: 0.14, green: 0.20, blue: 0.34)
        case .forest: return Color(red: 0.16, green: 0.26, blue: 0.21)
        case .obsidian: return Color(red: 0.18, green: 0.18, blue: 0.20)
        }
    }

    var pattern: StampPaperPattern {
        switch self {
        case .burgundy: return .waves
        case .navy: return .lattice
        case .forest: return .ripples
        case .obsidian: return .rosette
        }
    }
}

enum StampPaperPattern {
    case waves, lattice, ripples, rosette
}

// MARK: - Ink & Shapes & Seed

enum StampInk: Int, CaseIterable, Sendable {
    case navy, crimson, forest, plum, teal, umber, slate, cinnabar

    var color: Color {
        switch self {
        case .navy: return Color(red: 0.16, green: 0.30, blue: 0.62)
        case .crimson: return Color(red: 0.70, green: 0.17, blue: 0.20)
        case .forest: return Color(red: 0.20, green: 0.45, blue: 0.29)
        case .plum: return Color(red: 0.42, green: 0.27, blue: 0.58)
        case .teal: return Color(red: 0.08, green: 0.43, blue: 0.50)
        case .umber: return Color(red: 0.58, green: 0.32, blue: 0.16)
        case .slate: return Color(red: 0.22, green: 0.25, blue: 0.30)
        case .cinnabar: return Color(red: 0.78, green: 0.20, blue: 0.14)
        }
    }

    static let everyday: [StampInk] = [.navy, .crimson, .forest, .plum, .teal, .umber, .slate]
}

enum StampShape: Int, CaseIterable, Sendable {
    case rectangle, rounded, circle, oval, octagon, hexagon, ticket, scalloped
}

enum StampSeed {
    static func of(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

struct SeededRandom {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

// MARK: - Core Stamp Model

struct PassportStamp: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case entry, exit, province, city, special, set }

    let id: String
    let kind: Kind
    let date: Date
    var countryCode: String?
    var port: String?
    var byAir: Bool = false
    var days: Int = 0
    var provinceID: String?
    var city: String?
    var latitude: Double = 0.0
    var longitude: Double = 0.0
    var code: String?
    var value: String?

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var seed: UInt64 { StampSeed.of(id) }
    var tilt: Double { Double(seed % 1300) / 100 - 6.5 }
}

// MARK: - Country Stamp Style

struct CountryStampStyle {
    let native: String
    let ink: StampInk
    let shape: StampShape

    static func of(_ code: String) -> CountryStampStyle {
        if let curated = curated[code] {
            return CountryStampStyle(native: curated.0, ink: curated.1, shape: curated.2)
        }
        let seed = StampSeed.of(code)
        let fallbackShapes: [StampShape] = [.rectangle, .rounded, .circle, .oval, .octagon, .hexagon, .ticket]
        let english = Locale(identifier: "en").localizedString(forRegionCode: code)?.uppercased() ?? code
        return CountryStampStyle(
            native: english,
            ink: StampInk.everyday[Int(seed % UInt64(StampInk.everyday.count))],
            shape: fallbackShapes[Int((seed >> 8) % UInt64(fallbackShapes.count))]
        )
    }

    private static let curated: [String: (String, StampInk, StampShape)] = [
        "CN": ("中国", .crimson, .rectangle), "HK": ("香港", .crimson, .octagon), "MO": ("澳門", .forest, .octagon),
        "TW": ("台灣", .navy, .rounded), "JP": ("日本国", .crimson, .circle), "KR": ("대한민국", .navy, .rounded),
        "KP": ("조선", .crimson, .rectangle), "MN": ("МОНГОЛ УЛС", .navy, .hexagon), "SG": ("SINGAPORE", .crimson, .rectangle),
        "MY": ("MALAYSIA", .navy, .oval), "TH": ("ประเทศไทย", .plum, .rounded), "VN": ("VIỆT NAM", .crimson, .circle),
        "ID": ("INDONESIA", .forest, .ticket), "PH": ("PILIPINAS", .navy, .oval), "KH": ("កម្ពុជា", .umber, .octagon),
        "LA": ("ລາວ", .teal, .rounded), "MM": ("မြန်မာ", .forest, .circle), "BN": ("BRUNEI", .umber, .hexagon),
        "IN": ("भारत", .navy, .oval), "NP": ("नेपाल", .crimson, .hexagon), "LK": ("ශ්‍රී ලංකාව", .umber, .ticket),
        "BT": ("BHUTAN", .umber, .circle), "MV": ("MALDIVES", .teal, .oval), "PK": ("PAKISTAN", .forest, .rectangle),
        "AE": ("الإمارات", .forest, .rounded), "QA": ("قطر", .plum, .oval), "SA": ("السعودية", .forest, .rectangle),
        "JO": ("الأردن", .crimson, .octagon), "IL": ("ישראל", .navy, .rectangle), "TR": ("TÜRKİYE", .crimson, .circle),
        "EG": ("مصر", .umber, .hexagon), "MA": ("المغرب · MAROC", .crimson, .octagon), "IR": ("ایران", .forest, .rounded),
        "KZ": ("ҚАЗАҚСТАН", .teal, .oval), "UZ": ("OʻZBEKISTON", .teal, .hexagon), "GE": ("საქართველო", .crimson, .rounded),
        "RU": ("РОССИЯ", .navy, .rectangle), "UA": ("УКРАЇНА", .navy, .rounded), "GR": ("ΕΛΛΑΔΑ", .navy, .circle),
        "BG": ("БЪЛГАРИЯ", .forest, .rectangle), "RS": ("СРБИЈА", .crimson, .oval),
        "GB": ("UNITED KINGDOM", .slate, .rectangle), "IE": ("ÉIRE · IRELAND", .forest, .oval), "FR": ("FRANCE", .navy, .rounded),
        "DE": ("DEUTSCHLAND", .slate, .rectangle), "IT": ("ITALIA", .forest, .oval), "ES": ("ESPAÑA", .crimson, .rounded),
        "PT": ("PORTUGAL", .forest, .circle), "NL": ("NEDERLAND", .umber, .rectangle), "BE": ("BELGIË · BELGIQUE", .slate, .octagon),
        "LU": ("LËTZEBUERG", .teal, .hexagon), "CH": ("SCHWEIZ · SUISSE", .crimson, .rectangle), "AT": ("ÖSTERREICH", .crimson, .oval),
        "CZ": ("ČESKO", .navy, .ticket), "PL": ("POLSKA", .crimson, .rounded), "HU": ("MAGYARORSZÁG", .forest, .hexagon),
        "SK": ("SLOVENSKO", .navy, .oval), "SI": ("SLOVENIJA", .teal, .rounded), "HR": ("HRVATSKA", .navy, .circle),
        "RO": ("ROMÂNIA", .umber, .rectangle), "DK": ("DANMARK", .crimson, .rectangle), "SE": ("SVERIGE", .navy, .circle),
        "NO": ("NORGE", .crimson, .oval), "FI": ("SUOMI", .navy, .rounded), "IS": ("ÍSLAND", .teal, .hexagon),
        "EE": ("EESTI", .navy, .ticket), "LV": ("LATVIJA", .crimson, .rounded), "LT": ("LIETUVA", .forest, .oval),
        "MC": ("MONACO", .crimson, .circle), "VA": ("CITTÀ DEL VATICANO", .umber, .circle), "MT": ("MALTA", .crimson, .octagon),
        "US": ("UNITED STATES", .navy, .rounded), "CA": ("CANADA", .crimson, .rectangle), "MX": ("MÉXICO", .forest, .circle),
        "CU": ("CUBA", .navy, .oval), "BR": ("BRASIL", .forest, .rounded), "AR": ("ARGENTINA", .navy, .oval),
        "CL": ("CHILE", .crimson, .rectangle), "PE": ("PERÚ", .crimson, .hexagon), "CO": ("COLOMBIA", .umber, .rounded),
        "AU": ("AUSTRALIA", .navy, .rectangle), "NZ": ("AOTEAROA · NEW ZEALAND", .slate, .oval), "FJ": ("FIJI", .teal, .circle),
        "ZA": ("SOUTH AFRICA", .forest, .rounded), "KE": ("KENYA", .crimson, .hexagon), "TZ": ("TANZANIA", .forest, .oval),
        "MU": ("MAURICE", .teal, .rounded), "SC": ("SEYCHELLES", .teal, .octagon), "ET": ("ኢትዮጵያ", .forest, .circle),
    ]
}

// MARK: - China 34 Provinces (8x8 Geographic Tile Grid)

struct ChinaProvince: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let englishName: String
    let shortChar: String
    let row: Int
    let column: Int
    var regionCode: String? = nil

    static let columns = 8
    static let rows = 8

    static let all: [ChinaProvince] = [
        ChinaProvince(id: "heilongjiang", name: "黑龙江", englishName: "Heilongjiang", shortChar: "黑", row: 0, column: 7),
        ChinaProvince(id: "neimenggu", name: "内蒙古", englishName: "Inner Mongolia", shortChar: "蒙", row: 1, column: 4),
        ChinaProvince(id: "beijing", name: "北京", englishName: "Beijing", shortChar: "京", row: 1, column: 5),
        ChinaProvince(id: "liaoning", name: "辽宁", englishName: "Liaoning", shortChar: "辽", row: 1, column: 6),
        ChinaProvince(id: "jilin", name: "吉林", englishName: "Jilin", shortChar: "吉", row: 1, column: 7),
        ChinaProvince(id: "xinjiang", name: "新疆", englishName: "Xinjiang", shortChar: "新", row: 2, column: 0),
        ChinaProvince(id: "ningxia", name: "宁夏", englishName: "Ningxia", shortChar: "宁", row: 2, column: 3),
        ChinaProvince(id: "shanxi", name: "山西", englishName: "Shanxi", shortChar: "晋", row: 2, column: 4),
        ChinaProvince(id: "hebei", name: "河北", englishName: "Hebei", shortChar: "冀", row: 2, column: 5),
        ChinaProvince(id: "tianjin", name: "天津", englishName: "Tianjin", shortChar: "津", row: 2, column: 6),
        ChinaProvince(id: "qinghai", name: "青海", englishName: "Qinghai", shortChar: "青", row: 3, column: 1),
        ChinaProvince(id: "gansu", name: "甘肃", englishName: "Gansu", shortChar: "陇", row: 3, column: 2),
        ChinaProvince(id: "shaanxi", name: "陕西", englishName: "Shaanxi", shortChar: "秦", row: 3, column: 3),
        ChinaProvince(id: "henan", name: "河南", englishName: "Henan", shortChar: "豫", row: 3, column: 4),
        ChinaProvince(id: "shandong", name: "山东", englishName: "Shandong", shortChar: "鲁", row: 3, column: 5),
        ChinaProvince(id: "xizang", name: "西藏", englishName: "Tibet", shortChar: "藏", row: 4, column: 0),
        ChinaProvince(id: "sichuan", name: "四川", englishName: "Sichuan", shortChar: "蜀", row: 4, column: 2),
        ChinaProvince(id: "chongqing", name: "重庆", englishName: "Chongqing", shortChar: "渝", row: 4, column: 3),
        ChinaProvince(id: "hubei", name: "湖北", englishName: "Hubei", shortChar: "鄂", row: 4, column: 4),
        ChinaProvince(id: "anhui", name: "安徽", englishName: "Anhui", shortChar: "皖", row: 4, column: 5),
        ChinaProvince(id: "jiangsu", name: "江苏", englishName: "Jiangsu", shortChar: "苏", row: 4, column: 6),
        ChinaProvince(id: "shanghai", name: "上海", englishName: "Shanghai", shortChar: "沪", row: 4, column: 7),
        ChinaProvince(id: "guizhou", name: "贵州", englishName: "Guizhou", shortChar: "黔", row: 5, column: 2),
        ChinaProvince(id: "hunan", name: "湖南", englishName: "Hunan", shortChar: "湘", row: 5, column: 3),
        ChinaProvince(id: "jiangxi", name: "江西", englishName: "Jiangxi", shortChar: "赣", row: 5, column: 4),
        ChinaProvince(id: "zhejiang", name: "浙江", englishName: "Zhejiang", shortChar: "浙", row: 5, column: 5),
        ChinaProvince(id: "yunnan", name: "云南", englishName: "Yunnan", shortChar: "滇", row: 6, column: 1),
        ChinaProvince(id: "guangxi", name: "广西", englishName: "Guangxi", shortChar: "桂", row: 6, column: 2),
        ChinaProvince(id: "guangdong", name: "广东", englishName: "Guangdong", shortChar: "粤", row: 6, column: 3),
        ChinaProvince(id: "fujian", name: "福建", englishName: "Fujian", shortChar: "闽", row: 6, column: 4),
        ChinaProvince(id: "taiwan", name: "台湾", englishName: "Taiwan", shortChar: "台", row: 6, column: 6, regionCode: "TW"),
        ChinaProvince(id: "hainan", name: "海南", englishName: "Hainan", shortChar: "琼", row: 7, column: 2),
        ChinaProvince(id: "macau", name: "澳门", englishName: "Macau", shortChar: "澳", row: 7, column: 3, regionCode: "MO"),
        ChinaProvince(id: "hongkong", name: "香港", englishName: "Hong Kong", shortChar: "港", row: 7, column: 4, regionCode: "HK"),
    ]

    static func character(for id: String) -> String {
        all.first { $0.id == id }?.shortChar ?? "印"
    }

    static func isCarved(_ id: String) -> Bool {
        (all.firstIndex { $0.id == id } ?? 0) % 3 != 1
    }

    static func containing(countryCode: String?, region: String?, city: String?) -> ChinaProvince? {
        if let code = countryCode, let special = all.first(where: { $0.regionCode == code }) {
            return special
        }
        guard countryCode == "CN" else { return nil }
        // Fast path: direct Chinese name match without lowercasing or string splitting
        for raw in [region, city].compactMap({ $0 }) where !raw.isEmpty {
            if let match = all.first(where: { $0.regionCode == nil && raw.contains($0.name) }) {
                return match
            }
        }
        // Fallback: English / romanized names
        for text in [region, city].compactMap({ $0?.lowercased() }) where !text.isEmpty {
            if let match = all.first(where: { $0.regionCode == nil && $0.matches(text) }) {
                return match
            }
        }
        return nil
    }

    private func matches(_ text: String) -> Bool {
        if text.contains(name) { return true }
        let parts = text.split(separator: ",").map { part -> String in
            var s = part.trimmingCharacters(in: .whitespaces)
            for suffix in Self.englishSuffixes where s.hasSuffix(suffix) {
                s.removeLast(suffix.count)
                break
            }
            return s
        }
        return parts.contains { englishAliases.contains($0) }
    }

    private var englishAliases: [String] {
        switch id {
        case "xizang": return ["tibet", "xizang"]
        case "neimenggu": return ["inner mongolia", "nei mongol"]
        default: return [englishName.lowercased()]
        }
    }

    private static let englishSuffixes = [
        " zhuang autonomous region", " hui autonomous region", " uyghur autonomous region",
        " uygur autonomous region", " autonomous region", " province", " municipality",
        " sheng", " shi", " city"
    ]
}

// MARK: - Continents & Country Helpers

struct WorldContinent: Identifiable, Sendable {
    let id: String
    let regions: [String]

    var name: String {
        Locale(identifier: "zh_CN").localizedString(forRegionCode: id) ?? id
    }

    private static let uninhabited: Set<String> = [
        "AQ", "BV", "HM", "TF", "UM", "GS", "IO", "CP", "DG", "EA", "IC", "TA", "AC", "CQ", "XK"
    ]

    static let all: [WorldContinent] = {
        var byContinent: [String: [String]] = [:]
        for region in Locale.Region.isoRegions {
            let code = region.identifier
            guard code.count == 2, code.allSatisfy(\.isLetter), !uninhabited.contains(code),
                  let continent = region.continent?.identifier else { continue }
            byContinent[continent, default: []].append(code)
        }
        return byContinent.map { WorldContinent(id: $0.key, regions: $0.value.sorted()) }
    }()
}

enum CountryText {
    static func flag(for code: String) -> String {
        let base: UInt32 = 127397
        var s = ""
        for scalar in code.uppercased().unicodeScalars {
            if let flagScalar = UnicodeScalar(base + scalar.value) {
                s.unicodeScalars.append(flagScalar)
            }
        }
        return s.isEmpty ? "🏳️" : s
    }

    static func localizedName(code: String, fallback: String? = nil) -> String {
        if code == "CN" { return "中国" }
        if code == "HK" { return "中国香港" }
        if code == "MO" { return "中国澳门" }
        if code == "TW" { return "中国台湾" }
        if let name = Locale(identifier: "zh_CN").localizedString(forRegionCode: code), !name.isEmpty {
            return name
        }
        return fallback ?? code
    }
}

// MARK: - Country Borders (Natural Earth / DataV GeoAtlas)

enum CountryBorders {
    static let drawnWhole: Set<String> = ["CN"]
    private static var loaded: [String: [[CLLocationCoordinate2D]]]?
    private static let lock = NSLock()

    static func rings(for code: String) -> [[CLLocationCoordinate2D]] {
        ensureLoaded()
        return loaded?[code] ?? []
    }

    private static var boundingBoxes: [String: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)] = [:]

    private static func ensureLoaded() {
        lock.lock()
        defer { lock.unlock() }
        guard loaded == nil else { return }
        if let url = Bundle.main.url(forResource: "CountryBorders", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let raw = try? JSONDecoder().decode([String: [[[Double]]]].self, from: data) {
            var map: [String: [[CLLocationCoordinate2D]]] = [:]
            var boxes: [String: (Double, Double, Double, Double)] = [:]
            for (code, rings) in raw {
                let converted = rings.map { ring in
                    ring.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]).onMap }
                }
                map[code] = converted
                var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0
                for ring in converted {
                    for pt in ring {
                        if pt.latitude < minLat { minLat = pt.latitude }
                        if pt.latitude > maxLat { maxLat = pt.latitude }
                        if pt.longitude < minLon { minLon = pt.longitude }
                        if pt.longitude > maxLon { maxLon = pt.longitude }
                    }
                }
                boxes[code] = (minLat, maxLat, minLon, maxLon)
            }
            loaded = map
            boundingBoxes = boxes
        } else {
            loaded = [:]
        }
    }

    /// Offline point-in-polygon country lookup using bundled CountryBorders.json.
    static func countryCode(containing gps: CLLocationCoordinate2D) -> String? {
        ensureLoaded()
        lock.lock()
        let map = loaded ?? [:]
        let boxes = boundingBoxes
        lock.unlock()

        let pt = gps.onMap
        let priority = ["HK", "MO", "TW", "SG"]
        for code in priority {
            if let rings = map[code], rings.contains(where: { contains($0, pt) }) {
                return code
            }
        }
        for (code, box) in boxes {
            guard pt.latitude >= box.minLat && pt.latitude <= box.maxLat
                    && pt.longitude >= box.minLon && pt.longitude <= box.maxLon else { continue }
            if let rings = map[code], rings.contains(where: { contains($0, pt) }) {
                return code
            }
        }
        return nil
    }

    private static func contains(_ ring: [CLLocationCoordinate2D], _ point: CLLocationCoordinate2D) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in ring.indices {
            let a = ring[i], b = ring[j]
            if (a.latitude > point.latitude) != (b.latitude > point.latitude),
               point.longitude < (b.longitude - a.longitude) * (point.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    static func pieces(of code: String, visited: [CLLocationCoordinate2D]) -> [[CLLocationCoordinate2D]] {
        let all = rings(for: code).sorted { $0.count > $1.count }
        guard !drawnWhole.contains(code) else { return all }
        var kept = Set(all.indices.filter { all[$0].count >= 12 }.prefix(80))
        kept.formUnion(all.indices.prefix(3))
        for index in all.indices where !kept.contains(index) {
            let lats = all[index].map(\.latitude), lons = all[index].map(\.longitude)
            guard let south = lats.min(), let north = lats.max(), let west = lons.min(), let east = lons.max() else { continue }
            if visited.contains(where: { $0.latitude > south - 0.3 && $0.latitude < north + 0.3 && $0.longitude > west - 0.3 && $0.longitude < east + 0.3 }) {
                kept.insert(index)
            }
        }
        return kept.sorted().map { all[$0] }
    }
}

// MARK: - City Stamp Style (~150 Curated Cities)

struct CityStampStyle {
    let title: String
    let motto: String?
    let symbol: String
    let ink: StampInk
    let shape: StampShape

    struct Entry: Sendable {
        let country: String
        let names: [String]
        let latitude: Double
        let longitude: Double
        let title: String
        let motto: String?
        let symbol: String
        let ink: StampInk
        let shape: StampShape
        let zh: String
    }

    static func of(city: String, countryCode: String?, coordinate: CLLocationCoordinate2D) -> CityStampStyle {
        if let entry = match(city: city, countryCode: countryCode, coordinate: coordinate) {
            return CityStampStyle(title: entry.title, motto: entry.motto, symbol: entry.symbol, ink: entry.ink, shape: entry.shape)
        }
        let seed = StampSeed.of("\(countryCode ?? "")|\(city)")
        let shapes: [StampShape] = [.circle, .scalloped, .octagon, .rounded, .hexagon]
        let symbols = ["building.2.fill", "house.fill", "tree.fill", "signpost.right.fill", "map.fill", "leaf.fill"]
        return CityStampStyle(
            title: city,
            motto: nil,
            symbol: symbols[Int((seed >> 4) % UInt64(symbols.count))],
            ink: StampInk.everyday[Int(seed % UInt64(StampInk.everyday.count))],
            shape: shapes[Int((seed >> 12) % UInt64(shapes.count))]
        )
    }

    static func match(city: String, countryCode: String?, coordinate: CLLocationCoordinate2D) -> Entry? {
        let name = normalize(city)
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let candidates = catalog.filter { countryCode == nil || $0.country == countryCode }
        if let byName = candidates.first(where: { $0.names.contains { normalize($0) == name } }) { return byName }
        return candidates
            .map { ($0, CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: here)) }
            .filter { $0.1 < 12_000 }
            .min { $0.1 < $1.1 }?.0
    }

    static func displayName(_ stamp: PassportStamp) -> String {
        guard let city = stamp.city else { return "" }
        return match(city: city, countryCode: stamp.countryCode, coordinate: stamp.coordinate)?.zh ?? city
    }

    private static func normalize(_ name: String) -> String {
        var text = name.lowercased().folding(options: [.diacriticInsensitive], locale: nil)
        for suffix in ["市", " city", "-shi", " shi"] where text.hasSuffix(suffix) { text.removeLast(suffix.count) }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func e(_ country: String, _ names: [String], _ lat: Double, _ lon: Double, _ title: String, _ motto: String?,
                          _ symbol: String, _ ink: StampInk, _ shape: StampShape, zh: String) -> Entry {
        Entry(country: country, names: names, latitude: lat, longitude: lon, title: title, motto: motto, symbol: symbol, ink: ink, shape: shape, zh: zh)
    }

    static let catalog: [Entry] = [
        // China
        e("CN", ["北京", "Beijing"], 39.904, 116.407, "北京", "京华", "building.columns.fill", .crimson, .circle, zh: "北京"),
        e("CN", ["上海", "Shanghai"], 31.230, 121.474, "上海", "申城", "building.2.fill", .navy, .scalloped, zh: "上海"),
        e("CN", ["天津", "Tianjin"], 39.125, 117.190, "天津", "津门", "ferry.fill", .teal, .octagon, zh: "天津"),
        e("CN", ["重庆", "Chongqing"], 29.563, 106.551, "重庆", "山城", "cablecar.fill", .umber, .hexagon, zh: "重庆"),
        e("CN", ["广州", "Guangzhou"], 23.129, 113.264, "广州", "羊城", "building.2.fill", .forest, .circle, zh: "广州"),
        e("CN", ["深圳", "Shenzhen"], 22.543, 114.058, "深圳", "鹏城", "bird.fill", .teal, .rounded, zh: "深圳"),
        e("CN", ["杭州", "Hangzhou"], 30.274, 120.155, "杭州", "西子湖畔", "water.waves", .teal, .circle, zh: "杭州"),
        e("CN", ["南京", "Nanjing"], 32.060, 118.797, "南京", "金陵", "building.columns.fill", .plum, .octagon, zh: "南京"),
        e("CN", ["苏州", "Suzhou"], 31.299, 120.585, "苏州", "姑苏", "leaf.fill", .forest, .scalloped, zh: "苏州"),
        e("CN", ["成都", "Chengdu"], 30.573, 104.066, "成都", "天府之国", "pawprint.fill", .forest, .circle, zh: "成都"),
        e("CN", ["西安", "Xi'an", "Xian"], 34.342, 108.940, "西安", "长安", "building.columns.fill", .umber, .rectangle, zh: "西安"),
        e("CN", ["武汉", "Wuhan"], 30.593, 114.305, "武汉", "江城", "water.waves", .navy, .rounded, zh: "武汉"),
        e("CN", ["长沙", "Changsha"], 28.228, 112.939, "长沙", "星城", "sparkles", .crimson, .hexagon, zh: "长沙"),
        e("CN", ["厦门", "Xiamen"], 24.480, 118.089, "厦门", "鹭岛", "bird.fill", .teal, .oval, zh: "厦门"),
        e("CN", ["青岛", "Qingdao"], 36.067, 120.383, "青岛", "琴岛", "sailboat.fill", .navy, .circle, zh: "青岛"),
        e("CN", ["大连", "Dalian"], 38.914, 121.615, "大连", "滨城", "sailboat.fill", .teal, .rounded, zh: "大连"),
        e("CN", ["哈尔滨", "Harbin"], 45.803, 126.535, "哈尔滨", "冰城", "snowflake", .navy, .octagon, zh: "哈尔滨"),
        e("CN", ["沈阳", "Shenyang"], 41.806, 123.432, "沈阳", "盛京", "crown.fill", .umber, .circle, zh: "沈阳"),
        e("CN", ["长春", "Changchun"], 43.817, 125.324, "长春", "北国春城", "leaf.fill", .forest, .rounded, zh: "长春"),
        e("CN", ["昆明", "Kunming"], 25.038, 102.718, "昆明", "春城", "camera.macro", .crimson, .scalloped, zh: "昆明"),
        e("CN", ["丽江", "Lijiang"], 26.872, 100.227, "丽江", "古城", "mountain.2.fill", .umber, .hexagon, zh: "丽江"),
        e("CN", ["大理", "Dali"], 25.606, 100.268, "大理", "风花雪月", "wind", .navy, .circle, zh: "大理"),
        e("CN", ["西双版纳", "景洪", "Jinghong", "Xishuangbanna"], 22.008, 100.797, "西双版纳", "彩云之南", "tree.fill", .forest, .oval, zh: "西双版纳"),
        e("CN", ["拉萨", "Lhasa"], 29.652, 91.172, "拉萨", "日光城", "sun.max.fill", .crimson, .octagon, zh: "拉萨"),
        e("CN", ["桂林", "Guilin"], 25.274, 110.290, "桂林", "山水甲天下", "mountain.2.fill", .forest, .rounded, zh: "桂林"),
        e("CN", ["南宁", "Nanning"], 22.817, 108.366, "南宁", "绿城", "tree.fill", .forest, .circle, zh: "南宁"),
        e("CN", ["三亚", "Sanya"], 18.253, 109.512, "三亚", "鹿城", "beach.umbrella.fill", .teal, .scalloped, zh: "三亚"),
        e("CN", ["海口", "Haikou"], 20.044, 110.199, "海口", "椰城", "sun.max.fill", .teal, .rounded, zh: "海口"),
        e("CN", ["福州", "Fuzhou"], 26.074, 119.297, "福州", "榕城", "tree.fill", .forest, .hexagon, zh: "福州"),
        e("CN", ["泉州", "Quanzhou"], 24.874, 118.676, "泉州", "刺桐城", "sailboat.fill", .crimson, .circle, zh: "泉州"),
        e("CN", ["济南", "Jinan"], 36.651, 117.120, "济南", "泉城", "drop.fill", .teal, .circle, zh: "济南"),
        e("CN", ["郑州", "Zhengzhou"], 34.747, 113.625, "郑州", "商都", "tram.fill", .umber, .rectangle, zh: "郑州"),
        e("CN", ["洛阳", "Luoyang"], 34.620, 112.454, "洛阳", "神都", "camera.macro", .plum, .octagon, zh: "洛阳"),
        e("CN", ["开封", "Kaifeng"], 34.797, 114.308, "开封", "汴京", "building.columns.fill", .umber, .hexagon, zh: "开封"),
        e("CN", ["合肥", "Hefei"], 31.821, 117.227, "合肥", "庐州", "book.fill", .navy, .rounded, zh: "合肥"),
        e("CN", ["黄山", "Huangshan"], 29.715, 118.338, "黄山", "徽州", "mountain.2.fill", .slate, .octagon, zh: "黄山"),
        e("CN", ["南昌", "Nanchang"], 28.682, 115.858, "南昌", "洪城", "flag.fill", .crimson, .circle, zh: "南昌"),
        e("CN", ["景德镇", "Jingdezhen"], 29.269, 117.178, "景德镇", "瓷都", "cup.and.saucer.fill", .navy, .scalloped, zh: "景德镇"),
        e("CN", ["贵阳", "Guiyang"], 26.647, 106.630, "贵阳", "林城", "tree.fill", .forest, .rounded, zh: "贵阳"),
        e("CN", ["石家庄", "Shijiazhuang"], 38.042, 114.515, "石家庄", "石门", "tram.fill", .slate, .rectangle, zh: "石家庄"),
        e("CN", ["太原", "Taiyuan"], 37.871, 112.549, "太原", "龙城", "flame.fill", .umber, .circle, zh: "太原"),
        e("CN", ["大同", "Datong"], 40.077, 113.300, "大同", "云冈", "building.columns.fill", .slate, .hexagon, zh: "大同"),
        e("CN", ["呼和浩特", "Hohhot"], 40.842, 111.749, "呼和浩特", "青城", "wind", .teal, .oval, zh: "呼和浩特"),
        e("CN", ["兰州", "Lanzhou"], 36.061, 103.834, "兰州", "金城", "water.waves", .umber, .rounded, zh: "兰州"),
        e("CN", ["敦煌", "Dunhuang"], 40.142, 94.662, "敦煌", "沙州", "sun.dust.fill", .umber, .octagon, zh: "敦煌"),
        e("CN", ["西宁", "Xining"], 36.617, 101.778, "西宁", "夏都", "mountain.2.fill", .navy, .circle, zh: "西宁"),
        e("CN", ["银川", "Yinchuan"], 38.487, 106.231, "银川", "凤城", "bird.fill", .umber, .hexagon, zh: "银川"),
        e("CN", ["乌鲁木齐", "Urumqi", "Ürümqi"], 43.825, 87.617, "乌鲁木齐", "亚心之都", "mountain.2.fill", .teal, .rounded, zh: "乌鲁木齐"),
        e("CN", ["宁波", "Ningbo"], 29.868, 121.544, "宁波", "甬城", "ferry.fill", .navy, .octagon, zh: "宁波"),
        e("CN", ["绍兴", "Shaoxing"], 29.997, 120.582, "绍兴", "水乡", "sailboat.fill", .slate, .scalloped, zh: "绍兴"),
        e("CN", ["嘉兴", "Jiaxing"], 30.746, 120.756, "嘉兴", "禾城", "sailboat.fill", .crimson, .circle, zh: "嘉兴"),
        e("CN", ["扬州", "Yangzhou"], 32.394, 119.413, "扬州", "广陵", "moon.stars.fill", .plum, .rounded, zh: "扬州"),
        e("CN", ["无锡", "Wuxi"], 31.491, 120.312, "无锡", "太湖明珠", "water.waves", .teal, .hexagon, zh: "无锡"),
        e("CN", ["珠海", "Zhuhai"], 22.271, 113.577, "珠海", "百岛之市", "sailboat.fill", .teal, .circle, zh: "珠海"),
        e("CN", ["张家界", "Zhangjiajie"], 29.117, 110.479, "张家界", "武陵源", "mountain.2.fill", .forest, .octagon, zh: "张家界"),
        e("CN", ["秦皇岛", "Qinhuangdao"], 39.935, 119.600, "秦皇岛", "港城", "water.waves", .navy, .rounded, zh: "秦皇岛"),
        e("CN", ["烟台", "Yantai"], 37.464, 121.448, "烟台", "仙境", "cloud.fill", .teal, .circle, zh: "烟台"),
        e("CN", ["威海", "Weihai"], 37.513, 122.120, "威海", "海滨", "sailboat.fill", .navy, .scalloped, zh: "威海"),
        e("HK", ["香港", "Hong Kong"], 22.320, 114.170, "香港", "東方之珠", "sailboat.fill", .crimson, .circle, zh: "香港"),
        e("MO", ["澳门", "澳門", "Macau", "Macao"], 22.199, 113.544, "澳門", "濠江", "dice.fill", .forest, .octagon, zh: "澳门"),
        e("TW", ["台北", "臺北", "Taipei"], 25.033, 121.565, "臺北", nil, "building.2.fill", .navy, .rounded, zh: "台北"),
        // Asia
        e("JP", ["東京", "东京", "Tokyo"], 35.681, 139.767, "東京", "TOKYO", "tram.fill", .crimson, .circle, zh: "东京"),
        e("JP", ["京都", "Kyoto"], 35.012, 135.768, "京都", "古都", "building.columns.fill", .umber, .octagon, zh: "京都"),
        e("JP", ["大阪", "Osaka"], 34.694, 135.502, "大阪", "天下の台所", "fork.knife", .navy, .scalloped, zh: "大阪"),
        e("JP", ["奈良", "Nara"], 34.685, 135.805, "奈良", "平城京", "pawprint.fill", .forest, .circle, zh: "奈良"),
        e("JP", ["札幌", "Sapporo"], 43.062, 141.354, "札幌", "SAPPORO", "snowflake", .navy, .hexagon, zh: "札幌"),
        e("JP", ["横浜", "横滨", "Yokohama"], 35.444, 139.638, "横浜", "YOKOHAMA", "ferry.fill", .teal, .rounded, zh: "横滨"),
        e("JP", ["福岡", "福冈", "Fukuoka"], 33.590, 130.402, "福岡", "博多", "fork.knife", .crimson, .rounded, zh: "福冈"),
        e("JP", ["那覇", "那霸", "Naha"], 26.212, 127.681, "那覇", "琉球", "sun.max.fill", .teal, .circle, zh: "那霸"),
        e("JP", ["箱根", "Hakone"], 35.232, 139.107, "箱根", "温泉", "mountain.2.fill", .plum, .octagon, zh: "箱根"),
        e("KR", ["서울", "首尔", "Seoul"], 37.566, 126.978, "서울", "SEOUL", "building.2.fill", .navy, .rounded, zh: "首尔"),
        e("KR", ["부산", "釜山", "Busan"], 35.180, 129.075, "부산", "BUSAN", "water.waves", .teal, .circle, zh: "釜山"),
        e("KR", ["제주", "济州", "Jeju"], 33.499, 126.531, "제주", "탐라", "leaf.fill", .forest, .scalloped, zh: "济州"),
        e("SG", ["Singapore", "新加坡"], 1.290, 103.852, "SINGAPORE", "LION CITY", "building.2.fill", .crimson, .scalloped, zh: "新加坡"),
        e("MY", ["Kuala Lumpur", "吉隆坡"], 3.139, 101.687, "KUALA LUMPUR", nil, "building.2.fill", .navy, .rounded, zh: "吉隆坡"),
        e("MY", ["George Town", "Penang", "槟城", "乔治市"], 5.414, 100.329, "PENANG", "PEARL OF THE ORIENT", "fork.knife", .teal, .circle, zh: "槟城"),
        e("TH", ["Bangkok", "曼谷", "กรุงเทพมหานคร"], 13.756, 100.502, "กรุงเทพฯ", "BANGKOK", "building.columns.fill", .plum, .octagon, zh: "曼谷"),
        e("TH", ["Chiang Mai", "清迈"], 18.788, 98.985, "เชียงใหม่", "CHIANG MAI", "leaf.fill", .forest, .circle, zh: "清迈"),
        e("TH", ["Phuket", "普吉"], 7.880, 98.392, "ภูเก็ต", "PHUKET", "beach.umbrella.fill", .teal, .scalloped, zh: "普吉岛"),
        e("VN", ["Hanoi", "Hà Nội", "河内"], 21.028, 105.854, "HÀ NỘI", "THĂNG LONG", "building.columns.fill", .crimson, .rounded, zh: "河内"),
        e("VN", ["Ho Chi Minh City", "Thành phố Hồ Chí Minh", "胡志明市"], 10.776, 106.701, "SÀI GÒN", nil, "bicycle", .navy, .circle, zh: "胡志明市"),
        e("VN", ["Da Nang", "Đà Nẵng", "岘港"], 16.054, 108.202, "ĐÀ NẴNG", nil, "beach.umbrella.fill", .teal, .hexagon, zh: "岘港"),
        e("ID", ["Denpasar", "Bali", "巴厘岛", "Kuta", "Ubud"], -8.650, 115.216, "BALI", "PULAU DEWATA", "sun.max.fill", .forest, .scalloped, zh: "巴厘岛"),
        e("ID", ["Jakarta", "雅加达"], -6.208, 106.846, "JAKARTA", nil, "building.2.fill", .crimson, .rounded, zh: "雅加达"),
        e("PH", ["Manila", "马尼拉"], 14.599, 120.984, "MAYNILA", nil, "sailboat.fill", .navy, .circle, zh: "马尼拉"),
        e("KH", ["Siem Reap", "暹粒"], 13.362, 103.860, "សៀមរាប", "ANGKOR", "building.columns.fill", .umber, .octagon, zh: "暹粒"),
        e("IN", ["New Delhi", "Delhi", "新德里"], 28.614, 77.209, "नई दिल्ली", "NEW DELHI", "building.columns.fill", .umber, .circle, zh: "新德里"),
        e("AE", ["Dubai", "迪拜"], 25.204, 55.271, "دبي", "DUBAI", "building.2.fill", .umber, .hexagon, zh: "迪拜"),
        e("TR", ["Istanbul", "İstanbul", "伊斯坦布尔"], 41.008, 28.978, "İSTANBUL", nil, "moon.stars.fill", .crimson, .circle, zh: "伊斯坦布尔"),
        e("EG", ["Cairo", "开罗"], 30.044, 31.236, "القاهرة", "CAIRO", "triangle.fill", .umber, .octagon, zh: "开罗"),
        // Europe
        e("GB", ["London", "伦敦"], 51.507, -0.128, "LONDON", nil, "clock.fill", .crimson, .circle, zh: "伦敦"),
        e("GB", ["Edinburgh", "爱丁堡"], 55.953, -3.188, "EDINBURGH", nil, "building.columns.fill", .navy, .octagon, zh: "爱丁堡"),
        e("FR", ["Paris", "巴黎"], 48.857, 2.352, "PARIS", "LA VILLE LUMIÈRE", "sparkles", .navy, .scalloped, zh: "巴黎"),
        e("FR", ["Nice", "尼斯"], 43.710, 7.262, "NICE", "CÔTE D'AZUR", "sun.max.fill", .teal, .circle, zh: "尼斯"),
        e("IT", ["Roma", "Rome", "罗马"], 41.903, 12.496, "ROMA", "CAPUT MUNDI", "building.columns.fill", .umber, .circle, zh: "罗马"),
        e("IT", ["Venezia", "Venice", "威尼斯"], 45.441, 12.316, "VENEZIA", "LA SERENISSIMA", "sailboat.fill", .crimson, .octagon, zh: "威尼斯"),
        e("IT", ["Firenze", "Florence", "佛罗伦萨"], 43.770, 11.256, "FIRENZE", nil, "paintpalette.fill", .forest, .scalloped, zh: "佛罗伦萨"),
        e("IT", ["Milano", "Milan", "米兰"], 45.464, 9.190, "MILANO", nil, "tshirt.fill", .slate, .rounded, zh: "米兰"),
        e("ES", ["Barcelona", "巴塞罗那"], 41.385, 2.173, "BARCELONA", nil, "sun.max.fill", .crimson, .hexagon, zh: "巴塞罗那"),
        e("ES", ["Madrid", "马德里"], 40.417, -3.704, "MADRID", nil, "crown.fill", .navy, .circle, zh: "马德里"),
        e("PT", ["Lisboa", "Lisbon", "里斯本"], 38.722, -9.139, "LISBOA", nil, "tram.fill", .teal, .rounded, zh: "里斯本"),
        e("NL", ["Amsterdam", "阿姆斯特丹"], 52.368, 4.904, "AMSTERDAM", nil, "bicycle", .umber, .circle, zh: "阿姆斯特丹"),
        e("DE", ["Berlin", "柏林"], 52.520, 13.405, "BERLIN", nil, "building.columns.fill", .slate, .octagon, zh: "柏林"),
        e("DE", ["München", "Munich", "慕尼黑"], 48.135, 11.582, "MÜNCHEN", nil, "mug.fill", .navy, .rounded, zh: "慕尼黑"),
        e("AT", ["Wien", "Vienna", "维也纳"], 48.208, 16.374, "WIEN", nil, "music.note", .crimson, .scalloped, zh: "维也纳"),
        e("AT", ["Hallstatt", "哈尔施塔特"], 47.562, 13.649, "HALLSTATT", nil, "house.fill", .teal, .circle, zh: "哈尔施塔特"),
        e("CZ", ["Praha", "Prague", "布拉格"], 50.076, 14.438, "PRAHA", nil, "building.columns.fill", .plum, .octagon, zh: "布拉格"),
        e("HU", ["Budapest", "布达佩斯"], 47.498, 19.040, "BUDAPEST", nil, "water.waves", .forest, .rounded, zh: "布达佩斯"),
        e("CH", ["Zürich", "Zurich", "苏黎世"], 47.377, 8.542, "ZÜRICH", nil, "water.waves", .navy, .circle, zh: "苏黎世"),
        e("CH", ["Luzern", "Lucerne", "琉森", "卢塞恩"], 47.050, 8.309, "LUZERN", nil, "sailboat.fill", .teal, .scalloped, zh: "琉森"),
        e("CH", ["Interlaken", "因特拉肯"], 46.686, 7.863, "INTERLAKEN", nil, "mountain.2.fill", .forest, .octagon, zh: "因特拉肯"),
        e("CH", ["Zermatt", "采尔马特"], 46.020, 7.749, "ZERMATT", "MATTERHORN", "mountain.2.fill", .crimson, .rounded, zh: "采尔马特"),
        e("CH", ["Genève", "Geneva", "日内瓦"], 46.204, 6.143, "GENÈVE", nil, "drop.fill", .navy, .hexagon, zh: "日内瓦"),
        e("DK", ["København", "Copenhagen", "哥本哈根"], 55.676, 12.568, "KØBENHAVN", nil, "sailboat.fill", .crimson, .circle, zh: "哥本哈根"),
        e("SE", ["Stockholm", "斯德哥尔摩"], 59.329, 18.069, "STOCKHOLM", nil, "crown.fill", .navy, .rounded, zh: "斯德哥尔摩"),
        e("NO", ["Oslo", "奥斯陆"], 59.914, 10.752, "OSLO", nil, "ferry.fill", .navy, .octagon, zh: "奥斯陆"),
        e("FI", ["Helsinki", "赫尔辛基"], 60.170, 24.938, "HELSINKI", nil, "snowflake", .teal, .circle, zh: "赫尔辛基"),
        e("IS", ["Reykjavík", "Reykjavik", "雷克雅未克"], 64.147, -21.942, "REYKJAVÍK", nil, "sparkles", .teal, .hexagon, zh: "雷克雅未克"),
        e("GR", ["Athens", "Αθήνα", "雅典"], 37.984, 23.728, "ΑΘΗΝΑ", "ATHENS", "building.columns.fill", .navy, .circle, zh: "雅典"),
        e("GR", ["Santorini", "Thira", "Fira", "圣托里尼"], 36.416, 25.432, "ΣΑΝΤΟΡΙΝΗ", "SANTORINI", "sun.max.fill", .navy, .scalloped, zh: "圣托里尼"),
        e("RU", ["Moscow", "Москва", "莫斯科"], 55.756, 37.617, "МОСКВА", "MOSCOW", "star.fill", .crimson, .octagon, zh: "莫斯科"),
        // Americas, Oceania, Africa
        e("US", ["New York", "纽约"], 40.713, -74.006, "NEW YORK", "THE BIG APPLE", "building.2.fill", .navy, .circle, zh: "纽约"),
        e("US", ["Los Angeles", "洛杉矶"], 34.052, -118.244, "LOS ANGELES", "CITY OF ANGELS", "sun.max.fill", .umber, .scalloped, zh: "洛杉矶"),
        e("US", ["San Francisco", "旧金山"], 37.775, -122.419, "SAN FRANCISCO", "GOLDEN GATE", "cablecar.fill", .crimson, .rounded, zh: "旧金山"),
        e("US", ["Las Vegas", "拉斯维加斯"], 36.170, -115.140, "LAS VEGAS", nil, "dice.fill", .plum, .octagon, zh: "拉斯维加斯"),
        e("US", ["Seattle", "西雅图"], 47.606, -122.332, "SEATTLE", nil, "cup.and.saucer.fill", .forest, .circle, zh: "西雅图"),
        e("US", ["Chicago", "芝加哥"], 41.878, -87.630, "CHICAGO", "WINDY CITY", "wind", .navy, .hexagon, zh: "芝加哥"),
        e("US", ["Honolulu", "火奴鲁鲁", "檀香山"], 21.307, -157.858, "HONOLULU", "ALOHA", "beach.umbrella.fill", .teal, .scalloped, zh: "檀香山"),
        e("US", ["Washington", "华盛顿"], 38.907, -77.037, "WASHINGTON", "D.C.", "building.columns.fill", .slate, .circle, zh: "华盛顿"),
        e("CA", ["Vancouver", "温哥华"], 49.283, -123.121, "VANCOUVER", nil, "leaf.fill", .crimson, .rounded, zh: "温哥华"),
        e("CA", ["Toronto", "多伦多"], 43.653, -79.383, "TORONTO", nil, "building.2.fill", .navy, .octagon, zh: "多伦多"),
        e("MX", ["Ciudad de México", "Mexico City", "墨西哥城"], 19.433, -99.133, "CDMX", nil, "sun.max.fill", .forest, .circle, zh: "墨西哥城"),
        e("PE", ["Cusco", "Cuzco", "库斯科"], -13.532, -71.968, "CUSCO", "MACHU PICCHU", "mountain.2.fill", .umber, .octagon, zh: "库斯科"),
        e("BR", ["Rio de Janeiro", "里约热内卢"], -22.907, -43.173, "RIO DE JANEIRO", nil, "beach.umbrella.fill", .forest, .scalloped, zh: "里约热内卢"),
        e("AR", ["Buenos Aires", "布宜诺斯艾利斯"], -34.604, -58.382, "BUENOS AIRES", nil, "music.note", .navy, .circle, zh: "布宜诺斯艾利斯"),
        e("AU", ["Sydney", "悉尼"], -33.869, 151.209, "SYDNEY", nil, "sailboat.fill", .navy, .scalloped, zh: "悉尼"),
        e("AU", ["Melbourne", "墨尔本"], -37.814, 144.963, "MELBOURNE", nil, "cup.and.saucer.fill", .slate, .rounded, zh: "墨尔本"),
        e("NZ", ["Auckland", "奥克兰"], -36.849, 174.763, "AUCKLAND", nil, "sailboat.fill", .teal, .circle, zh: "奥克兰"),
        e("NZ", ["Queenstown", "皇后镇"], -45.031, 168.663, "QUEENSTOWN", nil, "mountain.2.fill", .forest, .octagon, zh: "皇后镇"),
        e("ZA", ["Cape Town", "开普敦"], -33.925, 18.424, "CAPE TOWN", nil, "mountain.2.fill", .forest, .rounded, zh: "开普敦"),
        e("MA", ["Marrakech", "Marrakesh", "马拉喀什"], 31.630, -7.981, "مراكش", "MARRAKECH", "sun.dust.fill", .crimson, .octagon, zh: "马拉喀什"),
    ]
}

// MARK: - 14 Stamp Sets

struct StampSet: Identifiable, Sendable {
    enum Layout: Sendable {
        case seal(carved: Bool)
        case map(StampShape)
        case label(StampShape)
    }

    let id: String
    let title: String
    let localizedName: String
    let motto: String
    let symbol: String
    let ink: StampInk
    let members: [String]
    let layout: Layout

    struct Progress: Identifiable, Sendable {
        let group: StampSet
        let visited: [String: PassportStamp]
        var id: String { group.id }
        var isComplete: Bool { visited.count == group.members.count }
        var stamp: PassportStamp? {
            guard isComplete, let last = visited.values.max(by: { $0.date < $1.date }) else { return nil }
            return PassportStamp(
                id: "set.\(group.id)", kind: .set, date: last.date, countryCode: last.countryCode,
                city: last.city, latitude: last.latitude, longitude: last.longitude, code: group.id
            )
        }
    }

    static func named(_ id: String?) -> StampSet? { all.first { $0.id == id } }

    static func memberName(_ title: String) -> String {
        CityStampStyle.catalog.first { $0.title == title }?.zh ?? title
    }

    static func progress(cities: [PassportStamp]) -> [Progress] {
        var byTitle: [String: PassportStamp] = [:]
        for stamp in cities {
            guard let city = stamp.city,
                  let entry = CityStampStyle.match(city: city, countryCode: stamp.countryCode, coordinate: stamp.coordinate),
                  byTitle[entry.title] == nil else { continue }
            byTitle[entry.title] = stamp
        }
        return all.map { group in
            Progress(group: group, visited: byTitle.filter { group.members.contains($0.key) })
        }
    }

    static let all: [StampSet] = [
        StampSet(id: "jiangnan", title: "江南", localizedName: "江南", motto: "烟雨江南", symbol: "sailboat.fill", ink: .teal,
                 members: ["苏州", "杭州", "无锡", "扬州", "绍兴", "嘉兴"], layout: .seal(carved: true)),
        StampSet(id: "capitals", title: "六大古都", localizedName: "六大古都", motto: "千年帝都", symbol: "building.columns.fill", ink: .crimson,
                 members: ["北京", "西安", "南京", "洛阳", "开封", "杭州"], layout: .seal(carved: false)),
        StampSet(id: "silkroad", title: "丝绸之路", localizedName: "丝绸之路", motto: "驼铃声声", symbol: "sun.dust.fill", ink: .umber,
                 members: ["西安", "兰州", "敦煌", "乌鲁木齐"], layout: .map(.ticket)),
        StampSet(id: "bay", title: "粤港澳", localizedName: "粤港澳", motto: "大湾区", symbol: "ferry.fill", ink: .navy,
                 members: ["广州", "深圳", "香港", "澳門", "珠海"], layout: .map(.hexagon)),
        StampSet(id: "yunnan", title: "彩云之南", localizedName: "彩云之南", motto: "云南", symbol: "cloud.sun.fill", ink: .forest,
                 members: ["昆明", "大理", "丽江", "西双版纳"], layout: .seal(carved: true)),
        StampSet(id: "northeast", title: "白山黑水", localizedName: "白山黑水", motto: "东北", symbol: "snowflake", ink: .slate,
                 members: ["哈尔滨", "长春", "沈阳", "大连"], layout: .seal(carved: false)),
        StampSet(id: "coast", title: "北方海滨", localizedName: "北方海滨", motto: "看海去", symbol: "water.waves", ink: .navy,
                 members: ["秦皇岛", "大连", "烟台", "威海", "青岛"], layout: .map(.oval)),
        StampSet(id: "kansai", title: "関西", localizedName: "关西", motto: "KANSAI", symbol: "building.columns.fill", ink: .crimson,
                 members: ["京都", "大阪", "奈良"], layout: .seal(carved: true)),
        StampSet(id: "kanto", title: "関東", localizedName: "关东", motto: "KANTO", symbol: "tram.fill", ink: .plum,
                 members: ["東京", "横浜", "箱根"], layout: .map(.circle)),
        StampSet(id: "swiss", title: "SWISS ALPS", localizedName: "瑞士阿尔卑斯", motto: "SCHWEIZ · SUISSE", symbol: "mountain.2.fill", ink: .crimson,
                 members: ["ZÜRICH", "LUZERN", "INTERLAKEN", "ZERMATT", "GENÈVE"], layout: .label(.hexagon)),
        StampSet(id: "italy", title: "ITALIA", localizedName: "意大利", motto: "LA DOLCE VITA", symbol: "fork.knife", ink: .forest,
                 members: ["ROMA", "FIRENZE", "VENEZIA", "MILANO"], layout: .label(.oval)),
        StampSet(id: "uswest", title: "AMERICAN WEST", localizedName: "美国西部", motto: "ROAD TRIP", symbol: "car.fill", ink: .umber,
                 members: ["SEATTLE", "SAN FRANCISCO", "LOS ANGELES", "LAS VEGAS"], layout: .map(.rounded)),
        StampSet(id: "nordic", title: "NORDEN", localizedName: "北欧", motto: "NORDIC CAPITALS", symbol: "snowflake", ink: .navy,
                 members: ["KØBENHAVN", "OSLO", "STOCKHOLM", "HELSINKI"], layout: .map(.scalloped)),
        StampSet(id: "southeastasia", title: "新马泰", localizedName: "新马泰", motto: "SOUTHEAST ASIA", symbol: "sun.max.fill", ink: .forest,
                 members: ["SINGAPORE", "KUALA LUMPUR", "กรุงเทพฯ"], layout: .label(.ticket)),
    ]
}

// MARK: - Special Stamp Style

struct SpecialStampStyle {
    let shape: StampShape
    let ink: StampInk
    let symbol: String
    let label: String

    static func of(_ code: String) -> SpecialStampStyle {
        switch code {
        case "equator": return SpecialStampStyle(shape: .circle, ink: .teal, symbol: "globe.americas.fill", label: "EQUATOR · 赤道")
        case "dateline": return SpecialStampStyle(shape: .ticket, ink: .plum, symbol: "arrow.left.arrow.right", label: "INTERNATIONAL DATE LINE")
        case "arctic": return SpecialStampStyle(shape: .hexagon, ink: .navy, symbol: "snowflake", label: "ARCTIC CIRCLE · 北极圈")
        case "antarctic": return SpecialStampStyle(shape: .hexagon, ink: .navy, symbol: "snowflake", label: "ANTARCTIC CIRCLE · 南极圈")
        case "record.north": return SpecialStampStyle(shape: .octagon, ink: .navy, symbol: "arrow.up", label: "最北 · NORTHERNMOST")
        case "record.south": return SpecialStampStyle(shape: .octagon, ink: .crimson, symbol: "arrow.down", label: "最南 · SOUTHERNMOST")
        case "record.east": return SpecialStampStyle(shape: .octagon, ink: .forest, symbol: "arrow.right", label: "最东 · EASTERNMOST")
        case "record.west": return SpecialStampStyle(shape: .octagon, ink: .umber, symbol: "arrow.left", label: "最西 · WESTERNMOST")
        case "record.high": return SpecialStampStyle(shape: .octagon, ink: .slate, symbol: "mountain.2.fill", label: "最高 · HIGHEST")
        default: return SpecialStampStyle(shape: .scalloped, ink: .crimson, symbol: "sparkles", label: "跨年 · HAPPY NEW YEAR")
        }
    }
}

// MARK: - Passport Summary Models

struct PassportProvinceVisit: Sendable {
    let province: ChinaProvince
    let days: Int
    let firstVisit: Date
    let topCities: [String]
}

struct PassportCountrySummary: Identifiable, Hashable, Sendable {
    var id: String { code }
    let code: String
    let name: String
    let flag: String
    let days: Int
    let firstVisit: Date
    let topCities: [String]
}

struct PassportSummary: Sendable {
    let homeCountryCode: String?
    let homeCountryName: String?
    let since: Date?
    let passportStamps: [PassportStamp]          // Interleaved entry + exit stamps (oldest first)
    let visitedCountries: Set<String>
    let countrySummaries: [PassportCountrySummary]
    let continentsVisited: Int
    let provinceVisits: [String: PassportProvinceVisit]
    let cityStamps: [PassportStamp]              // Oldest first
    let cityRoutes: [String: [CGPoint]]          // stamp.id -> normalized 0...1 first-day route
    let specials: [PassportStamp]                // equator, dateline, arctic, newyear, record.north/south/east/west/high
    let stampSets: [StampSet.Progress]
}

// MARK: - Engine

enum PassportEngine {
    static let arcticCircle = 66.5634

    static func build(stays: [Stay], chunks: [TrackChunk]) -> PassportSummary {
        let sorted = stays.filter { $0.countryCode != nil }.sorted { $0.arrival < $1.arrival }
        let since = sorted.first?.arrival
        let cal = Calendar.current

        // 1. Country runs & home country
        struct Run {
            let code: String
            var first: Stay
            var last: Stay
            var start: Date
            var end: Date
            var time: TimeInterval
            var count: Int
            var fromPhotos: Bool
        }

        var rawRuns: [(run: Run, stays: [Stay])] = []
        for stay in sorted {
            guard let code = stay.countryCode else { continue }
            let end = max(stay.departure ?? stay.arrival, stay.arrival)
            if rawRuns.last?.run.code == code {
                rawRuns[rawRuns.count - 1].run.last = stay
                rawRuns[rawRuns.count - 1].run.end = max(rawRuns[rawRuns.count - 1].run.end, end)
                rawRuns[rawRuns.count - 1].run.time += end.timeIntervalSince(stay.arrival)
                rawRuns[rawRuns.count - 1].run.count += 1
                rawRuns[rawRuns.count - 1].run.fromPhotos = rawRuns[rawRuns.count - 1].run.fromPhotos || stay.isFromPhotos
                rawRuns[rawRuns.count - 1].stays.append(stay)
            } else {
                rawRuns.append((Run(code: code, first: stay, last: stay, start: stay.arrival, end: end,
                                    time: end.timeIntervalSince(stay.arrival), count: 1, fromPhotos: stay.isFromPhotos), [stay]))
            }
        }

        func isPassingThrough(_ index: Int) -> Bool {
            let run = rawRuns[index].run
            if !(run.time >= 45 * 60 || run.count >= 3 || run.fromPhotos) { return true }
            if run.fromPhotos, run.count == 1, index > 0, index + 1 < rawRuns.count {
                let before = rawRuns[index - 1].run, after = rawRuns[index + 1].run
                if after.start.timeIntervalSince(before.end) < 86_400
                    && before.last.location.distance(from: run.first.location) > 300_000
                    && after.first.location.distance(from: run.first.location) > 300_000 {
                    return true
                }
            }
            // Border-edge drift filter (e.g. Niagara Falls on Canadian side within 25km of US border):
            // 1-2 brief photo stays (< 2h) right next to a neighboring country visit within 24h & 25km
            if run.fromPhotos, run.count <= 2, run.time < 2 * 3600 {
                let neighbors = [
                    index > 0 ? rawRuns[index - 1].run : nil,
                    index + 1 < rawRuns.count ? rawRuns[index + 1].run : nil
                ].compactMap { $0 }
                for nb in neighbors where nb.code != run.code {
                    let timeGap = min(abs(run.start.timeIntervalSince(nb.end)), abs(nb.start.timeIntervalSince(run.end)))
                    let dist = min(
                        run.first.location.distance(from: nb.last.location),
                        run.last.location.distance(from: nb.first.location)
                    )
                    if timeGap < 86_400 && dist < 25_000 && (nb.count >= 3 || nb.time >= 4 * 3600) {
                        return true
                    }
                }
            }
            return false
        }

        var passingIDs = Set<UUID>()
        var keptRuns: [Run] = []
        for i in rawRuns.indices {
            if isPassingThrough(i) {
                passingIDs.formUnion(rawRuns[i].stays.map(\.id))
            } else {
                let run = rawRuns[i].run
                if keptRuns.last?.code == run.code {
                    keptRuns[keptRuns.count - 1].last = run.last
                    keptRuns[keptRuns.count - 1].end = max(keptRuns[keptRuns.count - 1].end, run.end)
                    keptRuns[keptRuns.count - 1].time += run.time
                    keptRuns[keptRuns.count - 1].count += run.count
                } else {
                    keptRuns.append(run)
                }
            }
        }

        let visitedCountries = Set(keptRuns.map(\.code))
        var timeByCountry: [String: TimeInterval] = [:]
        for run in keptRuns { timeByCountry[run.code, default: 0] += max(run.end.timeIntervalSince(run.start), Double(run.count) * 3600) }
        let homeCode = timeByCountry.max { $0.value < $1.value }?.key
        let homeName = homeCode.map { CountryText.localizedName(code: $0) }

        // 2. Entry + Exit stamps (non-home countries)
        struct Visit {
            let code: String
            var first: Stay
            var last: Stay
            var start: Date
            var end: Date
            var arrivedByAir: Bool
            var next: Stay?
        }

        var visits: [Visit] = []
        let rejoin: TimeInterval = 3 * 86_400
        for (index, run) in keptRuns.enumerated() where run.code != homeCode {
            let next = index + 1 < keptRuns.count ? keptRuns[index + 1].first : nil
            if let open = visits.lastIndex(where: { $0.code == run.code }),
               open == visits.count - 1,
               run.start.timeIntervalSince(visits[open].end) < rejoin {
                visits[open].last = run.last
                visits[open].end = max(visits[open].end, run.end)
                visits[open].next = next
                continue
            }
            let prev = index > 0 ? keptRuns[index - 1].last : nil
            let byAir = run.first.category == .airport || (prev.map { $0.location.distance(from: run.first.location) > 400_000 } ?? false)
            visits.append(Visit(code: run.code, first: run.first, last: run.last, start: run.start, end: run.end, arrivedByAir: byAir, next: next))
        }

        var passportStamps: [PassportStamp] = []
        for visit in visits {
            let entryPort = visit.first.category == .airport ? visit.first.displayName : (visit.first.city ?? visit.first.placeName)
            passportStamps.append(PassportStamp(
                id: "entry.\(visit.code).\(Int(visit.start.timeIntervalSince1970))",
                kind: .entry,
                date: visit.start,
                countryCode: visit.code,
                port: entryPort,
                byAir: visit.arrivedByAir,
                latitude: visit.first.latitude,
                longitude: visit.first.longitude
            ))
            guard let next = visit.next else { continue }
            let days = max(1, (cal.dateComponents([.day], from: cal.startOfDay(for: visit.start), to: cal.startOfDay(for: max(visit.end, visit.start))).day ?? 0) + 1)
            let exitPort = visit.last.category == .airport ? visit.last.displayName : (visit.last.city ?? visit.last.placeName)
            let leftByAir = visit.last.category == .airport || visit.last.location.distance(from: next.location) > 400_000
            passportStamps.append(PassportStamp(
                id: "exit.\(visit.code).\(Int(visit.start.timeIntervalSince1970))",
                kind: .exit,
                date: visit.end,
                countryCode: visit.code,
                port: exitPort,
                byAir: leftByAir,
                days: days,
                latitude: visit.last.latitude,
                longitude: visit.last.longitude
            ))
        }

        // Apply user border-crossing overrides (delete / edit auto stamps, add manual stamps)
        passportStamps = BorderStampOverrides.apply(to: passportStamps)

        // 3. Country summaries, Province visits, City stamps
        var countryDays: [String: Set<Date>] = [:]
        var countryCities: [String: [String: Int]] = [:]
        var countryFirst: [String: Date] = [:]

        var provDays: [String: Set<Date>] = [:]
        var provCities: [String: [String: Int]] = [:]
        var provFirst: [String: Date] = [:]

        var seenCities = Set<String>()
        var cityStamps: [PassportStamp] = []

        for stay in sorted where !passingIDs.contains(stay.id) {
            guard let code = stay.countryCode else { continue }
            let day = cal.startOfDay(for: stay.arrival)
            countryDays[code, default: []].insert(day)
            if let city = stay.city, !city.isEmpty {
                countryCities[code, default: [:]][city, default: 0] += 1
            }
            countryFirst[code] = min(countryFirst[code] ?? .distantFuture, stay.arrival)

            if let province = ChinaProvince.containing(countryCode: code, region: stay.region, city: stay.city) {
                provDays[province.id, default: []].insert(day)
                if let city = stay.city, !city.isEmpty {
                    provCities[province.id, default: [:]][city, default: 0] += 1
                }
                provFirst[province.id] = min(provFirst[province.id] ?? .distantFuture, stay.arrival)
            }

            if let city = stay.city, !city.isEmpty {
                let key = "\(code)|\(city)"
                if seenCities.insert(key).inserted {
                    cityStamps.append(PassportStamp(
                        id: "city.\(key)",
                        kind: .city,
                        date: stay.arrival,
                        countryCode: code,
                        city: city,
                        latitude: stay.latitude,
                        longitude: stay.longitude
                    ))
                }
            }
        }

        let countrySummaries: [PassportCountrySummary] = visitedCountries.map { code in
            let top = (countryCities[code] ?? [:]).sorted { $0.value > $1.value }.prefix(3).map(\.key)
            return PassportCountrySummary(
                code: code,
                name: CountryText.localizedName(code: code),
                flag: CountryText.flag(for: code),
                days: max(1, countryDays[code]?.count ?? 1),
                firstVisit: countryFirst[code] ?? Date(),
                topCities: Array(top)
            )
        }.sorted { $0.days > $1.days }

        let continentsVisited = WorldContinent.all.filter { !Set($0.regions).isDisjoint(with: visitedCountries) }.count

        var provinceVisits: [String: PassportProvinceVisit] = [:]
        for province in ChinaProvince.all {
            if let days = provDays[province.id], !days.isEmpty {
                let top = (provCities[province.id] ?? [:]).sorted { $0.value > $1.value }.map(\.key)
                    .filter { $0 != province.name && $0 != "\(province.name)市" }
                provinceVisits[province.id] = PassportProvinceVisit(
                    province: province,
                    days: days.count,
                    firstVisit: provFirst[province.id] ?? Date(),
                    topCities: Array(top.prefix(3))
                )
            }
        }

        // 4. First-day track route inside each city stamp (fast day-indexed lookup)
        let groundChunks = chunks.filter { $0.mode != .flying }
        let chunksByDay = Dictionary(grouping: groundChunks) { cal.startOfDay(for: $0.startDate) }
        var cityRoutes: [String: [CGPoint]] = [:]
        for stamp in cityStamps {
            let day = cal.startOfDay(for: stamp.date)
            guard let dayChunks = chunksByDay[day], !dayChunks.isEmpty else { continue }
            let center = CLLocation(latitude: stamp.latitude, longitude: stamp.longitude)
            let coords = dayChunks.flatMap(\.points).compactMap { pt -> CLLocationCoordinate2D? in
                guard abs(pt.latitude - stamp.latitude) < 0.3 else { return nil }
                let loc = CLLocation(latitude: pt.latitude, longitude: pt.longitude)
                return loc.distance(from: center) < 25_000 ? CLLocationCoordinate2D(latitude: pt.latitude, longitude: pt.longitude) : nil
            }
            let normalized = normalizeRoute(coords)
            if normalized.count > 1 {
                cityRoutes[stamp.id] = normalized
            }
        }

        // 5. Specials: Crossings, New Year's Eves, Four Corners, Highest Point
        let allSorted = stays.sorted { $0.arrival < $1.arrival }
        var specials: [PassportStamp] = []
        func addSpecial(_ code: String, _ stay: Stay, value: String? = nil) {
            specials.append(PassportStamp(
                id: "special.\(code)",
                kind: .special,
                date: stay.arrival,
                countryCode: stay.countryCode,
                city: stay.city ?? stay.country ?? stay.displayName,
                latitude: stay.latitude,
                longitude: stay.longitude,
                code: code,
                value: value
            ))
        }

        var crossedEquator = false, crossedDateLine = false, arctic = false, antarctic = false
        for (prev, stay) in zip(allSorted, allSorted.dropFirst()) {
            if !crossedEquator, prev.latitude * stay.latitude < 0, abs(prev.latitude) > 0.2 || abs(stay.latitude) > 0.2 {
                crossedEquator = true
                addSpecial("equator", stay, value: "0°00′")
            }
            if !crossedDateLine, abs(prev.longitude - stay.longitude) > 180 {
                crossedDateLine = true
                addSpecial("dateline", stay, value: "180°")
            }
        }
        for stay in allSorted {
            if !arctic, stay.latitude >= arcticCircle { arctic = true; addSpecial("arctic", stay, value: "66°33′N") }
            if !antarctic, stay.latitude <= -arcticCircle { antarctic = true; addSpecial("antarctic", stay, value: "66°33′S") }
        }

        if let first = allSorted.first?.arrival {
            let firstYear = cal.component(.year, from: first)
            let thisYear = cal.component(.year, from: Date())
            for year in max(firstYear, thisYear - 40)...thisYear {
                guard let midnight = cal.date(from: DateComponents(year: year, month: 1, day: 1)), midnight <= Date() else { continue }
                func gap(_ stay: Stay) -> TimeInterval {
                    let end = max(stay.departure ?? stay.arrival, stay.arrival)
                    return stay.arrival > midnight ? stay.arrival.timeIntervalSince(midnight) : max(0, midnight.timeIntervalSince(end))
                }
                // 优先取零点前后 2 小时内（实时定位跨夜）；若为相册导入，则放宽至 12月31日 00:00 ~ 1月1日 23:59（±24 小时）内离零点最近的记录
                let candidates = allSorted.filter { gap($0) < 24 * 3600 }
                if let stay = candidates.min(by: { gap($0) < gap($1) }) {
                    specials.append(PassportStamp(
                        id: "special.newyear.\(year)",
                        kind: .special,
                        date: midnight,
                        countryCode: stay.countryCode,
                        city: stay.city ?? stay.displayName,
                        latitude: stay.latitude,
                        longitude: stay.longitude,
                        code: "newyear.\(year)",
                        value: String(year)
                    ))
                }
            }
        }

        let named = allSorted.filter { $0.city != nil }
        let cornerSource = named.count > 1 ? named : allSorted
        if !cornerSource.isEmpty {
            if let north = cornerSource.max(by: { $0.latitude < $1.latitude }) {
                addSpecial("record.north", north, value: degrees(north.latitude, "N", "S"))
            }
            if let south = cornerSource.min(by: { $0.latitude < $1.latitude }) {
                addSpecial("record.south", south, value: degrees(south.latitude, "N", "S"))
            }
            if let east = cornerSource.max(by: { $0.longitude < $1.longitude }) {
                addSpecial("record.east", east, value: degrees(east.longitude, "E", "W"))
            }
            if let west = cornerSource.min(by: { $0.longitude < $1.longitude }) {
                addSpecial("record.west", west, value: degrees(west.longitude, "E", "W"))
            }
        }

        // Highest point from ground tracks (95th percentile per chunk to reject GPS spikes)
        var bestAlt: (lat: Double, lon: Double, alt: Double, date: Date)?
        for chunk in groundChunks {
            let pts = chunk.points.filter { $0.accuracy < 30 && $0.altitude > 10 && $0.altitude < 9000 }
            guard pts.count >= 5 else { continue }
            let sortedPts = pts.sorted { $0.altitude < $1.altitude }
            let pt = sortedPts[Int(Double(sortedPts.count - 1) * 0.95)]
            if pt.altitude > (bestAlt?.alt ?? 200) {
                bestAlt = (pt.latitude, pt.longitude, pt.altitude, pt.timestamp)
            }
        }
        if let high = bestAlt {
            let here = CLLocation(latitude: high.lat, longitude: high.lon)
            let nearestCity = named.min { $0.location.distance(from: here) < $1.location.distance(from: here) }?.city
            let formattedAlt = NumberFormatter.localizedString(from: NSNumber(value: Int(high.alt.rounded())), number: .decimal) + " m"
            specials.append(PassportStamp(
                id: "special.record.high",
                kind: .special,
                date: high.date,
                city: nearestCity,
                latitude: high.lat,
                longitude: high.lon,
                code: "record.high",
                value: formattedAlt
            ))
        }

        // 6. Stamp sets (all 14)
        let sets = StampSet.progress(cities: cityStamps)

        return PassportSummary(
            homeCountryCode: homeCode,
            homeCountryName: homeName,
            since: since,
            passportStamps: passportStamps,
            visitedCountries: visitedCountries,
            countrySummaries: countrySummaries,
            continentsVisited: continentsVisited,
            provinceVisits: provinceVisits,
            cityStamps: cityStamps,
            cityRoutes: cityRoutes,
            specials: specials,
            stampSets: sets
        )
    }

    static func degrees(_ value: Double, _ positive: String, _ negative: String) -> String {
        let whole = Int(abs(value))
        let minutes = Int((abs(value) - Double(whole)) * 60)
        return "\(whole)°\(String(format: "%02d", minutes))′\(value >= 0 ? positive : negative)"
    }

    private static func normalizeRoute(_ coordinates: [CLLocationCoordinate2D]) -> [CGPoint] {
        guard coordinates.count >= 5 else { return [] }
        let k = cos(coordinates[0].latitude * .pi / 180)
        let xs = coordinates.map { $0.longitude * k }
        let ys = coordinates.map { -$0.latitude }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return [] }
        let span = max(maxX - minX, maxY - minY)
        guard span > 0.003 else { return [] }
        let offsetX = (span - (maxX - minX)) / 2
        let offsetY = (span - (maxY - minY)) / 2
        let step = max(1, coordinates.count / 120)
        return stride(from: 0, to: coordinates.count, by: step).map {
            CGPoint(x: (xs[$0] - minX + offsetX) / span, y: (ys[$0] - minY + offsetY) / span)
        }
    }
}
