import SwiftUI
import MapKit
import Photos
import UIKit

struct TripsView: View {
    @Binding var showingSettings: Bool
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var engine: LocationEngine

    private struct DiscoveredCardData: Identifiable, Sendable {
        let item: TripFinder.DiscoveredTrip
        let coordinates: [CLLocationCoordinate2D]
        var id: String { item.id }
    }

    fileprivate struct TripCityPin: Identifiable, Sendable {
        let id: String
        let name: String
        let center: CLLocationCoordinate2D
        let days: Int
    }

    fileprivate struct TripCardModel: Identifiable, Sendable {
        let trip: Trip
        let distance: Double
        let stayCount: Int
        let cities: [TripCityPin]
        let coordinates: [CLLocationCoordinate2D]
        let routePoints: [CLLocationCoordinate2D]
        let days: Int
        var id: UUID { trip.id }
    }

    private struct YearGroupModel: Identifiable, Sendable {
        let year: Int
        let totalDays: Int
        let cards: [TripCardModel]
        var id: Int { year }
    }

    @State private var tab = 0 // 0 = 旅程, 1 = 记录
    @State private var selectedYear: Int = 0 // 0 = 全部
    @State private var showNewRecording = false
    @State private var showNewTrip = false
    @State private var showAllDiscovered = false
    @State private var dismissedDiscoveredIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "wt16.trips.dismissedDiscovered") ?? [])
    @State private var discovered: [DiscoveredCardData] = []
    @State private var yearGroups: [YearGroupModel] = []
    @State private var recordingCards: [TripCardModel] = []
    @State private var hasLoadedOnce = false

    private var visibleDiscovered: [DiscoveredCardData] {
        discovered.filter { !dismissedDiscoveredIDs.contains($0.id) }
    }

    private var savedTripsCount: Int {
        store.trips.filter { !$0.isRecording }.count
    }
    private var savedRecordingsCount: Int {
        store.trips.filter { $0.isRecording }.count
    }

    private var filteredYearGroups: [YearGroupModel] {
        if selectedYear == 0 { return yearGroups }
        let matched = yearGroups.filter { $0.year == selectedYear }
        return matched.isEmpty ? yearGroups : matched
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let active = engine.activeTrip {
                        activeRecordingBanner(active)
                    }

                    Picker("类型", selection: $tab) {
                        Text("旅程 \(savedTripsCount)").tag(0)
                        Text("记录 \(savedRecordingsCount)").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if tab == 0 {
                        if !visibleDiscovered.isEmpty {
                            discoveredSection
                        }
                        if savedTripsCount == 0 {
                            VStack(spacing: 12) {
                                Image(systemName: "suitcase")
                                    .font(.system(size: 40, weight: .light))
                                    .foregroundColor(.secondary.opacity(0.45))
                                Text("旅程把几天的轨迹、地点和照片收在一起。也可以为已经过去的日子补建旅程，轨迹会自动归入。")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 34)
                        } else if !hasLoadedOnce && yearGroups.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView("正在整理旅程…")
                                Spacer()
                            }
                            .padding(.vertical, 36)
                        } else {
                            // 原版年份筛选横向胶囊栏（全部 N | 2026 M | 2025 K ...）
                            if yearGroups.count > 1 {
                                yearFilterStrip
                            }

                            ForEach(filteredYearGroups) { group in
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text(String(group.year))
                                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                                        Text("\(group.cards.count) 段 · \(group.totalDays) 天")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 4)
                                    .padding(.top, 2)

                                    ForEach(group.cards) { model in
                                        NavigationLink {
                                            TripDetailView(trip: model.trip)
                                        } label: {
                                            OriginalTripCardView(model: model)
                                        }
                                        .buttonStyle(PressableStyle())
                                    }
                                }
                            }
                        }
                    } else {
                        if savedRecordingsCount == 0 {
                            emptyCard(
                                icon: "figure.hiking",
                                title: "还没有运动记录",
                                subtitle: "徒步、跑步、骑行时可点右上角「开始高精度记录」，记录路线、配速与爬升。"
                            )
                        } else {
                            ForEach(recordingCards) { model in
                                NavigationLink {
                                    TripDetailView(trip: model.trip)
                                } label: {
                                    recordingCard(model)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("旅程")
            .scrollIndicators(.hidden)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button { showNewTrip = true } label: {
                            Label("新旅程", systemImage: "suitcase")
                        }
                        Button { showNewRecording = true } label: {
                            Label("开始记录", systemImage: "record.circle")
                        }
                        .disabled(engine.activeTripID != nil)
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                    ProfileToolbarButton(showingSettings: $showingSettings)
                }
            }
            .onChange(of: tab) { _ in selectedYear = 0 }
            .sheet(isPresented: $showNewRecording) { NewRecordingSheet() }
            .sheet(isPresented: $showNewTrip) { NewTripSheet() }
            .sheet(isPresented: $showAllDiscovered) {
                AllDiscoveredTripsSheet(
                    items: visibleDiscovered.map(\.item),
                    onSave: { saveDiscovered($0) },
                    onDismissItem: { dismissDiscovered($0.id) }
                )
            }
            .task(id: "\(store.stays.count)-\(store.trips.count)-\(store.chunks.count)") {
                let staysSnapshot = store.stays
                let tripsSnapshot = store.trips
                let chunksSnapshot = store.chunks
                let computed = await Task.detached(priority: .userInitiated) { () -> ([DiscoveredCardData], [YearGroupModel], [TripCardModel]) in
                    let cal = Calendar.current

                    let found = TripFinder.discover(from: staysSnapshot, existingTrips: tripsSnapshot)
                    let discCards: [DiscoveredCardData] = found.map { item in
                        let coords = staysSnapshot
                            .filter { $0.arrival >= item.startDate && $0.arrival <= item.endDate }
                            .prefix(12)
                            .map { $0.coordinate.onMap }
                        return DiscoveredCardData(item: item, coordinates: Array(coords))
                    }

                    func makeCard(_ trip: Trip) -> TripCardModel {
                        let end = trip.endDate ?? Date()
                        let tripStays = staysSnapshot.filter { $0.arrival >= trip.startDate && $0.arrival <= end }
                        let tripChunks = chunksSnapshot.filter {
                            $0.tripID == trip.id || ($0.endDate >= trip.startDate && $0.startDate <= end)
                        }
                        let dist = tripChunks.reduce(0.0) { $0 + $1.distance }
                        let byCity = Dictionary(grouping: tripStays.filter { ($0.city?.isEmpty == false) }) { $0.city! }
                        let cityPins: [TripCityPin] = byCity.map { name, list in
                            let lat = list.map(\.latitude).reduce(0, +) / Double(list.count)
                            let lon = list.map(\.longitude).reduce(0, +) / Double(list.count)
                            let dCount = max(1, Set(list.map { cal.startOfDay(for: $0.arrival) }).count)
                            return TripCityPin(
                                id: name,
                                name: name,
                                center: CLLocationCoordinate2D(latitude: lat, longitude: lon).onMap,
                                days: dCount
                            )
                        }.sorted { $0.days > $1.days }

                        let coords = Array(tripStays.prefix(20).map { $0.coordinate.onMap })
                        let routePts = tripChunks.prefix(6).flatMap { chunk -> [CLLocationCoordinate2D] in
                            let pts = chunk.points
                            let step = max(1, pts.count / 25)
                            return stride(from: 0, to: pts.count, by: step).map { pts[$0].coordinate.onMap }
                        }
                        let lastDay = max(trip.startDate, end.addingTimeInterval(-1))
                        let d = max(1, (cal.dateComponents([.day], from: cal.startOfDay(for: trip.startDate), to: cal.startOfDay(for: lastDay)).day ?? 0) + 1)
                        return TripCardModel(
                            trip: trip,
                            distance: dist,
                            stayCount: tripStays.count,
                            cities: cityPins,
                            coordinates: coords,
                            routePoints: routePts,
                            days: d
                        )
                    }

                    let saved = tripsSnapshot.filter { !$0.isRecording }.sorted { $0.startDate > $1.startDate }
                    let grouped = Dictionary(grouping: saved) { cal.component(.year, from: $0.startDate) }
                    let years: [YearGroupModel] = grouped.keys.sorted(by: >).map { yr in
                        let cards = (grouped[yr] ?? []).map(makeCard)
                        let totalDays = cards.reduce(0) { $0 + $1.days }
                        return YearGroupModel(year: yr, totalDays: totalDays, cards: cards)
                    }

                    let recs = tripsSnapshot.filter { $0.isRecording }.sorted { $0.startDate > $1.startDate }.map(makeCard)
                    return (discCards, years, recs)
                }.value

                discovered = computed.0
                yearGroups = computed.1
                recordingCards = computed.2
                hasLoadedOnce = true
            }
        }
    }

    // MARK: - Year Filter Chips (Original 全部 113 | 2026 14 | 2025 23)

    private var yearFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                yearChip(title: "全部", count: savedTripsCount, value: 0)
                ForEach(yearGroups) { group in
                    yearChip(title: String(group.year), count: group.cards.count, value: group.year)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func yearChip(title: String, count: Int, value: Int) -> some View {
        let selected = selectedYear == value
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedYear = value
            }
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text("\(count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .opacity(0.75)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundColor(selected ? .white : .primary)
            .background(
                selected ? Color.blue : Color(.secondarySystemGroupedBackground),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Active Recording Banner

    private func activeRecordingBanner(_ trip: Trip) -> some View {
        let chunks = store.chunks(for: trip)
        let dist = chunks.reduce(0.0) { $0 + $1.distance } + TrackPoint.distance(of: engine.pendingPoints)
        return HStack(spacing: 12) {
            PulsingDot(color: .orange)
            Text(trip.coverEmoji).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("正在记录：\(trip.title)").font(.subheadline.weight(.semibold))
                Text("\(Formatters.distance(dist)) · \(Formatters.duration(trip.duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("结束") { engine.endActiveRecording() }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Discovered Trips

    private var discoveredSection: some View {
        let list = visibleDiscovered
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("在足迹里找到 \(list.count) 段旅行")
                        .font(.title3.bold())
                    Text("根据你离开常住地的日子整理出来")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("查看全部") {
                    UISelectionFeedbackGenerator().selectionChanged()
                    showAllDiscovered = true
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(list.prefix(20)) { entry in
                        DiscoveredTripPhotoCard(
                            item: entry.item,
                            coordinates: entry.coordinates,
                            onSave: { saveDiscovered(entry.item) },
                            onDismiss: { dismissDiscovered(entry.id) }
                        )
                    }
                }
            }
        }
    }

    private func dismissDiscovered(_ id: String) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeInOut(duration: 0.22)) {
            _ = dismissedDiscoveredIDs.insert(id)
        }
        UserDefaults.standard.set(Array(dismissedDiscoveredIDs), forKey: "wt16.trips.dismissedDiscovered")
    }

    private func saveDiscovered(_ item: TripFinder.DiscoveredTrip) {
        let trip = Trip(
            title: item.title,
            startDate: item.startDate,
            endDate: item.endDate,
            notes: item.cities.joined(separator: " · "),
            coverEmoji: "🧳",
            activityRaw: nil
        )
        store.upsertTrip(trip)
    }

    private func recordingCard(_ model: TripCardModel) -> some View {
        let trip = model.trip
        return HStack(spacing: 14) {
            Text(trip.coverEmoji)
                .font(.title2)
                .frame(width: 48, height: 48)
                .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(trip.dateRangeText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(Formatters.distance(model.distance)) · \(Formatters.duration(trip.duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func emptyCard(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.largeTitle).foregroundColor(.secondary)
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - 1:1 Original TripCard (Map + City Tags + DateBadge + MiniPile + Fact Pills)

private struct TripCardMapResult {
    let image: UIImage
    let pins: [CGPoint] // normalized 0...1
}

private final class TripCardMapCache {
    static let shared = TripCardMapCache()
    private var cache: [String: TripCardMapResult] = [:]
    private let lock = NSLock()

    func get(_ key: String) -> TripCardMapResult? {
        lock.lock(); defer { lock.unlock() }
        return cache[key]
    }

    func set(_ value: TripCardMapResult, for key: String) {
        lock.lock(); defer { lock.unlock() }
        if cache.count > 120 { cache.removeAll() }
        cache[key] = value
    }
}

private struct OriginalTripCardView: View {
    let model: TripsView.TripCardModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var mapResult: TripCardMapResult?
    @State private var pilePhotos: [UIImage] = []
    @State private var photoCount: Int = 0

    private let mapHeight: CGFloat = 200

    private var trip: Trip { model.trip }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    if let mapResult {
                        Image(uiImage: mapResult.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                    } else {
                        LinearGradient(
                            colors: [Color.blue.opacity(0.10), Color.teal.opacity(0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }

                    // 城市悬浮标签 + 橙/蓝圆点
                    if let mapResult {
                        ForEach(Array(placedTags(result: mapResult, size: geo.size).enumerated()), id: \.offset) { idx, item in
                            TripCityTagView(name: item.name, prominent: idx == 0)
                                .position(x: item.point.x, y: item.point.y - 14)
                        }
                    }

                    // 左上角日历徽章
                    TripCalendarBadge(start: trip.startDate, end: trip.endDate ?? trip.startDate)
                        .padding(12)

                    // 右下角 3 张扇形白边照片叠放
                    if !pilePhotos.isEmpty {
                        TripMiniPhotoPile(images: pilePhotos)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(14)
                    }
                }
            }
            .frame(height: mapHeight)
            .clipped()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(trip.coverEmoji)
                        .font(.title3)
                    Text(trip.title)
                        .font(.title3.bold())
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    tripFactChip(symbol: "calendar", text: "\(model.days) 天")
                    if !model.cities.isEmpty {
                        tripFactChip(symbol: "building.2", text: "\(model.cities.count) 座城市")
                    }
                    if photoCount > 0 {
                        tripFactChip(symbol: "photo", text: "\(Self.formattedInt(photoCount)) 张照片")
                    }
                }

                if !model.cities.isEmpty {
                    Text(model.cities.prefix(5).map(\.name).joined(separator: " · "))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .task(id: "\(trip.id.uuidString)-\(trip.startDate.timeIntervalSince1970)-\(trip.endDate?.timeIntervalSince1970 ?? 0)-\(colorScheme == .dark)") {
            await loadMapAndPhotos()
        }
    }

    private func tripFactChip(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }

    private func placedTags(result: TripCardMapResult, size: CGSize) -> [(name: String, point: CGPoint)] {
        var placed: [(name: String, point: CGPoint)] = []
        for (city, unit) in zip(model.cities.prefix(4), result.pins) {
            let pin = CGPoint(x: unit.x * size.width, y: unit.y * size.height)
            guard pin.x > 4, pin.x < size.width - 4, pin.y > 30, pin.y < size.height - 6 else { continue }
            let half = CGFloat(city.name.count) * 7.5 + 14
            let point = CGPoint(x: min(max(pin.x, half + 6), size.width - half - 6), y: pin.y)
            let underBadge = point.x < 100 && point.y < 115
            let underPile = !pilePhotos.isEmpty && point.x > size.width - 135 && point.y > size.height - 105
            let crowded = placed.contains { abs($0.point.x - point.x) < 72 && abs($0.point.y - point.y) < 34 }
            if !underBadge && !underPile && !crowded {
                placed.append((city.name, point))
            }
        }
        return placed
    }

    private func loadMapAndPhotos() async {
        let isDark = colorScheme == .dark
        let pins = Array(model.cities.prefix(4).map(\.center))
        let fallbackCoords = pins.isEmpty ? model.coordinates : pins
        let key = "\(trip.id.uuidString)-\(isDark)-\(fallbackCoords.count)"

        if let cached = TripCardMapCache.shared.get(key) {
            mapResult = cached
        } else if let region = Self.region(around: fallbackCoords) {
            let size = CGSize(width: max(UIScreen.main.bounds.width - 32, 300), height: mapHeight)
            if let rendered = await Self.renderMap(region: region, size: size, pins: pins, dark: isDark) {
                TripCardMapCache.shared.set(rendered, for: key)
                mapResult = rendered
            }
        }

        let auth = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard auth == .authorized || auth == .limited else { return }
        let start = trip.startDate
        let end = trip.endDate ?? Date()
        let found = await TripPhotoFetcher.fetchAssets(from: start, to: end)
        photoCount = found.count
        guard !found.isEmpty else { return }
        let favs = found.filter(\.isFavorite)
        let pool = favs.count >= 3 ? favs : found
        let step = max(1, pool.count / 3)
        let picked = stride(from: 0, to: pool.count, by: step).prefix(3).map { pool[$0] }
        var thumbs: [UIImage] = []
        for asset in picked {
            if let img = await TripPhotoFetcher.thumbnail(for: asset, side: 150) {
                thumbs.append(img)
            }
        }
        pilePhotos = thumbs
    }

    private static func region(around coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard !coordinates.isEmpty else { return nil }
        let lats = coordinates.map(\.latitude)
        guard let minLat = lats.min(), let maxLat = lats.max() else { return nil }
        let lons = coordinates.map(\.longitude).sorted()
        var widest = lons[0] + 360 - lons[lons.count - 1]
        var west = lons[0]
        for (a, b) in zip(lons, lons.dropFirst()) where b - a > widest {
            widest = b - a
            west = b
        }
        let covered = 360 - widest
        let lonSpan = max(covered * (covered > 60 ? 1.6 : 2.0), 0.35)
        let latSpan = max((maxLat - minLat) * 2.4, lonSpan * 0.45)
        var centerLon = west + covered / 2 - lonSpan * 0.1
        if centerLon > 180 { centerLon -= 360 }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2 + latSpan * 0.06, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: min(latSpan, 120), longitudeDelta: min(lonSpan, 300))
        )
    }

    @MainActor
    private static func renderMap(region: MKCoordinateRegion, size: CGSize, pins: [CLLocationCoordinate2D], dark: Bool) async -> TripCardMapResult? {
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.scale = UIScreen.main.scale
        options.mapType = .mutedStandard
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let snapshotter = MKMapSnapshotter(options: options)
        return await withCheckedContinuation { cont in
            snapshotter.start(with: DispatchQueue.global(qos: .userInitiated)) { snapshot, _ in
                guard let snapshot else {
                    cont.resume(returning: nil)
                    return
                }
                let normPins = pins.map { c -> CGPoint in
                    let pt = snapshot.point(for: c)
                    return CGPoint(x: pt.x / size.width, y: pt.y / size.height)
                }
                cont.resume(returning: TripCardMapResult(image: snapshot.image, pins: normPins))
            }
        }
    }

    private static func formattedInt(_ n: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
    }
}

private struct TripCityTagView: View {
    let name: String
    let prominent: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(name)
                .font(prominent ? .footnote.weight(.bold) : .caption.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            Circle()
                .fill(prominent ? Color.orange : Color.blue)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(Color.white, lineWidth: 1.8))
        }
        .fixedSize()
    }
}

private struct TripMiniPhotoPile: View {
    let images: [UIImage]

    var body: some View {
        ZStack {
            ForEach(Array(images.prefix(3).enumerated()).reversed(), id: \.offset) { index, img in
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white, lineWidth: 2.2))
                    .shadow(color: .black.opacity(0.24), radius: 4, y: 2)
                    .rotationEffect(.degrees([-8.0, 6.0, -2.0][index]))
                    .offset(x: CGFloat(index) * -22, y: CGFloat(index) * 2)
            }
        }
        .padding(.leading, 44)
    }
}

// MARK: - Trip Photo Fetcher Helper

private enum TripPhotoFetcher {
    private final class OnceFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }

    static func fetchAssets(from start: Date, to end: Date) async -> [PHAsset] {
        await Task.detached(priority: .utility) { () -> [PHAsset] in
            let opts = PHFetchOptions()
            opts.predicate = NSPredicate(
                format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@",
                PHAssetMediaType.image.rawValue,
                start as NSDate,
                end as NSDate
            )
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let res = PHAsset.fetchAssets(with: opts)
            var arr: [PHAsset] = []
            arr.reserveCapacity(res.count)
            res.enumerateObjects { asset, _, _ in arr.append(asset) }
            return arr
        }.value
    }

    static func thumbnail(for asset: PHAsset, side: CGFloat) async -> UIImage? {
        await withCheckedContinuation { cont in
            let req = PHImageRequestOptions()
            req.deliveryMode = .highQualityFormat
            req.resizeMode = .fast
            req.isNetworkAccessAllowed = true
            let flag = OnceFlag()
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFill,
                options: req
            ) { img, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let hasErr = info?[PHImageErrorKey] != nil
                if (!degraded || cancelled || hasErr), flag.claim() {
                    cont.resume(returning: img)
                }
            }
        }
    }
}

// MARK: - Original Photo-Cover Discovered Trip Card & Full List Sheet

private struct DiscoveredTripPhotoCard: View {
    let item: TripFinder.DiscoveredTrip
    let coordinates: [CLLocationCoordinate2D]
    let onSave: () -> Void
    let onDismiss: () -> Void

    @State private var coverPhoto: UIImage?

    private var dateRangeText: String {
        let cal = Calendar.current
        let end = max(item.startDate, item.endDate.addingTimeInterval(-1))
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        let s = f.string(from: item.startDate)
        if cal.isDate(item.startDate, inSameDayAs: end) {
            return "\(s) · \(item.days) 天"
        } else if cal.isDate(item.startDate, equalTo: end, toGranularity: .month) {
            return "\(s)–\(cal.component(.day, from: end))日 · \(item.days) 天"
        } else if cal.isDate(item.startDate, equalTo: end, toGranularity: .year) {
            f.dateFormat = "M月d日"
            return "\(s)–\(f.string(from: end)) · \(item.days) 天"
        } else {
            return "\(s)–\(f.string(from: end)) · \(item.days) 天"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let coverPhoto {
                        Image(uiImage: coverPhoto)
                            .resizable()
                            .scaledToFill()
                    } else {
                        TripSnapshotMapView(
                            cacheKey: "disc-\(item.id)",
                            coordinates: coordinates,
                            routePoints: [],
                            dark: true
                        )
                    }
                }
                .frame(width: 256, height: 158)
                .clipped()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(10)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.headline.bold())
                    .lineLimit(1)
                Text(dateRangeText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if !item.cities.isEmpty {
                    Text(item.cities.prefix(3).joined(separator: " · "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onSave()
                } label: {
                    Label("收进旅程", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color(.systemBackground), in: Capsule())
                        .overlay(Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(14)
        }
        .frame(width: 256)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .task(id: item.id) {
            if coverPhoto != nil { return }
            coverPhoto = await StintPhotoFetcher.shared.dayThumbnail(around: item.startDate)
        }
    }
}

private struct AllDiscoveredTripsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let items: [TripFinder.DiscoveredTrip]
    let onSave: (TripFinder.DiscoveredTrip) -> Void
    let onDismissItem: (TripFinder.DiscoveredTrip) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.headline)
                            Text("\(Formatters.dayTitle(item.startDate)) · \(item.days) 天")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if !item.cities.isEmpty {
                                Text(item.cities.prefix(4).joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Button("收进旅程") {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onSave(item)
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                        .controlSize(.small)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            onDismissItem(item)
                        } label: {
                            Label("忽略", systemImage: "xmark")
                        }
                    }
                }
            }
            .navigationTitle("找到的旅行（\(items.count)）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !items.isEmpty {
                        Button("全部收下") {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            for item in items { onSave(item) }
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Memory + Disk Persistent Snapshot Cache

private final class TripSnapshotCache {
    static let shared = TripSnapshotCache()
    private let memory = NSCache<NSString, UIImage>()
    private let diskDir: URL

    private init() {
        memory.countLimit = 150
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        diskDir = caches.appendingPathComponent("TripMapSnapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
    }

    private func fileURL(for key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return diskDir.appendingPathComponent("\(safe).jpg")
    }

    func memoryImage(for key: String) -> UIImage? {
        memory.object(forKey: key as NSString)
    }

    func loadFromDisk(for key: String) -> UIImage? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else { return nil }
        memory.setObject(img, forKey: key as NSString)
        return img
    }

    func save(_ image: UIImage, for key: String) {
        memory.setObject(image, forKey: key as NSString)
        let url = fileURL(for: key)
        DispatchQueue.global(qos: .utility).async {
            if let data = image.jpegData(compressionQuality: 0.82) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}

private struct TripSnapshotMapView: View {
    let cacheKey: String
    let coordinates: [CLLocationCoordinate2D]
    let routePoints: [CLLocationCoordinate2D]
    let dark: Bool

    @State private var snapshotImage: UIImage?

    init(cacheKey: String, coordinates: [CLLocationCoordinate2D], routePoints: [CLLocationCoordinate2D], dark: Bool) {
        self.cacheKey = cacheKey
        self.coordinates = coordinates
        self.routePoints = routePoints
        self.dark = dark
        _snapshotImage = State(initialValue: TripSnapshotCache.shared.memoryImage(for: cacheKey))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let img = snapshotImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: dark
                            ? [Color(red: 0.08, green: 0.11, blue: 0.20), Color(red: 0.13, green: 0.17, blue: 0.28)]
                            : [Color(red: 0.86, green: 0.91, blue: 0.95), Color(red: 0.92, green: 0.95, blue: 0.97)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .task(id: cacheKey) {
                if snapshotImage != nil { return }
                if let mem = TripSnapshotCache.shared.memoryImage(for: cacheKey) {
                    snapshotImage = mem
                    return
                }
                let keyCopy = cacheKey
                if let disk = await Task.detached(priority: .userInitiated, operation: {
                    TripSnapshotCache.shared.loadFromDisk(for: keyCopy)
                }).value {
                    snapshotImage = disk
                    return
                }
                let size = CGSize(width: max(geo.size.width, 220), height: max(geo.size.height, 120))
                if let rendered = await renderSnapshot(size: size) {
                    TripSnapshotCache.shared.save(rendered, for: cacheKey)
                    snapshotImage = rendered
                }
            }
        }
    }

    private func renderSnapshot(size: CGSize) async -> UIImage? {
        let allCoords = coordinates + routePoints
        guard !allCoords.isEmpty else { return nil }
        let lats = allCoords.map(\.latitude), lons = allCoords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }

        let options = MKMapSnapshotter.Options()
        options.size = size
        options.scale = UIScreen.main.scale
        options.mapType = .mutedStandard
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: min(max((maxLat - minLat) * 2.1, dark ? 2.4 : 0.35), 110),
                longitudeDelta: min(max((maxLon - minLon) * 2.1, dark ? 3.0 : 0.35), 160)
            )
        )

        let snapshotter = MKMapSnapshotter(options: options)
        return await withCheckedContinuation { continuation in
            snapshotter.start(with: DispatchQueue.global(qos: .userInitiated)) { snapshot, _ in
                guard let snapshot else {
                    continuation.resume(returning: nil)
                    return
                }
                let img = UIGraphicsImageRenderer(size: size).image { ctx in
                    snapshot.image.draw(at: .zero)
                    let cg = ctx.cgContext

                    if routePoints.count >= 2 {
                        cg.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.85).cgColor)
                        cg.setLineWidth(2.6)
                        cg.setLineCap(.round)
                        cg.setLineJoin(.round)
                        cg.beginPath()
                        for (idx, c) in routePoints.enumerated() {
                            let pt = snapshot.point(for: c)
                            if idx == 0 { cg.move(to: pt) } else { cg.addLine(to: pt) }
                        }
                        cg.strokePath()
                    }

                    for c in coordinates {
                        let pt = snapshot.point(for: c)
                        if dark {
                            let colors = [UIColor.systemOrange.withAlphaComponent(0.65).cgColor, UIColor.systemOrange.withAlphaComponent(0).cgColor] as CFArray
                            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                                cg.drawRadialGradient(grad, startCenter: pt, startRadius: 2, endCenter: pt, endRadius: 16, options: [])
                            }
                            UIColor(red: 1.0, green: 0.94, blue: 0.72, alpha: 1).setFill()
                            cg.fillEllipse(in: CGRect(x: pt.x - 4.5, y: pt.y - 4.5, width: 9, height: 9))
                        } else {
                            UIColor.white.setFill()
                            cg.fillEllipse(in: CGRect(x: pt.x - 5.5, y: pt.y - 5.5, width: 11, height: 11))
                            UIColor.systemOrange.setFill()
                            cg.fillEllipse(in: CGRect(x: pt.x - 3.8, y: pt.y - 3.8, width: 7.6, height: 7.6))
                        }
                    }
                }
                continuation.resume(returning: img)
            }
        }
    }
}

// MARK: - Unified Single-Card Red-Header Calendar Badge (Matches Original DateBadge)

private struct TripCalendarBadge: View {
    let start: Date
    let end: Date

    private var lastDay: Date {
        max(start, end.addingTimeInterval(-1))
    }

    private var monthText: String {
        let cal = Calendar.current
        let m1 = cal.component(.month, from: start)
        let m2 = cal.component(.month, from: lastDay)
        return m1 == m2 ? "\(m1)月" : "\(m1)月–\(m2)月"
    }

    private var dayRangeText: String {
        let cal = Calendar.current
        let d1 = cal.component(.day, from: start)
        let d2 = cal.component(.day, from: lastDay)
        let sameMonth = cal.isDate(start, equalTo: lastDay, toGranularity: .month)
        return (d1 == d2 && sameMonth) ? "\(d1)" : "\(d1)–\(d2)"
    }

    private var yearText: String {
        String(Calendar.current.component(.year, from: start))
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(monthText)
                .font(.caption2.weight(.heavy))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(red: 0.90, green: 0.24, blue: 0.24))

            VStack(spacing: 1) {
                Text(dayRangeText)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(yearText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.black.opacity(0.55))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(Color.white)
        }
        .frame(minWidth: 66, maxWidth: 82)
        .background(Color.white)
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }
}

// MARK: - 1:1 Original TripDetailView (PhotoStack + Map + 2x2 Metrics + Inline Notes + Postcard + Every Day Cards)

struct TripDetailView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var engine: LocationEngine
    @Environment(\.dismiss) private var dismiss

    let trip: Trip
    @State private var notesDraft: String
    @State private var showFullMap = false
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    @State private var selectedStay: Stay?
    @State private var shareActivityURL: URL?
    @State private var tripPhotos: [PhotoPreviewItem] = []
    @State private var totalPhotoCount: Int = 0

    init(trip: Trip) {
        self.trip = trip
        _notesDraft = State(initialValue: trip.notes)
    }

    private var currentTrip: Trip {
        store.trips.first { $0.id == trip.id } ?? trip
    }

    private var chunks: [TrackChunk] { store.chunks(for: currentTrip) }
    private var stays: [Stay] { store.stays(for: currentTrip) }
    private var allPoints: [TrackPoint] { chunks.flatMap(\.points) }
    private var totalDistance: Double {
        chunks.reduce(0.0) { $0 + $1.distance }
            + (engine.activeTripID == currentTrip.id ? TrackPoint.distance(of: engine.pendingPoints) : 0)
    }
    private var climb: Double { TrackPoint.elevationGain(of: allPoints) }
    private var countries: [String] { stays.compactMap(\.countryCode).removingDuplicates() }

    private var tripDays: [(day: Date, stays: [Stay])] {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: currentTrip.startDate)
        let endDate = currentTrip.endDate ?? Date()
        let lastDay = cal.startOfDay(for: max(currentTrip.startDate, endDate.addingTimeInterval(-1)))
        var result: [(Date, [Stay])] = []
        var cursor = startDay
        while cursor <= lastDay {
            let next = cal.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86_400)
            let dayStays = stays.filter { $0.arrival < next && ($0.departure ?? Date()) > cursor }
            result.append((cursor, dayStays))
            cursor = next
        }
        return result
    }

    var body: some View {
        let activeTrip = currentTrip
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. 照片扇形叠放区
                if !tripPhotos.isEmpty {
                    photoStackSection
                }

                // 2. 路线地图卡片 + 查看地图
                Button {
                    showFullMap = true
                } label: {
                    ZStack(alignment: .bottomLeading) {
                        DayRouteMapView(
                            chunks: chunks,
                            pendingPoints: engine.activeTripID == activeTrip.id ? engine.pendingPoints : [],
                            stays: stays,
                            currentLocation: engine.currentLocation
                        )
                        .allowsHitTesting(false)

                        if chunks.isEmpty && stays.isEmpty {
                            Rectangle().fill(.ultraThinMaterial)
                            Label(activeTrip.isActive ? "出发后轨迹会出现在这里" : "这段时间没有轨迹", systemImage: "map")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            Label("查看地图", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(12)
                        }
                    }
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .buttonStyle(PressableStyle())

                // 3. 2x2 指标网格（距离 / 用时 / 地点 / 国家与地区）
                if activeTrip.isRecording {
                    MetricGrid2x2 {
                        MetricTile(title: "距离", value: Self.cnDistance(totalDistance), symbol: "point.topleft.down.curvedto.point.filled.bottomright.up", tint: .blue)
                    } topRight: {
                        MetricTile(title: "用时", value: Formatters.duration(activeTrip.duration), symbol: "clock.fill", tint: .orange)
                    } bottomLeft: {
                        MetricTile(title: "配速", value: Formatters.pace(distance: totalDistance, duration: activeTrip.duration), symbol: "speedometer", tint: .green)
                    } bottomRight: {
                        MetricTile(title: "爬升", value: "\(Int(climb.rounded())) m", symbol: "mountain.2.fill", tint: .brown)
                    }
                } else {
                    MetricGrid2x2 {
                        MetricTile(title: "距离", value: Self.cnDistance(totalDistance), symbol: "point.topleft.down.curvedto.point.filled.bottomright.up", tint: .blue)
                    } topRight: {
                        MetricTile(title: "用时", value: "\(max(1, tripDays.count)) 天", symbol: "clock.fill", tint: .orange)
                    } bottomLeft: {
                        MetricTile(title: "地点", value: "\(stays.count)", symbol: "mappin.and.ellipse", tint: .pink)
                    } bottomRight: {
                        MetricTile(
                            title: "国家与地区",
                            value: countries.isEmpty ? "—" : countries.map { CountryText.flag(for: $0) }.joined(),
                            symbol: "flag.fill",
                            tint: .red
                        )
                    }
                }

                // 4. 备注（原版内联输入框）
                VStack(alignment: .leading, spacing: 10) {
                    Text("备注")
                        .font(.title3.bold())
                        .padding(.horizontal, 4)

                    TextField(activeTrip.isRecording ? "记下这次的感受…" : "记下这段旅程的故事…", text: $notesDraft, axis: .vertical)
                        .lineLimit(3...10)
                        .padding(16)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .onChange(of: notesDraft) { newVal in
                            saveNotes(newVal)
                        }
                }

                // 5. 旅行明信片卡片（1:1 原版 PostcardInvite 样式）
                if !activeTrip.isActive && !stays.isEmpty {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if let url = ShareCardGenerator.renderTripCard(
                            trip: activeTrip,
                            distance: totalDistance,
                            stays: stays,
                            chunks: chunks,
                            privacyZones: store.privacyZones
                        ) {
                            shareActivityURL = url
                        }
                    } label: {
                        HStack(spacing: 14) {
                            TripSnapshotMapView(
                                cacheKey: "postcard-\(activeTrip.id.uuidString)-\(stays.count)",
                                coordinates: Array(stays.prefix(15).map { $0.coordinate.onMap }),
                                routePoints: Array(chunks.prefix(4).flatMap { $0.points.simplified(tolerance: 60).map { $0.coordinate.onMap } }),
                                dark: false
                            )
                            .frame(width: 78, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white, lineWidth: 2.5))
                            .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
                            .rotationEffect(.degrees(-3))

                            VStack(alignment: .leading, spacing: 3) {
                                Text("旅行明信片")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("做成一张明信片，分享出去，或寄给一年后的自己。")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                        .padding(16)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }

                // 6. 每一天（按天分组卡片 + 当天轨迹 + 圆形缩略图地点行）
                if !activeTrip.isRecording && !stays.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("每一天")
                                .font(.title3.bold())
                            Spacer()
                            Text("\(tripDays.count) 天")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 4)

                        ForEach(Array(tripDays.enumerated()), id: \.offset) { index, entry in
                            VStack(alignment: .leading, spacing: 0) {
                                NavigationLink {
                                    DayDetailPage(date: entry.day)
                                } label: {
                                    HStack(spacing: 8) {
                                        Text("第 \(index + 1) 天")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text(Self.daySubtitle(entry.day))
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Label("当天轨迹", systemImage: "calendar")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.blue)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 13)
                                }
                                .buttonStyle(.plain)

                                if entry.stays.isEmpty {
                                    Text("这一天没有停留记录")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 16)
                                        .padding(.bottom, 14)
                                } else {
                                    ForEach(entry.stays) { stay in
                                        Button {
                                            selectedStay = stay
                                        } label: {
                                            TripDayStayRow(stay: stay)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.bottom, 6)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("\(activeTrip.coverEmoji) \(activeTrip.title)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        showEditSheet = true
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }

                    Button {
                        if let url = ShareCardGenerator.renderTripCard(
                            trip: activeTrip,
                            distance: totalDistance,
                            stays: stays,
                            chunks: chunks,
                            privacyZones: store.privacyZones
                        ) {
                            shareActivityURL = url
                        }
                    } label: {
                        Label("分享旅程明信片", systemImage: "photo.artframe")
                    }

                    Button {
                        if let url = GPXExporter.export(
                            chunks: chunks,
                            stays: stays,
                            privacyZones: store.privacyZones,
                            filename: "\(activeTrip.title).gpx"
                        ) {
                            shareActivityURL = url
                        }
                    } label: {
                        Label("导出 GPX", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label(activeTrip.isRecording ? "删除记录" : "删除旅程", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditTripSheet(trip: activeTrip)
        }
        .sheet(item: $selectedStay) { stay in
            StayDetailSheet(stay: stay)
        }
        .sheet(isPresented: Binding(get: { shareActivityURL != nil }, set: { if !$0 { shareActivityURL = nil } })) {
            if let url = shareActivityURL {
                TripActivityShareSheet(items: [url])
            }
        }
        .fullScreenCover(isPresented: $showFullMap) {
            ZStack(alignment: .topTrailing) {
                DayRouteMapView(
                    chunks: chunks,
                    pendingPoints: engine.activeTripID == activeTrip.id ? engine.pendingPoints : [],
                    stays: stays,
                    currentLocation: engine.currentLocation
                )
                .ignoresSafeArea()
                Button {
                    showFullMap = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.primary)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding()
                }
            }
        }
        .confirmationDialog("确定删除这条记录吗？底层轨迹点不会被删除。", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if engine.activeTripID == activeTrip.id { engine.endActiveRecording() }
                store.deleteTrip(id: activeTrip.id)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        }
        .task(id: "\(activeTrip.id.uuidString)-\(activeTrip.startDate.timeIntervalSince1970)-\(activeTrip.endDate?.timeIntervalSince1970 ?? 0)") {
            notesDraft = activeTrip.notes
            await loadTripPhotos(activeTrip)
        }
    }

    private var photoStackSection: some View {
        let preview = Array(tripPhotos.prefix(5))
        let overflow = max(0, totalPhotoCount - preview.count)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("照片")
                    .font(.title3.bold())
                Text("\(totalPhotoCount)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)

            HStack(spacing: 14) {
                ZStack(alignment: .leading) {
                    ForEach(Array(preview.enumerated()).reversed(), id: \.element.id) { idx, item in
                        Image(uiImage: item.thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 112, height: 132)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white, lineWidth: 2.5))
                            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                            .rotationEffect(.degrees(Double(idx) * 2.2 - 1.5))
                            .offset(x: CGFloat(idx) * 28)
                    }
                }
                .frame(width: 112 + CGFloat(max(0, preview.count - 1)) * 28, height: 142, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    PhotoLightboxPresenter.present(items: tripPhotos, startIndex: 0)
                }

                Spacer(minLength: 4)

                if overflow > 0 {
                    Button {
                        PhotoLightboxPresenter.present(items: tripPhotos, startIndex: 0)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.body.weight(.semibold))
                            Text("+\(overflow)")
                                .font(.caption.weight(.bold).monospacedDigit())
                        }
                        .foregroundColor(.blue)
                        .frame(width: 58, height: 58)
                        .background(Color.blue.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func loadTripPhotos(_ trip: Trip) async {
        let auth = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard auth == .authorized || auth == .limited else { return }
        let assets = await TripPhotoFetcher.fetchAssets(from: trip.startDate, to: trip.endDate ?? Date())
        totalPhotoCount = assets.count
        guard !assets.isEmpty else { return }
        let sample = Array(assets.prefix(30))
        var loaded: [PhotoPreviewItem] = []
        for asset in sample {
            if let img = await TripPhotoFetcher.thumbnail(for: asset, side: 320) {
                loaded.append(PhotoPreviewItem(
                    id: asset.localIdentifier,
                    assetID: asset.localIdentifier,
                    thumbnail: img,
                    caption: trip.title
                ))
            }
        }
        tripPhotos = loaded
    }

    private func saveNotes(_ newValue: String) {
        var updated = currentTrip
        guard updated.notes != newValue else { return }
        updated.notes = newValue
        store.upsertTrip(updated)
    }

    private static func cnDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            let km = meters / 1000.0
            if km >= 10 {
                let s = NumberFormatter.localizedString(from: NSNumber(value: Int(km.rounded())), number: .decimal)
                return "\(s) 公里"
            }
            return String(format: "%.1f 公里", km)
        }
        return "\(Int(meters.rounded())) 米"
    }

    private static func daySubtitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f.string(from: date)
    }
}

private struct TripDayStayRow: View {
    let stay: Stay
    @State private var thumb: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let thumb {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle().fill(stay.category.tint.opacity(0.14))
                    PlaceIcon(category: stay.category, isLandmark: stay.isLandmark, size: 22)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(stay.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                let timeStr: String = {
                    if let dep = stay.departure {
                        return "\(Formatters.timeHM(stay.arrival)) – \(Formatters.timeHM(dep))"
                    }
                    return Formatters.timeHM(stay.arrival)
                }()
                Text([stay.city, timeStr].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .task(id: stay.id) {
            let items = await StintPhotoFetcher.shared.stayPhotoItems(for: stay)
            thumb = items.first?.thumbnail
        }
    }
}

private struct TripActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct EditTripSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    private static let emojiChoices = [
        "🧭", "🏔️", "🏝️", "🏙️", "✈️", "🚗", "🧳", "🚆", "🏕️", "🍜", "📷", "🌸", "🍁", "❄️"
    ]

    let trip: Trip
    @State private var title: String
    @State private var coverEmoji: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var notes: String

    init(trip: Trip) {
        self.trip = trip
        _title = State(initialValue: trip.title)
        _coverEmoji = State(initialValue: trip.coverEmoji)
        _startDate = State(initialValue: trip.startDate)
        _endDate = State(initialValue: trip.endDate ?? trip.startDate)
        _notes = State(initialValue: trip.notes)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("名称")
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.secondary)
                            .padding(.leading, 12)

                        VStack(spacing: 0) {
                            TextField("输入旅程名称", text: $title)
                                .font(.body)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)

                            Divider().padding(.leading, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(Self.emojiChoices, id: \.self) { emoji in
                                        let selected = coverEmoji == emoji
                                        Button {
                                            UISelectionFeedbackGenerator().selectionChanged()
                                            coverEmoji = emoji
                                        } label: {
                                            Text(emoji)
                                                .font(.system(size: 26))
                                                .frame(width: 46, height: 46)
                                                .background(
                                                    selected ? Color.blue.opacity(0.16) : Color.clear,
                                                    in: Circle()
                                                )
                                                .overlay(
                                                    Circle()
                                                        .stroke(selected ? Color.blue : Color.clear, lineWidth: 1.8)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("时间")
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.secondary)
                            .padding(.leading, 12)

                        VStack(spacing: 0) {
                            DatePicker("开始", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)

                            Divider().padding(.leading, 16)

                            DatePicker("结束", selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                        }
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("备注")
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.secondary)
                            .padding(.leading, 12)

                        TextEditor(text: $notes)
                            .frame(minHeight: 110)
                            .padding(10)
                            .scrollContentBackground(.hidden)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("编辑旅程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .frame(width: 32, height: 32)
                            .background(Color(.tertiarySystemFill), in: Circle())
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        var updated = trip
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedTitle.isEmpty { updated.title = trimmedTitle }
                        updated.coverEmoji = coverEmoji
                        updated.startDate = startDate
                        updated.endDate = max(startDate, endDate)
                        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.upsertTrip(updated)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.blue, in: Circle())
                    }
                }
            }
            .onChange(of: startDate) { newStart in
                if endDate < newStart { endDate = newStart }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

struct NewRecordingSheet: View {
    @EnvironmentObject private var engine: LocationEngine
    @Environment(\.dismiss) private var dismiss

    @State private var activity: ActivityType = .walking
    @State private var title = ""

    private var defaultPlaceholder: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return "\(activity.title) · \(f.string(from: Date()))"
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Text("开始记录")
                    .font(.headline)

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    engine.beginRecording(activity: activity, title: finalTitle.isEmpty ? defaultPlaceholder : finalTitle)
                    dismiss()
                } label: {
                    Image(systemName: "record.circle")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.blue, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(ActivityType.allCases) { item in
                        let selected = activity == item
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.easeInOut(duration: 0.18)) {
                                activity = item
                            }
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(selected ? Color.orange : Color.orange.opacity(0.16))
                                        .frame(width: 58, height: 58)
                                    Image(systemName: item.symbol)
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundColor(selected ? .white : .orange)
                                }
                                Text(item.title)
                                    .font(.subheadline.weight(selected ? .semibold : .regular))
                                    .foregroundColor(selected ? .primary : .secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 8)

                Divider().padding(.horizontal, 16)

                TextField(defaultPlaceholder, text: $title)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 16)

            Text("手动记录使用更高的定位精度，和全天自动记录互不影响。结束后保存在“旅程”页的“记录”里。")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .presentationDetents([.height(340), .medium])
        .presentationDragIndicator(.visible)
    }
}

struct NewTripSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("旅程信息") {
                    TextField("旅程名称（如：杭州 3 日游）", text: $title)
                    DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                    DatePicker("结束日期", selection: $endDate, in: startDate..., displayedComponents: .date)
                }
                Section("备注") {
                    TextField("写点回忆…", text: $notes)
                }
            }
            .navigationTitle("新建旅程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let cal = Calendar.current
                        let s = cal.startOfDay(for: startDate)
                        let e = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: endDate)) ?? endDate
                        let name = title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未命名旅程"
                        store.upsertTrip(Trip(title: name, startDate: s, endDate: e, notes: notes, coverEmoji: "🧳"))
                        dismiss()
                    }
                }
            }
        }
    }
}
