import Foundation
import SwiftUI
import UserNotifications

enum VisaEntries: String, CaseIterable, Codable, Identifiable {
    case single = "单次"
    case double = "两次"
    case multiple = "多次"
    var id: String { rawValue }
}

struct VisaRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var countryCode: String
    var countryName: String
    var visaType: String
    var visaNumber: String
    var issuingPost: String
    var entries: VisaEntries
    var maxStayDays: Int
    var issueDate: Date
    var expiryDate: Date
    var notes: String

    init(
        id: UUID = UUID(),
        countryCode: String = "US",
        countryName: String = "美国",
        visaType: String = "B1/B2 旅游商务",
        visaNumber: String = "",
        issuingPost: String = "",
        entries: VisaEntries = .multiple,
        maxStayDays: Int = 90,
        issueDate: Date = Date(),
        expiryDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date(),
        notes: String = ""
    ) {
        self.id = id
        self.countryCode = countryCode
        self.countryName = countryName
        self.visaType = visaType
        self.visaNumber = visaNumber
        self.issuingPost = issuingPost
        self.entries = entries
        self.maxStayDays = maxStayDays
        self.issueDate = issueDate
        self.expiryDate = expiryDate
        self.notes = notes
    }

    var remainingDays: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let exp = cal.startOfDay(for: expiryDate)
        return cal.dateComponents([.day], from: today, to: exp).day ?? 0
    }

    var isExpired: Bool { remainingDays < 0 }

    var isSchengen: Bool {
        countryCode == "EU" || VisaCatalog.schengenCodes.contains(countryCode)
    }

    var validityProgress: Double {
        let total = max(1, expiryDate.timeIntervalSince(issueDate))
        let remaining = max(0, expiryDate.timeIntervalSince(Date()))
        return min(1.0, remaining / total)
    }

    var cardColors: [Color] {
        switch countryCode {
        case "US": return [Color(red: 0.10, green: 0.21, blue: 0.42), Color(red: 0.18, green: 0.34, blue: 0.58)]
        case "EU", "FR", "DE", "IT", "ES", "CH", "NL", "AT", "GR":
            return [Color(red: 0.08, green: 0.22, blue: 0.52), Color(red: 0.16, green: 0.38, blue: 0.65)]
        case "JP": return [Color(red: 0.58, green: 0.42, blue: 0.24), Color(red: 0.74, green: 0.57, blue: 0.35)]
        case "GB": return [Color(red: 0.36, green: 0.10, blue: 0.18), Color(red: 0.54, green: 0.18, blue: 0.28)]
        case "AU", "NZ": return [Color(red: 0.09, green: 0.34, blue: 0.32), Color(red: 0.16, green: 0.48, blue: 0.44)]
        case "CA": return [Color(red: 0.56, green: 0.14, blue: 0.14), Color(red: 0.72, green: 0.24, blue: 0.22)]
        case "KR": return [Color(red: 0.14, green: 0.26, blue: 0.46), Color(red: 0.28, green: 0.40, blue: 0.62)]
        default: return [Color(red: 0.18, green: 0.22, blue: 0.28), Color(red: 0.30, green: 0.35, blue: 0.42)]
        }
    }

    var headerLabel: String {
        switch countryCode {
        case "US": return "UNITED STATES OF AMERICA · VISA"
        case "EU", "FR", "DE", "IT", "ES", "CH", "NL", "AT", "GR": return "SCHENGEN STATES · VALID FOR"
        case "JP": return "査証 · JAPAN VISA"
        case "AU", "NZ": return "ELECTRONIC VISA GRANT NOTICE"
        default: return "\(countryCode) · VISA"
        }
    }
}

enum VisaCatalog {
    static let schengenCodes: Set<String> = [
        "AT", "BE", "BG", "HR", "CZ", "DK", "EE", "FI", "FR", "DE",
        "GR", "HU", "IS", "IT", "LV", "LI", "LT", "LU", "MT", "NL",
        "NO", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "CH"
    ]

    static let presets: [(code: String, name: String)] = [
        ("US", "美国"),
        ("EU", "申根区"),
        ("JP", "日本"),
        ("GB", "英国"),
        ("CA", "加拿大"),
        ("AU", "澳大利亚"),
        ("NZ", "新西兰"),
        ("KR", "韩国"),
        ("SG", "新加坡"),
        ("TH", "泰国"),
        ("FR", "法国"),
        ("DE", "德国"),
        ("IT", "意大利"),
        ("ES", "西班牙"),
        ("CH", "瑞士")
    ]

    static let iso3ToIso2: [String: (code: String, name: String)] = [
        "USA": ("US", "美国"),
        "JPN": ("JP", "日本"),
        "GBR": ("GB", "英国"),
        "CAN": ("CA", "加拿大"),
        "AUS": ("AU", "澳大利亚"),
        "NZL": ("NZ", "新西兰"),
        "KOR": ("KR", "韩国"),
        "SGP": ("SG", "新加坡"),
        "THA": ("TH", "泰国"),
        "FRA": ("FR", "法国"),
        "DEU": ("DE", "德国"),
        "D<<": ("DE", "德国"),
        "ITA": ("IT", "意大利"),
        "ESP": ("ES", "西班牙"),
        "CHE": ("CH", "瑞士"),
        "NLD": ("NL", "荷兰"),
        "AUT": ("AT", "奥地利"),
        "GRC": ("GR", "希腊")
    ]

    /// Calculates Schengen 90/180 rolling window days used from recorded/imported Stays.
    static func schengenUsedDays(stays: [Stay], asOf date: Date = Date()) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: date)
        guard let windowStart = cal.date(byAdding: .day, value: -179, to: today) else { return 0 }
        var days = Set<Date>()
        for stay in stays {
            guard let code = stay.countryCode, schengenCodes.contains(code) else { continue }
            let dep = stay.departure ?? stay.arrival
            var cursor = max(cal.startOfDay(for: stay.arrival), windowStart)
            let end = min(cal.startOfDay(for: dep), today)
            while cursor <= end {
                days.insert(cursor)
                guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }
        return days.count
    }

    static func usageStats(for visa: VisaRecord, stays: [Stay]) -> (entries: Int, days: Int) {
        let cal = Calendar.current
        let matching = stays.filter { stay in
            guard let code = stay.countryCode else { return false }
            let countryMatch = visa.isSchengen ? schengenCodes.contains(code) : (code == visa.countryCode)
            return countryMatch && stay.arrival >= visa.issueDate && stay.arrival <= visa.expiryDate
        }.sorted { $0.arrival < $1.arrival }

        guard !matching.isEmpty else { return (0, 0) }
        var days = Set<Date>()
        var entries = 0
        var lastEnd: Date?
        for stay in matching {
            if let prev = lastEnd, stay.arrival.timeIntervalSince(prev) > 3 * 86_400 {
                entries += 1
            } else if lastEnd == nil {
                entries = 1
            }
            let dep = stay.departure ?? stay.arrival
            lastEnd = max(lastEnd ?? dep, dep)
            days.insert(cal.startOfDay(for: stay.arrival))
        }
        return (entries, days.count)
    }
}

/// Parses ICAO 9303 MRZ lines from visas (e.g. V<USA... / Line 2 with visa number & YYMMDD expiry).
enum MRZParser {
    struct Parsed {
        var countryCode: String
        var countryName: String
        var visaNumber: String
        var expiryDate: Date?
    }

    static func parse(lines: [String]) -> Parsed? {
        let cleaned = lines
            .map { $0.uppercased().replacingOccurrences(of: " ", with: "") }
            .filter { $0.count >= 28 }

        guard let line1 = cleaned.first(where: { $0.hasPrefix("V<") || $0.hasPrefix("VN") || $0.hasPrefix("VA") }) else {
            return nil
        }

        let iso3 = String(line1.dropFirst(2).prefix(3))
        let mapped = VisaCatalog.iso3ToIso2[iso3] ?? (String(iso3.prefix(2)), iso3)

        var visaNumber = ""
        var expiry: Date?

        if let line2 = cleaned.first(where: { $0 != line1 && $0.count >= 27 }) {
            visaNumber = String(line2.prefix(9)).replacingOccurrences(of: "<", with: "")
            // Standard MRV-A / MRV-B expiry date sits at index 21..26 (YYMMDD)
            if line2.count >= 27 {
                let start = line2.index(line2.startIndex, offsetBy: 21)
                let end = line2.index(start, offsetBy: 6)
                let yymmdd = String(line2[start..<end])
                expiry = parseYYMMDD(yymmdd)
            }
        }

        return Parsed(countryCode: mapped.0, countryName: mapped.1, visaNumber: visaNumber, expiryDate: expiry)
    }

    private static func parseYYMMDD(_ s: String) -> Date? {
        guard s.count == 6,
              let yy = Int(s.prefix(2)),
              let mm = Int(s.dropFirst(2).prefix(2)),
              let dd = Int(s.dropFirst(4).prefix(2)),
              (1...12).contains(mm), (1...31).contains(dd) else { return nil }
        var comps = DateComponents()
        comps.year = 2000 + yy
        comps.month = mm
        comps.day = dd
        return Calendar(identifier: .gregorian).date(from: comps)
    }
}

@MainActor
final class VisaStore: ObservableObject {
    static let shared = VisaStore()

    @Published private(set) var visas: [VisaRecord] = []

    private let fileURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        self.fileURL = support.appendingPathComponent("visas-v16.json")
        load()
    }

    func upsert(_ visa: VisaRecord) {
        if let idx = visas.firstIndex(where: { $0.id == visa.id }) {
            visas[idx] = visa
        } else {
            visas.insert(visa, at: 0)
        }
        visas.sort { $0.expiryDate > $1.expiryDate }
        save()
        scheduleReminders(for: visa)
    }

    func delete(id: UUID) {
        visas.removeAll { $0.id == id }
        save()
        cancelReminders(for: id)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([VisaRecord].self, from: data) else { return }
        visas = decoded.sorted { $0.expiryDate > $1.expiryDate }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(visas) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func scheduleReminders(for visa: VisaRecord) {
        cancelReminders(for: visa.id)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        for leadDays in [90, 30, 7] {
            guard let fireDate = Calendar.current.date(byAdding: .day, value: -leadDays, to: visa.expiryDate),
                  fireDate > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(visa.countryName)签证即将到期"
            content.body = "你的\(visa.countryName)（\(visa.visaType)）将在 \(leadDays) 天后到期，请提前安排续签或行程。"
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: "visa.\(visa.id.uuidString).\(leadDays)", content: content, trigger: trigger)
            center.add(req)
        }
    }

    private func cancelReminders(for id: UUID) {
        let ids = [90, 30, 7].map { "visa.\(id.uuidString).\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
