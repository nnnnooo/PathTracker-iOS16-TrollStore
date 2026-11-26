import Foundation
import CoreLocation
import UIKit
import UserNotifications

@MainActor
final class LocationEngine: ObservableObject {
    enum Activity: Equatable {
        case off, starting, moving, stationary, unavailable

        var title: String {
            switch self {
            case .off: return "未开启自动记录"
            case .starting: return "正在获取定位…"
            case .moving: return "正在记录轨迹"
            case .stationary: return "静止休眠中"
            case .unavailable: return "缺少定位权限"
            }
        }
    }

    enum Precision: String, CaseIterable, Identifiable {
        case battery, balanced, precise
        var id: String { rawValue }

        var title: String {
            switch self {
            case .battery: return "省电"
            case .balanced: return "均衡"
            case .precise: return "精细"
            }
        }

        var subtitle: String {
            switch self {
            case .battery: return "仅用系统到访与显著位置变化，几乎不耗电（类似 Rond）"
            case .balanced: return "移动时记录完整路线，停留满 10 分钟关 GPS 换 150 米地理围栏"
            case .precise: return "高精度连续定位，路线最贴合街道，适合徒步与骑行"
            }
        }
    }

    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var isPreciseLocation = true
    @Published private(set) var activity: Activity = .off
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var pendingPoints: [TrackPoint] = []
    @Published private(set) var openStay: Stay?
    @Published private(set) var pausedUntil: Date?
    @Published private(set) var activeTripID: UUID?

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            guard activeTripID == nil else { return }
            isEnabled ? start() : stop()
        }
    }

    @Published var precision: Precision {
        didSet {
            UserDefaults.standard.set(precision.rawValue, forKey: Keys.precision)
            if activeTripID == nil, isRecording { restart() }
        }
    }

    var isPaused: Bool { pausedUntil.map { $0 > Date() } ?? false }
    var isPausedIndefinitely: Bool { pausedUntil == .distantFuture }
    var isRecording: Bool { (isEnabled && !isPaused) || activeTripID != nil }
    var hasAlwaysPermission: Bool { authorization == .authorizedAlways }
    var hasAnyPermission: Bool { authorization == .authorizedAlways || authorization == .authorizedWhenInUse }

    var activeTrip: Trip? {
        guard let id = activeTripID else { return nil }
        return store.trips.first { $0.id == id && $0.endDate == nil }
    }

    private let store: DataStore
    private let tagger: PlaceTagger
    private let classifier = MotionClassifier()
    private let manager = CLLocationManager()
    private let delegate = LocationDelegate()

    private var anchor: (location: CLLocation, since: Date, latSum: Double, lonSum: Double, count: Int)?
    private var lastAcceptedLocation: CLLocation?
    private var rejectedJumps = 0
    private var dwellTask: Task<Void, Never>?
    private var resumeTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var isSettled = false
    private var isUpdatingGPS = false

    private static let fenceID = "waytrace16.stay.fence"

    private enum Keys {
        static let enabled = "wt16.tracking.enabled"
        static let precision = "wt16.tracking.precision"
        static let pausedUntil = "wt16.tracking.pausedUntil"
        static let alwaysRequested = "wt16.location.alwaysRequested"
        static let activeTripID = "wt16.tracking.activeTripID"
    }

    private enum Tuning {
        static let maxAccuracy: CLLocationAccuracy = 65
        static let coarseAccuracy: CLLocationAccuracy = 250
        static let minStepDistance: CLLocationDistance = 8
        static let stayRadius: CLLocationDistance = 120
        static let stayMinimumDwell: TimeInterval = 5 * 60
        static let stayMinimumDuration: TimeInterval = 3 * 60
        static let stayMergeGap: TimeInterval = 15 * 60
        static let chunkMaxPoints = 400
        static let chunkMaxDuration: TimeInterval = 20 * 60
        static let gapBreak: TimeInterval = 10 * 60
        static let maxGroundSpeed: CLLocationSpeed = 75
        static let settleAfter: TimeInterval = 10 * 60
        static let fenceRadius: CLLocationDistance = 150
        static let flightDistance: CLLocationDistance = 150_000
        static let flightSpeed: CLLocationSpeed = 50
        static let cruiseSpeed: CLLocationSpeed = 230
        static let groundTime: TimeInterval = 40 * 60
        static let gapDistance: CLLocationDistance = 1_000
        static let gapSilence: TimeInterval = 3 * 60
        static let drivingSpeed: CLLocationSpeed = 7
    }

    init(store: DataStore, tagger: PlaceTagger) {
        self.store = store
        self.tagger = tagger
        self.authorization = manager.authorizationStatus
        self.isPreciseLocation = manager.accuracyAuthorization == .fullAccuracy
        self.isEnabled = UserDefaults.standard.bool(forKey: Keys.enabled)
        self.activeTripID = UserDefaults.standard.string(forKey: Keys.activeTripID).flatMap(UUID.init)
        self.precision = Precision(rawValue: UserDefaults.standard.string(forKey: Keys.precision) ?? "") ?? .balanced
        let paused = UserDefaults.standard.object(forKey: Keys.pausedUntil) as? Date
        self.pausedUntil = paused.flatMap { $0 > Date() ? $0 : nil }

        manager.delegate = delegate
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true
        manager.showsBackgroundLocationIndicator = false

        delegate.onAuthChange = { [weak self] m in
            Task { @MainActor in self?.authorizationChanged(m) }
        }
        delegate.onLocations = { [weak self] locations in
            Task { @MainActor in self?.handleLocations(locations) }
        }
        delegate.onVisit = { [weak self] visit in
            Task { @MainActor in self?.handleVisit(visit) }
        }
        delegate.onExitRegion = { [weak self] region in
            Task { @MainActor in
                if region.identifier == Self.fenceID { self?.leftFence() }
            }
        }
        delegate.onPauseUpdates = { [weak self] in
            Task { @MainActor in self?.handleSystemPause() }
        }

        if isPaused { schedulePauseEnd() }
        pendingPoints = PendingTrackStore.load()
        restoreOpenStay()
        validateActiveTrip()

        if isRecording { start() } else { releaseAllMonitoring() }
    }

    // MARK: - Manual High-Precision Recording

    @discardableResult
    func beginRecording(activity: ActivityType, title: String) -> Trip {
        flushChunk(carryOver: true)
        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "\(activity.title) · \(Formatters.dayTitle(Date()))"
        let trip = Trip(
            title: finalTitle,
            startDate: Date(),
            endDate: nil,
            notes: "",
            coverEmoji: activity.emoji,
            activityRaw: activity.rawValue
        )
        store.upsertTrip(trip)
        activeTripID = trip.id
        UserDefaults.standard.set(trip.id.uuidString, forKey: Keys.activeTripID)
        start()
        return trip
    }

    func endActiveRecording() {
        guard var trip = activeTrip else {
            activeTripID = nil
            UserDefaults.standard.removeObject(forKey: Keys.activeTripID)
            return
        }
        flushChunk(carryOver: true)
        trip.endDate = Date()
        store.upsertTrip(trip)
        activeTripID = nil
        UserDefaults.standard.removeObject(forKey: Keys.activeTripID)
        if isRecording { restart() } else { stop() }
    }

    private func validateActiveTrip() {
        guard let id = activeTripID else { return }
        if !store.trips.contains(where: { $0.id == id && $0.endDate == nil }) {
            activeTripID = nil
            UserDefaults.standard.removeObject(forKey: Keys.activeTripID)
        }
    }

    // MARK: - Permissions

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }

    func requestAlways() {
        if UserDefaults.standard.bool(forKey: Keys.alwaysRequested) {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            return
        }
        UserDefaults.standard.set(true, forKey: Keys.alwaysRequested)
        manager.requestAlwaysAuthorization()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, self.authorization == .authorizedWhenInUse,
                  UIApplication.shared.applicationState == .active else { return }
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
        }
    }

    private func authorizationChanged(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        isPreciseLocation = manager.accuracyAuthorization == .fullAccuracy
        // “始终”权限下关闭后台定位蓝条/灵动岛图标；仅“使用期间”时系统要求显示指示器才能后台持续定位
        manager.showsBackgroundLocationIndicator = !hasAlwaysPermission
        if isRecording, hasAnyPermission, !isUpdatingGPS, !isSettled { start() }
        if !hasAnyPermission { activity = .unavailable }
    }

    private var usesContinuousGPS: Bool { activeTripID != nil || precision != .battery }

    func start() {
        guard isRecording else { return }
        guard hasAnyPermission else {
            activity = authorization == .notDetermined ? .off : .unavailable
            return
        }
        unsettle()
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = !hasAlwaysPermission
        manager.startMonitoringSignificantLocationChanges()
        activity = .starting

        guard usesContinuousGPS else {
            stopContinuousGPS()
            manager.startMonitoringVisits()
            activity = .stationary
            return
        }

        manager.stopMonitoringVisits()
        let highPrecision = (activeTripID != nil || precision == .precise)
        manager.activityType = highPrecision ? .fitness : .other
        manager.desiredAccuracy = highPrecision ? kCLLocationAccuracyBest : kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = highPrecision ? 5 : 10
        // 停留休眠由应用自己的 settleTask + 150m 地理围栏接管，避免 iOS 后台自动暂停后不再恢复
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
        isUpdatingGPS = true

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if self?.activity == .starting { self?.activity = .stationary }
        }
    }

    func stop() {
        unsettle()
        stopContinuousGPS()
        releaseAllMonitoring()
        flushChunk(carryOver: false)
        if let openStay { close(openStay, at: Date()) }
        anchor = nil
        dwellTask?.cancel()
        activity = .off
    }

    private func restart() {
        guard isRecording else { return }
        flushChunk(carryOver: true)
        start()
    }

    private func stopContinuousGPS() {
        manager.stopUpdatingLocation()
        isUpdatingGPS = false
    }

    private func releaseAllMonitoring() {
        stopContinuousGPS()
        manager.stopMonitoringVisits()
        manager.stopMonitoringSignificantLocationChanges()
        clearStayFence()
    }

    func persistNow() { PendingTrackStore.save(pendingPoints) }

    func refreshState() {
        validateActiveTrip()
        if pausedUntil != nil, !isPaused { resume() }
        // 处于静止休眠（isSettled）时保持地理围栏省电，不重新唤醒连续 GPS
        if isRecording, activity == .off, !isSettled { start() }
    }

    func reloadAfterClear() {
        openStay = nil
        anchor = nil
        lastAcceptedLocation = nil
        pendingPoints = []
        activeTripID = nil
        UserDefaults.standard.removeObject(forKey: Keys.activeTripID)
        PendingTrackStore.save([])
    }

    func pause(until date: Date? = nil) {
        let target = date ?? .distantFuture
        pausedUntil = target
        UserDefaults.standard.set(target, forKey: Keys.pausedUntil)
        if activeTripID == nil { stop() }
        schedulePauseEnd()
        schedulePauseEndReminder(at: target)
    }

    func resume() {
        resumeTask?.cancel()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["wt16.pause.end"])
        pausedUntil = nil
        UserDefaults.standard.removeObject(forKey: Keys.pausedUntil)
        if isRecording { start() }
    }

    private func schedulePauseEnd() {
        resumeTask?.cancel()
        guard let pausedUntil, pausedUntil != .distantFuture else { return }
        let delay = max(1, pausedUntil.timeIntervalSinceNow)
        resumeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.resume()
        }
    }

    private func schedulePauseEndReminder(at date: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["wt16.pause.end"])
        guard date != .distantFuture, date.timeIntervalSinceNow > 60 else { return }
        let content = UNMutableNotificationContent()
        content.title = "暂停结束了"
        content.body = "打开漫迹 iOS 16，继续记录你的足迹。"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: date.timeIntervalSinceNow, repeats: false)
        center.add(UNNotificationRequest(identifier: "wt16.pause.end", content: content, trigger: trigger))
    }

    private func handleSystemPause() {
        guard isRecording, usesContinuousGPS, activeTripID == nil else { return }
        activity = .stationary
        if let loc = lastAcceptedLocation { promoteAnchorIfStill(at: loc) }
        flushChunk(carryOver: true)
        scheduleSettle()
    }

    private func handleLocations(_ locations: [CLLocation]) {
        guard isRecording else { return }
        if pausedUntil != nil, !isPaused { resume() }

        if isSettled, let stay = openStay, let last = locations.last,
           last.distance(from: stay.location) > Tuning.fenceRadius + last.horizontalAccuracy {
            leftFence()
            return
        }

        if !usesContinuousGPS {
            handleCoarse(locations)
            return
        }

        for location in locations {
            currentLocation = location
            if activity == .starting {
                activity = location.speed > 0.5 ? .moving : .stationary
            }
            guard location.horizontalAccuracy > 0, location.horizontalAccuracy <= Tuning.maxAccuracy else { continue }
            guard abs(location.timestamp.timeIntervalSinceNow) < 60 else { continue }
            guard !isJump(location) else { continue }

            activity = (location.speed >= 0 && location.speed < 0.5 && openStay != nil) ? .stationary : .moving
            if !noteFlight(to: location) { bridgeGap(to: location) }
            record(location)
            detectStay(with: location)
        }
    }

    private func handleCoarse(_ locations: [CLLocation]) {
        for location in locations where location.horizontalAccuracy > 0 && location.horizontalAccuracy <= Tuning.coarseAccuracy {
            currentLocation = location
            noteFlight(to: location)
            lastAcceptedLocation = nil
            if let stay = openStay,
               location.distance(from: stay.location) > Tuning.stayRadius + location.horizontalAccuracy {
                close(stay, at: location.timestamp)
                activity = .moving
            }
            pendingPoints.append(TrackPoint(location))
        }
        PendingTrackStore.save(pendingPoints)
        if let first = pendingPoints.first, pendingPoints.count >= 2,
           pendingPoints.count >= 6 || Date().timeIntervalSince(first.timestamp) >= 5 * 60 {
            flushChunk(carryOver: true)
        }
    }

    private func handleVisit(_ visit: CLVisit) {
        if isSettled, visit.departureDate != .distantFuture { leftFence() }
        guard !usesContinuousGPS, isRecording else { return }
        let arrived = visit.arrivalDate != .distantPast ? visit.arrivalDate : Date()
        let location = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)

        if visit.departureDate == .distantFuture {
            guard openStay == nil else { return }
            beginStay(from: (location, arrived, visit.coordinate.latitude, visit.coordinate.longitude, 1))
            return
        }

        if let stay = openStay, location.distance(from: stay.location) <= 200 {
            if visit.departureDate > stay.arrival { close(stay, at: visit.departureDate) }
            return
        }

        guard visit.arrivalDate != .distantPast,
              visit.departureDate.timeIntervalSince(visit.arrivalDate) >= Tuning.stayMinimumDuration,
              !hasStay(overlapping: visit.arrivalDate, visit.departureDate) else { return }

        var stay = Stay(arrival: visit.arrivalDate, departure: visit.departureDate, coordinate: visit.coordinate)
        store.applyKnownName(to: &stay)
        store.upsertStay(stay)
        tagger.enqueue()
    }

    private func hasStay(overlapping start: Date, _ end: Date) -> Bool {
        store.stays.contains { stay in stay.arrival < end && (stay.departure ?? .distantFuture) > start }
    }

    private func isJump(_ location: CLLocation) -> Bool {
        guard let last = lastAcceptedLocation else { return false }
        let elapsed = location.timestamp.timeIntervalSince(last.timestamp)
        guard elapsed > 0, elapsed < Tuning.gapBreak else { rejectedJumps = 0; return false }
        let implied = location.distance(from: last) / elapsed
        let reported = max(location.speed, 0)
        if reported <= 50, implied > Tuning.maxGroundSpeed, implied > reported * 3 + 10, rejectedJumps < 3 {
            rejectedJumps += 1
            return true
        }
        rejectedJumps = 0
        return false
    }

    private func record(_ location: CLLocation) {
        if let last = lastAcceptedLocation ?? pendingPoints.last?.location {
            let gap = location.timestamp.timeIntervalSince(last.timestamp)
            if gap > Tuning.gapBreak { flushChunk(carryOver: false) }
            let step = location.distance(from: last)
            guard step >= max(Tuning.minStepDistance, location.horizontalAccuracy * 0.5) || gap > Tuning.gapBreak else { return }
        }
        lastAcceptedLocation = location
        pendingPoints.append(TrackPoint(location))
        if pendingPoints.count % 10 == 0 { PendingTrackStore.save(pendingPoints) }

        if let first = pendingPoints.first,
           pendingPoints.count >= Tuning.chunkMaxPoints || location.timestamp.timeIntervalSince(first.timestamp) >= Tuning.chunkMaxDuration {
            flushChunk(carryOver: true)
        }
    }

    private func flushChunk(carryOver: Bool) {
        let points = pendingPoints
        pendingPoints = carryOver ? Array(points.suffix(1)) : []
        if !carryOver { lastAcceptedLocation = nil }
        PendingTrackStore.save(pendingPoints)
        guard points.count >= 2, TrackPoint.distance(of: points) > 15 else { return }

        let tripID = activeTripID
        let initialMode = MotionClassifier.mode(forSpeeds: points.map(\.speed))
        let chunk = TrackChunk(points: points, mode: initialMode, tripID: tripID)
        store.insertChunk(chunk)

        Task {
            let legs = await classifier.legs(of: points)
            let validLegs = legs.filter { $0.points.count >= 2 }
            if validLegs.count > 1 {
                store.deleteChunk(id: chunk.id)
                for leg in validLegs {
                    store.insertChunk(TrackChunk(points: leg.points, mode: leg.mode, tripID: tripID))
                }
            } else if let leg = validLegs.first, leg.mode != initialMode {
                var updated = chunk
                updated.modeRaw = leg.mode.rawValue
                store.insertChunk(updated)
            }
        }
    }

    @discardableResult
    private func noteFlight(to location: CLLocation) -> Bool {
        var from: CLLocation?
        var left: Date?
        if let last = lastAcceptedLocation ?? pendingPoints.last?.location {
            from = last
            left = last.timestamp
        } else if let stay = openStay ?? lastClosedStay() {
            from = stay.location
            left = stay.departure ?? stay.arrival
        }
        guard let from, let left else { return false }
        let distance = location.distance(from: from)
        guard distance > Tuning.flightDistance else { return false }
        let flightTime = distance / Tuning.cruiseSpeed
        var takeoff = left
        if let stay = openStay {
            takeoff = max(stay.arrival.addingTimeInterval(Tuning.stayMinimumDuration),
                          location.timestamp.addingTimeInterval(-flightTime - Tuning.groundTime))
        }
        let elapsed = location.timestamp.timeIntervalSince(takeoff)
        guard elapsed > 0, distance / elapsed > Tuning.flightSpeed else { return false }

        let landing = max(takeoff.addingTimeInterval(flightTime), location.timestamp.addingTimeInterval(-15 * 60))
        let path = FlightPath.points(from: from.coordinate, to: location.coordinate,
                                     start: takeoff, end: min(landing, location.timestamp))
        flushChunk(carryOver: false)
        if let stay = openStay { close(stay, at: takeoff) }
        store.insertChunk(TrackChunk(points: path, mode: .flying, tripID: activeTripID))
        anchor = nil
        lastAcceptedLocation = nil
        pendingPoints = []
        return true
    }

    private func bridgeGap(to location: CLLocation) {
        let from: CLLocation
        var earliest: Date
        if let last = lastAcceptedLocation ?? pendingPoints.last?.location {
            from = last
            earliest = last.timestamp
        } else if let stay = openStay ?? lastClosedStay() {
            earliest = stay.departure ?? stay.arrival.addingTimeInterval(Tuning.stayMinimumDuration)
            from = CLLocation(coordinate: stay.location.coordinate, altitude: 0, horizontalAccuracy: 10,
                              verticalAccuracy: -1, timestamp: earliest)
        } else {
            return
        }
        let distance = location.distance(from: from)
        let silence = location.timestamp.timeIntervalSince(from.timestamp)
        guard distance >= Tuning.gapDistance, distance < Tuning.flightDistance, silence >= Tuning.gapSilence else { return }

        let drove = from.speed > Tuning.drivingSpeed
        let known = from.timestamp
        let tripID = activeTripID
        flushChunk(carryOver: false)
        Task {
            let journey = await classifier.journey(from: earliest, to: location.timestamp)
            var start = journey.map { max($0.start, earliest) } ?? known
            var end = journey.map { min($0.end, location.timestamp) } ?? location.timestamp
            if end.timeIntervalSince(start) < 60 {
                start = known
                end = location.timestamp
            }
            var mode: MovementMode = drove ? .automotive : .subway
            if let said = journey?.mode, [.walking, .running, .cycling].contains(said) { mode = said }
            let speed = distance / max(end.timeIntervalSince(start), 1)
            let points = [
                TrackPoint(latitude: from.coordinate.latitude, longitude: from.coordinate.longitude,
                           altitude: from.altitude, speed: speed, accuracy: 1000, timestamp: start),
                TrackPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                           altitude: location.altitude, speed: speed, accuracy: 1000, timestamp: end),
            ]
            store.insertChunk(TrackChunk(points: points, mode: mode, tripID: tripID))
        }
    }

    private func detectStay(with location: CLLocation) {
        if var stay = openStay {
            if location.distance(from: stay.location) <= Tuning.stayRadius + location.horizontalAccuracy {
                if location.horizontalAccuracy <= 30, stay.sampleCount < 200 {
                    let n = Double(stay.sampleCount)
                    stay.latitude = (stay.latitude * n + location.coordinate.latitude) / (n + 1)
                    stay.longitude = (stay.longitude * n + location.coordinate.longitude) / (n + 1)
                    stay.sampleCount += 1
                    openStay = stay
                    store.upsertStay(stay, notify: false)
                }
            } else {
                close(stay, at: location.timestamp)
                setAnchor(location)
            }
            return
        }

        guard var current = anchor, location.distance(from: current.location) <= Tuning.stayRadius else {
            setAnchor(location)
            return
        }
        current.latSum += location.coordinate.latitude
        current.lonSum += location.coordinate.longitude
        current.count += 1
        anchor = current
        if location.timestamp.timeIntervalSince(current.since) >= Tuning.stayMinimumDwell {
            beginStay(from: current)
        }
    }

    private func setAnchor(_ location: CLLocation) {
        anchor = (location, location.timestamp, location.coordinate.latitude, location.coordinate.longitude, 1)
        dwellTask?.cancel()
        let since = location.timestamp
        dwellTask = Task { [weak self] in
            let wait = max(1, Tuning.stayMinimumDwell - Date().timeIntervalSince(since))
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard let self, !Task.isCancelled, self.openStay == nil,
                  let current = self.anchor, current.since == since, self.isRecording else { return }
            self.beginStay(from: current)
            self.activity = .stationary
        }
    }

    private func promoteAnchorIfStill(at location: CLLocation) {
        guard openStay == nil else { return }
        if let current = anchor, location.distance(from: current.location) <= Tuning.stayRadius {
            beginStay(from: current)
        } else {
            beginStay(from: (location, location.timestamp, location.coordinate.latitude, location.coordinate.longitude, 1))
        }
    }

    private func beginStay(from anchor: (location: CLLocation, since: Date, latSum: Double, lonSum: Double, count: Int)) {
        dwellTask?.cancel()
        let center = CLLocationCoordinate2D(latitude: anchor.latSum / Double(anchor.count),
                                            longitude: anchor.lonSum / Double(anchor.count))
        self.anchor = nil
        flushChunk(carryOver: true)

        if var previous = lastClosedStay(),
           let left = previous.departure,
           anchor.since.timeIntervalSince(left) < Tuning.stayMergeGap,
           previous.location.distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude)) < Tuning.stayRadius {
            previous.departure = nil
            openStay = previous
            store.upsertStay(previous)
            scheduleSettle()
            return
        }

        var stay = Stay(arrival: anchor.since, coordinate: center, sampleCount: anchor.count)
        store.applyKnownName(to: &stay)
        store.upsertStay(stay)
        openStay = stay
        tagger.enqueue()
        scheduleSettle()
    }

    private func close(_ stay: Stay, at date: Date) {
        openStay = nil
        if date.timeIntervalSince(stay.arrival) < Tuning.stayMinimumDuration {
            store.deleteStay(id: stay.id)
        } else {
            var closed = stay
            closed.departure = date
            store.upsertStay(closed)
        }
    }

    private func scheduleSettle() {
        guard let stay = openStay, activeTripID == nil, usesContinuousGPS, !isSettled else { return }
        settleTask?.cancel()
        let wait = max(0, Tuning.settleAfter - Date().timeIntervalSince(stay.arrival))
        settleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            while !Task.isCancelled, let self, self.openStay?.id == stay.id, await self.classifier.isMoving() {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
            }
            guard let self, !Task.isCancelled, self.openStay?.id == stay.id else { return }
            self.settle()
        }
    }

    private func settle() {
        guard let stay = openStay, isRecording, activeTripID == nil, usesContinuousGPS, !isSettled else { return }
        isSettled = true
        stopContinuousGPS()
        flushChunk(carryOver: false)
        setStayFence(around: stay.coordinate)
        manager.startMonitoringVisits()
    }

    private func unsettle() {
        settleTask?.cancel()
        settleTask = nil
        isSettled = false
        clearStayFence()
    }

    private func leftFence() {
        guard isSettled else { return }
        if isRecording, let stay = openStay, pendingPoints.isEmpty {
            pendingPoints = [TrackPoint(CLLocation(coordinate: stay.coordinate, altitude: 0, horizontalAccuracy: 10,
                                                   verticalAccuracy: -1, timestamp: Date()))]
        }
        if isRecording { start() } else { unsettle() }
    }

    private func setStayFence(around center: CLLocationCoordinate2D) {
        clearStayFence()
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let region = CLCircularRegion(center: center, radius: Tuning.fenceRadius, identifier: Self.fenceID)
        region.notifyOnEntry = false
        region.notifyOnExit = true
        manager.startMonitoring(for: region)
    }

    private func clearStayFence() {
        for region in manager.monitoredRegions where region.identifier == Self.fenceID {
            manager.stopMonitoring(for: region)
        }
    }

    private func lastClosedStay() -> Stay? {
        store.stays.first { $0.departure != nil && !$0.isFromPhotos }
    }

    private func restoreOpenStay() {
        guard isRecording else { openStay = nil; return }
        let open = store.stays.filter { $0.departure == nil }
        openStay = open.first
        for var stale in open.dropFirst() {
            stale.departure = stale.arrival.addingTimeInterval(Tuning.stayMinimumDuration)
            store.upsertStay(stale)
        }
    }
}

private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    var onAuthChange: ((CLLocationManager) -> Void)?
    var onLocations: (([CLLocation]) -> Void)?
    var onVisit: ((CLVisit) -> Void)?
    var onExitRegion: ((CLRegion) -> Void)?
    var onPauseUpdates: (() -> Void)?

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { onAuthChange?(manager) }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { onLocations?(locations) }
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) { onVisit?(visit) }
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) { onExitRegion?(region) }
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) { onPauseUpdates?() }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

enum PendingTrackStore {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("pending-track-v16.bin")
    }

    static func save(_ points: [TrackPoint]) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? TrackCodec.encode(points).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func load() -> [TrackPoint] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return TrackCodec.decode(data)
    }
}
