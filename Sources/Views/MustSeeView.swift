import SwiftUI
import MapKit
import Photos
import PhotosUI

// MARK: - 1:1 Upstream MustSeeView (中国 100 / 世界 100)

struct MustSeeView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var engine: LocationEngine
    @ObservedObject private var userStore = MustSeeUserStore.shared

    enum Filter: Int, Hashable { case all = 0, lit = 1, wished = 2, unlit = 3 }

    @State private var listType: MustSee.ListType = .china
    @State private var filter: Filter = .all
    @State private var mapSelectedPlace: MustSeePlace?
    @State private var chinaVisited: [String: Date] = [:]
    @State private var worldVisited: [String: Date] = [:]
    @State private var justLit: [MustSeePlace] = []
    @State private var isLoading = true
    @AppStorage("wt16.mustsee.seen") private var seenRaw = ""

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
            .filter { visitedMap[$0.id] == nil && $0.countryCode == nil }
            .min { $0.location.distance(from: loc) < $1.location.distance(from: loc) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                listPicker
                heroCard
                if !justLit.isEmpty { litBanner }
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
            noticeNewlyLit(allLitIDs: Set(result.0.keys).union(result.1.keys))
        }
        .onChange(of: listType) { _ in
            mapSelectedPlace = nil
        }
    }

    // MARK: - Top Dual Capsule Switcher (1:1 Upstream)

    private var listPicker: some View {
        HStack(spacing: 0) {
            ForEach(MustSee.ListType.allCases) { option in
                let isOn = option == listType
                let count = option == .china ? chinaVisited.count : worldVisited.count
                Button {
                    Haptics.selection()
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

    // MARK: - Unified Night Star Map + Floating Selected Chip + 100-Tile Hero Card

    private var heroCard: some View {
        let nightBg = Color(red: 0.06, green: 0.07, blue: 0.13)
        let pct = places.isEmpty ? 0 : Int((Double(visitedCount) / Double(places.count) * 100).rounded())

        return VStack(spacing: 0) {
            MustSeeStarMap(
                places: places,
                visitedIDs: Set(visitedMap.keys),
                wishedIDs: userStore.wishIDs,
                selectedID: mapSelectedPlace?.id,
                isChina: listType == .china
            ) { place in
                withAnimation(.easeInOut(duration: 0.2)) {
                    mapSelectedPlace = place
                }
            }
            .frame(height: 330)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, nightBg], startPoint: .top, endPoint: .bottom)
                    .frame(height: 90)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                if let selected = mapSelectedPlace {
                    selectedChip(selected)
                        .padding(12)
                }
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

    private func selectedChip(_ place: MustSeePlace) -> some View {
        let litDate = visitedMap[place.id]
        let isManual = userStore.manualVisits[place.id] != nil && litDate != nil
        return NavigationLink {
            MustSeePlaceView(
                place: place,
                visitedDate: litDate,
                userLocation: engine.currentLocation ?? store.stays.first?.location
            )
        } label: {
            HStack(spacing: 8) {
                Image(systemName: place.kind.symbol)
                    .foregroundColor(litDate != nil ? .yellow : .white.opacity(0.75))
                VStack(alignment: .leading, spacing: 1) {
                    Text(place.name)
                        .font(.subheadline.weight(.semibold))
                    if isManual {
                        Text("去过 · 自己点亮的").font(.caption2)
                    } else if let date = litDate {
                        Text("\(Self.zhDate(date)) 第一次到这里").font(.caption2)
                    } else {
                        Text("还没去过").font(.caption2).opacity(0.72)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .opacity(0.65)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
            .environment(\.colorScheme, .dark)
        }
        .buttonStyle(.plain)
        .transition(.scale(scale: 0.92).combined(with: .opacity))
    }

    private var litBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 2) {
                Text("新点亮了 \(justLit.count) 处").font(.headline)
                Text(justLit.prefix(4).map(\.name).joined(separator: "、") + (justLit.count > 4 ? "…" : ""))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            LinearGradient(colors: [Color.orange.opacity(0.16), Color.yellow.opacity(0.08)], startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
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
        return NavigationLink {
            MustSeePlaceView(
                place: place,
                visitedDate: visitedMap[place.id],
                userLocation: loc
            )
        } label: {
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
            Haptics.selection()
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

    // MARK: - Region Sections & Place Rows (1:1 Original MustSeeThumb + Season Subtitle)

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
                        Divider().padding(.leading, 82)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func placeRow(_ place: MustSeePlace) -> some View {
        let litDate = visitedMap[place.id]
        let wished = userStore.wishIDs.contains(place.id)
        let isManual = userStore.manualVisits[place.id] != nil && litDate != nil

        return HStack(spacing: 0) {
            NavigationLink {
                MustSeePlaceView(
                    place: place,
                    visitedDate: litDate,
                    userLocation: engine.currentLocation ?? store.stays.first?.location
                )
            } label: {
                HStack(spacing: 14) {
                    MustSeePlaceThumbnail(place: place, litDate: litDate)
                        .frame(width: 54, height: 54)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(litDate != nil ? Color.orange : .clear, lineWidth: 2)
                        )
                        .overlay(alignment: .bottomTrailing) {
                            if litDate != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white, .orange)
                                    .background(Circle().fill(Color(.secondarySystemGroupedBackground)).padding(2))
                                    .offset(x: 5, y: 5)
                            }
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .font(.body.weight(litDate != nil ? .semibold : .regular))
                            .foregroundColor(.primary)
                        if let date = litDate {
                            Text(isManual ? "去过 · 自己点亮的" : "\(Self.zhDate(date)) · \(Self.ago(date))")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else if wished {
                            Text("想去").font(.caption).foregroundColor(.pink)
                        } else if let season = MustSee.story(place.id)?.season {
                            Text(season)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if litDate == nil {
                Button {
                    Haptics.light()
                    userStore.toggleWish(place.id)
                } label: {
                    Image(systemName: wished ? "heart.fill" : "heart")
                        .font(.body.weight(.semibold))
                        .foregroundColor(wished ? .pink : .secondary.opacity(0.6))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
            }
        }
    }

    private func noticeNewlyLit(allLitIDs: Set<String>) {
        let seen = Set(seenRaw.split(separator: ",").map(String.init))
        if !seenRaw.isEmpty {
            let fresh = MustSee.allPlaces.filter { allLitIDs.contains($0.id) && !seen.contains($0.id) }
            if !fresh.isEmpty {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { justLit = fresh }
                Haptics.success()
            }
        }
        seenRaw = allLitIDs.isEmpty ? "-" : allLitIDs.sorted().joined(separator: ",")
    }

    static func zhDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: date)
    }

    static func ago(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 1 { return "今天" }
        if days < 30 { return "\(days) 天前" }
        if days < 365 { return "\(days / 30) 个月前" }
        return "\(days / 365) 年前"
    }
}

// MARK: - 1:1 Original MustSeeThumb (Real Bundled Scenic Photo + Gold Border & Checkmark)

private struct MustSeeOriginalThumb: View {
    let place: MustSeePlace
    let lit: Bool
    @ObservedObject private var userStore = MustSeeUserStore.shared
    @State private var bundledThumb: UIImage?

    var body: some View {
        let custom = userStore.customCoverImage(for: place.id)
        let displayImg = custom ?? bundledThumb

        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    lit
                    ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.78, blue: 0.35), .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(Color.secondary.opacity(0.12))
                )
            Image(systemName: place.kind.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(lit ? .white : .secondary)
            if let displayImg {
                Image(uiImage: displayImg)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(lit ? Color.orange : .clear, lineWidth: 2)
        )
        .overlay(alignment: .bottomTrailing) {
            if lit {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white, .orange)
                    .background(Circle().fill(Color.white).padding(2))
                    .offset(x: 5, y: 5)
            }
        }
        .task(id: place.id) {
            guard custom == nil else { return }
            let found = await MustSeePhotos.thumb(place.id)
            withAnimation(.easeOut(duration: 0.2)) { bundledThumb = found }
        }
    }
}

// MARK: - 1:1 Original Immersive Night-Sky MustSeePlaceView (iOS 16 Adapted)

struct MustSeePlaceView: View {
    let place: MustSeePlace
    let visitedDate: Date?
    let userLocation: CLLocation?

    @EnvironmentObject private var store: DataStore
    @ObservedObject private var userStore = MustSeeUserStore.shared

    @State private var coverImage: UIImage?
    @State private var myPhotos: [PhotoPreviewItem] = []
    @State private var heroUserImages: [UIImage] = []
    @State private var showAllPhotos = false
    @State private var showEditSheet = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var appeared = false
    @State private var confirmingUnlight = false

    private static let night = Color(red: 0.05, green: 0.06, blue: 0.11)
    private static let gold = LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.55), .orange], startPoint: .top, endPoint: .bottom)
    private let heroHeight: CGFloat = 500

    private var isManuallyLit: Bool { userStore.manualVisits[place.id] != nil }
    private var isExcluded: Bool { userStore.excludedAutoIDs.contains(place.id) }
    private var isAutoLit: Bool { visitedDate != nil && !isManuallyLit && !isExcluded }
    private var isLit: Bool { isAutoLit || isManuallyLit }
    private var wished: Bool { userStore.wishIDs.contains(place.id) }
    private var story: MustSeeStory? { MustSee.story(place.id) }
    private var hasCustomCover: Bool { userStore.customCoverIDs.contains(place.id) }

    private var kilometres: Int? {
        guard let loc = userLocation ?? store.stays.first?.location else { return nil }
        return Int((loc.distance(from: place.location) / 1000.0).rounded())
    }

    private var reelImages: [UIImage] {
        var list: [UIImage] = []
        if let custom = userStore.customCoverImage(for: place.id) {
            list.append(custom)
        }
        list.append(contentsOf: heroUserImages)
        if !list.isEmpty {
            return list
        }
        if let coverImage {
            return [coverImage]
        }
        return []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroSection

                VStack(alignment: .leading, spacing: 26) {
                    if let story {
                        Text(story.text)
                            .font(.system(.title3, design: .serif))
                            .lineSpacing(8)
                            .foregroundColor(.white.opacity(0.88))
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 12)
                            .animation(.easeOut(duration: 0.55).delay(0.18), value: appeared)
                    }

                    factsSection

                    if isAutoLit, let first = visitedDate {
                        yoursSection(firstVisit: first)
                    } else if isManuallyLit {
                        manualMemorySection
                    }

                    elsewhereSection

                    actionButtonsSection

                    if !hasCustomCover && heroUserImages.isEmpty, let credit = MustSeePhotos.credit(place.id) {
                        Link(destination: credit.page) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: "camera")
                                Text("封面照片：\(credit.artist)，\(credit.license)，来自 Wikimedia Commons")
                                    .multilineTextAlignment(.leading)
                            }
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.4))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 48)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Self.night.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Haptics.selection()
                    showEditSheet = true
                } label: {
                    Text("编辑")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            MustSeeEditSheet(
                place: place,
                autoVisitedDate: visitedDate,
                defaultCoverImage: coverImage
            )
        }
        .onChange(of: pickedPhoto) { newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        userStore.saveCustomCover(data, for: place.id)
                        Haptics.success()
                    }
                }
                pickedPhoto = nil
            }
        }
        .confirmationDialog("取消点亮“\(place.name)”？", isPresented: $confirmingUnlight, titleVisibility: .visible) {
            Button("取消点亮", role: .destructive) {
                if isAutoLit {
                    userStore.markAsNotVisited(place.id)
                } else {
                    userStore.toggleManualVisit(place.id)
                }
                Haptics.success()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(isAutoLit ? "将忽略此处的自动识别结果，之后仍可随时恢复。" : "将取消手动点亮状态。")
        }
        .task(id: place.id) {
            appeared = true
            if isAutoLit {
                await loadUserPhotosForPlace()
            }
            coverImage = await MustSeePhotos.cover(place.id)
        }
    }

    // MARK: - Hero (500pt Drifting Scenic Photo / 3D Flyover + Serif Title + Status Pill)

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if reelImages.isEmpty {
                    MustSeeFlyoverMap(place: place)
                } else {
                    MustSeeDriftingReel(images: reelImages)
                }
            }
            .frame(height: heroHeight)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.38), location: 0),
                        .init(color: .clear, location: 0.22),
                        .init(color: .clear, location: 0.50),
                        .init(color: Self.night, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(place.region, systemImage: place.kind.symbol)
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.78))

                Text(place.name)
                    .font(.system(size: 40, weight: .bold, design: .serif))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)

                Text(place.nameEn)
                    .font(.system(.subheadline, design: .serif).italic())
                    .foregroundColor(.white.opacity(0.62))

                statusPill.padding(.top, 6)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(height: heroHeight)
    }

    @ViewBuilder
    private var statusPill: some View {
        if isAutoLit, let date = visitedDate {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("\(MustSeeView.zhDate(date)) 第一次到这里")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Self.gold)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.orange.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(Color.orange.opacity(0.35), lineWidth: 0.8))
        } else if isManuallyLit {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                if let manualDate = userStore.manualVisits[place.id] {
                    Text("\(MustSeeView.zhDate(manualDate)) 来过这里")
                } else {
                    Text("你来过这里")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Self.gold)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.orange.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(Color.orange.opacity(0.35), lineWidth: 0.8))
        } else {
            HStack(spacing: 6) {
                Image(systemName: wished ? "heart.fill" : "star")
                Text(wished ? "在你的想去清单里" : "还在远方等你")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(wished ? .pink : .white.opacity(0.88))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
        }
    }

    // MARK: - Facts (2-Column Tiles: Best Season + First Visit / Distance)

    private var factsSection: some View {
        HStack(alignment: .top, spacing: 10) {
            if let story {
                factTile(symbol: "calendar", title: "最好的时节", value: story.season)
            }
            if isAutoLit, let date = visitedDate {
                factTile(symbol: "clock.arrow.circlepath", title: "第一次来", value: MustSeeView.ago(date))
            } else if let km = kilometres, place.countryCode == nil {
                factTile(symbol: "location.north.line", title: "离你", value: "约 \(km) 公里")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func factTile(symbol: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.55))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Yours (Your Own Photos + Expand All + Back to That Day)

    private func yoursSection(firstVisit: Date) -> some View {
        let displayedPhotos = showAllPhotos ? myPhotos : Array(myPhotos.prefix(9))
        return VStack(alignment: .leading, spacing: 12) {
            if !myPhotos.isEmpty {
                sectionHeading("你在这里留下的", trailing: "\(myPhotos.count) 张照片")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(Array(displayedPhotos.enumerated()), id: \.element.id) { idx, item in
                        Button {
                            PhotoLightboxPresenter.present(items: myPhotos, startIndex: idx)
                        } label: {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    Image(uiImage: item.thumbnail)
                                        .resizable()
                                        .scaledToFill()
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }

                if myPhotos.count > 9 {
                    Button {
                        Haptics.selection()
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showAllPhotos.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(showAllPhotos ? "收起照片" : "展开全部 \(myPhotos.count) 张照片")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: showAllPhotos ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            NavigationLink {
                DayDetailPage(date: Calendar.current.startOfDay(for: firstVisit))
            } label: {
                HStack {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Self.gold)
                    Text("回到第一次来的那一天")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(16)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: - Manual Memory Section (Custom Cover + Date)

    private var manualMemorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("你在这里留下的", trailing: nil)
            HStack(spacing: 10) {
                PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .foregroundStyle(Self.gold)
                        Text(hasCustomCover ? "更换封面照片" : "添加一张你的照片")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressableStyle())

                if hasCustomCover {
                    Button {
                        userStore.removeCustomCover(for: place.id)
                    } label: {
                        Text("恢复默认")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.75))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            Text("是你自己点亮的。照片只存在这台设备上；以后足迹或相册到了这里，会自动记录那一天。")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Elsewhere (3D Satellite Flyover + Open in Apple Maps)

    private var elsewhereSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(isLit ? "再看一眼" : "先替你看一眼", trailing: nil)

            if !reelImages.isEmpty {
                MustSeeFlyoverMap(place: place)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        Label("从空中看", systemImage: "airplane")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(10)
                    }
            }

            Button {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate.onMap))
                item.name = place.name
                item.openInMaps()
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "map.fill")
                            .foregroundColor(.white)
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("在 Apple 地图中看看")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("介绍、开放时间与路线")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(14)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: - Action Buttons (Wish / Manual Light-Up / Unlight)

    private var actionButtonsSection: some View {
        VStack(spacing: 14) {
            if !isLit {
                VStack(spacing: 8) {
                    Button {
                        Haptics.light()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            userStore.toggleWish(place.id)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: wished ? "heart.fill" : "heart")
                            Text(wished ? "已收进想去清单" : "想去这里")
                        }
                        .font(.headline)
                        .foregroundColor(wished ? .pink : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background {
                            Capsule().fill(
                                wished
                                ? AnyShapeStyle(Color.pink.opacity(0.16))
                                : AnyShapeStyle(LinearGradient(
                                    colors: [Color(red: 0.93, green: 0.33, blue: 0.50), Color(red: 0.60, green: 0.30, blue: 0.85)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                            )
                        }
                    }
                    .buttonStyle(PressableStyle())

                    Text(wished ? "它会在夜空地图上亮成一颗粉色的星，等你出发。" : "收进清单，等一个出发的理由。")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.5))
                }

                VStack(spacing: 8) {
                    Button {
                        Haptics.medium()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            userStore.toggleManualVisit(place.id)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle")
                            Text("我去过这里")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())

                    Text("去过却没亮？可能那时还没有记录，也没在那里拍照。自己点亮它，再放上几张当时的照片。")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }

                if isExcluded {
                    Button {
                        userStore.restoreAutoVisit(place.id)
                    } label: {
                        Text("恢复自动识别")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    confirmingUnlight = true
                } label: {
                    Text(isAutoLit ? "识别有误，标记为未去过" : "其实没去过，取消点亮")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionHeading(_ title: String, trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.title3, design: .serif).weight(.bold))
                .foregroundColor(.white)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    private func loadUserPhotosForPlace() async {
        let center = place.location
        let radiusMeters = place.radius * 1000.0
        let code = place.countryCode
        let matched = store.stays.filter { stay in
            if let code { return stay.countryCode == code }
            return stay.location.distance(from: center) <= radiusMeters
        }.sorted { $0.arrival > $1.arrival }

        var collected: [PhotoPreviewItem] = []
        var seen = Set<String>()
        for stay in matched.prefix(12) {
            let items = await StintPhotoFetcher.shared.stayPhotoItems(for: stay)
            for item in items where seen.insert(item.id).inserted {
                collected.append(item)
                if collected.count >= 60 { break }
            }
            if collected.count >= 60 { break }
        }
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            myPhotos = collected
        }

        // Load high-resolution versions (supporting iCloud download) for the top hero carousel
        // so 200x200 grid thumbnails are never stretched full-screen.
        var hiRes: [UIImage] = []
        for item in collected.prefix(6) {
            guard !Task.isCancelled else { return }
            if let assetID = item.assetID,
               let img = await StintPhotoFetcher.shared.highResImage(forAssetID: assetID) {
                hiRes.append(img)
            }
        }
        guard !Task.isCancelled, !hiRes.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.35)) {
            heroUserImages = hiRes
        }
    }
}

// MARK: - Edit Sheet for MustSeePlace (Custom Cover Photo + Visit Status)

private struct MustSeeEditSheet: View {
    let place: MustSeePlace
    let autoVisitedDate: Date?
    let defaultCoverImage: UIImage?

    @ObservedObject private var userStore = MustSeeUserStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var pickedPhoto: PhotosPickerItem?
    @State private var manualDate: Date = Date()

    private var isManuallyLit: Bool { userStore.manualVisits[place.id] != nil }
    private var isExcluded: Bool { userStore.excludedAutoIDs.contains(place.id) }
    private var isAutoLit: Bool { autoVisitedDate != nil && !isManuallyLit && !isExcluded }
    private var hasCustomCover: Bool { userStore.customCoverIDs.contains(place.id) }

    var body: some View {
        NavigationStack {
            Form {
                Section("封面与图标照片") {
                    HStack(spacing: 14) {
                        Group {
                            if let custom = userStore.customCoverImage(for: place.id) {
                                Image(uiImage: custom)
                                    .resizable()
                                    .scaledToFill()
                            } else if let def = defaultCoverImage {
                                Image(uiImage: def)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                ZStack {
                                    Color.orange.opacity(0.18)
                                    Image(systemName: place.kind.symbol)
                                        .font(.title2)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(hasCustomCover ? "已使用自定义照片" : "当前使用默认封面")
                                .font(.subheadline.weight(.semibold))
                            Text("列表图标与详情页顶部轮播都会优先展示你选的照片。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                        Label(hasCustomCover ? "从相册更换照片" : "从相册选择照片", systemImage: "photo.on.rectangle.angled")
                    }

                    if hasCustomCover {
                        Button(role: .destructive) {
                            Haptics.selection()
                            userStore.removeCustomCover(for: place.id)
                        } label: {
                            Label("恢复默认照片", systemImage: "arrow.counterclockwise")
                        }
                    }
                }

                Section("到访状态") {
                    HStack {
                        Text("当前状态")
                        Spacer()
                        if isAutoLit, let d = autoVisitedDate {
                            Text("已自动点亮（\(MustSeeView.zhDate(d))）")
                                .foregroundColor(.orange)
                                .font(.subheadline)
                        } else if isManuallyLit {
                            Text("已手动点亮")
                                .foregroundColor(.orange)
                                .font(.subheadline)
                        } else if isExcluded {
                            Text("已标记为未去过")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        } else {
                            Text("未去过")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                    }

                    if isManuallyLit {
                        DatePicker("到访日期", selection: $manualDate, in: ...Date(), displayedComponents: .date)
                            .onChange(of: manualDate) { newDate in
                                userStore.setManualVisitDate(place.id, date: newDate)
                            }

                        Button(role: .destructive) {
                            Haptics.success()
                            userStore.toggleManualVisit(place.id)
                        } label: {
                            Label("标记为未去过（取消点亮）", systemImage: "xmark.circle")
                        }
                    } else if isAutoLit {
                        Button(role: .destructive) {
                            Haptics.success()
                            userStore.markAsNotVisited(place.id)
                        } label: {
                            Label("识别有误，标记为未去过", systemImage: "xmark.circle")
                        }
                    } else {
                        DatePicker("到访日期", selection: $manualDate, in: ...Date(), displayedComponents: .date)

                        Button {
                            Haptics.success()
                            userStore.setManualVisitDate(place.id, date: manualDate)
                        } label: {
                            Label("标记为我去过这里", systemImage: "checkmark.circle.fill")
                        }

                        if isExcluded {
                            Button {
                                Haptics.success()
                                userStore.restoreAutoVisit(place.id)
                            } label: {
                                Label("恢复自动识别", systemImage: "arrow.uturn.backward")
                            }
                        }
                    }
                }
            }
            .navigationTitle("编辑 \(place.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        Haptics.selection()
                        dismiss()
                    }
                }
            }
            .onAppear {
                manualDate = userStore.manualVisits[place.id] ?? autoVisitedDate ?? Date()
            }
            .onChange(of: pickedPhoto) { newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            userStore.saveCustomCover(data, for: place.id)
                            Haptics.success()
                        }
                    }
                    pickedPhoto = nil
                }
            }
        }
    }
}

// MARK: - Slowly Drifting Scenic Photo Reel (1:1 Original PhotoReel)

private struct MustSeeDriftingReel: View {
    let images: [UIImage]
    @State private var index = 0
    @State private var drift = false

    var body: some View {
        GeometryReader { geo in
            let current = images[min(index, images.count - 1)]
            Image(uiImage: current)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(drift ? 1.14 : 1.02, anchor: index.isMultiple(of: 2) ? .topLeading : .bottomTrailing)
                .clipped()
                .id(index)
                .transition(.opacity)
        }
        .onAppear {
            withAnimation(.linear(duration: 12)) { drift = true }
        }
        .task(id: images.count) {
            guard images.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 7_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 1.5)) {
                    index = (index + 1) % images.count
                }
            }
        }
    }
}

// MARK: - 3D Satellite Flyover Orbit Map (iOS 16 MKMapView)

private struct MustSeeFlyoverMap: UIViewRepresentable {
    let place: MustSeePlace

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType = .satelliteFlyover
        map.showsCompass = false
        map.showsScale = false
        map.isUserInteractionEnabled = false
        map.overrideUserInterfaceStyle = .dark
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        guard context.coordinator.lastID != place.id else { return }
        context.coordinator.lastID = place.id
        let center = place.coordinate.onMap
        let distance = min(max(place.radius * 2400.0, 2200.0), 40_000.0)
        let camera = MKMapCamera(lookingAtCenter: center, fromDistance: distance, pitch: 64, heading: 20)
        map.setCamera(camera, animated: false)
        context.coordinator.startOrbit(map: map, center: center, distance: distance)
    }

    static func dismantleUIView(_ uiView: MKMapView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var lastID = ""
        private var timer: Timer?
        private var heading: CLLocationDirection = 20

        func startOrbit(map: MKMapView, center: CLLocationCoordinate2D, distance: CLLocationDistance) {
            timer?.invalidate()
            heading = 20
            timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self, weak map] _ in
                guard let self, let map else { return }
                self.heading = (self.heading + 0.16).truncatingRemainder(dividingBy: 360)
                let cam = MKMapCamera(lookingAtCenter: center, fromDistance: distance, pitch: 64, heading: self.heading)
                map.camera = cam
            }
        }

        func stop() {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - Dark Night Star Map (MKMapView with Cached Radial Glow Images)

private final class MustSeeAnnotation: NSObject, MKAnnotation {
    let place: MustSeePlace
    let lit: Bool
    let wished: Bool
    let selected: Bool
    let coordinate: CLLocationCoordinate2D
    var title: String? { place.name }
    var subtitle: String? { place.region }

    init(place: MustSeePlace, lit: Bool, wished: Bool, selected: Bool) {
        self.place = place
        self.lit = lit
        self.wished = wished
        self.selected = selected
        self.coordinate = place.coordinate.onMap
    }
}

private struct MustSeeStarMap: UIViewRepresentable {
    let places: [MustSeePlace]
    let visitedIDs: Set<String>
    let wishedIDs: Set<String>
    let selectedID: String?
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
        let sig = "\(isChina)|\(visitedIDs.count)|\(wishedIDs.count)|\(selectedID ?? "")"
        guard context.coordinator.lastSig != sig else { return }
        let listChanged = context.coordinator.lastIsChina != isChina
        context.coordinator.lastSig = sig
        context.coordinator.lastIsChina = isChina

        map.removeAnnotations(map.annotations)
        let anns = places.map {
            MustSeeAnnotation(
                place: $0,
                lit: visitedIDs.contains($0.id),
                wished: wishedIDs.contains($0.id),
                selected: $0.id == selectedID
            )
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

        private lazy var litImage: UIImage = renderLit(selected: false)
        private lazy var litSelectedImage: UIImage = renderLit(selected: true)

        private func renderLit(selected: Bool) -> UIImage {
            let size: CGFloat = selected ? 30 : 24
            let center = size / 2
            let dotR: CGFloat = selected ? 6.5 : 4.5
            return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
                let colors = [UIColor.systemOrange.withAlphaComponent(0.68).cgColor, UIColor.systemOrange.withAlphaComponent(0).cgColor] as CFArray
                if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
                    ctx.cgContext.drawRadialGradient(
                        grad,
                        startCenter: CGPoint(x: center, y: center), startRadius: 2,
                        endCenter: CGPoint(x: center, y: center), endRadius: center,
                        options: []
                    )
                }
                UIColor(red: 1.0, green: 0.94, blue: 0.72, alpha: 1.0).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: center - dotR, y: center - dotR, width: dotR * 2, height: dotR * 2))
            }
        }

        private lazy var wishImage: UIImage = {
            UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { ctx in
                UIColor.systemPink.withAlphaComponent(0.9).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 1, y: 1, width: 8, height: 8))
            }
        }()

        private lazy var dimImage: UIImage = {
            UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
                UIColor.white.withAlphaComponent(0.55).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 1, y: 1, width: 6, height: 6))
            }
        }()

        private lazy var dimSelectedImage: UIImage = {
            UIGraphicsImageRenderer(size: CGSize(width: 14, height: 14)).image { ctx in
                UIColor.white.withAlphaComponent(0.9).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 2, y: 2, width: 10, height: 10))
            }
        }()

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let ann = annotation as? MustSeeAnnotation else { return nil }
            let id = ann.lit ? (ann.selected ? "starLitSel" : "starLit") : (ann.selected ? "starDimSel" : (ann.wished ? "starWish" : "starDim"))
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: ann, reuseIdentifier: id)
            view.annotation = ann
            view.canShowCallout = false
            if ann.lit {
                view.image = ann.selected ? litSelectedImage : litImage
            } else if ann.selected {
                view.image = dimSelectedImage
            } else {
                view.image = ann.wished ? wishImage : dimImage
            }
            view.displayPriority = (ann.lit || ann.selected) ? .required : .defaultLow
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
