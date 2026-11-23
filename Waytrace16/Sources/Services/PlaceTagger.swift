import Foundation
import CoreLocation
import MapKit

/// iOS 16 compatible place tagger using CLGeocoder + MKLocalPointsOfInterestRequest.
/// Uses ~10 km grid bucketing for photo-imported stays so thousands of photos only need
/// one reverse-geocode request per city/area instead of thousands of requests.
@MainActor
final class PlaceTagger: ObservableObject {
    @Published private(set) var isTagging = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var progressText: String?

    private let store: DataStore
    private let geocoder = CLGeocoder()
    private var needsAnotherPass = false

    init(store: DataStore) {
        self.store = store
        self.pendingCount = store.stays.filter { $0.tagState == .pending }.count
    }

    func enqueue() {
        pendingCount = store.stays.filter { $0.tagState == .pending }.count
        guard !isTagging else { needsAnotherPass = true; return }
        isTagging = true
        Task {
            repeat {
                needsAnotherPass = false
                await processPending()
            } while needsAnotherPass
            isTagging = false
            progressText = nil
            pendingCount = store.stays.filter { $0.tagState == .pending }.count
        }
    }

    func retryFailed() {
        let failed = store.stays.filter { $0.tagState == .failed }.map { stay -> Stay in
            var copy = stay
            copy.tagState = .pending
            return copy
        }
        guard !failed.isEmpty else { return }
        store.updateStaysBatch(failed)
        enqueue()
    }

    private func processPending() async {
        // 1. Always prioritize live-recorded stays first (with POI lookup)
        let recordedPending = store.stays.filter { $0.tagState == .pending && !$0.isFromPhotos }
        for var stay in recordedPending.prefix(50) {
            let outcome = await tagSingle(&stay, lookupPOI: true)
            if outcome == .rateLimited {
                try? await Task.sleep(nanoseconds: 62_000_000_000)
                let retry = await tagSingle(&stay, lookupPOI: true)
                if retry != .done { return }
            } else if outcome == .offline {
                return
            }
            store.upsertStay(stay)
            pendingCount = store.stays.filter { $0.tagState == .pending }.count
            try? await Task.sleep(nanoseconds: 1_300_000_000)
        }

        // 2. Fast area-bucketed tagging for photo-imported stays (1 request per ~10 km grid cell)
        let photoPending = store.stays.filter { $0.tagState == .pending && $0.isFromPhotos }
        guard !photoPending.isEmpty else { return }

        let taggedSnapshot = store.stays.filter { $0.tagState == .tagged && $0.countryCode != nil }

        // Group pending photo stays into ~10 km cells off the main thread
        let plan = await Task.detached(priority: .userInitiated) { () -> (copied: [Stay], buckets: [[Stay]]) in
            var grid = AreaGrid(cellDegrees: 0.09) // ~10 km
            for stay in taggedSnapshot { grid.add(stay) }

            var copied: [Stay] = []
            var pendingBuckets: [Int64: [Stay]] = [:]

            for var stay in photoPending {
                if let neighbour = grid.nearest(to: stay, within: 10_000) {
                    stay.country = neighbour.country
                    stay.countryCode = neighbour.countryCode
                    stay.city = neighbour.city
                    stay.region = neighbour.region
                    stay.timeZoneID = neighbour.timeZoneID
                    stay.tagState = .tagged
                    copied.append(stay)
                } else {
                    let k = grid.bucketKey(lat: stay.latitude, lon: stay.longitude)
                    pendingBuckets[k, default: []].append(stay)
                }
            }
            // Largest buckets first so the most stays get named immediately
            let sortedBuckets = pendingBuckets.values.sorted { $0.count > $1.count }
            return (copied, sortedBuckets)
        }.value

        if !plan.copied.isEmpty {
            store.updateStaysBatch(plan.copied)
            pendingCount = store.stays.filter { $0.tagState == .pending }.count
        }

        let totalBuckets = plan.buckets.count
        guard totalBuckets > 0 else {
            _ = await PhotoFootprints.consolidate(in: store)
            return
        }

        var completedBuckets = 0
        var stagedUpdates: [Stay] = []

        for bucket in plan.buckets {
            guard var representative = bucket.first else { continue }
            progressText = "识别区域 \(completedBuckets + 1)/\(totalBuckets)"

            var outcome = await tagSingle(&representative, lookupPOI: false)
            if outcome == .rateLimited {
                // Flush what we already have, wait out Apple's 1-minute geocoder window, and continue
                if !stagedUpdates.isEmpty {
                    store.updateStaysBatch(stagedUpdates)
                    stagedUpdates.removeAll()
                    pendingCount = store.stays.filter { $0.tagState == .pending }.count
                }
                progressText = "触发苹果频率限制，等待 60 秒继续 (\(completedBuckets)/\(totalBuckets))"
                try? await Task.sleep(nanoseconds: 62_000_000_000)
                outcome = await tagSingle(&representative, lookupPOI: false)
            }

            if outcome != .done {
                if !stagedUpdates.isEmpty {
                    store.updateStaysBatch(stagedUpdates)
                    stagedUpdates.removeAll()
                }
                break
            }

            // Apply the geocoded country/region/city/timezone to ALL stays in this ~10 km bucket
            for var item in bucket {
                item.country = representative.country
                item.countryCode = representative.countryCode
                item.region = representative.region
                item.city = representative.city
                item.street = item.street ?? representative.street
                item.timeZoneID = representative.timeZoneID
                item.tagState = representative.tagState
                stagedUpdates.append(item)
            }

            completedBuckets += 1
            if completedBuckets % 10 == 0 || stagedUpdates.count >= 200 {
                store.updateStaysBatch(stagedUpdates)
                stagedUpdates.removeAll()
                pendingCount = store.stays.filter { $0.tagState == .pending }.count
            }

            // Stay just under Apple's 50 requests/minute limit (~46 req/min)
            try? await Task.sleep(nanoseconds: 1_300_000_000)
        }

        if !stagedUpdates.isEmpty {
            store.updateStaysBatch(stagedUpdates)
            stagedUpdates.removeAll()
        }
        _ = await PhotoFootprints.consolidate(in: store)
        pendingCount = store.stays.filter { $0.tagState == .pending }.count
    }

    private enum TagOutcome { case done, rateLimited, offline }

    private func tagSingle(_ stay: inout Stay, lookupPOI: Bool) async -> TagOutcome {
        let location = stay.location
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "zh_CN"))
            if let p = placemarks.first {
                stay.countryCode = p.isoCountryCode
                stay.country = p.country
                stay.region = p.administrativeArea
                stay.city = normalizeCity(placemark: p)
                stay.street = [p.thoroughfare, p.subThoroughfare].compactMap { $0 }.joined().nilIfEmpty ?? p.name
                stay.timeZoneID = p.timeZone?.identifier
            }
        } catch let error as CLError {
            if error.code == .network {
                return .rateLimited
            }
            stay.tagState = .failed
            return .done
        } catch let error as NSError where error.domain == NSURLErrorDomain {
            return .offline
        } catch {
            stay.tagState = .failed
            return .done
        }

        if lookupPOI {
            let personal = PlaceCategory.chosenRawValues.contains(stay.categoryRaw ?? "")
            let overnight = stay.departure.map { $0.timeIntervalSince(stay.arrival) > 6 * 3600 } ?? false
            if !personal, !overnight, let landmark = await nearestLandmark(around: location) {
                stay.placeName = landmark.name
                stay.categoryRaw = landmark.pointOfInterestCategory?.rawValue
                stay.isLandmark = true
            } else if let poi = await nearestPOI(around: location, radius: 90, filter: .includingAll, excluding: PlaceCategory.utilityCategories) {
                stay.placeName = poi.name
                if stay.categoryRaw == nil { stay.categoryRaw = poi.pointOfInterestCategory?.rawValue }
            }
        }

        stay.tagState = (stay.country == nil && stay.city == nil) ? .failed : .tagged
        return .done
    }

    private func normalizeCity(placemark p: CLPlacemark) -> String? {
        if p.isoCountryCode == "HK" { return "香港" }
        if p.isoCountryCode == "MO" { return "澳门" }
        if let city = p.locality, !city.isEmpty { return city }
        if let admin = p.administrativeArea, !admin.isEmpty { return admin }
        return p.subAdministrativeArea
    }

    private func nearestLandmark(around location: CLLocation) async -> MKMapItem? {
        if let item = await nearestPOI(around: location, radius: 200,
                                       filter: MKPointOfInterestFilter(including: PlaceCategory.landmarkCategories)) {
            return item
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "景点"
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        return response.mapItems
            .filter { PlaceCategory.isSight($0.pointOfInterestCategory) }
            .map { ($0, $0.placemark.location?.distance(from: location) ?? .greatestFiniteMagnitude) }
            .filter { $0.1 <= 500 }
            .min { PlaceCategory.rankingScore($0.0.pointOfInterestCategory, distance: $0.1)
                    < PlaceCategory.rankingScore($1.0.pointOfInterestCategory, distance: $1.1) }?.0
    }

    private func nearestPOI(
        around location: CLLocation,
        radius: CLLocationDistance,
        filter: MKPointOfInterestFilter,
        excluding excluded: Set<MKPointOfInterestCategory> = []
    ) async -> MKMapItem? {
        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: radius)
        request.pointOfInterestFilter = filter
        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        return response.mapItems
            .filter { item in item.pointOfInterestCategory.map { !excluded.contains($0) } ?? true }
            .map { ($0, $0.placemark.location?.distance(from: location) ?? .greatestFiniteMagnitude) }
            .filter { $0.1 <= radius }
            .min { PlaceCategory.rankingScore($0.0.pointOfInterestCategory, distance: $0.1)
                    < PlaceCategory.rankingScore($1.0.pointOfInterestCategory, distance: $1.1) }?.0
    }
}

private struct AreaGrid {
    private var cells: [Int64: [Stay]] = [:]
    let cellDegrees: Double

    private func cell(_ lat: Double, _ lon: Double) -> (Int64, Int64) {
        (Int64((lat / cellDegrees).rounded(.down)), Int64((lon / cellDegrees).rounded(.down)))
    }

    func bucketKey(lat: Double, lon: Double) -> Int64 {
        let c = cell(lat, lon)
        return c.0 &* 100_000 &+ c.1
    }

    mutating func add(_ stay: Stay) {
        cells[bucketKey(lat: stay.latitude, lon: stay.longitude), default: []].append(stay)
    }

    func nearest(to stay: Stay, within radius: CLLocationDistance) -> Stay? {
        let c = cell(stay.latitude, stay.longitude)
        var best: (Stay, CLLocationDistance)?
        var countries = Set<String>()
        for dy in -1...1 {
            for dx in -1...1 {
                let k = (c.0 + Int64(dy)) &* 100_000 &+ (c.1 + Int64(dx))
                for other in cells[k] ?? [] {
                    let d = other.location.distance(from: stay.location)
                    guard d <= radius else { continue }
                    if let code = other.countryCode { countries.insert(code) }
                    if d < (best?.1 ?? .infinity) { best = (other, d) }
                }
            }
        }
        return countries.count > 1 ? nil : best?.0
    }
}
