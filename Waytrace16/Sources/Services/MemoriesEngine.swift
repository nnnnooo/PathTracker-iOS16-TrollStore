import Foundation
import CoreLocation

/// Computes "On This Day" (那年今日) and "Reunion" (重逢) moments from local stays.
enum MemoriesEngine {
    struct OnThisDayMemory: Identifiable {
        let id: UUID
        let yearsAgo: Int
        let year: Int
        let stay: Stay
    }

    struct ReunionMoment: Identifiable {
        let id: UUID
        let placeName: String
        let lastVisitDate: Date
        let daysSinceLastVisit: Int
        let totalVisits: Int
    }

    /// Finds stays on the same month & day from previous years.
    static func onThisDay(date: Date = Date(), stays: [Stay]) -> [OnThisDayMemory] {
        let cal = Calendar.current
        let target = cal.dateComponents([.year, .month, .day], from: date)
        guard let curYear = target.year, let month = target.month, let day = target.day else { return [] }

        var byYear: [Int: Stay] = [:]
        for stay in stays {
            let c = cal.dateComponents([.year, .month, .day], from: stay.arrival)
            guard let y = c.year, y < curYear, c.month == month, c.day == day else { continue }
            // Pick the longest or named stay for that year
            if let existing = byYear[y] {
                if stay.duration > existing.duration { byYear[y] = stay }
            } else {
                byYear[y] = stay
            }
        }

        return byYear.map { year, stay in
            OnThisDayMemory(id: stay.id, yearsAgo: curYear - year, year: year, stay: stay)
        }.sorted { $0.year > $1.year }
    }

    /// Detects if any stay today is a "Reunion" — returning to a spot after >= 365 days away.
    static func reunion(todayStays: [Stay], allStays: [Stay]) -> ReunionMoment? {
        for todayStay in todayStays.reversed() {
            // Skip home/work routine spots
            if todayStay.category == .home || todayStay.category == .work { continue }

            let earlier = allStays.filter { other in
                other.id != todayStay.id &&
                other.arrival < todayStay.arrival.addingTimeInterval(-86_400) &&
                other.location.distance(from: todayStay.location) <= 200
            }.sorted { $0.arrival > $1.arrival }

            guard let lastVisit = earlier.first else { continue }
            let daysGap = Int(todayStay.arrival.timeIntervalSince(lastVisit.arrival) / 86_400)
            if daysGap >= 365 {
                return ReunionMoment(
                    id: todayStay.id,
                    placeName: todayStay.displayName,
                    lastVisitDate: lastVisit.arrival,
                    daysSinceLastVisit: daysGap,
                    totalVisits: earlier.count + 1
                )
            }
        }
        return nil
    }
}
