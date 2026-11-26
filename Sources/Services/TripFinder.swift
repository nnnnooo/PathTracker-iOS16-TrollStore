import Foundation
import CoreLocation

/// Automatically discovers multi-day trips from recorded & photo-imported Stays
/// when the user stays >= 80 km away from their primary home city.
enum TripFinder {
    struct DiscoveredTrip: Identifiable, Hashable {
        var id: String { "\(Int(startDate.timeIntervalSince1970))-\(Int(endDate.timeIntervalSince1970))" }
        var title: String
        var startDate: Date
        var endDate: Date
        var cities: [String]
        var countries: [String]
        var stayCount: Int

        var days: Int {
            max(1, (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: startDate), to: Calendar.current.startOfDay(for: endDate)).day ?? 0) + 1)
        }
    }

    static func discover(from stays: [Stay], existingTrips: [Trip]) -> [DiscoveredTrip] {
        guard stays.count >= 2 else { return [] }
        guard let home = estimateHomeCoordinate(from: stays) else { return [] }

        let homeLoc = CLLocation(latitude: home.latitude, longitude: home.longitude)
        let awayStays = stays
            .filter { $0.location.distance(from: homeLoc) >= 80_000 }
            .sorted { $0.arrival < $1.arrival }

        guard !awayStays.isEmpty else { return [] }

        var groups: [[Stay]] = []
        var current: [Stay] = [awayStays[0]]

        for stay in awayStays.dropFirst() {
            let prev = current.last!
            let prevEnd = prev.departure ?? prev.arrival
            let gap = stay.arrival.timeIntervalSince(prevEnd)
            let dist = stay.location.distance(from: prev.location)
            // Break if gap > 36 hours or single-day jump > 5000 km
            if gap <= 36 * 3600 && dist < 5_000_000 {
                current.append(stay)
            } else {
                groups.append(current)
                current = [stay]
            }
        }
        groups.append(current)

        let cal = Calendar.current
        var results: [DiscoveredTrip] = []

        for group in groups {
            guard let first = group.first, let last = group.last else { continue }
            let start = cal.startOfDay(for: first.arrival)
            let endRaw = last.departure ?? last.arrival
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: endRaw)) ?? endRaw

            let daySpan = (cal.dateComponents([.day], from: start, to: end).day ?? 1)
            // Multi-day trip or at least 2 distinct stays away from home
            guard daySpan >= 2 || group.count >= 2 else { continue }

            // Skip if already covered by an existing saved Trip
            let alreadySaved = existingTrips.contains { trip in
                !trip.isRecording &&
                trip.startDate <= end && (trip.endDate ?? Date()) >= start
            }
            if alreadySaved { continue }

            let cities = group.compactMap(\.city).removingDuplicates()
            let countries = group.compactMap(\.country).removingDuplicates()
            let title: String
            if cities.count == 1, let c = cities.first {
                title = "\(c)之旅"
            } else if countries.count == 1, let country = countries.first, cities.count > 1 {
                title = "\(cities.prefix(2).joined(separator: "·"))"
                if title.isEmpty { _ = country }
            } else if let country = countries.first {
                title = "\(country)之旅"
            } else {
                title = "\(Formatters.dayTitle(start))出行"
            }

            results.append(DiscoveredTrip(
                title: title,
                startDate: start,
                endDate: end,
                cities: cities,
                countries: countries,
                stayCount: group.count
            ))
        }

        return results.sorted { $0.startDate > $1.startDate }
    }

    private static func estimateHomeCoordinate(from stays: [Stay]) -> CLLocationCoordinate2D? {
        // Group stays into ~20 km grid cells and pick the most frequent cell as home
        var buckets: [String: [Stay]] = [:]
        for stay in stays {
            let key = "\(Int((stay.latitude * 5).rounded()))_\(Int((stay.longitude * 5).rounded()))"
            buckets[key, default: []].append(stay)
        }
        guard let top = buckets.values.max(by: { $0.count < $1.count }), !top.isEmpty else { return nil }
        let lat = top.map(\.latitude).reduce(0, +) / Double(top.count)
        let lon = top.map(\.longitude).reduce(0, +) / Double(top.count)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
