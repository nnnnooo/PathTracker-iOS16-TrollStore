import Foundation
import SQLite3
import CoreLocation

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
final class DataStore: ObservableObject {
    @Published private(set) var chunks: [TrackChunk] = []
    @Published private(set) var stays: [Stay] = []
    @Published private(set) var trips: [Trip] = []
    @Published private(set) var privacyZones: [PrivacyZone] = []

    private var db: OpaquePointer?
    let dbURL: URL

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
            trip_id TEXT,
            points_data BLOB NOT NULL
        );
        """)
        // Safe migration for existing MVP databases
        execute("ALTER TABLE track_chunks ADD COLUMN trip_id TEXT;")
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

        execute("""
        CREATE TABLE IF NOT EXISTS trips (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            start_date REAL NOT NULL,
            end_date REAL,
            notes TEXT NOT NULL,
            cover_emoji TEXT NOT NULL,
            activity_raw TEXT
        );
        """)
        execute("CREATE INDEX IF NOT EXISTS idx_trips_start ON trips(start_date);")

        execute("""
        CREATE TABLE IF NOT EXISTS privacy_zones (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            radius REAL NOT NULL
        );
        """)
    }

    private func execute(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    func reloadAll() {
        self.chunks = fetchAllChunksFromDB()
        self.stays = fetchAllStaysFromDB()
        self.trips = fetchAllTripsFromDB()
        self.privacyZones = fetchAllPrivacyZonesFromDB()
    }

    // MARK: - Backup & Restore

    func exportBackupFile() -> URL? {
        execute("PRAGMA wal_checkpoint(TRUNCATE);")
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("Waytrace16-Backup.sqlite")
        try? FileManager.default.removeItem(at: target)
        do {
            try FileManager.default.copyItem(at: dbURL, to: target)
            return target
        } catch {
            return nil
        }
    }

    func restoreBackup(from sourceURL: URL) -> Bool {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
        let walURL = URL(fileURLWithPath: dbURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: dbURL.path + "-shm")
        try? FileManager.default.removeItem(at: walURL)
        try? FileManager.default.removeItem(at: shmURL)
        do {
            try? FileManager.default.removeItem(at: dbURL)
            try FileManager.default.copyItem(at: sourceURL, to: dbURL)
            openDatabase()
            createTables()
            reloadAll()
            return true
        } catch {
            openDatabase()
            createTables()
            reloadAll()
            return false
        }
    }

    // MARK: - TrackChunk CRUD

    func insertChunk(_ chunk: TrackChunk) {
        guard let db else { return }
        let sql = """
        INSERT OR REPLACE INTO track_chunks
        (id, start_date, end_date, distance, point_count, min_lat, max_lat, min_lon, max_lon, mode_raw, trip_id, points_data)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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
        bindOptionalText(stmt, 11, chunk.tripID?.uuidString)
        _ = chunk.pointsData.withUnsafeBytes { raw in
            sqlite3_bind_blob(stmt, 12, raw.baseAddress, Int32(chunk.pointsData.count), SQLITE_TRANSIENT)
        }
        sqlite3_step(stmt)

        if let idx = chunks.firstIndex(where: { $0.id == chunk.id }) {
            chunks[idx] = chunk
        } else {
            chunks.append(chunk)
            chunks.sort { $0.startDate < $1.startDate }
        }
    }

    func insertChunksBatch(_ newChunks: [TrackChunk]) {
        guard let db, !newChunks.isEmpty else { return }
        let sql = """
        INSERT OR REPLACE INTO track_chunks
        (id, start_date, end_date, distance, point_count, min_lat, max_lat, min_lon, max_lon, mode_raw, trip_id, points_data)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        execute("BEGIN TRANSACTION;")
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            for chunk in newChunks {
                sqlite3_reset(stmt)
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
                bindOptionalText(stmt, 11, chunk.tripID?.uuidString)
                _ = chunk.pointsData.withUnsafeBytes { raw in
                    sqlite3_bind_blob(stmt, 12, raw.baseAddress, Int32(chunk.pointsData.count), SQLITE_TRANSIENT)
                }
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
        execute("COMMIT;")

        var map = Dictionary(uniqueKeysWithValues: chunks.map { ($0.id, $0) })
        for chunk in newChunks { map[chunk.id] = chunk }
        chunks = map.values.sorted { $0.startDate < $1.startDate }
    }

    func updateChunkMode(id: UUID, mode: MovementMode) {
        guard var chunk = chunks.first(where: { $0.id == id }) else { return }
        chunk.modeRaw = mode.rawValue
        insertChunk(chunk)
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

    // MARK: - Stay CRUD

    func upsertStay(_ stay: Stay, notify: Bool = true) {
        guard let db else { return }
        writeStayRow(stay, db: db)
        if let idx = stays.firstIndex(where: { $0.id == stay.id }) {
            stays[idx] = stay
        } else {
            stays.append(stay)
            if notify { stays.sort { $0.arrival > $1.arrival } }
        }
    }

    func insertStaysBatch(_ newStays: [Stay]) {
        guard let db, !newStays.isEmpty else { return }
        execute("BEGIN TRANSACTION;")
        for stay in newStays { writeStayRow(stay, db: db) }
        execute("COMMIT;")
        stays.append(contentsOf: newStays)
        stays.sort { $0.arrival > $1.arrival }
    }

    func updateStaysBatch(_ updated: [Stay]) {
        guard let db, !updated.isEmpty else { return }
        execute("BEGIN TRANSACTION;")
        for stay in updated { writeStayRow(stay, db: db) }
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
        for existing in stays where ids.contains(existing.id) && existing.isFromPhotos {
            DeletedPhotoVisits.remember(existing)
        }
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

    // MARK: - Trip CRUD

    func upsertTrip(_ trip: Trip) {
        guard let db else { return }
        let sql = """
        INSERT OR REPLACE INTO trips (id, title, start_date, end_date, notes, cover_emoji, activity_raw)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        bindText(stmt, 1, trip.id.uuidString)
        bindText(stmt, 2, trip.title)
        sqlite3_bind_double(stmt, 3, trip.startDate.timeIntervalSince1970)
        if let end = trip.endDate {
            sqlite3_bind_double(stmt, 4, end.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        bindText(stmt, 5, trip.notes)
        bindText(stmt, 6, trip.coverEmoji)
        bindOptionalText(stmt, 7, trip.activityRaw)
        sqlite3_step(stmt)

        if let idx = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[idx] = trip
        } else {
            trips.append(trip)
            trips.sort { $0.startDate > $1.startDate }
        }
    }

    func deleteTrip(id: UUID) {
        guard let db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM trips WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, id.uuidString)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        trips.removeAll { $0.id == id }
    }

    func chunks(for trip: Trip) -> [TrackChunk] {
        if trip.isRecording {
            let direct = chunks.filter { $0.tripID == trip.id }
            if !direct.isEmpty { return direct }
        }
        let end = trip.endDate ?? Date()
        return chunks.filter { $0.endDate >= trip.startDate && $0.startDate <= end }
    }

    func stays(for trip: Trip) -> [Stay] {
        let end = trip.endDate ?? Date()
        return stays.filter { ($0.departure ?? Date()) >= trip.startDate && $0.arrival <= end }
            .sorted { $0.arrival < $1.arrival }
    }

    // MARK: - PrivacyZone CRUD

    func upsertPrivacyZone(_ zone: PrivacyZone) {
        guard let db else { return }
        let sql = "INSERT OR REPLACE INTO privacy_zones (id, name, latitude, longitude, radius) VALUES (?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, zone.id.uuidString)
        bindText(stmt, 2, zone.name)
        sqlite3_bind_double(stmt, 3, zone.latitude)
        sqlite3_bind_double(stmt, 4, zone.longitude)
        sqlite3_bind_double(stmt, 5, zone.radius)
        sqlite3_step(stmt)

        if let idx = privacyZones.firstIndex(where: { $0.id == zone.id }) {
            privacyZones[idx] = zone
        } else {
            privacyZones.append(zone)
        }
    }

    func deletePrivacyZone(id: UUID) {
        guard let db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM privacy_zones WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, id.uuidString)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        privacyZones.removeAll { $0.id == id }
    }

    func privacyZone(containing coord: CLLocationCoordinate2D) -> PrivacyZone? {
        privacyZones.first { $0.contains(coord) }
    }

    func isCoordinatePrivate(_ coord: CLLocationCoordinate2D) -> Bool {
        privacyZones.contains { $0.contains(coord) }
    }

    func deleteAllData() {
        execute("DELETE FROM track_chunks;")
        execute("DELETE FROM stays;")
        execute("DELETE FROM trips;")
        execute("DELETE FROM privacy_zones;")
        DeletedPhotoVisits.clear()
        chunks = []
        stays = []
        trips = []
        privacyZones = []
    }

    // MARK: - Queries

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

    func renameNearby(_ stay: Stay, to name: String?, categoryRaw: String?, note: String? = nil) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let radius: CLLocationDistance = 150
        var changed: [Stay] = []
        for var other in stays where other.location.distance(from: stay.location) <= radius {
            other.customName = trimmed
            if let categoryRaw {
                other.categoryRaw = categoryRaw
                other.isLandmark = (categoryRaw == "sight")
            }
            if other.id == stay.id {
                other.note = trimmedNote
            }
            changed.append(other)
        }
        updateStaysBatch(changed)
    }

    // MARK: - SQLite Helpers

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
        let sql = "SELECT id, start_date, end_date, distance, point_count, min_lat, max_lat, min_lon, max_lon, mode_raw, trip_id, points_data FROM track_chunks ORDER BY start_date ASC;"
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
            let tripID = columnText(stmt, 10).flatMap(UUID.init)
            let bytes = sqlite3_column_blob(stmt, 11)
            let length = Int(sqlite3_column_bytes(stmt, 11))
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
                tripID: tripID,
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

    private func fetchAllTripsFromDB() -> [Trip] {
        guard let db else { return [] }
        var result: [Trip] = []
        var stmt: OpaquePointer?
        let sql = "SELECT id, title, start_date, end_date, notes, cover_emoji, activity_raw FROM trips ORDER BY start_date DESC;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = columnText(stmt, 0), let id = UUID(uuidString: idStr) else { continue }
            let title = columnText(stmt, 1) ?? "未命名旅程"
            let startDate = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
            let endDate: Date? = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
            let notes = columnText(stmt, 4) ?? ""
            let emoji = columnText(stmt, 5) ?? "🧭"
            let activityRaw = columnText(stmt, 6)
            result.append(Trip(id: id, title: title, startDate: startDate, endDate: endDate, notes: notes, coverEmoji: emoji, activityRaw: activityRaw))
        }
        return result
    }

    private func fetchAllPrivacyZonesFromDB() -> [PrivacyZone] {
        guard let db else { return [] }
        var result: [PrivacyZone] = []
        var stmt: OpaquePointer?
        let sql = "SELECT id, name, latitude, longitude, radius FROM privacy_zones;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = columnText(stmt, 0), let id = UUID(uuidString: idStr) else { continue }
            let name = columnText(stmt, 1) ?? "隐私区域"
            let lat = sqlite3_column_double(stmt, 2)
            let lon = sqlite3_column_double(stmt, 3)
            let radius = sqlite3_column_double(stmt, 4)
            result.append(PrivacyZone(id: id, name: name, latitude: lat, longitude: lon, radius: radius))
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
