import Foundation
import SQLite3
import CoreLocation

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
final class DataStore: ObservableObject {
    @Published private(set) var chunks: [TrackChunk] = []
    @Published private(set) var stays: [Stay] = []

    private var db: OpaquePointer?
    private let dbURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        self.dbURL = support.appendingPathComponent("waytrace16.sqlite")
        openDatabase()
        createTables()
        reloadAll()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    private func openDatabase() {
        if sqlite3_open(dbURL.path, &db) == SQLITE_OK {
            execute("PRAGMA journal_mode=WAL;")
            execute("PRAGMA synchronous=NORMAL;")
        }
    }

    private func createTables() {
        execute("""
        CREATE TABLE IF NOT EXISTS track_chunks (
            id TEXT PRIMARY KEY,
            start_date REAL NOT NULL,
            end_date REAL NOT NULL,
            distance REAL NOT NULL,
            point_count INTEGER NOT NULL,
            min_lat REAL NOT NULL,
            max_lat REAL NOT NULL,
            min_lon REAL NOT NULL,
            max_lon REAL NOT NULL,
            mode_raw TEXT NOT NULL,
            points_data BLOB NOT NULL
        );
        """)
        execute("CREATE INDEX IF NOT EXISTS idx_chunks_start ON track_chunks(start_date);")

        execute("""
        CREATE TABLE IF NOT EXISTS stays (
            id TEXT PRIMARY KEY,
            arrival REAL NOT NULL,
            departure REAL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            sample_count INTEGER NOT NULL,
            place_name TEXT,
            category_raw TEXT,
            street TEXT,
            city TEXT,
            region TEXT,
            country TEXT,
            country_code TEXT,
            is_landmark INTEGER NOT NULL,
            tag_state_raw INTEGER NOT NULL,
            custom_name TEXT,
            note TEXT,
            source_raw TEXT,
            time_zone_id TEXT
        );
        """)
        execute("CREATE INDEX IF NOT EXISTS idx_stays_arrival ON stays(arrival);")
    }

    private func execute(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    func reloadAll() {
        self.chunks = fetchAllChunksFromDB()
        self.stays = fetchAllStaysFromDB()
    }

    func insertChunk(_ chunk: TrackChunk) {
        guard let db else { return }
        let sql = """
        INSERT OR REPLACE INTO track_chunks
        (id, start_date, end_date, distance, point_count, min_lat, max_lat, min_lon, max_lon, mode_raw, points_data)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        bindText(stmt, 1, chunk.id.uuidString)
        sqlite3_bind_double(stmt, 2, chunk.startDate.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 3, chunk.endDate.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 4, chunk.distance)
        sqlite3_bind_int(stmt, 5, Int32(chunk.pointCount))
        sqlite3_bind_double(stmt, 6, chunk.minLatitude)
        sqlite3_bind_double(stmt, 7, chunk.maxLatitude)
        sqlite3_bind_double(stmt, 8, chunk.minLongitude)
        sqlite3_bind_double(stmt, 9, chunk.maxLongitude)
        bindText(stmt, 10, chunk.modeRaw)
        chunk.pointsData.withUnsafeBytes { raw in
            sqlite3_bind_blob(stmt, 11, raw.baseAddress, Int32(chunk.pointsData.count), SQLITE_TRANSIENT)
        }
        sqlite3_step(stmt)

        if let idx = chunks.firstIndex(where: { $0.id == chunk.id }) {
            chunks[idx] = chunk
        } else {
            chunks.append(chunk)
            chunks.sort { $0.startDate < $1.startDate }
        }
    }

    func deleteChunk(id: UUID) {
        guard let db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM track_chunks WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, id.uuidString)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        chunks.removeAll { $0.id == id }
    }

    func upsertStay(_ stay: Stay, notify: Bool = true) {
        guard let db else { return }
        writeStayRow(stay, db: db)
        if let idx = stays.firstIndex(where: { $0.id == stay.id }) {
            stays[idx] = stay
        } else {
            stays.append(stay)
            if notify {
                stays.sort { $0.arrival > $1.arrival }
            }
        }
    }

    func insertStaysBatch(_ newStays: [Stay]) {
        guard let db, !newStays.isEmpty else { return }
        execute("BEGIN TRANSACTION;")
        for stay in newStays {
            writeStayRow(stay, db: db)
        }
        execute("COMMIT;")
        stays.append(contentsOf: newStays)
        stays.sort { $0.arrival > $1.arrival }
    }

    func updateStaysBatch(_ updated: [Stay]) {
        guard let db, !updated.isEmpty else { return }
        execute("BEGIN TRANSACTION;")
        for stay in updated {
            writeStayRow(stay, db: db)
        }
        execute("COMMIT;")
        var map = Dictionary(uniqueKeysWithValues: stays.map { ($0.id, $0) })
        for stay in updated { map[stay.id] = stay }
        stays = map.values.sorted { $0.arrival > $1.arrival }
    }

    func deleteStay(id: UUID) {
        guard let db else { return }
        if let existing = stays.first(where: { $0.id == id }), existing.isFromPhotos {
            DeletedPhotoVisits.remember(existing)
        }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM stays WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, id.uuidString)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        stays.removeAll { $0.id == id }
    }

    func deleteStays(ids: Set<UUID>) {
        guard let db, !ids.isEmpty else { return }
        execute("BEGIN TRANSACTION;")
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM stays WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK {
            for id in ids {
                sqlite3_reset(stmt)
                bindText(stmt, 1, id.uuidString)
                sqlite3_step(stmt)
            }
        }
        sqlite3_finalize(stmt)
        execute("COMMIT;")
        stays.removeAll { ids.contains($0.id) }
    }

    func deleteAllData() {
        execute("DELETE FROM track_chunks;")
        execute("DELETE FROM stays;")
        DeletedPhotoVisits.clear()
        chunks = []
        stays = []
    }

    func chunks(on day: Date) -> [TrackChunk] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return chunks.filter { $0.endDate >= start && $0.startDate < end }
    }

    func stays(on day: Date) -> [Stay] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return stays.filter { stay in
            let dep = stay.departure ?? Date()
            return dep >= start && stay.arrival < end
        }.sorted { $0.arrival < $1.arrival }
    }

    var recordedDaysCount: Int {
        let cal = Calendar.current
        var days = Set<Date>()
        for stay in stays { days.insert(cal.startOfDay(for: stay.arrival)) }
        for chunk in chunks { days.insert(cal.startOfDay(for: chunk.startDate)) }
        return days.count
    }

    var totalDistance: Double {
        chunks.reduce(0) { $0 + $1.distance }
    }

    func applyKnownName(to stay: inout Stay) {
        let radius: CLLocationDistance = 150
        let named = stays.filter { $0.customName != nil }
        if let match = named.min(by: { $0.location.distance(from: stay.location) < $1.location.distance(from: stay.location) }),
           match.location.distance(from: stay.location) <= radius {
            stay.customName = match.customName
            if let raw = match.categoryRaw, PlaceCategory.chosenRawValues.contains(raw) {
                stay.categoryRaw = raw
            }
        }
    }

    func renameNearby(_ stay: Stay, to name: String?, categoryRaw: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let radius: CLLocationDistance = 150
        var changed: [Stay] = []
        for var other in stays where other.location.distance(from: stay.location) <= radius {
            other.customName = trimmed
            if let categoryRaw {
                other.categoryRaw = categoryRaw
                other.isLandmark = (categoryRaw == "sight")
            }
            changed.append(other)
        }
        updateStaysBatch(changed)
    }

    private func writeStayRow(_ stay: Stay, db: OpaquePointer) {
        let sql = """
        INSERT OR REPLACE INTO stays
        (id, arrival, departure, latitude, longitude, sample_count, place_name, category_raw,
         street, city, region, country, country_code, is_landmark, tag_state_raw,
         custom_name, note, source_raw, time_zone_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        bindText(stmt, 1, stay.id.uuidString)
        sqlite3_bind_double(stmt, 2, stay.arrival.timeIntervalSince1970)
        if let dep = stay.departure {
            sqlite3_bind_double(stmt, 3, dep.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        sqlite3_bind_double(stmt, 4, stay.latitude)
        sqlite3_bind_double(stmt, 5, stay.longitude)
        sqlite3_bind_int(stmt, 6, Int32(stay.sampleCount))
        bindOptionalText(stmt, 7, stay.placeName)
        bindOptionalText(stmt, 8, stay.categoryRaw)
        bindOptionalText(stmt, 9, stay.street)
        bindOptionalText(stmt, 10, stay.city)
        bindOptionalText(stmt, 11, stay.region)
        bindOptionalText(stmt, 12, stay.country)
        bindOptionalText(stmt, 13, stay.countryCode)
        sqlite3_bind_int(stmt, 14, stay.isLandmark ? 1 : 0)
        sqlite3_bind_int(stmt, 15, Int32(stay.tagStateRaw))
        bindOptionalText(stmt, 16, stay.customName)
        bindOptionalText(stmt, 17, stay.note)
        bindOptionalText(stmt, 18, stay.sourceRaw)
        bindOptionalText(stmt, 19, stay.timeZoneID)

        sqlite3_step(stmt)
    }

    private func fetchAllChunksFromDB() -> [TrackChunk] {
        guard let db else { return [] }
        var result: [TrackChunk] = []
        var stmt: OpaquePointer?
        let sql = "SELECT id, start_date, end_date, distance, point_count, min_lat, max_lat, min_lon, max_lon, mode_raw, points_data FROM track_chunks ORDER BY start_date ASC;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = columnText(stmt, 0), let id = UUID(uuidString: idStr) else { continue }
            let startDate = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            let endDate = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
            let distance = sqlite3_column_double(stmt, 3)
            let pointCount = Int(sqlite3_column_int(stmt, 4))
            let minLat = sqlite3_column_double(stmt, 5)
            let maxLat = sqlite3_column_double(stmt, 6)
            let minLon = sqlite3_column_double(stmt, 7)
            let maxLon = sqlite3_column_double(stmt, 8)
            let modeRaw = columnText(stmt, 9) ?? MovementMode.unknown.rawValue
            let bytes = sqlite3_column_blob(stmt, 10)
            let length = Int(sqlite3_column_bytes(stmt, 10))
            let data = bytes.map { Data(bytes: $0, count: length) } ?? Data()

            result.append(TrackChunk(
                id: id,
                startDate: startDate,
                endDate: endDate,
                distance: distance,
                pointCount: pointCount,
                minLatitude: minLat,
                maxLatitude: maxLat,
                minLongitude: minLon,
                maxLongitude: maxLon,
                modeRaw: modeRaw,
                pointsData: data
            ))
        }
        return result
    }

    private func fetchAllStaysFromDB() -> [Stay] {
        guard let db else { return [] }
        var result: [Stay] = []
        var stmt: OpaquePointer?
        let sql = """
        SELECT id, arrival, departure, latitude, longitude, sample_count, place_name, category_raw,
               street, city, region, country, country_code, is_landmark, tag_state_raw,
               custom_name, note, source_raw, time_zone_id
        FROM stays ORDER BY arrival DESC;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = columnText(stmt, 0), let id = UUID(uuidString: idStr) else { continue }
            let arrival = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            let departure: Date? = sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
            let lat = sqlite3_column_double(stmt, 3)
            let lon = sqlite3_column_double(stmt, 4)
            let sampleCount = Int(sqlite3_column_int(stmt, 5))

            var stay = Stay(
                id: id,
                arrival: arrival,
                departure: departure,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                sampleCount: sampleCount
            )
            stay.placeName = columnText(stmt, 6)
            stay.categoryRaw = columnText(stmt, 7)
            stay.street = columnText(stmt, 8)
            stay.city = columnText(stmt, 9)
            stay.region = columnText(stmt, 10)
            stay.country = columnText(stmt, 11)
            stay.countryCode = columnText(stmt, 12)
            stay.isLandmark = sqlite3_column_int(stmt, 13) != 0
            stay.tagStateRaw = Int(sqlite3_column_int(stmt, 14))
            stay.customName = columnText(stmt, 15)
            stay.note = columnText(stmt, 16)
            stay.sourceRaw = columnText(stmt, 17)
            stay.timeZoneID = columnText(stmt, 18)
            result.append(stay)
        }
        return result
    }

    private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String) {
        sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT)
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: cStr)
    }
}
