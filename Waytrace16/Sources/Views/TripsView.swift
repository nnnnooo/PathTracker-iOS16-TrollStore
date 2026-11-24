import SwiftUI
import MapKit

struct TripsView: View {
    @Binding var showingSettings: Bool
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var engine: LocationEngine

    private struct DiscoveredCardData: Identifiable, Sendable {
        let item: TripFinder.DiscoveredTrip
        let coordinates: [CLLocationCoordinate2D]
        var id: String { item.id }
    }

    private struct TripCardModel: Identifiable, Sendable {
        let trip: Trip
        let distance: Double
        let stayCount: Int
        let cities: [String]
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

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
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
                            ForEach(yearGroups) { group in
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(String(group.year))
                                            .font(.system(size: 28, weight: .bold, design: .rounded))
                                        Text("\(group.cards.count) 段 · \(group.totalDays) 天")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 4)

                                    ForEach(group.cards) { model in
                                        NavigationLink {
                                            TripDetailView(trip: model.trip)
                                        } label: {
                                            tripCoverCard(model)
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
                        Button { showNewRecording = true } label: {
                            Label("开始高精度记录", systemImage: "record.circle")
                        }
                        Button { showNewTrip = true } label: {
                            Label("新建多日旅程", systemImage: "suitcase.rolling")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                    ProfileToolbarButton(showingSettings: $showingSettings)
                }
            }
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

                    // 1. Discovered trips (keep full list so count & 查看全部 match original UI)
                    let found = TripFinder.discover(from: staysSnapshot, existingTrips: tripsSnapshot)
                    let discCards: [DiscoveredCardData] = found.map { item in
                        let coords = staysSnapshot
                            .filter { $0.arrival >= item.startDate && $0.arrival <= item.endDate }
                            .prefix(12)
                            .map { $0.coordinate.onMap }
                        return DiscoveredCardData(item: item, coordinates: Array(coords))
                    }

                    // 2. Build TripCardModels once off main thread
                    func makeCard(_ trip: Trip) -> TripCardModel {
                        let end = trip.endDate ?? Date()
                        let tripStays = staysSnapshot.filter { $0.arrival >= trip.startDate && $0.arrival <= end }
                        let tripChunks = chunksSnapshot.filter {
                            $0.tripID == trip.id || ($0.endDate >= trip.startDate && $0.startDate <= end)
                        }
                        let dist = tripChunks.reduce(0.0) { $0 + $1.distance }
                        let cities = tripStays.compactMap(\.city).removingDuplicates()
                        let coords = Array(tripStays.prefix(20).map { $0.coordinate.onMap })
                        let routePts = tripChunks.prefix(6).flatMap { chunk -> [CLLocationCoordinate2D] in
                            let pts = chunk.points
                            let step = max(1, pts.count / 25)
                            return stride(from: 0, to: pts.count, by: step).map { pts[$0].coordinate.onMap }
                        }
                        let d = max(1, (cal.dateComponents([.day], from: cal.startOfDay(for: trip.startDate), to: cal.startOfDay(for: max(trip.startDate, end.addingTimeInterval(-1)))).day ?? 0) + 1)
                        return TripCardModel(
                            trip: trip,
                            distance: dist,
                            stayCount: tripStays.count,
                            cities: Array(cities.prefix(3)),
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

    // MARK: - Discovered Trips (1:1 Original Photo-Cover Carousel + 查看全部)

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

    // MARK: - Saved Trip Cover Card (Disk+Memory Cached Snapshot + Unified Calendar Badge)

    private func tripCoverCard(_ model: TripCardModel) -> some View {
        let trip = model.trip
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                TripSnapshotMapView(
                    cacheKey: "trip-\(trip.id.uuidString)-\(model.stayCount)",
                    coordinates: model.coordinates,
                    routePoints: model.routePoints,
                    dark: false
                )
                .frame(height: 185)

                TripCalendarBadge(start: trip.startDate, end: trip.endDate ?? trip.startDate)
                    .padding(12)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(trip.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                }
                HStack(spacing: 6) {
                    if !model.cities.isEmpty {
                        Text(model.cities.joined(separator: " · "))
                    }
                    if model.distance > 0 {
                        Text("· \(Formatters.distance(model.distance))")
                    }
                    Text("· \(model.stayCount) 个地点")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
            .padding(16)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
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

// MARK: - Unified Single-Card Red-Header Calendar Badge (Fixed iOS 16 Clipping)

private struct TripCalendarBadge: View {
    let start: Date
    let end: Date

    private var monthText: String {
        "\(Calendar.current.component(.month, from: start))月"
    }

    private var dayRangeText: String {
        let cal = Calendar.current
        let d1 = cal.component(.day, from: start)
        let d2 = cal.component(.day, from: max(start, end.addingTimeInterval(-1)))
        return d1 == d2 ? "\(d1)" : "\(d1)–\(d2)"
    }

    private var yearText: String {
        String(Calendar.current.component(.year, from: start))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(red: 0.90, green: 0.24, blue: 0.24)
                Text(monthText)
                    .font(.caption2.bold())
                    .foregroundColor(.white)
            }
            .frame(height: 20)

            VStack(spacing: 1) {
                Text(dayRangeText)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(yearText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(Color.white)
        }
        .frame(width: 72)
        .background(Color.white)
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }
}

// MARK: - Trip Detail & Sheets

struct TripDetailView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var engine: LocationEngine
    @Environment(\.dismiss) private var dismiss

    let trip: Trip
    @State private var exportedURL: URL?
    @State private var shareCardURL: URL?
    @State private var showDeleteConfirm = false
    @State private var showEditSheet = false

    private var currentTrip: Trip {
        store.trips.first { $0.id == trip.id } ?? trip
    }

    private var chunks: [TrackChunk] { store.chunks(for: currentTrip) }
    private var stays: [Stay] { store.stays(for: currentTrip) }
    private var allPoints: [TrackPoint] { chunks.flatMap(\.points) }
    private var totalDistance: Double { chunks.reduce(0.0) { $0 + $1.distance } }
    private var climb: Double { TrackPoint.elevationGain(of: allPoints) }

    var body: some View {
        let activeTrip = currentTrip
        ScrollView {
            VStack(spacing: 16) {
                DayRouteMapView(
                    chunks: chunks,
                    pendingPoints: engine.activeTripID == activeTrip.id ? engine.pendingPoints : [],
                    stays: stays,
                    currentLocation: engine.currentLocation
                )
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                HStack(spacing: 0) {
                    statCell("距离", Formatters.distance(totalDistance))
                    Divider().frame(height: 30)
                    statCell("用时", Formatters.duration(activeTrip.duration))
                    Divider().frame(height: 30)
                    if activeTrip.isRecording {
                        statCell("配速", Formatters.pace(distance: totalDistance, duration: activeTrip.duration))
                    } else {
                        statCell("地点", "\(stays.count)")
                    }
                }
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                if activeTrip.isRecording && climb > 0 {
                    HStack {
                        Label("累计爬升", systemImage: "arrow.up.right")
                        Spacer()
                        Text("\(Int(climb.rounded())) m").fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("备注", systemImage: "note.text")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            showEditSheet = true
                        } label: {
                            Text(activeTrip.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "添加备注" : "修改")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    if activeTrip.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("暂无备注，点击此处可记录这段旅程的心情或细节…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text(activeTrip.notes)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture {
                    UISelectionFeedbackGenerator().selectionChanged()
                    showEditSheet = true
                }

                if !stays.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("经过的地点").font(.headline).padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            ForEach(Array(stays.enumerated()), id: \.element.id) { idx, stay in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(stay.displayName).font(.subheadline.weight(.medium))
                                        Text("\(Formatters.dayTitle(stay.arrival)) \(Formatters.timeHM(stay.arrival))")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(Formatters.duration(stay.duration))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                if idx < stays.count - 1 { Divider().padding(.leading, 14) }
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }

                if let cardURL = shareCardURL {
                    ShareLink(item: cardURL) {
                        Label("分享旅程明信片图片", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        shareCardURL = ShareCardGenerator.renderTripCard(
                            trip: activeTrip,
                            distance: totalDistance,
                            stays: stays,
                            chunks: chunks,
                            privacyZones: store.privacyZones
                        )
                    } label: {
                        Label("生成旅程分享明信片", systemImage: "photo.artframe")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let url = exportedURL {
                    ShareLink(item: url) {
                        Label("分享此旅程 GPX", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        exportedURL = GPXExporter.export(
                            chunks: chunks,
                            stays: stays,
                            privacyZones: store.privacyZones,
                            filename: "\(activeTrip.title).gpx"
                        )
                    } label: {
                        Label("导出此旅程 GPX（自动过滤隐私区域）", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button("删除此记录", role: .destructive) {
                    showDeleteConfirm = true
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(activeTrip.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("编辑") {
                    UISelectionFeedbackGenerator().selectionChanged()
                    showEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditTripSheet(trip: activeTrip)
        }
        .confirmationDialog("确定删除这条记录吗？底层轨迹点不会被删除。", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if engine.activeTripID == activeTrip.id { engine.endActiveRecording() }
                store.deleteTrip(id: activeTrip.id)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func statCell(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct EditTripSheet: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let trip: Trip
    @State private var title: String
    @State private var notes: String

    init(trip: Trip) {
        self.trip = trip
        _title = State(initialValue: trip.title)
        _notes = State(initialValue: trip.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("旅程名称") {
                    TextField("输入旅程名称", text: $title)
                }
                Section("备注") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 140)
                }
            }
            .navigationTitle("编辑旅程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var updated = trip
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedTitle.isEmpty { updated.title = trimmedTitle }
                        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.upsertTrip(updated)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct NewRecordingSheet: View {
    @EnvironmentObject private var engine: LocationEngine
    @Environment(\.dismiss) private var dismiss

    @State private var activity: ActivityType = .hiking
    @State private var title = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("运动类型") {
                    Picker("类型", selection: $activity) {
                        ForEach(ActivityType.allCases) { item in
                            Text("\(item.emoji) \(item.title)").tag(item)
                        }
                    }
                    .pickerStyle(.inline)
                }
                Section("名称（可选）") {
                    TextField("例如：西湖环线徒步", text: $title)
                }
            }
            .navigationTitle("开始高精度记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始") {
                        engine.beginRecording(activity: activity, title: title)
                        dismiss()
                    }
                }
            }
        }
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
