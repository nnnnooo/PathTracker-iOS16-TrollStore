import Foundation
import CoreLocation
import Photos

enum PhotoFootprints {
    static let source = "photos"

    struct Shot: Equatable, Sendable {
        var date: Date
        var latitude: Double
        var longitude: Double
        var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    }

    struct Visit: Equatable, Sendable {
        var start: Date
        var end: Date
        var latitude: Double
        var longitude: Double
        var shots: Int
        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    }

    struct Known: Sendable {
        var arrival: Date
        var departure: Date
        var latitude: Double
        var longitude: Double
    }

    struct Summary: Equatable, Sendable {
        var scanned = 0
        var withLocation = 0
        var visits = 0
        var skippedAlreadyRecorded = 0
    }

    static var authorization: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    static func visits(from shots: [Shot], radius: CLLocationDistance = 500, calendar: Calendar = .current) -> [Visit] {
        var result: [Visit] = []
        var current: (shots: [Shot], anchor: CLLocation)?
        func close() {
            guard let group = current?.shots, let first = group.first, let last = group.last else { return }
            let lat = group.map(\.latitude).reduce(0, +) / Double(group.count)
            let lon = group.map(\.longitude).reduce(0, +) / Double(group.count)
            result.append(Visit(start: first.date, end: last.date, latitude: lat, longitude: lon, shots: group.count))
            current = nil
        }
        for shot in shots.sorted(by: { $0.date < $1.date }) {
            if let c = current, calendar.isDate(c.shots[0].date, inSameDayAs: shot.date),
               shot.location.distance(from: c.anchor) <= radius {
                current?.shots.append(shot)
            } else {
                close()
                current = ([shot], shot.location)
            }
        }
        close()
        return result
    }

    static func shotsInLibrary(progress: @Sendable (Int, Int) -> Void) -> (shots: [Shot], scanned: Int) {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                        PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(with: options)
        var shots: [Shot] = []
        shots.reserveCapacity(assets.count)
        for index in 0..<assets.count {
            let asset = assets.object(at: index)
            if let location = asset.location, let date = asset.creationDate,
               CLLocationCoordinate2DIsValid(location.coordinate),
               location.coordinate.latitude != 0 || location.coordinate.longitude != 0 {
                shots.append(Shot(date: date, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
            }
            if index % 400 == 0 { progress(index, assets.count) }
        }
        progress(assets.count, assets.count)
        return (shots, assets.count)
    }

    static func newVisits(_ visits: [Visit], recorded: [Known], imported: [Known]) -> (new: [Visit], skipped: Int) {
        let byArrival = recorded.sorted { $0.arrival < $1.arrival }
        let longest = byArrival.map { $0.departure.timeIntervalSince($0.arrival) }.max() ?? 0
        var importedStarts: [Int: [Known]] = [:]
        for known in imported { importedStarts[Int(known.arrival.timeIntervalSince1970), default: []].append(known) }
        let calendar = Calendar.current
        let importedByDay = Dictionary(grouping: imported) { calendar.startOfDay(for: $0.arrival) }

        var fresh: [Visit] = []
        var skipped = 0
        for visit in visits {
            let place = CLLocation(latitude: visit.latitude, longitude: visit.longitude)
            let from = visit.start.addingTimeInterval(-1800 - longest)
            let to = visit.end.addingTimeInterval(1800)
            var low = 0, high = byArrival.count
            while low < high {
                let mid = (low + high) / 2
                if byArrival[mid].arrival < from { low = mid + 1 } else { high = mid }
            }
            var covered = false
            var i = low
            while i < byArrival.count, byArrival[i].arrival <= to {
                let stay = byArrival[i]
                if stay.departure >= visit.start.addingTimeInterval(-1800),
                   CLLocation(latitude: stay.latitude, longitude: stay.longitude).distance(from: place) < 400 {
                    covered = true
                    break
                }
                i += 1
            }
            if covered { skipped += 1; continue }
            let second = Int(visit.start.timeIntervalSince1970)
            let seen = (second - 1...second + 1).contains { key in
                importedStarts[key]?.contains {
                    CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: place) < 50
                } ?? false
            }
            let merged = !seen && importedByDay[calendar.startOfDay(for: visit.start)]?.contains { known in
                known.arrival.addingTimeInterval(-60) <= visit.start && visit.start <= known.departure.addingTimeInterval(60)
                    && CLLocation(latitude: known.latitude, longitude: known.longitude).distance(from: place) < 40_000
            } == true
            if !seen && !merged { fresh.append(visit) }
        }
        return (fresh, skipped)
    }

    @MainActor
    static func importLibrary(
        into store: DataStore,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async -> Summary {
        let snapshot = store.stays.map {
            (Known(arrival: $0.arrival, departure: max($0.departure ?? Date(), $0.arrival),
                   latitude: $0.latitude, longitude: $0.longitude), $0.isFromPhotos)
        }
        let recorded = snapshot.filter { !$0.1 }.map(\.0)
        let imported = snapshot.filter(\.1).map(\.0) + DeletedPhotoVisits.all

        let found = await Task.detached(priority: .userInitiated) {
            let library = shotsInLibrary(progress: progress)
            let grouped = visits(from: library.shots)
            let result = newVisits(grouped, recorded: recorded, imported: imported)
            return (library.scanned, library.shots.count, result.new, result.skipped)
        }.value

        let newStays = found.2.map { visit in
            Stay(
                arrival: visit.start,
                departure: max(visit.end, visit.start.addingTimeInterval(60)),
                coordinate: visit.coordinate,
                sampleCount: visit.shots,
                sourceRaw: source
            )
        }
        store.insertStaysBatch(newStays)
        return Summary(scanned: found.0, withLocation: found.1, visits: newStays.count, skippedAlreadyRecorded: found.3)
    }

    @MainActor
    static func consolidate(in store: DataStore) async -> Int {
        let calendar = Calendar.current
        let editable = store.stays.filter {
            $0.isFromPhotos && $0.tagState == .tagged && $0.customName == nil && ($0.note ?? "").isEmpty && $0.city != nil
        }
        let groups = Dictionary(grouping: editable) {
            "\(calendar.startOfDay(for: $0.arrival).timeIntervalSince1970)|\($0.countryCode ?? "")|\($0.city ?? "")"
        }
        var updated: [Stay] = []
        var removedIDs = Set<UUID>()
        for members in groups.values where members.count > 1 {
            let sorted = members.sorted { $0.arrival < $1.arrival }
            var keep = sorted[0]
            keep.departure = sorted.compactMap(\.departure).max() ?? keep.departure
            keep.sampleCount = sorted.reduce(0) { $0 + max($1.sampleCount, 1) }
            updated.append(keep)
            for extra in sorted.dropFirst() { removedIDs.insert(extra.id) }
        }
        if !updated.isEmpty { store.updateStaysBatch(updated) }
        if !removedIDs.isEmpty { store.deleteStays(ids: removedIDs) }
        return removedIDs.count
    }
}

enum DeletedPhotoVisits {
    private static let key = "wt16.photoImport.deleted"
    private static let limit = 3000

    static var all: [PhotoFootprints.Known] {
        stored.compactMap { row in
            guard row.count == 4 else { return nil }
            return PhotoFootprints.Known(
                arrival: Date(timeIntervalSince1970: row[0]),
                departure: Date(timeIntervalSince1970: row[1]),
                latitude: row[2],
                longitude: row[3]
            )
        }
    }

    static func remember(_ stay: Stay) {
        guard stay.isFromPhotos else { return }
        let row = [
            stay.arrival.timeIntervalSince1970,
            max(stay.departure ?? stay.arrival, stay.arrival).timeIntervalSince1970,
            stay.latitude,
            stay.longitude
        ]
        let rows = Array((stored + [row]).suffix(limit))
        UserDefaults.standard.set(rows, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static var stored: [[Double]] {
        UserDefaults.standard.array(forKey: key) as? [[Double]] ?? []
    }
}
