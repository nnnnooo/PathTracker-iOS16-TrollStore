import Foundation
import SwiftUI
import UIKit
import Vision
import UserNotifications

enum VisaDocumentKind: String, CaseIterable, Codable, Identifiable, Hashable {
    case passport
    case visa
    case eVisa

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passport: return "护照"
        case .visa: return "签证"
        case .eVisa: return "电子签"
        }
    }
}

enum VisaEntries: String, CaseIterable, Codable, Identifiable, Hashable {
    case single = "一次"
    case double = "两次"
    case multiple = "多次"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "单次", "一次", "single": self = .single
        case "两次", "double": self = .double
        default: self = .multiple
        }
    }
}

struct VisaRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: VisaDocumentKind
    var countryCode: String
    var countryName: String
    var visaType: String
    var visaNumber: String
    var holder: String
    var issuingPost: String
    var entries: VisaEntries
    var stayDays: Int?
    var issuedDate: Date?
    var expiryDate: Date
    var addedDate: Date
    var notes: String

    // Backward-compatible computed bridges
    var maxStayDays: Int {
        get { stayDays ?? 90 }
        set { stayDays = newValue }
    }

    var issueDate: Date {
        get { issuedDate ?? addedDate }
        set { issuedDate = newValue }
    }

    init(
        id: UUID = UUID(),
        kind: VisaDocumentKind = .visa,
        countryCode: String = "US",
        countryName: String = "美国",
        visaType: String = "",
        visaNumber: String = "",
        holder: String = "",
        issuingPost: String = "",
        entries: VisaEntries = .multiple,
        stayDays: Int? = nil,
        issuedDate: Date? = nil,
        expiryDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date(),
        addedDate: Date = Date(),
        notes: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.countryCode = countryCode
        self.countryName = countryName
        self.visaType = visaType
        self.visaNumber = visaNumber
        self.holder = holder
        self.issuingPost = issuingPost
        self.entries = entries
        self.stayDays = stayDays
        self.issuedDate = issuedDate
        self.expiryDate = expiryDate
        self.addedDate = addedDate
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, countryCode, countryName, visaType, visaNumber, holder, issuingPost
        case entries, stayDays, maxStayDays, issuedDate, issueDate, expiryDate, addedDate, notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.kind = try c.decodeIfPresent(VisaDocumentKind.self, forKey: .kind) ?? .visa
        self.countryCode = try c.decodeIfPresent(String.self, forKey: .countryCode) ?? "US"
        self.countryName = try c.decodeIfPresent(String.self, forKey: .countryName)
            ?? VisaCatalog.localizedName(for: self.countryCode)
        self.visaType = try c.decodeIfPresent(String.self, forKey: .visaType) ?? ""
        self.visaNumber = try c.decodeIfPresent(String.self, forKey: .visaNumber) ?? ""
        self.holder = try c.decodeIfPresent(String.self, forKey: .holder) ?? ""
        self.issuingPost = try c.decodeIfPresent(String.self, forKey: .issuingPost) ?? ""
        self.entries = try c.decodeIfPresent(VisaEntries.self, forKey: .entries) ?? .multiple
        if let s = try c.decodeIfPresent(Int.self, forKey: .stayDays) {
            self.stayDays = s
        } else if let legacy = try c.decodeIfPresent(Int.self, forKey: .maxStayDays), legacy > 0 {
            self.stayDays = legacy
        } else {
            self.stayDays = nil
        }
        if let issued = try c.decodeIfPresent(Date.self, forKey: .issuedDate) {
            self.issuedDate = issued
        } else {
            self.issuedDate = try c.decodeIfPresent(Date.self, forKey: .issueDate)
        }
        self.expiryDate = try c.decodeIfPresent(Date.self, forKey: .expiryDate)
            ?? (Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date())
        self.addedDate = try c.decodeIfPresent(Date.self, forKey: .addedDate) ?? Date()
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(countryCode, forKey: .countryCode)
        try c.encode(countryName, forKey: .countryName)
        try c.encode(visaType, forKey: .visaType)
        try c.encode(visaNumber, forKey: .visaNumber)
        try c.encode(holder, forKey: .holder)
        try c.encode(issuingPost, forKey: .issuingPost)
        try c.encode(entries, forKey: .entries)
        try c.encodeIfPresent(stayDays, forKey: .stayDays)
        try c.encodeIfPresent(issuedDate, forKey: .issuedDate)
        try c.encode(expiryDate, forKey: .expiryDate)
        try c.encode(addedDate, forKey: .addedDate)
        try c.encode(notes, forKey: .notes)
    }

    var remainingDays: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let exp = cal.startOfDay(for: expiryDate)
        return cal.dateComponents([.day], from: today, to: exp).day ?? 0
    }

    var isExpired: Bool { remainingDays < 0 }

    var isExpiringSoon: Bool {
        guard !isExpired else { return false }
        return remainingDays < (kind == .passport ? 183 : 90)
    }

    var isSchengen: Bool {
        kind != .passport && (countryCode == VisaCatalog.schengenCode || VisaCatalog.schengenCodes.contains(countryCode))
    }

    var flag: String {
        if countryCode == VisaCatalog.schengenCode { return "🇪🇺" }
        return CountryText.flag(for: countryCode)
    }

    var englishName: String {
        if countryCode == VisaCatalog.schengenCode { return "SCHENGEN" }
        return (Locale(identifier: "en_US").localizedString(forRegionCode: countryCode) ?? countryCode).uppercased()
    }

    var validityProgress: Double {
        let start = issuedDate ?? addedDate
        let total = max(1, expiryDate.timeIntervalSince(start))
        let remaining = max(0, expiryDate.timeIntervalSince(Date()))
        return min(1.0, remaining / total)
    }
}

enum VisaCatalog {
    static let schengenCode = "EU"

    static let schengenCodes: Set<String> = [
        "AT", "BE", "BG", "HR", "CZ", "DK", "EE", "FI", "FR", "DE",
        "GR", "HU", "IS", "IT", "LV", "LI", "LT", "LU", "MT", "NL",
        "NO", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "CH"
    ]

    static let presets: [(code: String, name: String)] = [
        ("EU", "申根区"),
        ("CN", "中国"),
        ("US", "美国"),
        ("JP", "日本"),
        ("CA", "加拿大"),
        ("GB", "英国"),
        ("AU", "澳大利亚"),
        ("NZ", "新西兰"),
        ("KR", "韩国"),
        ("SG", "新加坡"),
        ("TH", "泰国"),
        ("MY", "马来西亚"),
        ("VN", "越南"),
        ("ID", "印度尼西亚"),
        ("PH", "菲律宾"),
        ("FR", "法国"),
        ("DE", "德国"),
        ("IT", "意大利"),
        ("ES", "西班牙"),
        ("CH", "瑞士"),
        ("NL", "荷兰"),
        ("AT", "奥地利"),
        ("GR", "希腊"),
        ("SE", "瑞典"),
        ("NO", "挪威"),
        ("FI", "芬兰"),
        ("IS", "冰岛"),
        ("TR", "土耳其"),
        ("AE", "阿联酋"),
        ("RU", "俄罗斯"),
        ("BR", "巴西"),
        ("MX", "墨西哥"),
        ("AR", "阿根廷"),
        ("ZA", "南非"),
        ("EG", "埃及"),
        ("HK", "中国香港"),
        ("MO", "中国澳门"),
        ("TW", "中国台湾")
    ]

    static func localizedName(for code: String) -> String {
        if code == schengenCode { return "申根区" }
        if let found = presets.first(where: { $0.code == code }) { return found.name }
        return CountryText.localizedName(code: code)
    }

    static let iso2ToIso3: [String: String] = [
        "CN": "CHN", "US": "USA", "JP": "JPN", "GB": "GBR", "CA": "CAN",
        "AU": "AUS", "NZ": "NZL", "KR": "KOR", "SG": "SGP", "TH": "THA",
        "MY": "MYS", "VN": "VNM", "ID": "IDN", "PH": "PHL", "FR": "FRA",
        "DE": "DEU", "IT": "ITA", "ES": "ESP", "CH": "CHE", "NL": "NLD",
        "AT": "AUT", "GR": "GRC", "SE": "SWE", "NO": "NOR", "FI": "FIN",
        "IS": "ISL", "TR": "TUR", "AE": "ARE", "RU": "RUS", "BR": "BRA",
        "MX": "MEX", "AR": "ARG", "ZA": "ZAF", "EG": "EGY", "HK": "HKG",
        "MO": "MAC", "TW": "TWN", "EU": "EUE"
    ]

    static let iso3ToIso2: [String: (code: String, name: String)] = {
        var map: [String: (String, String)] = [
            "D<<": ("DE", "德国"),
            "EUE": ("EU", "申根区")
        ]
        for (iso2, iso3) in iso2ToIso3 {
            map[iso3] = (iso2, localizedName(for: iso2))
        }
        return map
    }()

    static func alpha3(_ code: String) -> String {
        iso2ToIso3[code.uppercased()] ?? String((code.uppercased() + "<<<").prefix(3))
    }

    static func mrzCheckDigit(_ text: String) -> Int {
        let weights = [7, 3, 1]
        var sum = 0
        for (idx, ch) in text.uppercased().enumerated() {
            let val: Int
            if let digit = ch.wholeNumberValue {
                val = digit
            } else if let ascii = ch.asciiValue, ascii >= 65 && ascii <= 90 {
                val = Int(ascii) - 55
            } else {
                val = 0
            }
            sum += val * weights[idx % 3]
        }
        return sum % 10
    }

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
        let start = visa.issuedDate ?? .distantPast
        let matching = stays.filter { stay in
            guard let code = stay.countryCode else { return false }
            let countryMatch = visa.isSchengen ? schengenCodes.contains(code) : (code == visa.countryCode)
            return countryMatch && stay.arrival >= start && stay.arrival <= visa.expiryDate
        }.sorted { $0.arrival < $1.arrival }

        guard !matching.isEmpty else { return (0, 0) }
        var days = Set<Date>()
        var entries = 0
        var lastEnd: Date?
        for stay in matching {
            if let prev = lastEnd, stay.arrival.timeIntervalSince(prev) > 2 * 86_400 {
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

/// Parses ICAO 9303 MRZ lines from passports and visas, and supports local Vision OCR on photos.
enum MRZParser {
    struct Parsed: Sendable {
        var isPassport: Bool
        var countryCode: String
        var countryName: String
        var visaNumber: String
        var holder: String
        var expiryDate: Date?
        var verified: Bool
    }

    static func parse(lines: [String]) -> Parsed? {
        let cleaned = lines
            .map { $0.uppercased().replacingOccurrences(of: " ", with: "") }
            .filter { $0.count >= 28 }

        guard let line1 = cleaned.first(where: {
            $0.hasPrefix("V<") || $0.hasPrefix("VN") || $0.hasPrefix("VA") || $0.hasPrefix("VC") || $0.hasPrefix("P<")
        }) else {
            return nil
        }

        let isPassport = line1.hasPrefix("P<")
        let iso3 = String(line1.dropFirst(2).prefix(3))
        let mapped = VisaCatalog.iso3ToIso2[iso3] ?? (String(iso3.prefix(2)), VisaCatalog.localizedName(for: String(iso3.prefix(2))))

        // Parse holder name from line1 after index 5 (SURNAME<<GIVEN<NAME<<<)
        let nameRaw = String(line1.dropFirst(5))
        let nameParts = nameRaw.components(separatedBy: "<<")
        let surname = (nameParts.first ?? "").replacingOccurrences(of: "<", with: " ").trimmingCharacters(in: .whitespaces)
        let given = (nameParts.count > 1 ? nameParts[1] : "").replacingOccurrences(of: "<", with: " ").trimmingCharacters(in: .whitespaces)
        let holder = [surname, given].filter { !$0.isEmpty }.joined(separator: " ")

        var docNumber = ""
        var expiry: Date?
        var verified = false

        if let line2 = cleaned.first(where: { $0 != line1 && $0.count >= 27 }) {
            docNumber = String(line2.prefix(9)).replacingOccurrences(of: "<", with: "")
            if line2.count >= 27 {
                let start = line2.index(line2.startIndex, offsetBy: 21)
                let end = line2.index(start, offsetBy: 6)
                let yymmdd = String(line2[start..<end])
                expiry = parseYYMMDD(yymmdd)
                if line2.count >= 28 {
                    let checkChar = line2[end]
                    if let digit = checkChar.wholeNumberValue, digit == VisaCatalog.mrzCheckDigit(yymmdd) {
                        verified = true
                    }
                }
            }
        }

        return Parsed(
            isPassport: isPassport,
            countryCode: mapped.0,
            countryName: mapped.1,
            visaNumber: docNumber,
            holder: holder,
            expiryDate: expiry,
            verified: verified
        )
    }

    /// Runs local Vision text recognition on a user-selected photo to extract MRZ fields.
    static func recognize(image: UIImage) async -> Parsed? {
        guard let cgImage = image.cgImage else { return nil }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return parse(lines: lines)
        }.value
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

    var passport: VisaRecord? {
        visas.first { $0.kind == .passport }
    }

    /// Valid passport first, then valid visas by soonest expiry, then expired cards.
    var sorted: [VisaRecord] {
        visas.sorted { a, b in
            if a.isExpired != b.isExpired { return !a.isExpired }
            if a.kind == .passport && b.kind != .passport { return true }
            if b.kind == .passport && a.kind != .passport { return false }
            return a.expiryDate < b.expiryDate
        }
    }

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
        visas = decoded
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

        let leads = visa.kind == .passport ? [180, 90, 30, 7] : [90, 30, 7]
        for leadDays in leads {
            guard let fireDate = Calendar.current.date(byAdding: .day, value: -leadDays, to: visa.expiryDate),
                  fireDate > Date() else { continue }
            let content = UNMutableNotificationContent()
            if visa.kind == .passport {
                content.title = "护照即将到期"
                content.body = "你的\(visa.countryName)护照将在 \(leadDays) 天后到期，很多国家要求入境时护照剩余有效期超过 6 个月。"
            } else {
                content.title = "\(visa.countryName)签证即将到期"
                content.body = "你的\(visa.countryName)（\(visa.visaType.nilIfEmpty ?? "签证")）将在 \(leadDays) 天后到期，请提前安排续签或行程。"
            }
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: "visa.\(visa.id.uuidString).\(leadDays)", content: content, trigger: trigger)
            center.add(req)
        }
    }

    private func cancelReminders(for id: UUID) {
        let ids = [180, 90, 30, 7].map { "visa.\(id.uuidString).\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
