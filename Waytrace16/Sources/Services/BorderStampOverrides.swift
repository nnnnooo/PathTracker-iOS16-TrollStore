import Foundation
import Combine

// MARK: - Persistent User Overrides for Passport Entry / Exit Stamps

struct BorderStampRecord: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var isEntry: Bool
    var countryCode: String
    var date: Date
    var port: String
    var byAir: Bool
    var days: Int

    func toPassportStamp() -> PassportStamp {
        PassportStamp(
            id: id,
            kind: isEntry ? .entry : .exit,
            date: date,
            countryCode: countryCode,
            port: port.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            byAir: byAir,
            days: isEntry ? 0 : max(1, days)
        )
    }

    static func from(_ stamp: PassportStamp) -> BorderStampRecord {
        BorderStampRecord(
            id: stamp.id,
            isEntry: stamp.kind == .entry,
            countryCode: stamp.countryCode ?? "CN",
            date: stamp.date,
            port: stamp.port ?? "",
            byAir: stamp.byAir,
            days: stamp.days
        )
    }
}

struct BorderStampOverridePayload: Codable, Sendable {
    var hiddenAutoIDs: Set<String> = []
    var editedAuto: [String: BorderStampRecord] = [:]
    var manualStamps: [BorderStampRecord] = []
}

enum BorderStampOverrides {
    private static let key = "wt16.passport.borderOverrides.v1"
    private static let lock = NSLock()

    static func load() -> BorderStampOverridePayload {
        lock.lock()
        defer { lock.unlock() }
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(BorderStampOverridePayload.self, from: data) else {
            return BorderStampOverridePayload()
        }
        return decoded
    }

    static func save(_ payload: BorderStampOverridePayload) {
        lock.lock()
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: key)
        }
        lock.unlock()
        DispatchQueue.main.async {
            BorderStampOverrideStore.shared.bump()
        }
    }

    static func apply(to autoStamps: [PassportStamp]) -> [PassportStamp] {
        let overrides = load()
        var result: [PassportStamp] = []
        result.reserveCapacity(autoStamps.count + overrides.manualStamps.count)

        for stamp in autoStamps {
            if overrides.hiddenAutoIDs.contains(stamp.id) { continue }
            if let edited = overrides.editedAuto[stamp.id] {
                var merged = edited.toPassportStamp()
                merged.latitude = stamp.latitude
                merged.longitude = stamp.longitude
                result.append(merged)
            } else {
                result.append(stamp)
            }
        }

        for manual in overrides.manualStamps {
            result.append(manual.toPassportStamp())
        }

        return result.sorted { a, b in
            if a.date != b.date { return a.date < b.date }
            if a.kind != b.kind { return a.kind == .entry }
            return a.id < b.id
        }
    }
}

@MainActor
final class BorderStampOverrideStore: ObservableObject {
    static let shared = BorderStampOverrideStore()

    @Published private(set) var revision: Int = 0
    @Published private(set) var payload: BorderStampOverridePayload

    private init() {
        self.payload = BorderStampOverrides.load()
    }

    func bump() {
        payload = BorderStampOverrides.load()
        revision &+= 1
    }

    func isManual(id: String) -> Bool {
        id.hasPrefix("manual.")
    }

    func isEditedAuto(id: String) -> Bool {
        payload.editedAuto[id] != nil
    }

    var hasAnyOverrides: Bool {
        !payload.hiddenAutoIDs.isEmpty || !payload.editedAuto.isEmpty || !payload.manualStamps.isEmpty
    }

    func deleteStamp(id: String) {
        var next = BorderStampOverrides.load()
        if isManual(id: id) {
            next.manualStamps.removeAll { $0.id == id }
        } else {
            next.hiddenAutoIDs.insert(id)
            next.editedAuto.removeValue(forKey: id)
        }
        BorderStampOverrides.save(next)
    }

    func saveStamp(_ record: BorderStampRecord) {
        var next = BorderStampOverrides.load()
        if isManual(id: record.id) {
            if let idx = next.manualStamps.firstIndex(where: { $0.id == record.id }) {
                next.manualStamps[idx] = record
            } else {
                next.manualStamps.append(record)
            }
        } else {
            next.hiddenAutoIDs.remove(record.id)
            next.editedAuto[record.id] = record
        }
        BorderStampOverrides.save(next)
    }

    func addManualStamp(isEntry: Bool, countryCode: String, date: Date, port: String, byAir: Bool, days: Int) {
        let record = BorderStampRecord(
            id: "manual.\(UUID().uuidString)",
            isEntry: isEntry,
            countryCode: countryCode,
            date: date,
            port: port,
            byAir: byAir,
            days: isEntry ? 0 : max(1, days)
        )
        saveStamp(record)
    }

    func resetAutoOverrides() {
        var next = BorderStampOverrides.load()
        next.hiddenAutoIDs.removeAll()
        next.editedAuto.removeAll()
        BorderStampOverrides.save(next)
    }
}
