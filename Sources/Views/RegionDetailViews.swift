import SwiftUI
import MapKit
import CoreLocation
import Photos

// MARK: - City Stint Model (Consecutive Visits to One City)

struct CityStint: Identifiable, Hashable, Sendable {
    let id: String
    let city: String
    let start: Date
    let end: Date
    let days: Int
    let stayCount: Int
    let latitude: Double
    let longitude: Double

    static func == (lhs: CityStint, rhs: CityStint) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isSingleDay: Bool { days <= 1 }

    var dateRangeText: String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        if cal.isDate(start, inSameDayAs: end) {
            f.dateFormat = "yyyy年M月d日 EEE"
            return f.string(from: start)
        }
        f.dateFormat = "yyyy年M月d日"
        let s1 = f.string(from: start)
        if cal.isDate(start, equalTo: end, toGranularity: .month) {
            let d2 = cal.component(.day, from: end)
            return "\(s1)–\(d2)日"
        } else if cal.isDate(start, equalTo: end, toGranularity: .year) {
            f.dateFormat = "M月d日"
            return "\(s1)–\(f.string(from: end))"
        } else {
            return "\(s1)–\(f.string(from: end))"
        }
    }

    private static func isProvinceOnlyName(_ name: String) -> Bool {
        name.hasSuffix("省") || name.hasSuffix("自治区") || name == "未知地点"
    }

    static func group(_ stays: [Stay]) -> [CityStint] {
        let cal = Calendar.current
        let sorted = stays.sorted { $0.arrival < $1.arrival }
        guard !sorted.isEmpty else { return [] }

        // Pass 1: O(N) bounded time-window lookup for province-only / missing city names (within 36h & 80km)
        var resolvedNames: [String] = sorted.map { $0.city?.nilIfEmpty ?? $0.displayName }
        let maxWindow: TimeInterval = 36 * 3600
        for i in sorted.indices where isProvinceOnlyName(resolvedNames[i]) {
            let cur = sorted[i]
            var bestName: String?
            var bestTimeDiff = TimeInterval.greatestFiniteMagnitude
            var j = i - 1
            while j >= 0 {
                let dt = cur.arrival.timeIntervalSince(sorted[j].arrival)
                if dt > maxWindow { break }
                if !isProvinceOnlyName(resolvedNames[j]), dt < bestTimeDiff,
                   cur.location.distance(from: sorted[j].location) < 80_000 {
                    bestTimeDiff = dt
                    bestName = resolvedNames[j]
                }
                j -= 1
            }
            j = i + 1
            while j < sorted.count {
                let dt = sorted[j].arrival.timeIntervalSince(cur.arrival)
                if dt > maxWindow { break }
                if !isProvinceOnlyName(resolvedNames[j]), dt < bestTimeDiff,
                   cur.location.distance(from: sorted[j].location) < 80_000 {
                    bestTimeDiff = dt
                    bestName = resolvedNames[j]
                }
                j += 1
            }
            if let bestName {
                resolvedNames[i] = bestName
            }
        }

        // Pass 2: Strictly O(N) in-place aggregation (zero array CoW duplication for multi-thousand home-city stays)
        struct Bucket {
            let city: String
            let start: Date
            var end: Date
            var lastDay: Date
            var days: Set<Date>
            var count: Int
            var latSum: Double
            var lonSum: Double
        }

        var buckets: [Bucket] = []
        buckets.reserveCapacity(64)
        for (idx, stay) in sorted.enumerated() {
            let city = resolvedNames[idx]
            let stayStartDay = cal.startOfDay(for: stay.arrival)
            let stayEnd = max(stay.departure ?? stay.arrival, stay.arrival)
            let stayEndDay = cal.startOfDay(for: stayEnd)
            if !buckets.isEmpty {
                let lastIdx = buckets.count - 1
                if buckets[lastIdx].city == city {
                    let gapDays = cal.dateComponents([.day], from: buckets[lastIdx].lastDay, to: stayStartDay).day ?? 0
                    if gapDays <= 1 {
                        if stayEnd > buckets[lastIdx].end { buckets[lastIdx].end = stayEnd }
                        if stayEndDay > buckets[lastIdx].lastDay { buckets[lastIdx].lastDay = stayEndDay }
                        buckets[lastIdx].days.insert(stayStartDay)
                        buckets[lastIdx].count += 1
                        buckets[lastIdx].latSum += stay.latitude
                        buckets[lastIdx].lonSum += stay.longitude
                        continue
                    }
                }
            }
            buckets.append(Bucket(
                city: city,
                start: stay.arrival,
                end: stayEnd,
                lastDay: stayEndDay,
                days: [stayStartDay],
                count: 1,
                latSum: stay.latitude,
                lonSum: stay.longitude
            ))
        }

        return buckets.enumerated().map { idx, b in
            CityStint(
                id: "\(idx)-\(b.city)-\(Int(b.start.timeIntervalSince1970))-\(b.count)",
                city: b.city,
                start: b.start,
                end: b.end,
                days: max(1, b.days.count),
                stayCount: b.count,
                latitude: b.latSum / Double(b.count),
                longitude: b.lonSum / Double(b.count)
            )
        }
        .sorted { $0.start > $1.start }
    }
}

struct CityGlowSpot: Identifiable, Sendable {
    let id: String
    let name: String
    let days: Int
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Async Precomputed Detail Payloads (Zero Main-Thread Blocking on Push)

private struct CountryDetailPayload: Sendable {
    let totalDays: Int
    let citySpots: [CityGlowSpot]
    let daysByCity: [String: Int]
    let firstDate: Date?
    let lastDate: Date?
    let borderStamps: [PassportStamp]
    let cityStamps: [PassportStamp]
    let countryLandmarks: [Stay]
    let stints: [CityStint]
}

private struct ProvinceDetailPayload: Sendable {
    let totalDays: Int
    let totalPlaces: Int
    let citySpots: [CityGlowSpot]
    let firstDate: Date?
    let stints: [CityStint]
}

// MARK: - 1:1 Upstream Country Detail View

struct CountryDetailView: View {
    let countryCode: String
    let fallbackName: String?

    @EnvironmentObject private var store: DataStore
    @State private var payload: CountryDetailPayload?
    @State private var visibleCityStampCount = 9

    init(countryCode: String, fallbackName: String? = nil) {
        self.countryCode = countryCode
        self.fallbackName = fallbackName
    }

    private var countryName: String {
        CountryText.localizedName(code: countryCode, fallback: fallbackName)
    }

    var body: some View {
        Group {
            if let data = payload {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        CityGlowMKMapView(
                            spots: data.citySpots,
                            countryCode: countryCode
                        )
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )

                        MetricGrid2x2 {
                            MetricTile(title: "停留天数", value: "\(data.totalDays)", symbol: "calendar", tint: .teal)
                        } topRight: {
                            MetricTile(title: "城市", value: "\(data.citySpots.count)", symbol: "building.2.fill", tint: .indigo)
                        } bottomLeft: {
                            MetricTile(
                                title: "首次到访",
                                value: data.firstDate.map(Self.zhDate) ?? "—",
                                symbol: "airplane.arrival",
                                tint: .blue
                            )
                        } bottomRight: {
                            MetricTile(
                                title: "最近一次",
                                value: data.lastDate.map(Self.zhDate) ?? "—",
                                symbol: "clock.fill",
                                tint: .orange
                            )
                        }

                        if !data.borderStamps.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "出入境章", trailing: "\(data.borderStamps.count) 枚")
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 14) {
                                        ForEach(data.borderStamps) { stamp in
                                            StampArtView(stamp: stamp)
                                                .frame(width: 120, height: 100)
                                                .rotationEffect(.degrees(stamp.tilt * 0.5))
                                        }
                                    }
                                    .padding(16)
                                }
                                .background(StampPaperView(style: .book))
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            }
                        }

                        if !data.cityStamps.isEmpty {
                            cityStampsSection(data: data)
                        }

                        if !data.countryLandmarks.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "去过的景点", trailing: "\(data.countryLandmarks.count)")
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(data.countryLandmarks.prefix(15)) { stay in
                                            NavigationLink {
                                                DayDetailPage(date: stay.arrival)
                                            } label: {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    PlaceIcon(category: stay.category, isLandmark: true, size: 30)
                                                    Text(stay.displayName)
                                                        .font(.subheadline.weight(.semibold))
                                                        .foregroundColor(.primary)
                                                        .lineLimit(1)
                                                    Text(stay.city ?? Self.zhDate(stay.arrival))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                        .lineLimit(1)
                                                }
                                                .padding(14)
                                                .frame(width: 142, alignment: .leading)
                                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }

                        if !data.stints.isEmpty {
                            StintsByYearSection(stints: data.stints)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在加载\(countryName)足迹…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("\(CountryText.flag(for: countryCode)) \(countryName)")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(countryCode)-\(store.stays.count)") {
            let staysSnap = store.stays
            let code = countryCode
            let computed = await Task.detached(priority: .userInitiated) { () -> CountryDetailPayload in
                let cal = Calendar.current
                let mine = staysSnap.filter { $0.countryCode == code }
                let totalDays = Set(mine.map { cal.startOfDay(for: $0.arrival) }).count
                let byCity = Dictionary(grouping: mine.filter { ($0.city?.isEmpty == false) }) { $0.city! }
                let spots: [CityGlowSpot] = byCity.map { city, list in
                    let d = max(1, Set(list.map { cal.startOfDay(for: $0.arrival) }).count)
                    let lat = list.map(\.latitude).reduce(0, +) / Double(list.count)
                    let lon = list.map(\.longitude).reduce(0, +) / Double(list.count)
                    return CityGlowSpot(id: city, name: city, days: d, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon).onMap)
                }.sorted { $0.days > $1.days }

                let daysByCity = Dictionary(uniqueKeysWithValues: spots.map { ($0.name, $0.days) })
                // Lightweight PassportEngine build without chunks (instant)
                let p = PassportEngine.build(stays: staysSnap, chunks: [])
                let borderStamps = p.passportStamps.filter { $0.countryCode == code }
                let cityStamps = p.cityStamps
                    .filter { $0.countryCode == code }
                    .sorted { (daysByCity[$0.city ?? ""] ?? 0) > (daysByCity[$1.city ?? ""] ?? 0) }

                var seenLandmarks = Set<String>()
                let landmarks = mine.filter(\.isLandmark).filter { seenLandmarks.insert($0.displayName).inserted }
                let stints = CityStint.group(mine)

                return CountryDetailPayload(
                    totalDays: totalDays,
                    citySpots: spots,
                    daysByCity: daysByCity,
                    firstDate: mine.map(\.arrival).min(),
                    lastDate: mine.map { $0.departure ?? $0.arrival }.max(),
                    borderStamps: borderStamps,
                    cityStamps: cityStamps,
                    countryLandmarks: landmarks,
                    stints: stints
                )
            }.value
            guard !Task.isCancelled else { return }
            payload = computed
        }
    }

    @ViewBuilder
    private func cityStampsSection(data: CountryDetailPayload) -> some View {
        let daysByCity = data.daysByCity
        let displayed = Array(data.cityStamps.prefix(visibleCityStampCount))
        let rows = stride(from: 0, to: displayed.count, by: 3).map { idx in
            Array(displayed[idx..<min(idx + 3, displayed.count)])
        }
        let remaining = max(0, data.cityStamps.count - visibleCityStampCount)

        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "城市", trailing: "\(data.cityStamps.count) 枚城市章")
            VStack(spacing: 14) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(row) { stamp in
                            let cityName = stamp.city ?? ""
                            let d = daysByCity[cityName] ?? 1
                            NavigationLink {
                                CityAllVisitsView(city: cityName, countryCode: countryCode)
                            } label: {
                                VStack(spacing: 6) {
                                    StampArtView(stamp: stamp)
                                        .frame(height: 92)
                                        .rotationEffect(.degrees(stamp.tilt * 0.5))
                                    Text(CityStampStyle.displayName(stamp))
                                        .font(.footnote.weight(.semibold))
                                        .foregroundColor(Color(red: 0.25, green: 0.22, blue: 0.2))
                                        .lineLimit(1)
                                    Text("\(d) 天")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundColor(Color(red: 0.45, green: 0.42, blue: 0.38))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                        if row.count < 3 {
                            ForEach(0..<(3 - row.count), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }

                if data.cityStamps.count > 9 {
                    HStack(spacing: 10) {
                        if remaining > 0 {
                            Button {
                                Haptics.selection()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    visibleCityStampCount += 18
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("展开更多城市章（剩余 \(remaining) 枚）")
                                        .font(.footnote.weight(.semibold))
                                    Image(systemName: "chevron.down")
                                        .font(.caption2.weight(.bold))
                                }
                                .foregroundColor(Color(red: 0.35, green: 0.30, blue: 0.24))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.06), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        if visibleCityStampCount > 9 {
                            Button {
                                Haptics.selection()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    visibleCityStampCount = 9
                                }
                            } label: {
                                Text("收起")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(Color(red: 0.35, green: 0.30, blue: 0.24))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.black.opacity(0.06), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 10)
            .background(StampPaperView(style: .book))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private static func zhDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: date)
    }
}

// MARK: - 1:1 Upstream Province Detail View

struct ProvinceDetailView: View {
    let province: ChinaProvince

    @EnvironmentObject private var store: DataStore
    @State private var payload: ProvinceDetailPayload?

    var body: some View {
        Group {
            if let data = payload {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        CityGlowMKMapView(spots: data.citySpots, countryCode: nil)
                            .frame(height: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                            )

                        MetricGrid2x2 {
                            MetricTile(title: "停留天数", value: "\(data.totalDays)", symbol: "calendar", tint: .teal)
                        } topRight: {
                            MetricTile(title: "城市", value: "\(data.citySpots.count)", symbol: "building.2.fill", tint: .indigo)
                        } bottomLeft: {
                            MetricTile(
                                title: "首次到访",
                                value: data.firstDate.map(Self.zhDate) ?? "—",
                                symbol: "airplane.arrival",
                                tint: .blue
                            )
                        } bottomRight: {
                            MetricTile(title: "到访地点", value: "\(data.totalPlaces)", symbol: "mappin.and.ellipse", tint: .pink)
                        }

                        if !data.stints.isEmpty {
                            StintsByYearSection(stints: data.stints)
                        } else {
                            WaytraceCard {
                                Text("暂无该省份的详细停留记录")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在加载\(province.name)足迹…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(province.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(province.id)-\(store.stays.count)") {
            let staysSnap = store.stays
            let targetID = province.id
            let computed = await Task.detached(priority: .userInitiated) { () -> ProvinceDetailPayload in
                let cal = Calendar.current
                let mine = staysSnap.filter {
                    ChinaProvince.containing(countryCode: $0.countryCode, region: $0.region, city: $0.city)?.id == targetID
                }
                let totalDays = Set(mine.map { cal.startOfDay(for: $0.arrival) }).count
                let byCity = Dictionary(grouping: mine.filter {
                    if let c = $0.city, !c.isEmpty, !c.hasSuffix("省"), !c.hasSuffix("自治区") { return true }
                    return false
                }) { $0.city! }

                let spots: [CityGlowSpot] = byCity.map { city, list in
                    let d = max(1, Set(list.map { cal.startOfDay(for: $0.arrival) }).count)
                    let lat = list.map(\.latitude).reduce(0, +) / Double(list.count)
                    let lon = list.map(\.longitude).reduce(0, +) / Double(list.count)
                    return CityGlowSpot(id: city, name: city, days: d, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon).onMap)
                }.sorted { $0.days > $1.days }

                let stints = CityStint.group(mine)
                return ProvinceDetailPayload(
                    totalDays: totalDays,
                    totalPlaces: mine.count,
                    citySpots: spots,
                    firstDate: mine.map(\.arrival).min(),
                    stints: stints
                )
            }.value
            guard !Task.isCancelled else { return }
            payload = computed
        }
    }

    private static func zhDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: date)
    }
}

// MARK: - City All Visits View (Tapped from City Stamp)

struct CityAllVisitsView: View {
    let city: String
    let countryCode: String?
    let initialStays: [Stay]?

    @EnvironmentObject private var store: DataStore
    @State private var resolvedStays: [Stay] = []
    @State private var stints: [CityStint] = []
    @State private var totalDays: Int = 0
    @State private var firstDate: Date?
    @State private var loaded = false

    init(city: String, countryCode: String?, stays: [Stay]? = nil) {
        self.city = city
        self.countryCode = countryCode
        self.initialStays = stays
    }

    var body: some View {
        Group {
            if loaded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        DayRouteMapView(chunks: [], pendingPoints: [], stays: Array(resolvedStays.prefix(150)), currentLocation: nil)
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                        MetricGrid2x2 {
                            MetricTile(title: "停留天数", value: "\(totalDays)", symbol: "calendar", tint: .teal)
                        } topRight: {
                            MetricTile(title: "到访次数", value: "\(stints.count)", symbol: "arrow.triangle.swap", tint: .indigo)
                        } bottomLeft: {
                            MetricTile(
                                title: "首次到访",
                                value: firstDate.map(Self.zhDate) ?? "—",
                                symbol: "airplane.arrival",
                                tint: .blue
                            )
                        } bottomRight: {
                            MetricTile(title: "到访地点", value: "\(resolvedStays.count)", symbol: "mappin.and.ellipse", tint: .pink)
                        }

                        if !stints.isEmpty {
                            StintsByYearSection(stints: stints)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
            } else {
                ProgressView("正在加载\(city)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(city)
        .navigationBarTitleDisplayMode(.large)
        .task(id: "\(city)-\(store.stays.count)") {
            let passed = initialStays
            let allStays = store.stays
            let targetCity = city
            let targetCode = countryCode
            let computed = await Task.detached(priority: .userInitiated) { () -> ([Stay], [CityStint], Int, Date?) in
                let snap = passed ?? allStays.filter { s in
                    s.city == targetCity && (targetCode == nil || s.countryCode == targetCode)
                }
                let cal = Calendar.current
                let days = Set(snap.map { cal.startOfDay(for: $0.arrival) }).count
                return (snap, CityStint.group(snap), days, snap.map(\.arrival).min())
            }.value
            resolvedStays = computed.0
            stints = computed.1
            totalDays = computed.2
            firstDate = computed.3
            loaded = true
        }
    }

    private static func zhDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: date)
    }
}

// MARK: - 1:1 Upstream StintsByYear Section (Year Chips + 12-Month Bar Strip + Monthly Rows)

struct StintsByYearSection: View {
    let stints: [CityStint]
    private let stintsByYear: [Int: [CityStint]]
    private let years: [(year: Int, count: Int)]

    @State private var selectedYear: Int
    @State private var selectedMonth: Int? = nil
    @State private var visibleLimit: Int = 10

    init(stints: [CityStint]) {
        self.stints = stints
        let cal = Calendar.current
        let grouped = Dictionary(grouping: stints) { cal.component(.year, from: $0.start) }
            .mapValues { $0.sorted { $0.start > $1.start } }
        let sortedYears: [(year: Int, count: Int)] = grouped
            .map { (year: $0.key, count: $0.value.count) }
            .sorted { $0.year > $1.year }
        self.stintsByYear = grouped
        self.years = sortedYears
        let firstYear = sortedYears.first?.year ?? cal.component(.year, from: Date())
        _selectedYear = State(initialValue: firstYear)
    }

    private static let zhMonths = ["", "一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月"]

    var body: some View {
        let cal = Calendar.current
        let activeYear = stintsByYear[selectedYear] != nil
            ? selectedYear
            : (years.first?.year ?? cal.component(.year, from: Date()))
        let currentYearStints = stintsByYear[activeYear] ?? []
        var monthDays: [Int: Int] = [:]
        for stint in currentYearStints {
            let m = cal.component(.month, from: stint.start)
            monthDays[m, default: 0] += stint.days
        }
        let filteredStints: [CityStint] = selectedMonth == nil
            ? currentYearStints
            : currentYearStints.filter { cal.component(.month, from: $0.start) == selectedMonth }
        let visibleStints = Array(filteredStints.prefix(visibleLimit))
        let groupedByMonth = Dictionary(grouping: visibleStints) { cal.component(.month, from: $0.start) }
        let monthlyGroups: [(month: Int, stints: [CityStint], totalDays: Int)] = groupedByMonth.map { m, list in
            let days = list.reduce(0) { $0 + $1.days }
            return (m, list, days)
        }
        .sorted { $0.month > $1.month }
        let remaining = max(0, filteredStints.count - visibleLimit)

        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "每一次到访", trailing: "\(stints.count) 次")

            if !years.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(years, id: \.year) { item in
                            let on = activeYear == item.year
                            Button {
                                Haptics.selection()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedYear = item.year
                                    selectedMonth = nil
                                    visibleLimit = 15
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Text(String(item.year))
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(item.count)")
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .opacity(0.75)
                                }
                                .foregroundColor(on ? .white : .primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    on ? Color.accentColor : Color(.secondarySystemGroupedBackground),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            monthBarStrip(daysPerMonth: monthDays)

            ForEach(monthlyGroups, id: \.month) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(group.month >= 1 && group.month <= 12 ? Self.zhMonths[group.month] : "\(group.month)月")
                            .font(.headline)
                        Spacer()
                        Text("\(group.stints.count) 次 · \(group.totalDays) 天")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(group.stints.enumerated()), id: \.element.id) { idx, stint in
                            NavigationLink {
                                if stint.isSingleDay {
                                    DayDetailPage(date: stint.start)
                                } else {
                                    CityStintView(stint: stint)
                                }
                            } label: {
                                CityStintRow(stint: stint, peerStints: group.stints)
                            }
                            .buttonStyle(.plain)

                            if idx < group.stints.count - 1 {
                                Divider().padding(.leading, 82)
                            }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }

            if remaining > 0 {
                Button {
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        visibleLimit += 25
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("加载更多（剩余 \(remaining) 次）")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: stints.count) { _ in
            if stintsByYear[selectedYear] == nil, let first = years.first?.year {
                selectedYear = first
            }
        }
    }

    private func monthBarStrip(daysPerMonth: [Int: Int]) -> some View {
        let maxDays = max(1, daysPerMonth.values.max() ?? 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(1...12, id: \.self) { m in
                let d = daysPerMonth[m] ?? 0
                let isSelected = selectedMonth == m
                let fraction = d > 0 ? max(0.16, CGFloat(d) / CGFloat(maxDays)) : 0
                Button {
                    guard d > 0 else { return }
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedMonth = isSelected ? nil : m
                        visibleLimit = 20
                    }
                } label: {
                    VStack(spacing: 5) {
                        ZStack(alignment: .bottom) {
                            Color.clear.frame(height: 54)
                            if d > 0 {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: isSelected
                                                ? [Color.orange, Color.orange.opacity(0.8)]
                                                : [Color(red: 0.14, green: 0.62, blue: 1.0), Color(red: 0.04, green: 0.45, blue: 0.96)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(height: 54 * fraction)
                            } else {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.16))
                                    .frame(height: 4)
                            }
                        }
                        Text("\(m)")
                            .font(.caption2.monospacedDigit().weight(d > 0 ? .semibold : .regular))
                            .foregroundColor(d > 0 ? (isSelected ? .orange : .primary) : .secondary.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct CityStintRow: View {
    let stint: CityStint
    var peerStints: [CityStint] = []
    @State private var photoItem: PhotoPreviewItem?
    @State private var photoCount: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let item = photoItem {
                    Image(uiImage: item.thumbnail)
                        .resizable()
                        .scaledToFill()
                        .onTapGesture {
                            PhotoLightboxPresenter.present(items: [item])
                        }
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.22), Color.indigo.opacity(0.14)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Text(String(stint.city.prefix(1)))
                            .font(.title3.weight(.bold))
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(stint.city)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(stint.dateRangeText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                let photoPart = photoCount > 0 ? " · \(photoCount) 张照片" : ""
                Text("\(stint.days) 天 · \(stint.stayCount) 处\(photoPart)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .task(id: stint.id) {
            let result = await StintPhotoFetcher.shared.stintPhotoItem(for: stint, among: peerStints)
            guard !Task.isCancelled else { return }
            photoItem = result.item
            photoCount = result.count
        }
    }
}

// MARK: - City Stint Detail View (Multi-Day Visit to a City)

struct CityStintView: View {
    let stint: CityStint
    @EnvironmentObject private var store: DataStore
    @State private var matchedStays: [Stay] = []
    @State private var days: [StintDayGroup] = []
    @State private var loaded = false

    private struct StintDayGroup: Identifiable, Sendable {
        let date: Date
        let stays: [Stay]
        var id: Date { date }
    }

    var body: some View {
        Group {
            if loaded {
                stintScrollContent
            } else {
                ProgressView("正在加载\(stint.city)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(stint.city)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: stint.id) {
            let all = store.stays
            let s = stint
            let result = await Task.detached(priority: .userInitiated) { () -> ([Stay], [StintDayGroup]) in
                let startBound = s.start.addingTimeInterval(-60)
                let endBound = max(s.end, s.start).addingTimeInterval(60)
                let filtered = all.filter { stay in
                    stay.arrival >= startBound && stay.arrival <= endBound
                }
                let cal = Calendar.current
                let grouped = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.arrival) }
                let dayList = grouped.map { StintDayGroup(date: $0.key, stays: $0.value.sorted { $0.arrival < $1.arrival }) }
                    .sorted { $0.date > $1.date }
                return (filtered, dayList)
            }.value
            matchedStays = result.0
            days = result.1
            loaded = true
        }
    }

    private var stintScrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DayRouteMapView(chunks: [], pendingPoints: [], stays: Array(matchedStays.prefix(120)), currentLocation: nil)
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                HStack(spacing: 0) {
                    stintMetric(value: "\(stint.days)", label: "天", symbol: "calendar", tint: .teal)
                    Divider().frame(height: 32)
                    stintMetric(value: "\(stint.stayCount)", label: "个地点", symbol: "mappin.and.ellipse", tint: .pink)
                }
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                SectionHeader(title: "每日行程", trailing: "\(days.count) 天")
                daysListCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    private var daysListCard: some View {
        let visibleDays = Array(days.prefix(60))
        return VStack(spacing: 0) {
            ForEach(Array(visibleDays.enumerated()), id: \.element.id) { idx, item in
                NavigationLink {
                    DayDetailPage(date: item.date)
                } label: {
                    dayRowLabel(item)
                }
                .buttonStyle(.plain)

                if idx < visibleDays.count - 1 {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func dayRowLabel(_ item: StintDayGroup) -> some View {
        let preview = item.stays.map(\.displayName).removingDuplicates().prefix(3).joined(separator: " · ")
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Formatters.dayTitle(item.date))
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(preview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(item.stays.count) 处")
                .font(.subheadline.monospacedDigit())
                .foregroundColor(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func stintMetric(value: String, label: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
            HStack(spacing: 4) {
                Image(systemName: symbol).foregroundColor(tint)
                Text(label).foregroundColor(.secondary)
            }
            .font(.caption.weight(.medium))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 1:1 Upstream Day Detail Page

struct DayDetailPage: View {
    let date: Date

    @EnvironmentObject private var store: DataStore
    @AppStorage("wt16.timeline.newestFirst") private var newestFirst = true
    @State private var showFullMap = false
    @State private var selectedStay: Stay?

    private var dayStays: [Stay] { store.stays(on: date) }
    private var dayChunks: [TrackChunk] { store.chunks(on: date) }
    private var dayDistance: Double { dayChunks.reduce(0) { $0 + $1.distance } }

    private enum Entry: Identifiable {
        case stay(Stay)
        case move(TrackChunk)
        var id: String {
            switch self {
            case .stay(let s): return "s-\(s.id.uuidString)"
            case .move(let c): return "c-\(c.id.uuidString)"
            }
        }
        var sortDate: Date {
            switch self {
            case .stay(let s): return s.arrival
            case .move(let c): return c.startDate
            }
        }

        var endDate: Date {
            switch self {
            case .stay(let s): return s.departure ?? Date.distantFuture
            case .move(let c): return c.endDate
            }
        }
    }

    private static func isEarlier(_ lhs: Entry, _ rhs: Entry) -> Bool {
        let lEnd = lhs.endDate
        let rEnd = rhs.endDate
        if abs(lEnd.timeIntervalSince(rEnd)) > 90 {
            return lEnd < rEnd
        }
        switch (lhs, rhs) {
        case (.stay(let s), .move(let c)):
            let dep = s.departure ?? Date.distantFuture
            return abs(c.endDate.timeIntervalSince(dep)) <= abs(c.endDate.timeIntervalSince(s.arrival))
        case (.move(let c), .stay(let s)):
            let dep = s.departure ?? Date.distantFuture
            return abs(c.endDate.timeIntervalSince(s.arrival)) < abs(c.endDate.timeIntervalSince(dep))
        default:
            return lhs.sortDate < rhs.sortDate
        }
    }

    private var entries: [Entry] {
        let sorted = (dayStays.map(Entry.stay) + dayChunks.map(Entry.move)).sorted(by: Self.isEarlier)
        return newestFirst ? sorted.reversed() : sorted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button { showFullMap = true } label: {
                    ZStack(alignment: .bottomLeading) {
                        DayRouteMapView(chunks: dayChunks, pendingPoints: [], stays: dayStays, currentLocation: nil)
                            .allowsHitTesting(false)
                        Label("查看地图", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(12)
                    }
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .buttonStyle(PressableStyle())

                HStack(spacing: 0) {
                    dayMetric(value: Formatters.distance(dayDistance), label: "移动", symbol: "point.topleft.down.curvedto.point.bottomright.up", tint: .blue)
                    Divider().frame(height: 34)
                    dayMetric(value: "\(dayChunks.count)", label: "段行程", symbol: "figure.walk", tint: .green)
                    Divider().frame(height: 34)
                    dayMetric(value: "\(dayStays.count)", label: "个地点", symbol: "mappin.and.ellipse", tint: .pink)
                }
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                HStack {
                    Text("时间线").font(.title3.bold())
                    Spacer()
                    Button {
                        Haptics.selection()
                        withAnimation(.easeInOut(duration: 0.2)) { newestFirst.toggle() }
                    } label: {
                        Label(newestFirst ? "最新在前" : "最早在前", systemImage: "arrow.up.arrow.down")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                        switch entry {
                        case .stay(let stay):
                            DayDetailStayRow(stay: stay, day: date, dayStays: dayStays, isFirst: idx == 0, isLast: idx == entries.count - 1)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedStay = stay }
                        case .move(let chunk):
                            DayDetailMoveRow(chunk: chunk)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(Formatters.dayTitle(date)).font(.headline)
                    Text(Formatters.weekdaySubtitle(date)).font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .sheet(item: $selectedStay) { stay in
            StayDetailSheet(stay: stay)
        }
        .fullScreenCover(isPresented: $showFullMap) {
            ZStack(alignment: .topTrailing) {
                DayRouteMapView(chunks: dayChunks, pendingPoints: [], stays: dayStays, currentLocation: nil)
                    .ignoresSafeArea()
                Button { showFullMap = false } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.primary)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding()
                }
            }
        }
    }

    private func dayMetric(value: String, label: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 3) {
                Image(systemName: symbol).foregroundColor(tint)
                Text(label).foregroundColor(.secondary)
            }
            .font(.caption.weight(.medium))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DayDetailStayRow: View {
    let stay: Stay
    let day: Date
    let dayStays: [Stay]
    let isFirst: Bool
    let isLast: Bool

    @State private var photos: [PhotoPreviewItem] = []

    private func dayOffset(of target: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: day), to: cal.startOfDay(for: target)).day ?? 0
    }

    @ViewBuilder
    private func timeWithDayBadge(_ date: Date, font: Font, color: Color) -> some View {
        let offset = dayOffset(of: date)
        HStack(alignment: .center, spacing: 3) {
            if offset != 0 {
                Text(offset > 0 ? "+\(offset)" : "\(offset)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 3.5)
                    .padding(.vertical, 1)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                    .fixedSize()
            }
            Text(Formatters.timeHM(date))
                .font(font)
                .foregroundColor(color)
                .fixedSize()
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .trailing, spacing: 2) {
                if let dep = stay.departure {
                    timeWithDayBadge(dep, font: .subheadline.weight(.semibold), color: .primary)
                } else {
                    Text("现在")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .fixedSize()
                }
                timeWithDayBadge(stay.arrival, font: .caption, color: .secondary)
            }
            .monospacedDigit()
            .lineLimit(1)
            .frame(width: 62, alignment: .trailing)
            .padding(.top, 12)

            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(width: 2)
                    .padding(.top, isFirst ? 22 : 0)
                    .padding(.bottom, isLast ? 22 : 0)

                PlaceIcon(category: stay.category, isLandmark: stay.isLandmark, size: 26)
                    .padding(3)
                    .background(Circle().fill(Color(.systemGroupedBackground)))
                    .overlay(alignment: .bottomTrailing) {
                        if stay.isFromPhotos {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 14, height: 14)
                                .background(Circle().fill(Color.pink))
                                .overlay(Circle().stroke(Color(.systemGroupedBackground), lineWidth: 1.5))
                                .offset(x: 2, y: 2)
                        }
                    }
                    .padding(.top, 10)
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stay.displayName)
                        .font(.headline)
                        .lineLimit(2)
                    Text([stay.city, Formatters.duration(stay.duration)].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(photos.enumerated()), id: \.element.id) { idx, item in
                                Image(uiImage: item.thumbnail)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .onTapGesture {
                                        PhotoLightboxPresenter.present(items: photos, startIndex: idx)
                                    }
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.bottom, 10)
        }
        .task(id: stay.id) {
            photos = await StintPhotoFetcher.shared.stayPhotoItems(for: stay, among: dayStays)
        }
    }
}

private struct DayDetailMoveRow: View {
    let chunk: TrackChunk

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 62)
            Rectangle()
                .fill(chunk.mode.color.opacity(0.75))
                .frame(width: 3)
                .frame(width: 36)
            HStack(spacing: 8) {
                Image(systemName: chunk.mode.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundColor(chunk.mode.color)
                    .frame(width: 24, height: 24)
                    .background(chunk.mode.color.opacity(0.14), in: Circle())
                Text(chunk.mode.title).font(.footnote.weight(.semibold))
                Text("\(Formatters.distance(chunk.distance)) · \(Formatters.duration(chunk.duration))")
                    .font(.footnote.monospacedDigit())
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Orange City Glow Map (Native Frosted Glass Pills + 4-Direction Anti-Overlap Placement)

private enum CityPillPlacement {
    case above, below, right, left
}

private final class CityGlowAnnotation: NSObject, MKAnnotation {
    let spot: CityGlowSpot
    var showLabel: Bool
    var placement: CityPillPlacement = .above
    dynamic var coordinate: CLLocationCoordinate2D

    init(spot: CityGlowSpot, showLabel: Bool) {
        self.spot = spot
        self.showLabel = showLabel
        self.coordinate = spot.coordinate
    }
}

private final class CityGlowAnnotationView: MKAnnotationView {
    private let glassContainer = UIView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var isLabelVisible = false
    private var currentPlacement: CityPillPlacement = .above
    private var currentPillSize: CGSize = .zero

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        displayPriority = .required
        clipsToBounds = false

        glassContainer.isUserInteractionEnabled = false
        glassContainer.alpha = 0
        glassContainer.isHidden = true
        glassContainer.layer.shadowColor = UIColor.black.cgColor
        glassContainer.layer.shadowOpacity = 0.14
        glassContainer.layer.shadowRadius = 6
        glassContainer.layer.shadowOffset = CGSize(width: 0, height: 2)

        blurView.clipsToBounds = true
        blurView.layer.cornerRadius = 12
        blurView.layer.cornerCurve = .continuous
        blurView.layer.borderWidth = 0.6
        blurView.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        glassContainer.addSubview(blurView)

        titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center

        blurView.contentView.addSubview(titleLabel)
        blurView.contentView.addSubview(subtitleLabel)
        addSubview(glassContainer)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func pillSize(for spot: CityGlowSpot) -> CGSize {
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .semibold)]
        let subAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)]
        let tw = min(140, ceil((spot.name as NSString).size(withAttributes: titleAttrs).width))
        let th = ceil((spot.name as NSString).size(withAttributes: titleAttrs).height)
        let sw = ceil(("\(spot.days) 天" as NSString).size(withAttributes: subAttrs).width)
        let sh = ceil(("\(spot.days) 天" as NSString).size(withAttributes: subAttrs).height)
        return CGSize(width: max(tw, sw) + 18, height: th + sh + 10)
    }

    func setDotImage(_ dot: UIImage) {
        if self.image !== dot {
            self.image = dot
            self.centerOffset = .zero
            positionPill()
        }
    }

    func configureLabel(spot: CityGlowSpot, visible: Bool, placement: CityPillPlacement, animated: Bool, rank: Int = 0) {
        let size = Self.pillSize(for: spot)
        currentPillSize = size
        currentPlacement = placement

        titleLabel.text = spot.name
        subtitleLabel.text = "\(spot.days) 天"
        glassContainer.bounds = CGRect(origin: .zero, size: size)
        blurView.frame = glassContainer.bounds
        let titleH: CGFloat = 15
        let subH: CGFloat = 13
        titleLabel.frame = CGRect(x: 9, y: 4, width: size.width - 18, height: titleH)
        subtitleLabel.frame = CGRect(x: 9, y: 4 + titleH + 1, width: size.width - 18, height: subH)
        positionPill()

        if visible {
            zPriority = MKAnnotationViewZPriority(rawValue: max(500, 1000 - Float(rank) * 15))
        } else {
            zPriority = .defaultUnselected
        }

        guard isLabelVisible != visible else { return }
        isLabelVisible = visible

        if visible {
            glassContainer.isHidden = false
            if animated {
                glassContainer.alpha = 0
                glassContainer.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
                UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                    self.glassContainer.alpha = 1
                    self.glassContainer.transform = .identity
                }
            } else {
                glassContainer.alpha = 1
                glassContainer.transform = .identity
            }
        } else {
            if animated {
                UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseIn, .beginFromCurrentState], animations: {
                    self.glassContainer.alpha = 0
                    self.glassContainer.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
                }) { finished in
                    if finished && !self.isLabelVisible {
                        self.glassContainer.isHidden = true
                        self.glassContainer.transform = .identity
                    }
                }
            } else {
                glassContainer.alpha = 0
                glassContainer.isHidden = true
                glassContainer.transform = .identity
            }
        }
    }

    private func positionPill() {
        let s = currentPillSize
        guard s.width > 0 else { return }
        let gap: CGFloat = 12
        let cx = bounds.midX
        let cy = bounds.midY
        switch currentPlacement {
        case .above:
            glassContainer.center = CGPoint(x: cx, y: cy - gap - s.height / 2)
        case .below:
            glassContainer.center = CGPoint(x: cx, y: cy + gap + s.height / 2)
        case .right:
            glassContainer.center = CGPoint(x: cx + gap + s.width / 2, y: cy)
        case .left:
            glassContainer.center = CGPoint(x: cx - gap - s.width / 2, y: cy)
        }
    }
}

private struct CityGlowMKMapView: UIViewRepresentable {
    let spots: [CityGlowSpot]
    let countryCode: String?
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        let config = MKStandardMapConfiguration(elevationStyle: .flat)
        config.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = config
        map.showsCompass = false
        map.showsScale = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.delegate = context.coordinator
        context.coordinator.isDark = (colorScheme == .dark)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let isDark = (colorScheme == .dark)
        if context.coordinator.isDark != isDark {
            context.coordinator.isDark = isDark
        }

        let sig = "\(countryCode ?? "")|\(spots.count)|\(spots.first?.id ?? "")"
        guard context.coordinator.lastSignature != sig else { return }
        context.coordinator.lastSignature = sig

        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)

        let validSpots = spots.filter { $0.coordinate.latitude.isFinite && $0.coordinate.longitude.isFinite && abs($0.coordinate.latitude) <= 90 && abs($0.coordinate.longitude) <= 180 }
        var allCoords: [CLLocationCoordinate2D] = validSpots.map(\.coordinate)

        if let code = countryCode {
            let rings = CountryBorders.pieces(of: code, visited: validSpots.map(\.coordinate))
            var polys: [MKPolygon] = []
            for ring in rings where ring.count >= 3 {
                var coords = ring.filter { $0.latitude.isFinite && $0.longitude.isFinite && abs($0.latitude) <= 90 && abs($0.longitude) <= 180 }
                guard coords.count >= 3 else { continue }
                polys.append(MKPolygon(coordinates: &coords, count: coords.count))
                let step = max(1, coords.count / 30)
                for i in stride(from: 0, to: coords.count, by: step) {
                    allCoords.append(coords[i])
                }
            }
            if !polys.isEmpty {
                map.addOverlay(MKMultiPolygon(polys), level: .aboveRoads)
            }
        }

        let annotations = validSpots.map { CityGlowAnnotation(spot: $0, showLabel: false) }
        context.coordinator.allAnnotations = annotations
        map.addAnnotations(annotations)

        if !allCoords.isEmpty {
            let lats = allCoords.map(\.latitude)
            let lons = allCoords.map(\.longitude)
            var minLat = lats.min()!
            var maxLat = lats.max()!
            let minLon = lons.min()!
            let maxLon = lons.max()!

            if countryCode != nil, !validSpots.isEmpty {
                let spotLats = validSpots.map(\.coordinate.latitude)
                let spotMinLat = spotLats.min()!
                let spotMaxLat = spotLats.max()!
                maxLat = min(maxLat, max(spotMaxLat + 14.0, spotMinLat + 22.0))
                minLat = min(minLat, spotMinLat - 5.0)
            }

            let rawLatSpan = max(0, maxLat - minLat)
            let rawLonSpan = max(0, maxLon - minLon)
            let minSpan: Double = countryCode == nil ? 1.6 : 6.0
            let latDelta = min(120.0, max(minSpan, rawLatSpan * (countryCode == nil ? 1.85 : 1.45)))
            let lonDelta = min(260.0, max(minSpan * 1.15, rawLonSpan * (countryCode == nil ? 1.95 : 1.35)))
            let centerLat: Double
            if countryCode == nil {
                centerLat = (minLat + maxLat) / 2.0 + latDelta * 0.06
            } else if !validSpots.isEmpty {
                let mid = (minLat + maxLat) / 2.0
                let spotMinLat = validSpots.map(\.coordinate.latitude).min()!
                let maxAllowedCenter = spotMinLat + latDelta * 0.30
                centerLat = min(mid, maxAllowedCenter)
            } else {
                centerLat = (minLat + maxLat) / 2.0
            }
            let centerLon = min(180, max(-180, (minLon + maxLon) / 2.0))
            let safeCenterLat = min(80, max(-80, centerLat))
            guard safeCenterLat.isFinite, centerLon.isFinite, latDelta.isFinite, lonDelta.isFinite else { return }

            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: safeCenterLat, longitude: centerLon),
                span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
            )
            map.setRegion(region, animated: false)
            DispatchQueue.main.async {
                context.coordinator.refreshDynamicLabels(in: map, animated: false)
            }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var lastSignature = ""
        var isDark = false
        var allAnnotations: [CityGlowAnnotation] = []
        private var dotCache: [Int: UIImage] = [:]

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            refreshDynamicLabels(in: mapView, animated: true)
        }

        private static func candidateRect(for pt: CGPoint, size: CGSize, placement: CityPillPlacement) -> CGRect {
            let gap: CGFloat = 12
            let center: CGPoint
            switch placement {
            case .above: center = CGPoint(x: pt.x, y: pt.y - gap - size.height / 2)
            case .below: center = CGPoint(x: pt.x, y: pt.y + gap + size.height / 2)
            case .right: center = CGPoint(x: pt.x + gap + size.width / 2, y: pt.y)
            case .left:  center = CGPoint(x: pt.x - gap - size.width / 2, y: pt.y)
            }
            return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        }

        /// Dynamically places frosted-glass city pills in 4 directions (above -> below -> right -> left)
        /// avoiding both other pills and every visible glowing dot.
        func refreshDynamicLabels(in mapView: MKMapView, animated: Bool) {
            guard !allAnnotations.isEmpty, mapView.bounds.width > 10 else { return }
            let visibleRect = mapView.visibleMapRect
            let safeBounds = mapView.bounds.insetBy(dx: 8, dy: 8)

            var dotRects: [(ObjectIdentifier, CGRect)] = []
            var visiblePoints: [ObjectIdentifier: CGPoint] = [:]
            for ann in allAnnotations {
                let mp = MKMapPoint(ann.coordinate)
                guard visibleRect.contains(mp) else { continue }
                let pt = mapView.convert(ann.coordinate, toPointTo: mapView)
                if mapView.bounds.contains(pt) {
                    let oid = ObjectIdentifier(ann)
                    visiblePoints[oid] = pt
                    dotRects.append((oid, CGRect(x: pt.x - 10, y: pt.y - 10, width: 20, height: 20)))
                }
            }

            var occupiedPills: [CGRect] = []
            var visibleLabelCount = 0
            let maxLabels = 16
            let order: [CityPillPlacement] = [.above, .below, .right, .left]

            for ann in allAnnotations {
                let oid = ObjectIdentifier(ann)
                var chosenPlacement: CityPillPlacement? = nil
                var rank = visibleLabelCount

                if visibleLabelCount < maxLabels, let pt = visiblePoints[oid] {
                    let pillSize = CityGlowAnnotationView.pillSize(for: ann.spot)
                    for dir in order {
                        let rect = Self.candidateRect(for: pt, size: pillSize, placement: dir)
                        guard safeBounds.contains(rect) else { continue }
                        let padded = rect.insetBy(dx: -3, dy: -3)
                        let hitsPill = occupiedPills.contains { $0.intersects(padded) }
                        if hitsPill { continue }
                        let hitsOtherDot = dotRects.contains { $0.0 != oid && $0.1.intersects(padded) }
                        if hitsOtherDot { continue }
                        chosenPlacement = dir
                        occupiedPills.append(rect)
                        rank = visibleLabelCount
                        visibleLabelCount += 1
                        break
                    }
                }

                let shouldShow = (chosenPlacement != nil)
                let finalPlacement = chosenPlacement ?? ann.placement
                let changed = (ann.showLabel != shouldShow) || (shouldShow && ann.placement != finalPlacement)
                ann.showLabel = shouldShow
                ann.placement = finalPlacement

                if changed, let view = mapView.view(for: ann) as? CityGlowAnnotationView {
                    view.configureLabel(
                        spot: ann.spot,
                        visible: shouldShow,
                        placement: finalPlacement,
                        animated: animated,
                        rank: rank
                    )
                } else if shouldShow, let view = mapView.view(for: ann) as? CityGlowAnnotationView {
                    view.zPriority = MKAnnotationViewZPriority(rawValue: max(500, 1000 - Float(rank) * 15))
                }
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let multi = overlay as? MKMultiPolygon {
                let r = MKMultiPolygonRenderer(multiPolygon: multi)
                r.fillColor = UIColor.systemBlue.withAlphaComponent(0.06)
                r.strokeColor = UIColor.systemBlue.withAlphaComponent(0.78)
                r.lineWidth = 1.2
                r.lineJoin = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let glowAnn = annotation as? CityGlowAnnotation else { return nil }
            let id = "cityGlowPin"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? CityGlowAnnotationView)
                ?? CityGlowAnnotationView(annotation: glowAnn, reuseIdentifier: id)
            view.annotation = glowAnn
            view.setDotImage(renderDotImage(days: glowAnn.spot.days))
            view.configureLabel(
                spot: glowAnn.spot,
                visible: glowAnn.showLabel,
                placement: glowAnn.placement,
                animated: false
            )
            return view
        }

        private func renderDotImage(days: Int) -> UIImage {
            let glowRadius: CGFloat = min(30, max(18, 17 + CGFloat(log2(Double(max(1, days)) + 1)) * 3.5))
            let radiusKey = Int(glowRadius.rounded())
            if let cached = dotCache[radiusKey] { return cached }
            let glowDiameter = CGFloat(radiusKey) * 2
            let size = CGSize(width: glowDiameter, height: glowDiameter)
            let img = UIGraphicsImageRenderer(size: size).image { ctx in
                drawOrangeGlow(in: ctx.cgContext, center: CGPoint(x: CGFloat(radiusKey), y: CGFloat(radiusKey)), radius: CGFloat(radiusKey))
            }
            dotCache[radiusKey] = img
            return img
        }

        private func drawOrangeGlow(in ctx: CGContext, center: CGPoint, radius: CGFloat) {
            let orange = UIColor(red: 0.96, green: 0.48, blue: 0.14, alpha: 1.0)
            let colors = [
                orange.withAlphaComponent(0.55).cgColor,
                orange.withAlphaComponent(0.22).cgColor,
                orange.withAlphaComponent(0.0).cgColor
            ] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.55, 1.0]) {
                ctx.drawRadialGradient(grad, startCenter: center, startRadius: 2, endCenter: center, endRadius: radius, options: [])
            }
            let dotR: CGFloat = 6.5
            let dotRect = CGRect(x: center.x - dotR, y: center.y - dotR, width: dotR * 2, height: dotR * 2)
            orange.setFill()
            UIBezierPath(ovalIn: dotRect).fill()
            UIColor.white.setStroke()
            let strokePath = UIBezierPath(ovalIn: dotRect)
            strokePath.lineWidth = 2.0
            strokePath.stroke()
        }
    }
}

// MARK: - Lightweight Local Photo Thumbnail Fetcher (Time-Window Scoped to Each Stint)

actor StintPhotoFetcher {
    static let shared = StintPhotoFetcher()

    /// Whether pictures without GPS location are excluded from timeline, stays, and trips.
    static let locatedOnlyKey = "wt16.photos.locatedOnly"
    static var locatedOnly: Bool { UserDefaults.standard.bool(forKey: locatedOnlyKey) }

    /// A photo with GPS belongs to a stay only when within 2 km of the stay.
    static let placeRadius: CLLocationDistance = 2_000

    static func belongs(photoAt location: CLLocation?, to place: CLLocation, locatedOnly: Bool) -> Bool {
        guard let location else { return !locatedOnly }
        return location.distance(from: place) <= placeRadius
    }

    private var stintCache: [String: (item: PhotoPreviewItem?, count: Int)] = [:]
    private var stayCache: [UUID: [PhotoPreviewItem]] = [:]
    private var dayThumbCache: [String: PhotoPreviewItem] = [:]
    private var placeThumbCache: [String: PhotoPreviewItem?] = [:]
    private var heroImageCache: [String: UIImage] = [:]

    func invalidateCaches() {
        stintCache.removeAll()
        stayCache.removeAll()
        dayThumbCache.removeAll()
        placeThumbCache.removeAll()
    }

    /// Fetches a crisp high-resolution image (downloading from iCloud if needed) for full-bleed hero banners.
    func highResImage(forAssetID assetID: String, maxSize: CGSize = CGSize(width: 1400, height: 1400)) async -> UIImage? {
        if let cached = heroImageCache[assetID] { return cached }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetched.firstObject else { return nil }
        let img = await requestHighRes(asset: asset, size: maxSize)
        if let img {
            if heroImageCache.count > 40 { heroImageCache.removeAll() }
            heroImageCache[assetID] = img
        }
        return img
    }

    /// Fetches a representative photo actually taken near a MustSeePlace on `date`:
    /// 1) Prioritizes GPS-tagged photos within `max(place.radius * 1000, 2000)` meters of `place.location`.
    /// 2) Falls back to untagged (no-GPS) photos taken within ±20 minutes of `date`.
    /// 3) Never picks a photo whose GPS coordinate is elsewhere; returns `nil` to fall back to the place icon.
    func placePhotoItem(for place: MustSeePlace, around date: Date) async -> PhotoPreviewItem? {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let key = "\(place.id)-\(Int(dayStart.timeIntervalSince1970))"
        if let cached = placeThumbCache[key] {
            return cached
        }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }

        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", dayStart as NSDate, dayEnd as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.fetchLimit = 200
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        guard assets.count > 0 else {
            if placeThumbCache.count > 200 { placeThumbCache.removeAll() }
            placeThumbCache[key] = nil
            return nil
        }

        let center = place.location
        let maxDistance = max(place.radius * 1000.0, 2_000.0)
        var gpsMatched: [PHAsset] = []
        var untaggedNearTime: [PHAsset] = []

        for i in 0..<assets.count {
            let asset = assets.object(at: i)
            if place.countryCode != nil {
                gpsMatched.append(asset)
            } else if let loc = asset.location {
                if loc.distance(from: center) <= maxDistance {
                    gpsMatched.append(asset)
                }
            } else if let created = asset.creationDate, abs(created.timeIntervalSince(date)) <= 1_200 {
                untaggedNearTime.append(asset)
            }
        }

        let candidates = !gpsMatched.isEmpty ? gpsMatched : untaggedNearTime
        guard !candidates.isEmpty else {
            if placeThumbCache.count > 200 { placeThumbCache.removeAll() }
            placeThumbCache[key] = nil
            return nil
        }

        let chosen = candidates[candidates.count / 2]
        let img = await requestThumb(asset: chosen, size: CGSize(width: 200, height: 200))
        let item = img.map {
            PhotoPreviewItem(
                id: chosen.localIdentifier,
                assetID: chosen.localIdentifier,
                thumbnail: $0,
                caption: "\(place.name) · \(Formatters.dayTitle(date))"
            )
        }
        if placeThumbCache.count > 200 { placeThumbCache.removeAll() }
        placeThumbCache[key] = item
        return item
    }

    func dayPhotoItem(around date: Date, caption: String? = nil) async -> PhotoPreviewItem? {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let key = "\(Int(dayStart.timeIntervalSince1970))"
        if let cached = dayThumbCache[key] {
            return PhotoPreviewItem(id: cached.id, assetID: cached.assetID, thumbnail: cached.thumbnail, caption: caption ?? cached.caption)
        }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }

        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", dayStart as NSDate, dayEnd as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.fetchLimit = 60
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        let requireLocation = Self.locatedOnly
        var candidates: [PHAsset] = []
        for i in 0..<assets.count {
            let asset = assets.object(at: i)
            guard !asset.mediaSubtypes.contains(.photoScreenshot) else { continue }
            if !requireLocation || asset.location != nil {
                candidates.append(asset)
            }
        }
        guard !candidates.isEmpty else { return nil }
        let chosen = candidates[candidates.count / 2]
        if let img = await requestThumb(asset: chosen, size: CGSize(width: 200, height: 200)) {
            let item = PhotoPreviewItem(id: chosen.localIdentifier, assetID: chosen.localIdentifier, thumbnail: img, caption: caption ?? Formatters.dayTitle(date))
            if dayThumbCache.count > 120 { dayThumbCache.removeAll() }
            dayThumbCache[key] = item
            return item
        }
        return nil
    }

    func dayThumbnail(around date: Date) async -> UIImage? {
        await dayPhotoItem(around: date)?.thumbnail
    }

    func stintPhotoItem(for stint: CityStint, among peerStints: [CityStint] = []) async -> (item: PhotoPreviewItem?, count: Int) {
        if peerStints.isEmpty, let cached = stintCache[stint.id] { return cached }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return (nil, 0)
        }

        let windowStart = stint.start.addingTimeInterval(-900)
        let rawEnd = max(stint.end, stint.start).addingTimeInterval(900)
        let windowEnd = min(rawEnd, stint.start.addingTimeInterval(7 * 86_400))

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", windowStart as NSDate, windowEnd as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.fetchLimit = 80

        let assets = PHAsset.fetchAssets(with: .image, options: options)
        let requireLocation = Self.locatedOnly
        let stintCenter = CLLocation(latitude: stint.latitude, longitude: stint.longitude)
        let peers = peerStints.count > 1 ? peerStints : []
        var candidates: [PHAsset] = []
        for i in 0..<assets.count {
            let asset = assets.object(at: i)
            guard !asset.mediaSubtypes.contains(.photoScreenshot) else { continue }
            let fitsLocation: Bool
            if let loc = asset.location {
                fitsLocation = loc.distance(from: stintCenter) <= 50_000
            } else {
                fitsLocation = !requireLocation
            }
            guard fitsLocation else { continue }
            if !peers.isEmpty, let bestID = Self.bestMatchingStintID(for: asset, among: peers, locatedOnly: requireLocation), bestID != stint.id {
                continue
            }
            candidates.append(asset)
        }
        let count = candidates.count
        guard count > 0 else {
            if stintCache.count > 160 { stintCache.removeAll() }
            stintCache[stint.id] = (nil, 0)
            return (nil, 0)
        }

        let chosen = candidates[count / 2]
        let img = await requestThumb(asset: chosen, size: CGSize(width: 180, height: 180))
        let item = img.map { PhotoPreviewItem(id: chosen.localIdentifier, assetID: chosen.localIdentifier, thumbnail: $0, caption: "\(stint.city) · \(stint.dateRangeText)") }
        let res = (item, count)
        if stintCache.count > 160 { stintCache.removeAll() }
        stintCache[stint.id] = res
        return res
    }

    private static func stintTimeDistance(from date: Date, to stint: CityStint) -> TimeInterval {
        let end = max(stint.end, stint.start)
        if date < stint.start { return stint.start.timeIntervalSince(date) }
        if date > end { return date.timeIntervalSince(end) }
        return 0
    }

    /// Assigns each photo exclusively to the single closest CityStint (GPS distance first, then time) so adjacent cities never show duplicate photos.
    private static func bestMatchingStintID(for asset: PHAsset, among stints: [CityStint], locatedOnly: Bool) -> String? {
        guard let created = asset.creationDate else { return nil }
        let candidates = stints.filter { s in
            guard stintTimeDistance(from: created, to: s) <= 900 else { return false }
            if let loc = asset.location {
                return loc.distance(from: CLLocation(latitude: s.latitude, longitude: s.longitude)) <= 50_000
            }
            return !locatedOnly
        }
        guard !candidates.isEmpty else { return nil }
        if let loc = asset.location {
            return candidates.min { a, b in
                let da = loc.distance(from: CLLocation(latitude: a.latitude, longitude: a.longitude))
                let db = loc.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
                if abs(da - db) > 50 { return da < db }
                let ta = stintTimeDistance(from: created, to: a)
                let tb = stintTimeDistance(from: created, to: b)
                if abs(ta - tb) > 1 { return ta < tb }
                return a.start < b.start
            }?.id
        }
        return candidates.min { a, b in
            let ta = stintTimeDistance(from: created, to: a)
            let tb = stintTimeDistance(from: created, to: b)
            if abs(ta - tb) > 1 { return ta < tb }
            return a.start < b.start
        }?.id
    }

    func thumbnail(for stint: CityStint) async -> (image: UIImage?, count: Int) {
        let r = await stintPhotoItem(for: stint)
        return (r.item?.thumbnail, r.count)
    }

    func stayPhotoItems(for stay: Stay, among dayStays: [Stay] = []) async -> [PhotoPreviewItem] {
        if dayStays.isEmpty, let cached = stayCache[stay.id] { return cached }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return [] }

        let start = stay.arrival.addingTimeInterval(-300)
        let rawEnd = Self.effectiveEnd(of: stay)
        let end = rawEnd.addingTimeInterval(300)
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.fetchLimit = 80

        let assets = PHAsset.fetchAssets(with: .image, options: options)
        let requireLocation = Self.locatedOnly
        let place = stay.location
        let peers = dayStays.count > 1 ? dayStays : []
        var items: [PhotoPreviewItem] = []
        let cap = "\(stay.displayName) · \(Formatters.dayTitle(stay.arrival))"
        for i in 0..<assets.count {
            let asset = assets.object(at: i)
            guard !asset.mediaSubtypes.contains(.photoScreenshot) else { continue }
            guard Self.belongs(photoAt: asset.location, to: place, locatedOnly: requireLocation) else { continue }
            if !peers.isEmpty, let bestID = Self.bestMatchingStayID(for: asset, among: peers, locatedOnly: requireLocation), bestID != stay.id {
                continue
            }
            if let img = await requestThumb(asset: asset, size: CGSize(width: 200, height: 200)) {
                items.append(PhotoPreviewItem(id: asset.localIdentifier, assetID: asset.localIdentifier, thumbnail: img, caption: cap))
                if items.count >= 36 { break }
            }
        }
        if stayCache.count > 160 { stayCache.removeAll() }
        stayCache[stay.id] = items
        return items
    }

    private static func effectiveEnd(of stay: Stay) -> Date {
        if let dep = stay.departure { return max(dep, stay.arrival) }
        return min(max(Date(), stay.arrival), stay.arrival.addingTimeInterval(86_400))
    }

    private static func timeDistance(from date: Date, to stay: Stay) -> TimeInterval {
        let end = effectiveEnd(of: stay)
        if date < stay.arrival { return stay.arrival.timeIntervalSince(date) }
        if date > end { return date.timeIntervalSince(end) }
        return 0
    }

    /// Assigns each photo exclusively to the single closest stay (by GPS distance first, then time) so the same photo never duplicates across nearby stays.
    private static func bestMatchingStayID(for asset: PHAsset, among stays: [Stay], locatedOnly: Bool) -> UUID? {
        guard let created = asset.creationDate else { return nil }
        let candidates = stays.filter { s in
            timeDistance(from: created, to: s) <= 300
                && belongs(photoAt: asset.location, to: s.location, locatedOnly: locatedOnly)
        }
        guard !candidates.isEmpty else { return nil }
        if let loc = asset.location {
            return candidates.min { a, b in
                let da = loc.distance(from: a.location)
                let db = loc.distance(from: b.location)
                if abs(da - db) > 15 { return da < db }
                let ta = timeDistance(from: created, to: a)
                let tb = timeDistance(from: created, to: b)
                if abs(ta - tb) > 1 { return ta < tb }
                return a.arrival < b.arrival
            }?.id
        }
        return candidates.min { a, b in
            let ta = timeDistance(from: created, to: a)
            let tb = timeDistance(from: created, to: b)
            if abs(ta - tb) > 1 { return ta < tb }
            return a.arrival < b.arrival
        }?.id
    }

    func stayPhotos(for stay: Stay) async -> [UIImage] {
        await stayPhotoItems(for: stay).map(\.thumbnail)
    }

    private final class OnceResumeFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }

    private func requestThumb(asset: PHAsset, size: CGSize) async -> UIImage? {
        await withCheckedContinuation { cont in
            let req = PHImageRequestOptions()
            req.deliveryMode = .fastFormat
            req.resizeMode = .fast
            req.isNetworkAccessAllowed = false
            let flag = OnceResumeFlag()
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: req) { img, _ in
                if flag.claim() {
                    cont.resume(returning: img)
                }
            }
        }
    }

    private func requestHighRes(asset: PHAsset, size: CGSize) async -> UIImage? {
        await withCheckedContinuation { cont in
            let req = PHImageRequestOptions()
            req.deliveryMode = .highQualityFormat
            req.resizeMode = .fast
            req.isNetworkAccessAllowed = true
            let flag = OnceResumeFlag()
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: req) { img, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded, flag.claim() {
                    cont.resume(returning: img)
                }
            }
        }
    }
}
