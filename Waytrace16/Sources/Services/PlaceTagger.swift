import Foundation
import CoreLocation
import MapKit

@MainActor
final class PlaceTagger: ObservableObject {
    @Published private(set) var isTagging = false
    @Published private(set) var pendingCount = 0

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
        let recordedPending = store.stays.filter { $0.tagState == .pending && !$0.isFromPhotos }
        for var stay in recordedPending.prefix(80) {
            let ok = await tagSingle(&stay, lookupPOI: true)
            store.upsertStay(stay)
            pendingCount = store.stays.filter { $0.tagState == .pending }.count
            if !ok { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }

        let photoPending = store.stays.filter { $0.tagState == .pending && $0.isFromPhotos }
        guard !photoPending.isEmpty else { return }

        var grid = PhotoGrid()
        for stay in store.stays where stay.tagState == .tagged && stay.countryCode != nil {
            grid.add(stay)
        }

        var batchCopied: [Stay] = []
        var needGeocode: [Stay] = []

        for var stay in photoPending {
            if let neighbour = grid.nearest(to: stay, within: 3_000) {
                stay.country = neighbour.country
                stay.countryCode = neighbour.countryCode
                stay.city = neighbour.city
                stay.region = neighbour.region
                stay.timeZoneID = neighbour.timeZoneID
                stay.tagState = .tagged
                batchCopied.append(stay)
            } else {
                needGeocode.append(stay)
            }
        }
        if !batchCopied.isEmpty { store.updateStaysBatch(batchCopied) }

        var geocodedBatch: [Stay] = []
        for var stay in needGeocode {
            if let neighbour = grid.nearest(to: stay, within: 3_000) {
                stay.country = neighbour.country
                stay.countryCode = neighbour.countryCode
                stay.city = neighbour.city
                stay.region = neighbour.region
                stay.timeZoneID = neighbour.timeZoneID
                stay.tagState = .tagged
                geocodedBatch.append(stay)
                continue
            }
            let ok = await tagSingle(&stay, lookupPOI: false)
            if stay.countryCode != nil { grid.add(stay) }
            geocodedBatch.append(stay)
            if geocodedBatch.count >= 8 {
                store.updateStaysBatch(geocodedBatch)
                geocodedBatch.removeAll()
                pendingCount = store.stays.filter { $0.tagState == .pending }.count
            }
            if !ok { break }
            try? await Task.sleep(nanoseconds: 1_400_000_000)
        }
        if !geocodedBatch.isEmpty { store.updateStaysBatch(geocodedBatch) }
        _ = await PhotoFootprints.consolidate(in: store)
    }

    private func tagSingle(_ stay: inout Stay, lookupPOI: Bool) async -> Bool {
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
        } catch let error as CLError where error.code == .network {
            return false
        } catch {
            stay.tagState = .failed
            return true
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
        return true
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

private struct PhotoGrid {
    private var cells: [Int64: [Stay]] = [:]
    private let size = 0.03

    private func cell(_ lat: Double, _ lon: Double) -> (Int64, Int64) {
        (Int64((lat / size).rounded(.down)), Int64((lon / size).rounded(.down)))
    }

    private func key(_ c: (Int64, Int64)) -> Int64 { c.0 &* 100_000 &+ c.1 }

    mutating func add(_ stay: Stay) {
        cells[key(cell(stay.latitude, stay.longitude)), default: []].append(stay)
    }

    func nearest(to stay: Stay, within radius: CLLocationDistance) -> Stay? {
        let c = cell(stay.latitude, stay.longitude)
        var best: (Stay, CLLocationDistance)?
        var countries = Set<String>()
        for dy in -1...1 {
            for dx in -1...1 {
                for other in cells[key((c.0 + Int64(dy), c.1 + Int64(dx)))] ?? [] {
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
