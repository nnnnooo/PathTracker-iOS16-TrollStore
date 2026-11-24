import SwiftUI
import MapKit
import PhotosUI

struct MustSeeView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var engine: LocationEngine
    @ObservedObject private var userStore = MustSeeUserStore.shared

    enum Filter: Int, Hashable { case all = 0, lit = 1, wished = 2, unlit = 3 }

    @State private var listType: MustSee.ListType = .china
    @State private var filter: Filter = .all
    @State private var selectedPlace: MustSeePlace?
    @State private var chinaVisited: [String: Date] = [:]
    @State private var worldVisited: [String: Date] = [:]
    @State private var isLoading = true

    private var places: [MustSeePlace] { listType.places }
    private var visitedMap: [String: Date] { listType == .china ? chinaVisited : worldVisited }
    private var visitedCount: Int { visitedMap.count }

    private var filteredPlaces: [MustSeePlace] {
        switch filter {
        case .all: return places
        case .lit: return places.filter { visitedMap[$0.id] != nil }
        case .wished: return places.filter { userStore.wishIDs.contains($0.id) && visitedMap[$0.id] == nil }
        case .unlit: return places.filter { visitedMap[$0.id] == nil }
        }
    }

    private var groupedRegions: [(name: String, places: [MustSeePlace])] {
        var order: [String] = []
        var groups: [String: [MustSeePlace]] = [:]
        for place in filteredPlaces {
            if groups[place.region] == nil { order.append(place.region) }
            groups[place.region, default: []].append(place)
        }
        let litRegions = Set(places.filter { visitedMap[$0.id] != nil }.map(\.region))
        let known = order.filter { litRegions.contains($0) }
        return (known + order.filter { !known.contains($0) }).map { ($0, groups[$0] ?? []) }
    }

    private var nearestUnlit: MustSeePlace? {
        guard !isLoading, let loc = engine.currentLocation ?? store.stays.first?.location else { return nil }
        return places
            .filter { visitedMap[$0.id] == nil }
            .min { $0.location.distance(from: loc) < $1.location.distance(from: loc) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                listPicker
                heroCard
                if let next = nearestUnlit { nextStopCard(next) }
                filterChips

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("正在匹配足迹…")
                        Spacer()
                    }
                    .padding(.vertical, 24)
                } else if filteredPlaces.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: filter == .wished ? "heart" : "sparkles")
                            .font(.title)
                            .foregroundColor(.secondary)
                        Text(filter == .wished ? "点一下 ♡，把想去的地方收进来" : "还没有点亮的地方，出发吧")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(groupedRegions, id: \.name) { group in
                            regionSection(group.name, members: group.places)
                        }
                    }
                }

                Text("清单由漫迹整理，参考世界遗产名录与国家 5A 级景区。在附近停留过，或在那里拍过照片，就会点亮。")
                    .font(.caption)
                    .foregroundColor(Color(.tertiaryLabel))
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("此生必去")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(store.stays.count)-\(userStore.revision)") {
            let staysSnapshot = store.stays
            let manualSnapshot = userStore.manualVisits
            let excludedSnapshot = userStore.excludedAutoIDs
            let result = await Task.detached(priority: .userInitiated) { () -> ([String: Date], [String: Date]) in
                let cn = MustSee.visitedMap(places: MustSee.china, stays: staysSnapshot, manual: manualSnapshot, excluded: excludedSnapshot)
                let wd = MustSee.visitedMap(places: MustSee.world, stays: staysSnapshot, manual: manualSnapshot, excluded: excludedSnapshot)
                return (cn, wd)
            }.value
            chinaVisited = result.0
            worldVisited = result.1
            isLoading = false
        }
        .sheet(item: $selectedPlace) { place in
            MustSeeDetailSheet(
                place: place,
                visitedDate: visitedMap[place.id],
                userLocation: engine.currentLocation ?? store.stays.first?.location
            )
        }
    }

    // MARK: - Top Dual Capsule Switcher (1:1 Upstream)

    private var listPicker: some View {
        HStack(spacing: 0) {
            ForEach(MustSee.ListType.allCases) { option in
                let isOn = option == listType
                let count = option == .china ? chinaVisited.count : worldVisited.count
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.easeInOut(duration: 0.25)) { listType = option }
                } label: {
                    VStack(spacing: 2) {
                        Text(option == .china ? "中国 100" : "世界 100")
                            .font(.headline)
                        Text("\(count) 处已点亮")
                            .font(.caption.monospacedDigit())
                            .opacity(0.78)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundColor(isOn ? .white : .primary)
                    .background {
                        if isOn {
                            Capsule().fill(
                                LinearGradient(
                                    colors: [Color(red: 0.13, green: 0.16, blue: 0.32), Color(red: 0.27, green: 0.20, blue: 0.42)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
    }

    // MARK: - Unified Night Star Map + 100-Tile Hero Card (1:1 Upstream)

    private var heroCard: some View {
        let nightBg = Color(red: 0.06, green: 0.07, blue: 0.13)
        let pct = places.isEmpty ? 0 : Int((Double(visitedCount) / Double(places.count) * 100).rounded())

        return VStack(spacing: 0) {
            MustSeeStarMap(
                places: places,
                visitedIDs: Set(visitedMap.keys),
                wishedIDs: userStore.wishIDs,
                isChina: listType == .china
            ) { place in
                selectedPlace = place
            }
            .frame(height: 310)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, nightBg], startPoint: .top, endPoint: .bottom)
                    .frame(height: 84)
                    .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(visitedCount)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [Color(red: 1, green: 0.86, blue: 0.5), .orange], startPoint: .top, endPoint: .bottom)
                        )
                    Text("/ \(places.count)")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundColor(.white.opacity(0.45))
                    Spacer()
                    Text("\(pct)%")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundColor(.white.opacity(0.62))
                }

                Text(tagline)
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.92))

                // 100-square glowing progress grid (20 x 5)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 20), spacing: 4) {
                    ForEach(0..<places.count, id: \.self) { idx in
                        let lit = idx < visitedCount
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(
                                lit
                                ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.45), .orange], startPoint: .top, endPoint: .bottom))
                                : AnyShapeStyle(Color.white.opacity(0.11))
                            )
                            .aspectRatio(1, contentMode: .fit)
                            .shadow(color: lit ? .orange.opacity(0.6) : .clear, radius: 3)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 20)
            .background(nightBg)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    private var tagline: String {
        switch visitedCount {
        case 0: return "第一盏灯，等你去点亮"
        case 1..<10: return "已经出发了，前面还有很多风景"
        case 10..<30: return "走过的地方，都成了你的一部分"
        case 30..<60: return "你看过的世界，比大多数人都辽阔"
        case 60..<places.count: return "剩下的，是留给未来的惊喜"
        default: return "一百处，你都去过了"
        }
    }

    // MARK: - Nearest Unlit Next Stop Card

    private func nextStopCard(_ place: MustSeePlace) -> some View {
        let loc = engine.currentLocation ?? store.stays.first?.location
        let km = loc.map { Int(($0.distance(from: place.location) / 1000).rounded()) } ?? 0
        return Button { selectedPlace = place } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.indigo.opacity(0.15))
                    Image(systemName: "location.north.line.fill").foregroundColor(.indigo)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("离你最近的下一站").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                    Text(place.name).font(.headline).foregroundColor(.primary)
                    Text("\(place.region) · 约 \(km) 公里").font(.subheadline).foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        let wishedCount = places.filter { userStore.wishIDs.contains($0.id) && visitedMap[$0.id] == nil }.count
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(.all, title: "全部", count: places.count)
                filterChip(.lit, title: "已点亮", count: visitedCount)
                filterChip(.wished, title: "想去", count: wishedCount)
                filterChip(.unlit, title: "还没去", count: places.count - visitedCount)
            }
        }
    }

    private func filterChip(_ value: Filter, title: String, count: Int) -> some View {
        let on = filter == value
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.2)) { filter = value }
        } label: {
            HStack(spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text("\(count)").font(.caption.weight(.semibold).monospacedDigit()).opacity(0.75)
            }
            .foregroundColor(on ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(on ? Color.accentColor : Color(.secondarySystemGroupedBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Region Sections & Place Rows

    private func regionSection(_ name: String, members: [MustSeePlace]) -> some View {
        let allInRegion = places.filter { $0.region == name }
        let litInRegion = allInRegion.filter { visitedMap[$0.id] != nil }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.title3.bold())
                Spacer()
                Text("\(litInRegion) / \(allInRegion.count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundColor(litInRegion == allInRegion.count ? .orange : .secondary)
                if litInRegion == allInRegion.count {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(members.enumerated()), id: \.element.id) { idx, place in
                    placeRow(place)
                    if idx < members.count - 1 {
                        Divider().padding(.leading, 80)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func placeRow(_ place: MustSeePlace) -> some View {
        let litDate = visitedMap[place.id]
        let wished = userStore.wishIDs.contains(place.id)
        return HStack(spacing: 0) {
            Button { selectedPlace = place } label: {
                HStack(spacing: 14) {
                    MustSeePlaceThumbnail(place: place, litDate: litDate)
                        .frame(width: 52, height: 52)
                        .overlay(alignment: .bottomTrailing) {
                            if litDate != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white, .orange)
                                    .background(Circle().fill(Color(.secondarySystemGroupedBackground)).padding(2))
                                    .offset(x: 4, y: 4)
                            }
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .font(.body.weight(litDate != nil ? .semibold : .regular))
                            .foregroundColor(.primary)
                        if let date = litDate {
                            Text(userStore.manualVisits[place.id] != nil ? "去过 · 手动点亮" : Formatters.dayTitle(date))
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else if wished {
                            Text("想去").font(.caption).foregroundColor(.pink)
                        } else {
                            Text(place.kind.title).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if litDate != nil {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(Color(.tertiaryLabel))
                            .padding(.trailing, 14)
                    }
                }
                .padding(.leading, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if litDate == nil {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    userStore.toggleWish(place.id)
                } label: {
                    Image(systemName: wished ? "heart.fill" : "heart")
                        .font(.body.weight(.semibold))
                        .foregroundColor(wished ? .pink : .secondary.opacity(0.6))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
            }
        }
    }
}

// MARK: - Detail Sheet

private struct MustSeeDetailSheet: View {
    @ObservedObject private var userStore = MustSeeUserStore.shared
    @Environment(\.dismiss) private var dismiss

    let place: MustSeePlace
    let visitedDate: Date?
    let userLocation: CLLocation?

    @State private var pickedPhoto: PhotosPickerItem?

    var body: some View {
        let isWished = userStore.wishIDs.contains(place.id)
        let isManuallyLit = userStore.manualVisits[place.id] != nil
        let isExcluded = userStore.excludedAutoIDs.contains(place.id)
        let hasCustomCover = userStore.customCoverIDs.contains(place.id)
        let isAutoLit = visitedDate != nil && !isManuallyLit

        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    MustSeePlaceThumbnail(place: place, litDate: visitedDate)
                        .frame(width: 96, height: 96)
                        .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
                        .padding(.top, 12)

                    VStack(spacing: 6) {
                        Text(place.name).font(.title2.bold())
                        Text("\(place.region) · \(place.nameEn)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 16) {
                        Label(place.kind.title, systemImage: place.kind.symbol)
                        if let loc = userLocation {
                            let km = place.location.distance(from: loc) / 1000.0
                            Label(String(format: "距你 %.0f km", km), systemImage: "location.fill")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    if let date = visitedDate {
                        Text(isManuallyLit ? "已手动点亮" : "已于 \(Formatters.dayTitle(date)) 自动点亮")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    } else if isExcluded {
                        Text("已标记为未去过（已忽略误识别）")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }

                    VStack(spacing: 10) {
                        // 1. Custom cover photo picker
                        HStack(spacing: 8) {
                            PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                                Label(hasCustomCover ? "更换封面照片" : "手动选择封面照片", systemImage: "photo.on.rectangle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)

                            if hasCustomCover {
                                Button(role: .destructive) {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    userStore.removeCustomCover(for: place.id)
                                } label: {
                                    Text("恢复默认")
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        // 2. Manual status correction (handle false-positive auto-detections like 故宫)
                        if isAutoLit {
                            Button(role: .destructive) {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                userStore.markAsNotVisited(place.id)
                            } label: {
                                Label("识别有误：标记为未去过", systemImage: "xmark.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        } else {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                userStore.toggleManualVisit(place.id)
                            } label: {
                                Label(isManuallyLit ? "取消手动点亮" : "我去过这里（手动点亮）", systemImage: isManuallyLit ? "checkmark.circle.fill" : "sparkles")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)

                            if isExcluded {
                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    userStore.restoreAutoVisit(place.id)
                                } label: {
                                    Label("恢复自动识别", systemImage: "arrow.uturn.backward.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        if visitedDate == nil {
                            Button { userStore.toggleWish(place.id) } label: {
                                Label(isWished ? "已加入想去清单" : "加入想去清单", systemImage: isWished ? "heart.fill" : "heart")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.pink)
                        }

                        Button {
                            let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate.onMap))
                            item.name = place.name
                            item.openInMaps()
                        } label: {
                            Label("在 Apple 地图中打开", systemImage: "map")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onChange(of: pickedPhoto) { newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            userStore.saveCustomCover(data, for: place.id)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Dark Night Star Map (MKMapView with Cached Radial Glow Images)

private final class MustSeeAnnotation: NSObject, MKAnnotation {
    let place: MustSeePlace
    let lit: Bool
    let wished: Bool
    let coordinate: CLLocationCoordinate2D
    var title: String? { place.name }
    var subtitle: String? { place.region }

    init(place: MustSeePlace, lit: Bool, wished: Bool) {
        self.place = place
        self.lit = lit
        self.wished = wished
        self.coordinate = place.coordinate.onMap
    }
}

private struct MustSeeStarMap: UIViewRepresentable {
    let places: [MustSeePlace]
    let visitedIDs: Set<String>
    let wishedIDs: Set<String>
    let isChina: Bool
    let onSelect: (MustSeePlace) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        map.mapType = .mutedStandard
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsScale = false
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.onSelect = onSelect
        let sig = "\(isChina)|\(visitedIDs.count)|\(wishedIDs.count)"
        guard context.coordinator.lastSig != sig else { return }
        let listChanged = context.coordinator.lastIsChina != isChina
        context.coordinator.lastSig = sig
        context.coordinator.lastIsChina = isChina

        map.removeAnnotations(map.annotations)
        let anns = places.map {
            MustSeeAnnotation(place: $0, lit: visitedIDs.contains($0.id), wished: wishedIDs.contains($0.id))
        }
        map.addAnnotations(anns)

        let litAppeared = !context.coordinator.hadLitOnFrame && !visitedIDs.isEmpty
        if listChanged || !context.coordinator.hasFramed || litAppeared {
            context.coordinator.hasFramed = true
            context.coordinator.hadLitOnFrame = !visitedIDs.isEmpty
            let region: MKCoordinateRegion
            if isChina {
                region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 34.5, longitude: 104),
                    span: MKCoordinateSpan(latitudeDelta: 38, longitudeDelta: 52)
                )
            } else {
                let litPlaces = places.filter { visitedIDs.contains($0.id) }
                if litPlaces.count == 1, let only = litPlaces.first {
                    region = MKCoordinateRegion(
                        center: only.coordinate.onMap,
                        span: MKCoordinateSpan(latitudeDelta: 70, longitudeDelta: 105)
                    )
                } else if !litPlaces.isEmpty {
                    let coords = litPlaces.map { $0.coordinate.onMap }
                    let lats = coords.map(\.latitude).sorted()
                    let lons = coords.map(\.longitude).sorted()
                    let lonSpan = lons.last! - lons.first!
                    if lonSpan > 160 {
                        region = MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: lats[lats.count / 2], longitude: lons[lons.count / 2]),
                            span: MKCoordinateSpan(latitudeDelta: 95, longitudeDelta: 150)
                        )
                    } else {
                        region = MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: (lats.first! + lats.last!) / 2, longitude: (lons.first! + lons.last!) / 2),
                            span: MKCoordinateSpan(
                                latitudeDelta: min(120, max(55, (lats.last! - lats.first!) * 1.6)),
                                longitudeDelta: min(240, max(85, lonSpan * 1.6))
                            )
                        )
                    }
                } else {
                    region = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 20, longitude: 40),
                        span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 260)
                    )
                }
            }
            map.setRegion(region, animated: false)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onSelect: (MustSeePlace) -> Void
        var lastSig = ""
        var lastIsChina = true
        var hasFramed = false
        var hadLitOnFrame = false

        init(onSelect: @escaping (MustSeePlace) -> Void) {
            self.onSelect = onSelect
        }

        private lazy var litImage: UIImage = {
            let size: CGFloat = 24
            return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
                let colors = [UIColor.systemOrange.withAlphaComponent(0.65).cgColor, UIColor.systemOrange.withAlphaComponent(0).cgColor] as CFArray
                if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
                    ctx.cgContext.drawRadialGradient(
                        grad,
                        startCenter: CGPoint(x: 12, y: 12), startRadius: 2,
                        endCenter: CGPoint(x: 12, y: 12), endRadius: 12,
                        options: []
                    )
                }
                UIColor(red: 1.0, green: 0.94, blue: 0.72, alpha: 1.0).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 7.5, y: 7.5, width: 9, height: 9))
            }
        }()

        private lazy var wishImage: UIImage = {
            let size: CGFloat = 10
            return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
                UIColor.systemPink.withAlphaComponent(0.9).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 1, y: 1, width: 8, height: 8))
            }
        }()

        private lazy var dimImage: UIImage = {
            let size: CGFloat = 8
            return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
                UIColor.white.withAlphaComponent(0.55).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 1, y: 1, width: 6, height: 6))
            }
        }()

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let ann = annotation as? MustSeeAnnotation else { return nil }
            let id = ann.lit ? "starLit" : (ann.wished ? "starWish" : "starDim")
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: ann, reuseIdentifier: id)
            view.annotation = ann
            view.canShowCallout = false
            view.image = ann.lit ? litImage : (ann.wished ? wishImage : dimImage)
            view.displayPriority = ann.lit ? .required : .defaultLow
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            mapView.deselectAnnotation(view.annotation, animated: false)
            if let ann = view.annotation as? MustSeeAnnotation {
                onSelect(ann.place)
            }
        }
    }
}
