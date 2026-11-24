import Foundation
import CoreLocation
import MapKit
import SwiftUI

// MARK: - Level

enum ChinaRegionLevel: String, CaseIterable, Identifiable, Sendable {
    case district = "district"
    case city = "city"
    case province = "province"

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .district: return "县"
        case .city: return "市"
        case .province: return "省"
        }
    }

    var fullTitle: String {
        switch self {
        case .district: return "区县"
        case .city: return "地级市"
        case .province: return "省级行政区"
        }
    }
}

// MARK: - Visited Areas JSON Schema (compatible with MyTravelsChina/visited_areas.json)

struct VisitedAreasPayload: Codable, Sendable {
    var _comment: String?
    var district: [String]
    var city: [String]
    var province: [String]
    var municipalities: [String]

    init(
        _comment: String? = "足迹地图配置文件 - 漫迹16 与 GitHub 双向同步",
        district: [String] = [],
        city: [String] = [],
        province: [String] = [],
        municipalities: [String] = []
    ) {
        self._comment = _comment
        self.district = district
        self.city = city
        self.province = province
        self.municipalities = municipalities
    }
}

// MARK: - GeoJSON Feature Model

struct ChinaGeoFeature: Identifiable, Sendable {
    let id: String
    let adcode: Int
    let name: String
    let level: ChinaRegionLevel
    let parentAdcode: Int?
    let center: CLLocationCoordinate2D?
    /// Polygon exterior rings in GCJ-02 (directly aligned with Apple Maps in China).
    let rings: [[CLLocationCoordinate2D]]
    /// High-precision MKMapPoints for zoomed-in rendering (no jagged triangles).
    let mapRings: [[MKMapPoint]]
    /// Coarse MKMapPoints for zoomed-out nationwide 60fps rendering.
    let coarseMapRings: [[MKMapPoint]]
    let mapRect: MKMapRect
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double

    /// Key used in `visited_areas.json`
    var visitedKey: String {
        switch level {
        case .district: return "\(name)|\(adcode)"
        case .city, .province: return name
        }
    }

    func contains(gcj02 point: CLLocationCoordinate2D) -> Bool {
        guard point.latitude >= minLat && point.latitude <= maxLat
                && point.longitude >= minLon && point.longitude <= maxLon else {
            return false
        }
        return rings.contains { ChinaGeoLoader.pointInRing(point, ring: $0) }
    }
}

// MARK: - Fast GeoJSON Loader with Douglas-Peucker Simplification & Cache

enum ChinaGeoLoader {
    private static let lock = NSLock()
    private static var provinceCache: [ChinaGeoFeature]?
    private static var cityCache: [ChinaGeoFeature]?
    private static var districtCache: [ChinaGeoFeature]?

    private static let municipalityAdcodes: Set<Int> = [110000, 120000, 310000, 500000]
    private static let allProvinceAdcodes: [Int] = [
        110000, 120000, 130000, 140000, 150000,
        210000, 220000, 230000,
        310000, 320000, 330000, 340000, 350000, 360000, 370000,
        410000, 420000, 430000, 440000, 450000, 460000,
        500000, 510000, 520000, 530000, 540000,
        610000, 620000, 630000, 640000, 650000
    ]

    static func load(level: ChinaRegionLevel) -> [ChinaGeoFeature] {
        switch level {
        case .province:
            return loadProvinces()
        case .city:
            return loadCities()
        case .district:
            return loadDistricts()
        }
    }

    static func loadProvinces() -> [ChinaGeoFeature] {
        lock.lock()
        if let cached = provinceCache {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // detailTolerance = 0 preserves raw GeoJSON shared vertices so zoomed-in adjacent borders never cross or gap
        let features = parseGeoJSON(named: "100000_full", level: .province, detailTolerance: 0, coarseTolerance: 0.025)
        lock.lock()
        provinceCache = features
        lock.unlock()
        return features
    }

    static func loadCities() -> [ChinaGeoFeature] {
        lock.lock()
        if let cached = cityCache {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // 1. Parse prefecture-level cities and exclude sub-districts of the 4 direct-controlled municipalities
        let rawCities = parseGeoJSON(named: "100000_full_city", level: .city, detailTolerance: 0, coarseTolerance: 0.014)
        var filtered = rawCities.filter { feat in
            let provincePrefix = (feat.adcode / 10000) * 10000
            if municipalityAdcodes.contains(provincePrefix) || municipalityAdcodes.contains(feat.adcode) {
                return false
            }
            if let parent = feat.parentAdcode, municipalityAdcodes.contains(parent) {
                return false
            }
            return true
        }

        // 2. Append the 4 whole municipalities (北京市/天津市/上海市/重庆市) from province GeoJSON as single city-level areas
        let wholeMunicipalities = parseGeoJSON(named: "100000_full", level: .city, detailTolerance: 0, coarseTolerance: 0.014)
            .filter { municipalityAdcodes.contains($0.adcode) }
        filtered.append(contentsOf: wholeMunicipalities)

        lock.lock()
        cityCache = filtered
        lock.unlock()
        return filtered
    }

    static func loadDistricts() -> [ChinaGeoFeature] {
        lock.lock()
        if let cached = districtCache {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var all: [ChinaGeoFeature] = []
        all.reserveCapacity(2900)
        for code in allProvinceAdcodes {
            let fileName = municipalityAdcodes.contains(code) ? "\(code)_full" : "\(code)_full_district"
            let parsed = parseGeoJSON(named: fileName, level: .district, detailTolerance: 0, coarseTolerance: 0.008)
            all.append(contentsOf: parsed)
        }
        lock.lock()
        districtCache = all
        lock.unlock()
        return all
    }

    private static func fileURL(named name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "ChinaGeoJSON") {
            return url
        }
        return Bundle.main.url(forResource: name, withExtension: "json")
    }

    private static func parseGeoJSON(named name: String, level: ChinaRegionLevel, detailTolerance: Double, coarseTolerance: Double) -> [ChinaGeoFeature] {
        guard let url = fileURL(named: name),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else {
            return []
        }

        var result: [ChinaGeoFeature] = []
        result.reserveCapacity(features.count)

        for feat in features {
            guard let props = feat["properties"] as? [String: Any],
                  let rawName = props["name"] as? String,
                  !rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let geom = feat["geometry"] as? [String: Any],
                  let geomType = geom["type"] as? String else {
                continue
            }

            let adcode: Int
            if let intCode = props["adcode"] as? Int {
                adcode = intCode
            } else if let strCode = props["adcode"] as? String, let parsed = Int(strCode) {
                adcode = parsed
            } else {
                continue
            }
            if adcode == 100000 { continue }

            let parentAdcode: Int? = (props["parent"] as? [String: Any])?["adcode"] as? Int
            var centerCoord: CLLocationCoordinate2D?
            if let centerArr = props["center"] as? [Double], centerArr.count >= 2 {
                centerCoord = CLLocationCoordinate2D(latitude: centerArr[1], longitude: centerArr[0])
            } else if let centerArr = props["centroid"] as? [Double], centerArr.count >= 2 {
                centerCoord = CLLocationCoordinate2D(latitude: centerArr[1], longitude: centerArr[0])
            }

            var rings: [[CLLocationCoordinate2D]] = []
            var coarseRings: [[CLLocationCoordinate2D]] = []
            if geomType == "Polygon", let coords = geom["coordinates"] as? [[[Double]]] {
                if let exterior = coords.first {
                    let detail = simplifyRing(exterior, tolerance: detailTolerance)
                    if detail.count >= 3 {
                        rings.append(detail)
                        let coarse = simplifyCoords(detail, tolerance: coarseTolerance)
                        coarseRings.append(coarse.count >= 3 ? coarse : detail)
                    }
                }
            } else if geomType == "MultiPolygon", let polys = geom["coordinates"] as? [[[[Double]]]] {
                var candidateRings: [([CLLocationCoordinate2D], Double)] = []
                for poly in polys {
                    if let exterior = poly.first {
                        let detail = simplifyRing(exterior, tolerance: detailTolerance)
                        if detail.count >= 3 {
                            candidateRings.append((detail, ringSpan(detail)))
                        }
                    }
                }
                let maxSpan = candidateRings.map(\.1).max() ?? 0
                let minKeepSpan = level == .province ? 0.05 : (level == .city ? 0.02 : 0.008)
                for (detail, span) in candidateRings {
                    if span >= minKeepSpan || span == maxSpan {
                        rings.append(detail)
                        let coarse = simplifyCoords(detail, tolerance: coarseTolerance)
                        coarseRings.append(coarse.count >= 3 ? coarse : detail)
                    }
                }
            }

            guard !rings.isEmpty else { continue }

            var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0
            var mapRings: [[MKMapPoint]] = []
            mapRings.reserveCapacity(rings.count)
            var minX = Double.greatestFiniteMagnitude
            var maxX = -Double.greatestFiniteMagnitude
            var minY = Double.greatestFiniteMagnitude
            var maxY = -Double.greatestFiniteMagnitude

            for ring in rings {
                var pts: [MKMapPoint] = []
                pts.reserveCapacity(ring.count)
                for pt in ring {
                    if pt.latitude < minLat { minLat = pt.latitude }
                    if pt.latitude > maxLat { maxLat = pt.latitude }
                    if pt.longitude < minLon { minLon = pt.longitude }
                    if pt.longitude > maxLon { maxLon = pt.longitude }
                    let mp = MKMapPoint(pt)
                    pts.append(mp)
                    if mp.x < minX { minX = mp.x }
                    if mp.x > maxX { maxX = mp.x }
                    if mp.y < minY { minY = mp.y }
                    if mp.y > maxY { maxY = mp.y }
                }
                mapRings.append(pts)
            }
            let coarseMapRings: [[MKMapPoint]] = coarseRings.map { $0.map { MKMapPoint($0) } }
            let rect = MKMapRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))

            result.append(ChinaGeoFeature(
                id: "\(level.rawValue).\(adcode).\(rawName)",
                adcode: adcode,
                name: rawName,
                level: level,
                parentAdcode: parentAdcode,
                center: centerCoord ?? CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                rings: rings,
                mapRings: mapRings,
                coarseMapRings: coarseMapRings,
                mapRect: rect,
                minLat: minLat,
                maxLat: maxLat,
                minLon: minLon,
                maxLon: maxLon
            ))
        }
        return result
    }

    private static func ringSpan(_ ring: [CLLocationCoordinate2D]) -> Double {
        var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0
        for pt in ring {
            if pt.latitude < minLat { minLat = pt.latitude }
            if pt.latitude > maxLat { maxLat = pt.latitude }
            if pt.longitude < minLon { minLon = pt.longitude }
            if pt.longitude > maxLon { maxLon = pt.longitude }
        }
        return max(maxLat - minLat, maxLon - minLon)
    }

    /// Fast radial + Douglas-Peucker simplification (tolerance <= 0 preserves exact GeoJSON vertices).
    private static func simplifyRing(_ raw: [[Double]], tolerance: Double) -> [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        coords.reserveCapacity(raw.count)
        var lastLat = Double.nan
        var lastLon = Double.nan
        for pt in raw where pt.count >= 2 {
            let lat = pt[1], lon = pt[0]
            if lat != lastLat || lon != lastLon {
                coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                lastLat = lat
                lastLon = lon
            }
        }
        guard tolerance > 0 else { return coords }
        return simplifyCoords(coords, tolerance: tolerance)
    }

    private static func simplifyCoords(_ coords: [CLLocationCoordinate2D], tolerance: Double) -> [CLLocationCoordinate2D] {
        guard coords.count > 6 else { return coords }

        // Step 1: Quick radial distance decimation
        let tolSq = tolerance * tolerance
        var filtered: [CLLocationCoordinate2D] = [coords[0]]
        var prev = coords[0]
        for i in 1..<(coords.count - 1) {
            let p = coords[i]
            let dLat = p.latitude - prev.latitude
            let dLon = p.longitude - prev.longitude
            if (dLat * dLat + dLon * dLon) >= tolSq * 0.36 {
                filtered.append(p)
                prev = p
            }
        }
        if let last = coords.last {
            filtered.append(last)
        }
        guard filtered.count > 6 else { return filtered }

        // Step 2: Iterative Douglas-Peucker
        let n = filtered.count
        var keep = [Bool](repeating: false, count: n)
        keep[0] = true
        keep[n - 1] = true
        var stack: [(Int, Int)] = [(0, n - 1)]

        while let (start, end) = stack.popLast() {
            guard end - start > 1 else { continue }
            let a = filtered[start]
            let b = filtered[end]
            var maxDistSq = 0.0
            var maxIdx = start

            for i in (start + 1)..<end {
                let dSq = perpendicularDistSq(filtered[i], a, b)
                if dSq > maxDistSq {
                    maxDistSq = dSq
                    maxIdx = i
                }
            }
            if maxDistSq > tolSq {
                keep[maxIdx] = true
                stack.append((start, maxIdx))
                stack.append((maxIdx, end))
            }
        }

        var simplified: [CLLocationCoordinate2D] = []
        simplified.reserveCapacity(n / 3)
        for i in 0..<n where keep[i] {
            simplified.append(filtered[i])
        }
        return simplified.count >= 3 ? simplified : filtered
    }

    private static func perpendicularDistSq(_ p: CLLocationCoordinate2D, _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let dx = b.longitude - a.longitude
        let dy = b.latitude - a.latitude
        let lenSq = dx * dx + dy * dy
        if lenSq == 0 {
            let ex = p.longitude - a.longitude
            let ey = p.latitude - a.latitude
            return ex * ex + ey * ey
        }
        let t = max(0, min(1, ((p.longitude - a.longitude) * dx + (p.latitude - a.latitude) * dy) / lenSq))
        let projLon = a.longitude + t * dx
        let projLat = a.latitude + t * dy
        let ex = p.longitude - projLon
        let ey = p.latitude - projLat
        return ex * ex + ey * ey
    }

    static func pointInRing(_ point: CLLocationCoordinate2D, ring: [CLLocationCoordinate2D]) -> Bool {
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
}

// MARK: - China Regions Store (Pre-seeded + Auto-Match + Manual Toggle + GitHub Sync)

@MainActor
final class ChinaRegionsStore: ObservableObject {
    static let shared = ChinaRegionsStore()

    nonisolated static let municipalityNames: Set<String> = ["北京市", "天津市", "上海市", "重庆市"]

    @Published var visitedDistricts: Set<String> = []
    @Published var visitedCities: Set<String> = []
    @Published var visitedProvinces: Set<String> = []
    @Published var visitedMunicipalities: Set<String> = []

    @Published var ghToken: String {
        didSet { UserDefaults.standard.set(ghToken, forKey: "wt16.gh.token") }
    }
    @Published var ghRepo: String {
        didSet { UserDefaults.standard.set(ghRepo, forKey: "wt16.gh.repo") }
    }
    @Published var ghBranch: String {
        didSet { UserDefaults.standard.set(ghBranch, forKey: "wt16.gh.branch") }
    }
    @Published var ghSHA: String? {
        didSet { UserDefaults.standard.set(ghSHA, forKey: "wt16.gh.sha") }
    }

    @Published var isSyncing = false
    @Published var isAutoMatching = false
    @Published var syncMessage: String?
    @Published var syncError: String?
    @Published var hasUnsyncedChanges = false

    private var manuallyRemoved: Set<String> = []
    private let localURL: URL

    var isGitHubConfigured: Bool {
        !ghToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !ghRepo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var litProvinceCount: Int {
        visitedProvinces.union(visitedMunicipalities).count
    }

    var litCityCount: Int {
        visitedCities.union(visitedMunicipalities).count
    }

    var litDistrictCount: Int {
        visitedDistricts.count
    }

    init() {
        self.ghToken = UserDefaults.standard.string(forKey: "wt16.gh.token") ?? ""
        self.ghRepo = UserDefaults.standard.string(forKey: "wt16.gh.repo") ?? ""
        self.ghBranch = UserDefaults.standard.string(forKey: "wt16.gh.branch") ?? "main"
        self.ghSHA = UserDefaults.standard.string(forKey: "wt16.gh.sha")

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Waytrace16", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.localURL = dir.appendingPathComponent("visited_areas.json")

        if let saved = UserDefaults.standard.array(forKey: "wt16.china.removed") as? [String] {
            self.manuallyRemoved = Set(saved)
        }

        loadLocalOrSeed()
    }

    // MARK: - Query & Manual Toggle

    func isLit(_ feature: ChinaGeoFeature) -> Bool {
        switch feature.level {
        case .district:
            return visitedDistricts.contains(feature.visitedKey) || visitedDistricts.contains(feature.name)
        case .city:
            return visitedCities.contains(feature.name) || visitedMunicipalities.contains(feature.name)
        case .province:
            return visitedProvinces.contains(feature.name) || visitedMunicipalities.contains(feature.name)
        }
    }

    @discardableResult
    func toggle(_ feature: ChinaGeoFeature) -> Bool {
        let nowLit: Bool
        switch feature.level {
        case .district:
            let key = feature.visitedKey
            if visitedDistricts.contains(key) || visitedDistricts.contains(feature.name) {
                visitedDistricts.remove(key)
                visitedDistricts.remove(feature.name)
                manuallyRemoved.insert("d:\(key)")
                nowLit = false
            } else {
                visitedDistricts.insert(key)
                manuallyRemoved.remove("d:\(key)")
                nowLit = true
            }
        case .city:
            if Self.municipalityNames.contains(feature.name) {
                if visitedMunicipalities.contains(feature.name) {
                    visitedMunicipalities.remove(feature.name)
                    manuallyRemoved.insert("m:\(feature.name)")
                    nowLit = false
                } else {
                    visitedMunicipalities.insert(feature.name)
                    manuallyRemoved.remove("m:\(feature.name)")
                    nowLit = true
                }
            } else if visitedCities.contains(feature.name) {
                visitedCities.remove(feature.name)
                manuallyRemoved.insert("c:\(feature.name)")
                nowLit = false
            } else {
                visitedCities.insert(feature.name)
                manuallyRemoved.remove("c:\(feature.name)")
                nowLit = true
            }
        case .province:
            if Self.municipalityNames.contains(feature.name) {
                if visitedMunicipalities.contains(feature.name) {
                    visitedMunicipalities.remove(feature.name)
                    visitedProvinces.remove(feature.name)
                    manuallyRemoved.insert("m:\(feature.name)")
                    nowLit = false
                } else {
                    visitedMunicipalities.insert(feature.name)
                    manuallyRemoved.remove("m:\(feature.name)")
                    nowLit = true
                }
            } else if visitedProvinces.contains(feature.name) {
                visitedProvinces.remove(feature.name)
                manuallyRemoved.insert("p:\(feature.name)")
                nowLit = false
            } else {
                visitedProvinces.insert(feature.name)
                manuallyRemoved.remove("p:\(feature.name)")
                nowLit = true
            }
        }
        hasUnsyncedChanges = true
        persistLocal()
        return nowLit
    }

    // MARK: - Auto-Match from DataStore Stays (WGS-84 -> GCJ-02 -> Point-in-Polygon)

    func autoMatch(stays: [Stay], includeDistricts: Bool = true) async -> (provinces: Int, cities: Int, districts: Int) {
        guard !isAutoMatching else { return (0, 0, 0) }
        isAutoMatching = true
        defer { isAutoMatching = false }

        // Deduplicate stay coordinates to ~2km grid in China bounding box
        var uniquePoints: [CLLocationCoordinate2D] = []
        var seenGrid = Set<String>()
        for stay in stays {
            let lat = stay.latitude, lon = stay.longitude
            guard lat >= 3.0 && lat <= 54.0 && lon >= 73.0 && lon <= 136.0 else { continue }
            let key = "\(Int((lat * 50).rounded()))_\(Int((lon * 50).rounded()))"
            if seenGrid.insert(key).inserted {
                uniquePoints.append(stay.coordinate.onMap)
            }
        }

        guard !uniquePoints.isEmpty else { return (0, 0, 0) }

        let removedSnapshot = manuallyRemoved
        let matched = await Task.detached(priority: .utility) { () -> (Set<String>, Set<String>, Set<String>, Set<String>) in
            let provinces = ChinaGeoLoader.loadProvinces()
            let cities = ChinaGeoLoader.loadCities()
            let districts = includeDistricts ? ChinaGeoLoader.loadDistricts() : []

            var foundProvs = Set<String>()
            var foundMuns = Set<String>()
            var foundCities = Set<String>()
            var foundDistricts = Set<String>()

            for pt in uniquePoints {
                if let p = provinces.first(where: { $0.contains(gcj02: pt) }) {
                    if Self.municipalityNames.contains(p.name) {
                        if !removedSnapshot.contains("m:\(p.name)") { foundMuns.insert(p.name) }
                    } else {
                        if !removedSnapshot.contains("p:\(p.name)") { foundProvs.insert(p.name) }
                    }
                }
                if let c = cities.first(where: { $0.contains(gcj02: pt) }) {
                    if Self.municipalityNames.contains(c.name) {
                        if !removedSnapshot.contains("m:\(c.name)") { foundMuns.insert(c.name) }
                    } else {
                        if !removedSnapshot.contains("c:\(c.name)") { foundCities.insert(c.name) }
                    }
                }
                if includeDistricts, let d = districts.first(where: { $0.contains(gcj02: pt) }) {
                    if !removedSnapshot.contains("d:\(d.visitedKey)") { foundDistricts.insert(d.visitedKey) }
                }
            }
            return (foundProvs, foundMuns, foundCities, foundDistricts)
        }.value

        let addedP = matched.0.subtracting(visitedProvinces).count + matched.1.subtracting(visitedMunicipalities).count
        let addedC = matched.2.subtracting(visitedCities).count
        let addedD = matched.3.subtracting(visitedDistricts).count

        if addedP > 0 || addedC > 0 || addedD > 0 {
            visitedProvinces.formUnion(matched.0)
            visitedMunicipalities.formUnion(matched.1)
            visitedCities.formUnion(matched.2)
            visitedDistricts.formUnion(matched.3)
            hasUnsyncedChanges = true
            persistLocal()
        }
        return (addedP, addedC, addedD)
    }

    // MARK: - Local Persistence & Seeding

    private func loadLocalOrSeed() {
        if let data = try? Data(contentsOf: localURL),
           let payload = try? JSONDecoder().decode(VisitedAreasPayload.self, from: data) {
            apply(payload)
            return
        }
        let seedURL = Bundle.main.url(forResource: "visited_areas", withExtension: "json", subdirectory: "ChinaGeoJSON")
            ?? Bundle.main.url(forResource: "visited_areas", withExtension: "json")
        if let seedURL,
           let data = try? Data(contentsOf: seedURL),
           let payload = try? JSONDecoder().decode(VisitedAreasPayload.self, from: data) {
            apply(payload)
            persistLocal()
        }
    }

    private func apply(_ payload: VisitedAreasPayload) {
        visitedDistricts = Set(payload.district)
        visitedCities = Set(payload.city)
        visitedProvinces = Set(payload.province)
        visitedMunicipalities = Set(payload.municipalities)
    }

    func buildPayload() -> VisitedAreasPayload {
        VisitedAreasPayload(
            _comment: "足迹地图配置文件 - 漫迹16 与 GitHub 双向同步",
            district: visitedDistricts.sorted(),
            city: visitedCities.sorted(),
            province: visitedProvinces.sorted(),
            municipalities: visitedMunicipalities.sorted()
        )
    }

    private func encodeOrderedJSON(_ payload: VisitedAreasPayload) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        return try? encoder.encode(payload)
    }

    func persistLocal() {
        UserDefaults.standard.set(Array(manuallyRemoved), forKey: "wt16.china.removed")
        if let data = encodeOrderedJSON(buildPayload()) {
            try? data.write(to: localURL, options: .atomic)
        }
    }

    // MARK: - GitHub Bidirectional Sync (1:1 Compatible with MyTravelsChina editor.js)

    func pullFromGitHub() async {
        let token = ghToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = ghRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = ghBranch.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "main"
        guard !token.isEmpty, !repo.isEmpty else {
            syncError = "请先填写 GitHub 仓库（如 用户名/仓库名）和 Personal Access Token"
            return
        }

        isSyncing = true
        syncError = nil
        syncMessage = nil
        defer { isSyncing = false }

        guard let url = URL(string: "https://api.github.com/repos/\(repo)/contents/visited_areas.json?ref=\(branch)") else {
            syncError = "仓库名称格式无效"
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                syncError = "网络响应异常"
                return
            }
            guard (200...299).contains(http.statusCode) else {
                if http.statusCode == 404 {
                    syncError = "仓库中未找到 visited_areas.json（请检查仓库名或分支）"
                } else if http.statusCode == 401 {
                    syncError = "Token 无效或已过期"
                } else {
                    syncError = "拉取失败（HTTP \(http.statusCode)）"
                }
                return
            }

            struct GHFileResponse: Decodable {
                let sha: String
                let content: String
            }
            let ghFile = try JSONDecoder().decode(GHFileResponse.self, from: data)
            let cleanedBase64 = ghFile.content.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
            guard let decodedData = Data(base64Encoded: cleanedBase64) else {
                syncError = "Base64 内容解码失败"
                return
            }
            let payload = try JSONDecoder().decode(VisitedAreasPayload.self, from: decodedData)
            apply(payload)
            ghSHA = ghFile.sha
            hasUnsyncedChanges = false
            persistLocal()
            syncMessage = "已从 GitHub 拉取：\(litProvinceCount) 省 · \(litCityCount) 市 · \(litDistrictCount) 区县"
        } catch {
            syncError = "拉取失败：\(error.localizedDescription)"
        }
    }

    func pushToGitHub() async {
        let token = ghToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = ghRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = ghBranch.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "main"
        guard !token.isEmpty, !repo.isEmpty else {
            syncError = "请先填写 GitHub 仓库（如 用户名/仓库名）和 Personal Access Token"
            return
        }

        isSyncing = true
        syncError = nil
        syncMessage = nil
        defer { isSyncing = false }

        guard let putURL = URL(string: "https://api.github.com/repos/\(repo)/contents/visited_areas.json") else {
            syncError = "仓库名称格式无效"
            return
        }

        var latestSHA = ghSHA
        if let getURL = URL(string: "https://api.github.com/repos/\(repo)/contents/visited_areas.json?ref=\(branch)") {
            var getReq = URLRequest(url: getURL)
            getReq.httpMethod = "GET"
            getReq.setValue("token \(token)", forHTTPHeaderField: "Authorization")
            getReq.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            getReq.cachePolicy = .reloadIgnoringLocalCacheData
            if let (getData, getResp) = try? await URLSession.shared.data(for: getReq),
               let http = getResp as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let obj = try? JSONSerialization.jsonObject(with: getData) as? [String: Any],
               let remoteSHA = obj["sha"] as? String {
                latestSHA = remoteSHA
            }
        }

        guard let jsonData = encodeOrderedJSON(buildPayload()) else {
            syncError = "生成 JSON 失败"
            return
        }

        var body: [String: Any] = [
            "message": "🗺️ 在线更新访问地区配置",
            "content": jsonData.base64EncodedString(),
            "branch": branch
        ]
        if let sha = latestSHA {
            body["sha"] = sha
        }

        var req = URLRequest(url: putURL)
        req.httpMethod = "PUT"
        req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                syncError = "网络响应异常"
                return
            }
            guard (200...299).contains(http.statusCode) else {
                if http.statusCode == 401 {
                    syncError = "Token 无效或缺少 repo 写入权限"
                } else if http.statusCode == 409 {
                    syncError = "文件版本冲突，请先拉取最新配置"
                } else {
                    syncError = "推送失败（HTTP \(http.statusCode)）"
                }
                return
            }

            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = obj["content"] as? [String: Any],
               let newSHA = content["sha"] as? String {
                ghSHA = newSHA
            }
            hasUnsyncedChanges = false
            syncMessage = "已成功推送到 GitHub（\(branch)）"
        } catch {
            syncError = "推送失败：\(error.localizedDescription)"
        }
    }
}
