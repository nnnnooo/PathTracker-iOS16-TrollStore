import SwiftUI
import Photos

private struct WorldSummaryCache: Codable {
    var countryCount: Int = 0
    var cityCount: Int = 0
    var landmarkCount: Int = 0
    var entryCount: Int = 0
    var provinceCount: Int = 0
    var passportCityCount: Int = 0
    var chinaLit: Int = 0
    var worldLit: Int = 0

    private static let key = "wt16.world.summaryCache"

    static func load() -> WorldSummaryCache {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(WorldSummaryCache.self, from: data) else {
            return WorldSummaryCache()
        }
        return decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

struct WorldView: View {
    @Binding var showingSettings: Bool
    @Binding var selectedTab: RootTab
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var tagger: PlaceTagger
    @ObservedObject private var borderOverrides = BorderStampOverrideStore.shared
    @ObservedObject private var mustSeeUserStore = MustSeeUserStore.shared

    @AppStorage("wt16.passport.theme") private var themeRaw: String = PassportTheme.burgundy.rawValue
    @State private var showFullMap = false
    @State private var fullMapLayer = 0
    @State private var showPhotoImport = false
    @State private var showAllFrequent = false
    @State private var searchText = ""
    @State private var cachedSummary = WorldSummaryCache.load()
    @State private var hasComputedOnce = false
    @State private var passportPreview: PassportPreviewData?
    @State private var countryStats: [RegionStat] = []
    @State private var frequentPlaces: [FrequentPlace] = []
    @State private var cityCount: Int = WorldSummaryCache.load().cityCount
    @State private var landmarkStays: [Stay] = []

    private struct PassportPreviewData: Sendable {
        let entryCount: Int
        let provinceCount: Int
        let cityCount: Int
        let latestStamps: [PassportStamp]
        let chinaLit: Int
        let worldLit: Int
    }

    private struct RegionStat: Identifiable, Sendable {
        let id: String
        let code: String?
        let name: String
        let stayCount: Int
        let dayCount: Int
        let cityCount: Int
        let latestYear: Int
        let topCities: [String]
    }

    fileprivate struct FrequentPlace: Identifiable, Sendable {
        let id: String
        let name: String
        let visitCount: Int
        let totalDuration: TimeInterval
        let latestDate: Date
        let sampleStay: Stay
    }

    private var theme: PassportTheme { PassportTheme(rawValue: themeRaw) ?? .burgundy }

    private var searchResults: [Stay] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return Array(store.stays.filter { stay in
            stay.displayName.localizedCaseInsensitiveContains(q)
            || (stay.city?.localizedCaseInsensitiveContains(q) ?? false)
            || (stay.country?.localizedCaseInsensitiveContains(q) ?? false)
            || (stay.street?.localizedCaseInsensitiveContains(q) ?? false)
        }.prefix(50))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !searchText.isEmpty {
                        searchResultsSection
                    } else {
                        summaryGrid
                        passportCard
                        mustSeeCard
                        blindBoxCard
                        mapCard
                        albumCard
                        if !countryStats.isEmpty {
                            countriesSection
                        }
                        if !frequentPlaces.isEmpty {
                            frequentPlacesSection
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("足迹")
            .searchable(text: $searchText, prompt: "搜索地点、城市或国家")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showPhotoImport = true
                    } label: {
                        Image(systemName: "photo.on.rectangle.angled")
                    }
                    ProfileToolbarButton(showingSettings: $showingSettings)
                }
            }
            .sheet(isPresented: $showPhotoImport) { PhotoImportSheet() }
            .sheet(isPresented: $showAllFrequent) {
                FrequentPlacesListSheet(places: frequentPlaces)
            }
            .fullScreenCover(isPresented: $showFullMap) {
                NavigationStack {
                    WorldFootprintMapView(
                        stays: store.stays,
                        chunks: store.chunks,
                        showRoutes: fullMapLayer == 1
                    )
                    .ignoresSafeArea()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { showFullMap = false }
                        }
                        ToolbarItem(placement: .principal) {
                            Picker("图层", selection: $fullMapLayer) {
                                Text("地点").tag(0)
                                Text("路线").tag(1)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }
                    }
                }
            }
            .task(id: "\(store.stays.count)-\(tagger.pendingCount)-\(borderOverrides.revision)-\(mustSeeUserStore.revision)") {
                let staysSnapshot = store.stays
                let manual = mustSeeUserStore.manualVisits
                let excluded = mustSeeUserStore.excludedAutoIDs
                let computed = await Task.detached(priority: .utility) { () -> (PassportPreviewData, [RegionStat], Int, [Stay], [FrequentPlace]) in
                    let cal = Calendar.current
                    let p = PassportEngine.build(stays: staysSnapshot, chunks: [])
                    let validCodes = p.visitedCountries
                    let grouped = Dictionary(grouping: staysSnapshot.filter {
                        if let code = $0.countryCode { return validCodes.contains(code) }
                        return false
                    }) { $0.countryCode! }

                    let countries: [RegionStat] = grouped.compactMap { code, list in
                        let name = CountryText.localizedName(code: code)
                        let days = Set(list.map { cal.startOfDay(for: $0.arrival) }).count
                        let cityCounts = Dictionary(grouping: list.compactMap(\.city)) { $0 }.mapValues(\.count)
                        let topCities = cityCounts.sorted { $0.value > $1.value }.prefix(3).map(\.key)
                        let latestDate = list.map(\.arrival).max() ?? Date()
                        let latestYear = cal.component(.year, from: latestDate)
                        return RegionStat(
                            id: code,
                            code: code,
                            name: name,
                            stayCount: list.count,
                            dayCount: days,
                            cityCount: cityCounts.count,
                            latestYear: latestYear,
                            topCities: Array(topCities)
                        )
                    }.sorted { $0.dayCount > $1.dayCount }

                    let cities = Set(staysSnapshot.compactMap(\.city)).count
                    let landmarks = staysSnapshot.filter(\.isLandmark)

                    // Frequent places grouped by displayName (min 2 visits)
                    let byPlace = Dictionary(grouping: staysSnapshot.filter { $0.displayName != "未知地点" }) { $0.displayName }
                    let freq: [FrequentPlace] = byPlace.compactMap { name, list in
                        guard list.count >= 2, let latest = list.max(by: { $0.arrival < $1.arrival }) else { return nil }
                        let totalDur = list.reduce(0.0) { $0 + $1.duration }
                        return FrequentPlace(
                            id: name,
                            name: name,
                            visitCount: list.count,
                            totalDuration: totalDur,
                            latestDate: latest.arrival,
                            sampleStay: latest
                        )
                    }
                    .sorted { $0.visitCount > $1.visitCount }
                    .prefix(30)
                    .map { $0 }

                    let entries = p.passportStamps.filter { $0.kind == .entry }
                    let provStamps = p.provinceVisits.values.map {
                        PassportStamp(id: "province.\($0.province.id)", kind: .province, date: $0.firstVisit, provinceID: $0.province.id)
                    }
                    let latest = Array((entries + provStamps + p.cityStamps).sorted { $0.date > $1.date }.prefix(3))
                    let chinaVisited = MustSee.visitedMap(places: MustSee.china, stays: staysSnapshot, manual: manual, excluded: excluded).count
                    let worldVisited = MustSee.visitedMap(places: MustSee.world, stays: staysSnapshot, manual: manual, excluded: excluded).count
                    let preview = PassportPreviewData(
                        entryCount: entries.count,
                        provinceCount: p.provinceVisits.count,
                        cityCount: p.cityStamps.count,
                        latestStamps: latest,
                        chinaLit: chinaVisited,
                        worldLit: worldVisited
                    )
                    return (preview, countries, cities, landmarks, freq)
                }.value

                passportPreview = computed.0
                countryStats = computed.1
                cityCount = computed.2
                landmarkStays = computed.3
                frequentPlaces = computed.4
                hasComputedOnce = true

                let updatedCache = WorldSummaryCache(
                    countryCount: computed.1.count,
                    cityCount: computed.2,
                    landmarkCount: computed.3.count,
                    entryCount: computed.0.entryCount,
                    provinceCount: computed.0.provinceCount,
                    passportCityCount: computed.0.cityCount,
                    chinaLit: computed.0.chinaLit,
                    worldLit: computed.0.worldLit
                )
                cachedSummary = updatedCache
                updatedCache.save()
            }
        }
    }

    // MARK: - 1. 2x2 Hairline Metric Grid

    private var summaryGrid: some View {
        MetricGrid2x2 {
            MetricTile(title: "国家与地区", value: "\(hasComputedOnce ? countryStats.count : cachedSummary.countryCount)", symbol: "flag.fill", tint: .red)
        } topRight: {
            NavigationLink {
                PassportView(initialScope: .cities)
            } label: {
                MetricTile(title: "城市", value: "\(hasComputedOnce ? cityCount : cachedSummary.cityCount)", symbol: "building.2.fill", tint: .indigo, showsChevron: true)
            }
            .buttonStyle(.plain)
        } bottomLeft: {
            MetricTile(title: "景点", value: "\(hasComputedOnce ? landmarkStays.count : cachedSummary.landmarkCount)", symbol: "star.fill", tint: .yellow)
        } bottomRight: {
            MetricTile(title: "记录天数", value: "\(store.recordedDaysCount)", symbol: "calendar", tint: .teal)
        }
    }

    // MARK: - 2. 护照与印章 Card (Original Entry Point + Single-Line Subtitle Fix)

    private var passportCard: some View {
        NavigationLink {
            PassportView()
        } label: {
            HStack(spacing: 14) {
                miniPassportCover
                    .frame(width: 72, height: 102)
                    .shadow(color: .black.opacity(0.22), radius: 6, y: 3)

                VStack(alignment: .leading, spacing: 5) {
                    Text("护照与印章")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text("入境 \(passportPreview?.entryCount ?? cachedSummary.entryCount) · 省份 \(passportPreview?.provinceCount ?? cachedSummary.provinceCount) · 城市 \(passportPreview?.cityCount ?? cachedSummary.passportCityCount)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    let cachedHasStamps = (cachedSummary.entryCount + cachedSummary.provinceCount + cachedSummary.passportCityCount) > 0
                    if let stamps = passportPreview?.latestStamps, !stamps.isEmpty {
                        ZStack(alignment: .leading) {
                            ForEach(Array(stamps.enumerated()), id: \.element.id) { index, stamp in
                                StampArtView(stamp: stamp)
                                    .frame(width: 48, height: 44)
                                    .rotationEffect(.degrees(stamp.tilt))
                                    .offset(x: CGFloat(index) * 38)
                            }
                        }
                        .frame(height: 46)
                        .padding(.top, 2)
                    } else if !hasComputedOnce && cachedHasStamps {
                        // 冷启动异步计算期间保留印章占位高度，避免闪现副标题文字后又消失
                        Color.clear
                            .frame(height: 46)
                            .padding(.top, 2)
                    } else {
                        Text("出入境章 · 34 省朱砂印 · 城市章")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private var miniPassportCover: some View {
        let shape = BookCornerRect(topLeading: 2, bottomLeading: 2, bottomTrailing: 7, topTrailing: 7)
        return ZStack {
            shape.fill(theme.leather)
            VStack(spacing: 4) {
                Text("护照")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2)
                Text("PASSPORT")
                    .font(.system(size: 5.5, weight: .medium, design: .serif))
                    .tracking(1)
                ZStack {
                    Circle().stroke(lineWidth: 0.9)
                    Image(systemName: theme.emblem)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 17, height: 17)
                }
                .frame(width: 32, height: 32)
                .padding(.vertical, 3)
                Text("漫迹")
                    .font(.system(size: 6, weight: .semibold))
                    .tracking(1.5)
            }
            .foregroundStyle(theme.foilGradient)
            Rectangle()
                .fill(Color.black.opacity(0.22))
                .frame(width: 3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(shape)
    }

    // MARK: - 3. 此生必去 Card (1:1 Original Dual 10x10 Dot-Matrix Card)

    private var mustSeeCard: some View {
        let cnLit = passportPreview?.chinaLit ?? cachedSummary.chinaLit
        let worldLit = passportPreview?.worldLit ?? cachedSummary.worldLit

        return NavigationLink {
            MustSeeView()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("此生必去")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                        Text("中国与世界，各一百处值得一去的地方")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.68))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 4)
                }

                HStack(spacing: 12) {
                    mustSeeSubPanel(title: "中国", count: cnLit)
                    mustSeeSubPanel(title: "世界", count: worldLit)
                }
            }
            .padding(18)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.14, green: 0.14, blue: 0.30), Color(red: 0.11, green: 0.10, blue: 0.24)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
        }
        .buttonStyle(PressableStyle())
    }

    private func mustSeeSubPanel(title: String, count: Int) -> some View {
        let clamped = min(100, max(0, count))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.88))
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(clamped)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.86, blue: 0.50), Color(red: 1.0, green: 0.52, blue: 0.14)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Text("/100")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            // 20x5 dot matrix (= 100 dots, crisp and compact just like the original UI)
            Canvas { ctx, size in
                let cols = 20
                let rows = 5
                let spacingX = size.width / CGFloat(cols)
                let spacingY = size.height / CGFloat(rows)
                let dotSize = min(spacingX, spacingY) * 0.56
                let litColor = Color(red: 1.0, green: 0.58, blue: 0.16)
                let unlitColor = Color.white.opacity(0.16)

                for i in 0..<100 {
                    let r = i / cols
                    let c = i % cols
                    let x = CGFloat(c) * spacingX + (spacingX - dotSize) / 2
                    let y = CGFloat(r) * spacingY + (spacingY - dotSize) / 2
                    let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                    ctx.fill(Path(ellipseIn: rect), with: .color(i < clamped ? litColor : unlitColor))
                }
            }
            .frame(height: 36)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 4. 旅行盲盒 Card (1:1 Original Full-Width Mystery Parcel Card)

    private var blindBoxCard: some View {
        NavigationLink {
            BlindBoxView()
        } label: {
            HStack(spacing: 16) {
                KraftParcelArt()
                    .scaleEffect(0.35)
                    .frame(width: 78, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text("旅行盲盒")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("不知道去哪儿？这次让它替你选。")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.11, green: 0.12, blue: 0.21), Color(red: 0.26, green: 0.19, blue: 0.18)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - 5. World Map Card

    private var mapCard: some View {
        Button {
            showFullMap = true
        } label: {
            WorldFootprintMapView(
                stays: store.stays,
                chunks: store.chunks,
                showRoutes: false
            )
            .allowsHitTesting(false)
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Label("全部足迹", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
            }
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - 6. 相册 Card (1:1 Original Layout)

    private var albumCard: some View {
        Button {
            showPhotoImport = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("相册")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    if tagger.isTagging {
                        ProgressView().scaleEffect(0.85)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                }

                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 52, height: 52)
                        Image(systemName: "photo.fill.on.rectangle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }

                    Text(tagger.progressText ?? "从相册导入历史足迹，或在时间线上点开地点记录心情。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - 7. Countries List (1:1 Original Formatting)

    private var countriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("国家和地区")
                .font(.title3.bold())
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(countryStats.enumerated()), id: \.element.id) { index, item in
                    NavigationLink {
                        CountryDetailView(countryCode: item.code ?? item.id, fallbackName: item.name)
                    } label: {
                        HStack(spacing: 12) {
                            Text(item.code.map { CountryText.flag(for: $0) } ?? "🌍")
                                .font(.system(size: 32))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("\(Self.formattedNumber(item.dayCount)) 天 · \(item.cityCount) 座城市 · 最近 \(String(item.latestYear))")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                    }
                    if index < countryStats.count - 1 {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    // MARK: - 8. 常去的地方 Horizontal Photo Cards (1:1 Original UI)

    private var frequentPlacesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("常去的地方")
                    .font(.title3.bold())
                Spacer()
                Button("全部") {
                    Haptics.selection()
                    showAllFrequent = true
                }
                .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(frequentPlaces.prefix(10)) { place in
                        NavigationLink {
                            DayDetailPage(date: place.latestDate)
                        } label: {
                            FrequentPlaceCardView(place: place)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }

            Text("给常去的地方起个名字，比如“家”或“学校”，以后每次到访都会自动用上。")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "搜索结果", trailing: "\(searchResults.count)")
            if searchResults.isEmpty {
                WaytraceCard {
                    Text("没有找到匹配的地点").font(.subheadline).foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(searchResults.enumerated()), id: \.element.id) { idx, stay in
                        NavigationLink {
                            DayDetailPage(date: stay.arrival)
                        } label: {
                            HStack(spacing: 12) {
                                PlaceIcon(category: stay.category, isLandmark: stay.isLandmark, size: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stay.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.primary)
                                    Text([stay.subtitle, Formatters.dayTitle(stay.arrival)].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Color(.tertiaryLabel))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if idx < searchResults.count - 1 { Divider().padding(.leading, 62) }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    private static func formattedNumber(_ n: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
    }
}

// MARK: - Frequent Place Photo Card & Full List Sheet

private struct FrequentPlaceCardView: View {
    let place: WorldView.FrequentPlace
    @State private var photoItem: PhotoPreviewItem?

    private var durationSummary: String {
        let totalHours = Int(place.totalDuration / 3600)
        let days = totalHours / 24
        let hours = totalHours % 24
        if days > 0 {
            return hours > 0 ? "\(days)天\(hours)小时" : "\(days)天"
        }
        return Formatters.duration(place.totalDuration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let item = photoItem {
                    Image(uiImage: item.thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [place.sampleStay.category.tint.opacity(0.22), Color(.tertiarySystemFill)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    PlaceIcon(category: place.sampleStay.category, isLandmark: place.sampleStay.isLandmark, size: 34)
                }
            }
            .frame(width: 158, height: 108)
            .clipped()

            VStack(alignment: .leading, spacing: 3) {
                Text(place.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("\(place.visitCount) 次 · \(durationSummary)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 158, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task(id: place.id) {
            photoItem = await StintPhotoFetcher.shared.dayPhotoItem(
                around: place.latestDate,
                caption: place.name
            )
        }
    }
}

private struct FrequentPlacesListSheet: View {
    let places: [WorldView.FrequentPlace]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(places) { place in
                NavigationLink {
                    DayDetailPage(date: place.latestDate)
                } label: {
                    HStack(spacing: 12) {
                        PlaceIcon(category: place.sampleStay.category, isLandmark: place.sampleStay.isLandmark, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name).font(.body.weight(.semibold))
                            Text("\(place.visitCount) 次 · 累计 \(Formatters.duration(place.totalDuration))")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("常去的地方")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        Haptics.selection()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct PhotoImportSheet: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var tagger: PlaceTagger
    @Environment(\.dismiss) private var dismiss

    @State private var isScanning = false
    @State private var scannedCount = 0
    @State private var totalCount = 0
    @State private var summary: PhotoFootprints.Summary?
    @State private var permissionDenied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                    .padding(.top, 20)

                Text("从相册导入历史足迹")
                    .font(.title3.bold())

                Text("仅在本地读取照片和视频的拍摄时间与 GPS 坐标，自动聚合成停留记录并在后台按区域批量识别城市与国家，照片本身不会上传。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if isScanning {
                    VStack(spacing: 8) {
                        ProgressView(value: totalCount > 0 ? Double(scannedCount) / Double(totalCount) : 0)
                        Text("正在扫描相册：\(scannedCount) / \(totalCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 32)
                } else if let s = summary {
                    VStack(spacing: 6) {
                        Text("导入完成")
                            .font(.headline)
                            .foregroundColor(.green)
                        Text("共扫描 \(s.scanned) 项，含位置 \(s.withLocation) 项，新增 \(s.visits) 条历史足迹（已自动跳过重复记录 \(s.skippedAlreadyRecorded) 条）。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Text("城市与国家名称正在后台按 10km 网格快速识别中。")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24)
                }

                if permissionDenied {
                    Text("没有相册读取权限，请前往系统设置授予权限。")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Spacer()

                Button {
                    startImport()
                } label: {
                    Text(isScanning ? "正在扫描…" : (summary == nil ? "开始扫描相册" : "重新扫描新增照片"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isScanning)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func startImport() {
        permissionDenied = false
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard status == .authorized || status == .limited else {
                permissionDenied = true
                return
            }
            isScanning = true
            let result = await PhotoFootprints.importLibrary(into: store) { current, total in
                Task { @MainActor in
                    scannedCount = current
                    totalCount = total
                }
            }
            summary = result
            isScanning = false
            tagger.enqueue()
        }
    }
}
