import SwiftUI
import MapKit
import CoreLocation
import Photos
import UIKit

/// 年度足迹 8 页故事（1:1 复原原版 YearReportView + YearStoryPages，适配 iOS 16）
struct YearReportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DataStore

    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var choseYear = false
    @State private var data: StoryData?
    @State private var page = 0
    @State private var shareItem: ShareableYearImage?

    struct StoryData {
        var report: YearReportSummary
        var routes: [RouteLine]
        var longestDayRoutes: [RouteLine]
        var passportSummary: PassportSummary
        var cover: UIImage?
        var placesMap: YearMapBackdrop?
        var placesPins: [String] = []
        var placesElsewhere: [String] = []
        var dayMap: YearMapBackdrop?
        var libraryPhotos: [PHAsset] = []
        var libraryCount: Int = 0
        var favoritePhotos: [PHAsset] = []
    }

    struct RouteLine {
        let coordinates: [CLLocationCoordinate2D]
        let color: Color
    }

    private var availableYears: [Int] {
        let cal = Calendar.current
        let stayYears = store.stays.map { cal.component(.year, from: $0.arrival) }
        let chunkYears = store.chunks.map { cal.component(.year, from: $0.startDate) }
        return Array(Set(stayYears + chunkYears)).sorted(by: >)
    }

    private var pickableYears: [Int] {
        Array(Set(availableYears + [year])).sorted(by: >)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let data {
                if data.report.isEmpty {
                    emptyYearView
                } else {
                    let pages = storyPages(data)
                    TabView(selection: $page) {
                        ForEach(pages.indices, id: \.self) { index in
                            pages[index].view(page == index)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                    .overlay(alignment: .top) {
                        storyBar(count: pages.count)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("正在整理这一年…")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: page) { _ in
            UISelectionFeedbackGenerator().selectionChanged()
        }
        .sheet(item: $shareItem) { item in
            YearActivityShareSheet(items: [item.image])
        }
        .task(id: year) {
            if !choseYear {
                choseYear = true
                let initial = Self.defaultYear(among: availableYears)
                if initial != year {
                    year = initial
                    return
                }
            }
            await load()
        }
    }

    // MARK: - Top Chrome

    private func storyBar(count: Int) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(Color.white.opacity(index <= page ? 0.95 : 0.25))
                        .frame(height: 3)
                        .animation(.easeOut(duration: 0.25), value: page)
                }
            }
            HStack {
                yearPicker
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.15), in: Circle())
                }
                .accessibilityLabel("关闭")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var yearPicker: some View {
        if pickableYears.count > 1 {
            Menu {
                Picker("年份", selection: $year) {
                    ForEach(pickableYears, id: \.self) { y in
                        Text(String(y)).tag(y)
                    }
                }
            } label: {
                Label(String(year), systemImage: "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.15), in: Capsule())
            }
        } else {
            Text(String(year))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.15), in: Capsule())
        }
    }

    private var emptyYearView: some View {
        VStack(spacing: 14) {
            Text(String(year))
                .font(.system(size: 72, weight: .heavy, design: .rounded))
                .foregroundColor(.white.opacity(0.3))
            Text("\(String(year)) 年还没有记录")
                .font(.title3.bold())
                .foregroundColor(.white)
            Text("记录一段时间之后，这里会整理出你的年度足迹。")
                .foregroundColor(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) { yearPicker.padding() }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.15), in: Circle())
            }
            .padding()
        }
    }

    static func defaultYear(among years: [Int], now: Date = Date(), calendar: Calendar = .current) -> Int {
        let current = calendar.component(.year, from: now)
        if calendar.component(.month, from: now) == 1,
           calendar.component(.day, from: now) <= 14,
           years.contains(current - 1) {
            return current - 1
        }
        return years.contains(current) ? current : (years.filter { $0 < current }.max() ?? years.max() ?? current)
    }

    // MARK: - Data Loading

    private func load() async {
        data = nil
        page = 0
        let targetYear = year
        let cal = Calendar.current
        guard let start = cal.date(from: DateComponents(year: targetYear, month: 1, day: 1)),
              let end = cal.date(byAdding: .year, value: 1, to: start) else { return }

        let allStays = store.stays
        let allChunks = store.chunks
        let privacyZones = store.privacyZones

        let computed = await Task.detached(priority: .userInitiated) { () -> (
            YearReportSummary,
            [RouteLine],
            [RouteLine],
            PassportSummary,
            [Stay]
        ) in
            let yearChunks = allChunks
                .filter { $0.startDate >= start && $0.startDate < end }
                .sorted { $0.startDate < $1.startDate }
            let yearStays = allStays
                .filter { $0.arrival >= start && $0.arrival < end }
                .sorted { $0.arrival < $1.arrival }

            let report = YearReportSummary.make(
                year: targetYear,
                allStays: allStays,
                yearStays: yearStays,
                yearChunks: yearChunks,
                privacyZones: privacyZones
            )

            let ground = yearChunks.filter { $0.mode != .flying }
            let homeChunks = Self.homeArea(ground)
            let routes = homeChunks.map {
                RouteLine(coordinates: $0.points.simplified(tolerance: 40).map { $0.coordinate.onMap }, color: $0.mode.color)
            }
            var longest: [RouteLine] = []
            if let day = report.longestDay?.date {
                longest = ground
                    .filter { cal.isDate($0.startDate, inSameDayAs: day) }
                    .map { RouteLine(coordinates: $0.points.simplified(tolerance: 15).map { $0.coordinate.onMap }, color: $0.mode.color) }
            }
            let passport = PassportEngine.build(stays: allStays, chunks: [])
            return (report, routes, longest, passport, yearStays)
        }.value

        guard !Task.isCancelled, year == targetYear else { return }

        let story = StoryData(
            report: computed.0,
            routes: computed.1,
            longestDayRoutes: computed.2,
            passportSummary: computed.3
        )
        withAnimation(.easeOut(duration: 0.3)) {
            data = story
        }

        let yearStays = computed.4
        let size = UIScreen.main.bounds.size
        let cities = YearCityGlow.glows(for: yearStays)
        if let cover = await YearCoverRenderer.render(cities: cities, routes: computed.1, size: size),
           data?.report.year == targetYear {
            withAnimation(.easeOut(duration: 0.7)) {
                data?.cover = cover
            }
        }

        await loadPictures(
            yearStays: yearStays,
            interval: DateInterval(start: start, end: min(end, Date())),
            longest: computed.2,
            report: computed.0,
            size: size,
            targetYear: targetYear
        )
    }

    private func loadPictures(
        yearStays: [Stay],
        interval: DateInterval,
        longest: [RouteLine],
        report: YearReportSummary,
        size: CGSize,
        targetYear: Int
    ) async {
        // Country pins
        let byCountry = Dictionary(grouping: yearStays.filter { $0.countryCode != nil }, by: { $0.countryCode! })
        let pins = byCountry.map { code, list -> (String, CLLocationCoordinate2D) in
            let lat = list.map(\.latitude).reduce(0, +) / Double(list.count)
            let lon = list.map(\.longitude).reduce(0, +) / Double(list.count)
            return (code, CLLocationCoordinate2D(latitude: lat, longitude: lon).onMap)
        }
        .sorted { (byCountry[$0.0]?.count ?? 0) > (byCountry[$1.0]?.count ?? 0) }

        let toLoc: (CLLocationCoordinate2D) -> CLLocation = { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        let anchor = pins.max { a, b in
            let weightA = pins.filter { toLoc($0.1).distance(from: toLoc(a.1)) < 3_500_000 }
                .reduce(0) { $0 + (byCountry[$1.0]?.count ?? 0) }
            let weightB = pins.filter { toLoc($0.1).distance(from: toLoc(b.1)) < 3_500_000 }
                .reduce(0) { $0 + (byCountry[$1.0]?.count ?? 0) }
            return weightA < weightB
        }
        let framed = anchor.map { a in pins.filter { toLoc($0.1).distance(from: toLoc(a.1)) < 3_500_000 } } ?? []
        if let region = YearMapBackdrop.region(around: framed.map(\.1), size: size, minimumSpan: 8, lift: 0.12),
           let map = await YearMapBackdrop.render(region: region, size: size, pins: framed.map(\.1)),
           data?.report.year == targetYear {
            data?.placesMap = map
            data?.placesPins = framed.map(\.0)
            data?.placesElsewhere = pins.map(\.0).filter { !(data?.placesPins.contains($0) ?? false) }
        }

        // Longest day route backdrop
        let dayLines = longest.map(\.coordinates).filter { $0.count > 1 }
        if let region = YearMapBackdrop.region(around: dayLines.flatMap { $0 }, size: size, minimumSpan: 0.02),
           let map = await YearMapBackdrop.render(region: region, size: size, lines: dayLines),
           data?.report.year == targetYear {
            data?.dayMap = map
        }

        // Photos from library for that year
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }

        let allAssets = await Task.detached(priority: .userInitiated) { () -> [PHAsset] in
            let opts = PHFetchOptions()
            opts.predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate < %@",
                interval.start as NSDate,
                interval.end as NSDate
            )
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let result = PHAsset.fetchAssets(with: .image, options: opts)
            var list: [PHAsset] = []
            list.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in
                list.append(asset)
            }
            return list
        }.value

        guard data?.report.year == targetYear else { return }

        // Pick 9 evenly distributed photos across the year
        let picked9: [PHAsset] = {
            guard allAssets.count > 9 else { return allAssets }
            return (0..<9).map { idx in
                let pos = Int(Double(idx) / 8.0 * Double(allAssets.count - 1))
                return allAssets[pos]
            }
        }()

        var favPhotos: [PHAsset] = []
        if let favCoord = report.favoritePlace?.coordinate {
            let favLoc = CLLocation(latitude: favCoord.latitude, longitude: favCoord.longitude)
            let near = allAssets.filter { ($0.location?.distance(from: favLoc) ?? .infinity) < 550 }
            favPhotos = Array(near.prefix(12))
        }

        guard data?.report.year == targetYear else { return }
        data?.libraryPhotos = picked9
        data?.libraryCount = allAssets.count
        data?.favoritePhotos = favPhotos
    }

    private nonisolated static func homeArea(_ chunks: [TrackChunk]) -> [TrackChunk] {
        guard chunks.count > 2 else { return chunks }
        let lats = chunks.map { ($0.minLatitude + $0.maxLatitude) / 2 }.sorted()
        let lons = chunks.map { ($0.minLongitude + $0.maxLongitude) / 2 }.sorted()
        let center = CLLocation(latitude: lats[lats.count / 2], longitude: lons[lons.count / 2])
        let near = chunks.filter {
            CLLocation(
                latitude: ($0.minLatitude + $0.maxLatitude) / 2,
                longitude: ($0.minLongitude + $0.maxLongitude) / 2
            ).distance(from: center) < 40_000
        }
        return near.isEmpty ? chunks : near
    }

    @MainActor
    private func sharePoster(_ storyData: StoryData) {
        let poster = YearPoster(data: storyData)
            .frame(width: 390, height: 640)
        let renderer = ImageRenderer(content: poster)
        renderer.scale = 3
        if let img = renderer.uiImage {
            shareItem = ShareableYearImage(image: img)
        }
    }

    // MARK: - Story Pages Assembly

    private struct StoryPageItem {
        let view: (Bool) -> AnyView
    }

    private func storyPages(_ story: StoryData) -> [StoryPageItem] {
        let r = story.report
        var pages: [StoryPageItem] = [
            StoryPageItem { AnyView(YearCoverPage(data: story, isActive: $0)) },
            StoryPageItem { AnyView(YearDistancePage(report: r, isActive: $0)) }
        ]
        if !r.countries.isEmpty {
            pages.append(StoryPageItem {
                AnyView(YearPlacesPage(
                    report: r,
                    backdrop: story.placesMap,
                    pinCodes: story.placesPins,
                    elsewhere: story.placesElsewhere,
                    isActive: $0
                ))
            })
        }
        let yearStamps = YearPassportPage.stamps(for: r.year, summary: story.passportSummary)
        if !yearStamps.isEmpty {
            pages.append(StoryPageItem {
                AnyView(YearPassportPage(year: r.year, stamps: yearStamps, isActive: $0))
            })
        }
        if r.longestDay != nil, !story.longestDayRoutes.isEmpty {
            pages.append(StoryPageItem {
                AnyView(YearLongestDayPage(report: r, backdrop: story.dayMap, isActive: $0))
            })
        }
        if r.favoritePlace != nil || r.farthestPlace != nil {
            pages.append(StoryPageItem {
                AnyView(YearFavoritePage(report: r, photos: story.favoritePhotos, isActive: $0))
            })
        }
        if story.libraryPhotos.count >= 3 {
            pages.append(StoryPageItem {
                AnyView(YearPhotosPage(assets: story.libraryPhotos, total: story.libraryCount, isActive: $0))
            })
        }
        pages.append(StoryPageItem { _ in
            AnyView(YearSharePage(data: story, stampCount: yearStamps.count) {
                sharePoster(story)
            })
        })
        return pages
    }
}

// MARK: - Year Report Summary Model

struct YearReportSummary {
    let year: Int
    let groundDistance: Double
    let flightDistance: Double
    let shareOfEquator: Double
    let countries: [String]
    let cities: [String]
    let provinces: [String]
    let newCities: [String]
    let daysRecorded: Int
    let longestDay: (date: Date, distance: Double)?
    let busiestMonth: (month: Date, distance: Double)?
    let favoritePlace: (name: String, visits: Int, coordinate: CLLocationCoordinate2D)?
    let farthestPlace: (name: String, distance: Double)?

    var isEmpty: Bool {
        groundDistance < 10 && flightDistance < 10 && cities.isEmpty && daysRecorded == 0
    }

    static func make(
        year: Int,
        allStays: [Stay],
        yearStays: [Stay],
        yearChunks: [TrackChunk],
        privacyZones: [PrivacyZone]
    ) -> YearReportSummary {
        let cal = Calendar.current
        let ground = yearChunks.filter { $0.mode != .flying }
        let flights = yearChunks.filter { $0.mode == .flying }
        let groundDist = ground.reduce(0.0) { $0 + $1.distance }
        let flightDist = flights.reduce(0.0) { $0 + $1.distance }

        let countries = Array(Set(yearStays.compactMap(\.countryCode))).sorted()
        let cities = Array(Set(yearStays.compactMap(\.city).filter { !$0.isEmpty })).sorted()
        let provinces = Array(Set(yearStays.compactMap {
            ChinaProvince.containing(countryCode: $0.countryCode, region: $0.region, city: $0.city)?.id
        }))

        let priorCities = Set(
            allStays
                .filter { cal.component(.year, from: $0.arrival) < year }
                .compactMap(\.city)
        )
        let firstVisitDateByCity: [String: Date] = {
            var map: [String: Date] = [:]
            for s in yearStays {
                guard let c = s.city, !c.isEmpty, !priorCities.contains(c) else { continue }
                if map[c] == nil || s.arrival < map[c]! {
                    map[c] = s.arrival
                }
            }
            return map
        }()
        let newCities = firstVisitDateByCity.sorted { $0.value > $1.value }.map(\.key)

        let stayDays = Set(yearStays.map { cal.startOfDay(for: $0.arrival) })
        let chunkDays = Set(yearChunks.map { cal.startOfDay(for: $0.startDate) })
        let daysRecorded = stayDays.union(chunkDays).count

        // Longest day
        let byDay = Dictionary(grouping: ground) { cal.startOfDay(for: $0.startDate) }
        let longestDay: (date: Date, distance: Double)? = byDay
            .map { (date: $0.key, distance: $0.value.reduce(0.0) { $0 + $1.distance }) }
            .max { $0.distance < $1.distance }

        // Busiest month
        let byMonth = Dictionary(grouping: ground) {
            cal.date(from: cal.dateComponents([.year, .month], from: $0.startDate)) ?? $0.startDate
        }
        let busiestMonth: (month: Date, distance: Double)? = byMonth
            .map { (month: $0.key, distance: $0.value.reduce(0.0) { $0 + $1.distance }) }
            .max { $0.distance < $1.distance }

        // Home detection (privacy zones or .home stays or densest stay cluster)
        let homeLocation: CLLocation? = {
            if let tagged = allStays.first(where: { $0.category == .home }) {
                return tagged.location
            }
            if let zone = privacyZones.first {
                return zone.location
            }
            let buckets = Dictionary(grouping: yearStays) { s in
                "\(Int((s.latitude * 200).rounded()))_\(Int((s.longitude * 200).rounded()))"
            }
            if let top = buckets.values.max(by: { $0.count < $1.count }), top.count >= 5 {
                let lat = top.map(\.latitude).reduce(0, +) / Double(top.count)
                let lon = top.map(\.longitude).reduce(0, +) / Double(top.count)
                return CLLocation(latitude: lat, longitude: lon)
            }
            return nil
        }()

        // Favorite non-home place
        let nonHomeStays = yearStays.filter { stay in
            if stay.category == .home { return false }
            if privacyZones.contains(where: { $0.contains(stay.coordinate) }) { return false }
            if let homeLocation, stay.location.distance(from: homeLocation) < 400 { return false }
            return true
        }
        let byPlaceName = Dictionary(grouping: nonHomeStays.filter { $0.displayName != "未知地点" }) { $0.displayName }
        let favoritePlace: (name: String, visits: Int, coordinate: CLLocationCoordinate2D)? = byPlaceName
            .max { $0.value.count < $1.value.count }
            .map { name, list in
                let lat = list.map(\.latitude).reduce(0, +) / Double(list.count)
                let lon = list.map(\.longitude).reduce(0, +) / Double(list.count)
                return (name, list.count, CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }

        // Farthest place from home
        let farthestPlace: (name: String, distance: Double)? = {
            guard let homeLocation else { return nil }
            return yearStays
                .map { ($0, $0.location.distance(from: homeLocation)) }
                .max { $0.1 < $1.1 }
                .flatMap { stay, dist in
                    guard dist > 2_000 else { return nil }
                    let label = stay.city ?? stay.displayName
                    return (label, dist)
                }
        }()

        return YearReportSummary(
            year: year,
            groundDistance: groundDist,
            flightDistance: flightDist,
            shareOfEquator: groundDist / 40_075_000.0,
            countries: countries,
            cities: cities,
            provinces: provinces,
            newCities: newCities,
            daysRecorded: daysRecorded,
            longestDay: longestDay,
            busiestMonth: busiestMonth,
            favoritePlace: favoritePlace,
            farthestPlace: farthestPlace
        )
    }
}

// MARK: - Map Backdrop & Year Cover Renderers

struct YearCityGlow {
    let center: CLLocationCoordinate2D
    let days: Int

    static func glows(for stays: [Stay]) -> [YearCityGlow] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: stays.filter { ($0.city?.isEmpty == false) }) { $0.city! }
        return grouped.map { _, list in
            let lat = list.map(\.latitude).reduce(0, +) / Double(list.count)
            let lon = list.map(\.longitude).reduce(0, +) / Double(list.count)
            let days = max(1, Set(list.map { cal.startOfDay(for: $0.arrival) }).count)
            return YearCityGlow(center: CLLocationCoordinate2D(latitude: lat, longitude: lon).onMap, days: days)
        }
    }
}

struct YearMapBackdrop {
    let image: UIImage
    let lines: [[CGPoint]]
    let pins: [CGPoint]

    @MainActor
    static func render(
        region: MKCoordinateRegion,
        size: CGSize,
        lines: [[CLLocationCoordinate2D]] = [],
        pins: [CLLocationCoordinate2D] = []
    ) async -> YearMapBackdrop? {
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        if #available(iOS 17.0, *) {
            let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            config.pointOfInterestFilter = .excludingAll
            options.preferredConfiguration = config
        } else {
            options.mapType = .mutedStandard
            options.pointOfInterestFilter = .excludingAll
        }
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        func unit(_ c: CLLocationCoordinate2D) -> CGPoint {
            let p = snapshot.point(for: c)
            return CGPoint(x: p.x / size.width, y: p.y / size.height)
        }
        return YearMapBackdrop(image: snapshot.image, lines: lines.map { $0.map(unit) }, pins: pins.map(unit))
    }

    static func region(
        around coordinates: [CLLocationCoordinate2D],
        size: CGSize,
        minimumSpan: Double,
        lift: Double = 0.18
    ) -> MKCoordinateRegion? {
        let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        let aspect = size.height / max(size.width, 1)
        let lonSpan = max((maxLon - minLon) * 1.5, minimumSpan)
        let latSpan = max((maxLat - minLat) * 2.2, lonSpan * aspect * 0.8, minimumSpan)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2 - latSpan * lift, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: min(latSpan, 150), longitudeDelta: min(lonSpan, 340))
        )
    }
}

enum YearCoverRenderer {
    @MainActor
    static func render(cities: [YearCityGlow], routes: [YearReportView.RouteLine], size: CGSize) async -> UIImage? {
        guard !cities.isEmpty, size.width > 0 else { return nil }
        let best = cities.max { a, b in
            func weight(_ c: YearCityGlow) -> Int {
                let here = CLLocation(latitude: c.center.latitude, longitude: c.center.longitude)
                return cities.filter {
                    CLLocation(latitude: $0.center.latitude, longitude: $0.center.longitude).distance(from: here) < 2_500_000
                }.reduce(0) { $0 + $1.days }
            }
            return weight(a) < weight(b)
        }!

        let anchor = CLLocation(latitude: best.center.latitude, longitude: best.center.longitude)
        let framed = cities.filter {
            CLLocation(latitude: $0.center.latitude, longitude: $0.center.longitude).distance(from: anchor) < 2_500_000
        }
        let lats = framed.map(\.center.latitude), lons = framed.map(\.center.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!, minLon = lons.min()!, maxLon = lons.max()!
        let latSpan = max((maxLat - minLat) * 1.6, 0.6)
        let lonSpan = max((maxLon - minLon) * 1.5, latSpan * size.width / size.height)
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2 - latSpan * 0.18, longitude: (minLon + maxLon) / 2)

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: min(latSpan * 1.5, 170), longitudeDelta: min(lonSpan, 360))
        )
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        if #available(iOS 17.0, *) {
            let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            config.pointOfInterestFilter = .excludingAll
            options.preferredConfiguration = config
        } else {
            options.mapType = .mutedStandard
            options.pointOfInterestFilter = .excludingAll
        }
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let maxDays = Double(cities.map(\.days).max() ?? 1)
        return UIGraphicsImageRenderer(size: size).image { renderer in
            snapshot.image.draw(at: .zero)
            let context = renderer.cgContext

            for line in routes where line.coordinates.count > 1 {
                let path = UIBezierPath()
                for (index, coord) in line.coordinates.enumerated() {
                    let pt = snapshot.point(for: coord)
                    index == 0 ? path.move(to: pt) : path.addLine(to: pt)
                }
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                context.saveGState()
                context.setShadow(offset: .zero, blur: 6, color: UIColor.white.withAlphaComponent(0.6).cgColor)
                UIColor.white.withAlphaComponent(0.85).setStroke()
                path.lineWidth = 1.4
                path.stroke()
                context.restoreGState()
            }

            let colors = [
                UIColor(red: 1, green: 0.62, blue: 0.25, alpha: 0.85).cgColor,
                UIColor(red: 1, green: 0.45, blue: 0.2, alpha: 0).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                for city in cities.reversed() {
                    let pt = snapshot.point(for: city.center)
                    let weight = sqrt(Double(city.days) / maxDays)
                    let radius = CGFloat(14 + 34 * weight)
                    context.drawRadialGradient(gradient, startCenter: pt, startRadius: 0, endCenter: pt, endRadius: radius, options: [])
                    let core = CGFloat(3 + 3 * weight)
                    UIColor(red: 1, green: 0.93, blue: 0.8, alpha: 1).setFill()
                    UIBezierPath(ovalIn: CGRect(x: pt.x - core, y: pt.y - core, width: core * 2, height: core * 2)).fill()
                }
            }
        }
    }
}

// MARK: - Shared Story UI Helpers (iOS 16 Safe)

private struct StoryRevealModifier: ViewModifier {
    let isActive: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1 : 0)
            .offset(y: isActive ? 0 : 24)
            .blur(radius: isActive ? 0 : 6)
            .animation(.spring(response: 0.75, dampingFraction: 0.85).delay(isActive ? delay : 0), value: isActive)
    }
}

private extension View {
    func storyReveal(_ isActive: Bool, after delay: Double = 0) -> some View {
        modifier(StoryRevealModifier(isActive: isActive, delay: delay))
    }
}

private struct StoryNumberView: View, Animatable {
    var value: Double
    var unit: String = ""
    var decimals: Int = 0
    var size: CGFloat = 84

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(formattedValue)
                .font(.system(size: size, weight: .black, design: .rounded))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: size * 0.32, weight: .heavy, design: .rounded))
                    .opacity(0.8)
            }
        }
    }

    private var formattedValue: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = decimals
        f.maximumFractionDigits = decimals
        return f.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}

private struct StoryKicker: View {
    let text: String
    var tint: Color = .white

    var body: some View {
        Text(text)
            .font(.footnote.weight(.bold))
            .tracking(2.2)
            .foregroundColor(tint)
    }
}

private struct StoryPageText<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer()
            content
        }
        .foregroundColor(.white)
        .padding(.horizontal, 28)
        .padding(.bottom, 64)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StoryBackdropImage: View {
    let image: UIImage
    let isActive: Bool

    var body: some View {
        ZStack {
            Color.clear
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(isActive ? 1.06 : 1.0)
                        .animation(.easeInOut(duration: 12), value: isActive)
                }
                .clipped()
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.45), location: 0),
                    .init(color: .clear, location: 0.22),
                    .init(color: .black.opacity(0.15), location: 0.5),
                    .init(color: .black.opacity(0.88), location: 0.82)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

private struct StoryNightGradient: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.07, blue: 0.22),
                Color(red: 0.22, green: 0.11, blue: 0.36),
                Color(red: 0.08, green: 0.05, blue: 0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct StoryWrappingLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Page 1: Cover Page (Screenshot 2)

private struct YearCoverPage: View {
    let data: YearReportView.StoryData
    let isActive: Bool

    var body: some View {
        ZStack {
            StoryNightGradient()

            if let cover = data.cover {
                Color.clear
                    .overlay {
                        Image(uiImage: cover)
                            .resizable()
                            .scaledToFill()
                            .scaleEffect(isActive ? 1.08 : 1.0)
                            .animation(.easeInOut(duration: 14), value: isActive)
                    }
                    .clipped()
                    .ignoresSafeArea()

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.35), location: 0),
                        .init(color: .clear, location: 0.25),
                        .init(color: .black.opacity(0.2), location: 0.5),
                        .init(color: .black.opacity(0.86), location: 0.85)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }

            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                Text(String(data.report.year))
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .storyReveal(isActive, after: 0.15)
                Text("我的年度足迹")
                    .font(.system(size: 30, weight: .bold))
                    .storyReveal(isActive, after: 0.30)
                Text("这一年去了 \(data.report.cities.count) 座城市，记录了 \(data.report.daysRecorded) 天。")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.75))
                    .storyReveal(isActive, after: 0.45)
                Label("向左滑动", systemImage: "hand.draw.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 18)
                    .padding(.bottom, 70)
                    .storyReveal(isActive, after: 0.75)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Page 2: Dotted Globe & Distance (Screenshot 3)

private struct YearDistancePage: View {
    let report: YearReportSummary
    let isActive: Bool

    private var equatorPctText: String {
        let pct = report.shareOfEquator * 100.0
        return String(format: "%.1f%%", pct)
    }

    private func formatKm(_ meters: Double) -> String {
        let km = meters / 1000.0
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return (f.string(from: NSNumber(value: km)) ?? "\(Int(km))") + " 公里"
    }

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(red: 0.05, green: 0.2, blue: 0.4), .black],
                center: UnitPoint(x: 0.5, y: 0.32),
                startRadius: 10,
                endRadius: 520
            )
            .ignoresSafeArea()

            YearStarField()
                .ignoresSafeArea()
                .opacity(0.6)

            YearDottedGlobe(progress: isActive ? min(report.shareOfEquator, 1.0) : 0.0)
                .frame(width: 300, height: 300)
                .position(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height * 0.32)
                .scaleEffect(isActive ? 1 : 0.85)
                .opacity(isActive ? 1 : 0)
                .animation(.spring(response: 1.2, dampingFraction: 0.8), value: isActive)

            StoryPageText {
                StoryKicker(text: "这一年你移动了", tint: Color(red: 0.5, green: 0.85, blue: 1))
                    .storyReveal(isActive, after: 0.2)
                StoryNumberView(value: isActive ? report.groundDistance / 1000.0 : 0, unit: "公里")
                    .animation(.easeOut(duration: 1.8).delay(0.25), value: isActive)
                Text("地面上的路程相当于绕赤道 \(equatorPctText)")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .storyReveal(isActive, after: 0.65)
                if report.flightDistance > 0 {
                    Label("另外飞行 \(formatKm(report.flightDistance))", systemImage: "airplane")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.7))
                        .storyReveal(isActive, after: 0.9)
                }
            }
        }
    }
}

private struct YearDottedGlobe: View {
    var progress: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let spin = timeline.date.timeIntervalSinceReferenceDate * 0.25
            Canvas { context, size in
                drawGlobe(in: context, size: size, spin: spin, progress: progress)
            }
        }
        .animation(.easeInOut(duration: 2.2).delay(0.35), value: progress)
    }

    private func drawGlobe(in context: GraphicsContext, size: CGSize, spin: Double, progress: Double) {
        let r: CGFloat = min(size.width, size.height) / 2.0 * 0.78
        let c = CGPoint(x: size.width / 2.0, y: size.height / 2.0)

        let atmoRect = CGRect(x: c.x - r * 1.12, y: c.y - r * 1.12, width: r * 2.24, height: r * 2.24)
        context.fill(
            Path(ellipseIn: atmoRect),
            with: .radialGradient(
                Gradient(colors: [Color(red: 0.3, green: 0.7, blue: 1.0).opacity(0.35), .clear]),
                center: c,
                startRadius: r * 0.9,
                endRadius: r * 1.12
            )
        )

        let tilt = 0.4
        let cosTilt = cos(tilt)
        let sinTilt = sin(tilt)

        for latStep in stride(from: -78.0, through: 78.0, by: 6.0) {
            let lat = latStep * Double.pi / 180.0
            let ring = cos(lat)
            let sinLat = sin(lat)
            let count = max(6, Int(60.0 * ring))
            for i in 0..<count {
                let lon = Double(i) / Double(count) * 2.0 * Double.pi + spin
                let x = ring * sin(lon)
                let y0 = sinLat
                let z0 = ring * cos(lon)
                let y = y0 * cosTilt - z0 * sinTilt
                let z = y0 * sinTilt + z0 * cosTilt
                guard z > -0.05 else { continue }
                let dot: CGFloat = CGFloat(1.1 + 1.4 * z)
                let px: CGFloat = c.x + CGFloat(x) * r
                let py: CGFloat = c.y - CGFloat(y) * r
                let dotRect = CGRect(x: px - dot / 2.0, y: py - dot / 2.0, width: dot, height: dot)
                let alpha = 0.25 + 0.75 * z
                context.fill(
                    Path(ellipseIn: dotRect),
                    with: .color(Color(red: 0.55, green: 0.85, blue: 1.0).opacity(alpha))
                )
            }
        }

        let orbitRect = CGRect(x: c.x - r * 1.28, y: c.y - r * 0.42, width: r * 2.56, height: r * 0.84)
        let orbit = Path(ellipseIn: orbitRect)
        context.stroke(orbit, with: .color(.white.opacity(0.12)), lineWidth: 1.5)

        let lit = orbit.trimmedPath(from: 0, to: CGFloat(max(0.005, progress)))
        var glow = context
        glow.addFilter(.blur(radius: 6))
        glow.stroke(lit, with: .color(Color(red: 1.0, green: 0.75, blue: 0.35)), lineWidth: 6)
        context.stroke(lit, with: .color(Color(red: 1.0, green: 0.88, blue: 0.6)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        if let head = lit.currentPoint {
            context.fill(Path(ellipseIn: CGRect(x: head.x - 5, y: head.y - 5, width: 10, height: 10)), with: .color(.white))
        }
    }
}

private struct YearStarField: View {
    private let stars: [(CGPoint, CGFloat)] = {
        var rng = SeededRandom(777)
        return (0..<70).map { _ in
            (CGPoint(x: rng.unit(), y: rng.unit() * 0.75), CGFloat(0.6 + rng.unit() * 1.2))
        }
    }()

    var body: some View {
        Canvas { context, size in
            drawStars(in: context, size: size)
        }
    }

    private func drawStars(in context: GraphicsContext, size: CGSize) {
        for (p, r) in stars {
            let rect = CGRect(x: p.x * size.width, y: p.y * size.height, width: r, height: r)
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.7)))
        }
    }
}

// MARK: - Page 3: Places + Flag Pins + First-Time City Chips (Screenshot 4)

private struct YearPlacesPage: View {
    let report: YearReportSummary
    let backdrop: YearMapBackdrop?
    let pinCodes: [String]
    let elsewhere: [String]
    let isActive: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let backdrop {
                StoryBackdropImage(image: backdrop.image, isActive: isActive)
                GeometryReader { geo in
                    ForEach(Array(zip(pinCodes, backdrop.pins).enumerated()), id: \.offset) { index, item in
                        if item.1.y < 0.48 {
                            YearFlagPin(code: item.0)
                                .position(x: item.1.x * geo.size.width, y: item.1.y * geo.size.height - 20)
                                .scaleEffect(isActive ? 1 : 0.1, anchor: .bottom)
                                .opacity(isActive ? 1 : 0)
                                .animation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.35 + Double(index) * 0.12), value: isActive)
                        }
                    }
                }
                .ignoresSafeArea()
            }

            StoryPageText {
                StoryKicker(text: "这一年去过", tint: Color(red: 1, green: 0.7, blue: 0.45))
                    .storyReveal(isActive, after: 0.2)

                HStack(spacing: 10) {
                    countTile(report.countries.count, "国家和地区", delay: 0.3)
                    countTile(report.cities.count, "座城市", delay: 0.4)
                    if !report.provinces.isEmpty {
                        countTile(report.provinces.count, "个省份", delay: 0.5)
                    }
                }

                if !elsewhere.isEmpty {
                    Text("还有 \(elsewhere.map { CountryText.flag(for: $0) }.joined(separator: " "))")
                        .font(.title3.weight(.semibold))
                        .storyReveal(isActive, after: 0.7)
                }

                if !report.newCities.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("第一次去")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.75))
                        StoryWrappingLayout(spacing: 8) {
                            ForEach(Array(report.newCities.prefix(8)), id: \.self) { city in
                                Text(city)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color(red: 1, green: 0.6, blue: 0.3).opacity(0.25), in: Capsule())
                                    .overlay(Capsule().stroke(Color(red: 1, green: 0.7, blue: 0.45).opacity(0.55), lineWidth: 1))
                            }
                        }
                    }
                    .padding(.top, 6)
                    .storyReveal(isActive, after: 0.85)
                }
            }
        }
    }

    private func countTile(_ value: Int, _ label: String, delay: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            StoryNumberView(value: isActive ? Double(value) : 0, size: 44)
                .animation(.easeOut(duration: 1.2).delay(delay), value: isActive)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.7)
        )
        .storyReveal(isActive, after: delay)
    }
}

private struct YearFlagPin: View {
    let code: String

    var body: some View {
        VStack(spacing: 0) {
            Text(CountryText.flag(for: code))
                .font(.system(size: 26))
                .padding(6)
                .background(Circle().fill(Color.white))
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
            PinTriangle()
                .fill(Color.white)
                .frame(width: 10, height: 7)
        }
    }

    private struct PinTriangle: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
            return p
        }
    }
}

// MARK: - Page 4: Year's Passport Stamps (Screenshot 5)

private struct YearPassportPage: View {
    let year: Int
    let stamps: [PassportStamp]
    let isActive: Bool

    static func stamps(for year: Int, summary: PassportSummary) -> [PassportStamp] {
        let cal = Calendar.current
        let inYear: (PassportStamp) -> Bool = { cal.component(.year, from: $0.date) == year }
        let entries = summary.passportStamps.filter { $0.kind == .entry && inYear($0) }
        let sets = summary.stampSets.compactMap(\.stamp).filter(inYear)
        let specials = summary.specials.filter { $0.kind == .special && inYear($0) }
        let provinces = ChinaProvince.all.compactMap { p -> PassportStamp? in
            guard let v = summary.provinceVisits[p.id], cal.component(.year, from: v.firstVisit) == year else { return nil }
            return PassportStamp(id: "province.\(p.id)", kind: .province, date: v.firstVisit, provinceID: p.id)
        }
        let cities = summary.cityStamps.filter(inYear)
        return entries + sets + specials + provinces + cities
    }

    private static let slots: [CGPoint] = [
        CGPoint(x: 0.22, y: 0.20), CGPoint(x: 0.55, y: 0.16), CGPoint(x: 0.80, y: 0.27),
        CGPoint(x: 0.27, y: 0.48), CGPoint(x: 0.60, y: 0.47), CGPoint(x: 0.82, y: 0.60),
        CGPoint(x: 0.20, y: 0.78), CGPoint(x: 0.50, y: 0.80), CGPoint(x: 0.78, y: 0.86)
    ]

    var body: some View {
        let shown = Array(stamps.prefix(Self.slots.count))
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.24, green: 0.05, blue: 0.08), Color(red: 0.08, green: 0.02, blue: 0.03)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GeometryReader { geo in
                let width = min(geo.size.width - 64, 330)
                let height = width * 1.2
                ZStack {
                    StampPaperView(style: .passport)
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, stamp in
                        StampArtView(stamp: stamp)
                            .frame(width: width * 0.34, height: width * 0.34)
                            .rotationEffect(.degrees(stamp.tilt))
                            .scaleEffect(isActive ? 1 : 1.55)
                            .opacity(isActive ? 1 : 0)
                            .animation(
                                .spring(response: 0.28, dampingFraction: 0.6).delay(isActive ? 0.45 + Double(index) * 0.26 : 0),
                                value: isActive
                            )
                            .position(x: Self.slots[index].x * width, y: Self.slots[index].y * height)
                    }
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .rotationEffect(.degrees(-2))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.36)
            }

            StoryPageText {
                StoryKicker(text: "今年的护照", tint: Color(red: 0.95, green: 0.8, blue: 0.5))
                    .storyReveal(isActive, after: 0.2)
                StoryNumberView(value: isActive ? Double(stamps.count) : 0, unit: "枚印章", size: 64)
                    .animation(.easeOut(duration: 1.5).delay(0.35), value: isActive)
                Text(summaryText)
                    .font(.title3.weight(.semibold))
                    .opacity(0.85)
                    .storyReveal(isActive, after: 0.75)
            }
        }
    }

    private var summaryText: String {
        let counts: [(PassportStamp.Kind, String)] = [
            (.entry, "入境章"),
            (.province, "省份印"),
            (.city, "城市章")
        ]
        var parts = counts.compactMap { kind, name -> String? in
            let n = stamps.filter { $0.kind == kind }.count
            return n > 0 ? "\(n) \(name)" : nil
        }
        let keepsakes = stamps.filter { $0.kind == .special || $0.kind == .set }.count
        if keepsakes > 0 { parts.append("\(keepsakes) 纪念章") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Page 5: Longest Day (Screenshot 6)

private struct YearLongestDayPage: View {
    let report: YearReportSummary
    let backdrop: YearMapBackdrop?
    let isActive: Bool
    @State private var drawn: CGFloat = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.12, green: 0.05, blue: 0.25), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if let backdrop {
                StoryBackdropImage(image: backdrop.image, isActive: isActive)
                GeometryReader { geo in
                    let path = Path { p in
                        for line in backdrop.lines where line.count > 1 {
                            p.addLines(line.map { CGPoint(x: $0.x * geo.size.width, y: $0.y * geo.size.height) })
                        }
                    }
                    let trimmed = path.trimmedPath(from: 0, to: drawn)
                    trimmed.stroke(
                        Color(red: 0.75, green: 0.55, blue: 1),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 8)
                    trimmed.stroke(.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))

                    if let first = backdrop.lines.first?.first {
                        Circle()
                            .fill(.white)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color(red: 0.75, green: 0.55, blue: 1), lineWidth: 3))
                            .position(x: first.x * geo.size.width, y: first.y * geo.size.height)
                            .opacity(drawn > 0 ? 1 : 0)
                    }
                }
                .ignoresSafeArea()
            }

            StoryPageText {
                StoryKicker(text: "移动最远的一天", tint: Color(red: 0.8, green: 0.65, blue: 1))
                    .storyReveal(isActive, after: 0.2)
                if let longest = report.longestDay {
                    Text(zhMonthDayWeekday(longest.date))
                        .font(.title2.weight(.bold))
                        .storyReveal(isActive, after: 0.3)
                    StoryNumberView(value: isActive ? longest.distance / 1000.0 : 0, unit: "km", decimals: 1, size: 72)
                        .animation(.easeOut(duration: 1.5).delay(0.35), value: isActive)
                }
                if let month = report.busiestMonth {
                    Label("最常在路上的是 \(zhMonth(month.month))，共 \(formatKm(month.distance))", systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.7))
                        .storyReveal(isActive, after: 1.1)
                }
            }
        }
        .onAppear {
            if isActive {
                drawn = 0
                withAnimation(.easeInOut(duration: 2.2).delay(0.4)) { drawn = 1 }
            }
        }
        .onChange(of: isActive) { active in
            drawn = 0
            if active {
                withAnimation(.easeInOut(duration: 2.2).delay(0.4)) { drawn = 1 }
            }
        }
    }

    private func zhMonthDayWeekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日EEEE"
        return f.string(from: date)
    }

    private func zhMonth(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月"
        return f.string(from: date)
    }

    private func formatKm(_ meters: Double) -> String {
        let km = meters / 1000.0
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return (f.string(from: NSNumber(value: km)) ?? "\(Int(km))") + " 公里"
    }
}

// MARK: - Page 6: Favorite Non-Home Place & Farthest Place (Screenshot 7)

private struct YearFavoritePage: View {
    let report: YearReportSummary
    let photos: [PHAsset]
    let isActive: Bool
    @State private var index = 0
    @State private var image: UIImage?

    private var choiceKey: String { "yearStory.\(report.year).favoritePhoto" }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.22, green: 0.14, blue: 0.08), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if let image {
                    Color.clear
                        .overlay { Image(uiImage: image).resizable().scaledToFill() }
                        .clipped()
                        .blur(radius: 40)
                        .overlay(Color.black.opacity(0.5))
                }
            }
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: geo.safeAreaInsets.top + 56)

                if let image {
                    VStack(spacing: 14) {
                        PolaroidPrint(
                            image: image,
                            date: photos.indices.contains(index) ? photos[index].creationDate : nil
                        )
                        .frame(maxWidth: geo.size.width - 64, maxHeight: geo.size.height * 0.42)
                        .rotationEffect(.degrees(isActive ? -2 : -8))
                        .scaleEffect(isActive ? 1 : 0.9)
                        .animation(.spring(response: 0.9, dampingFraction: 0.75).delay(0.1), value: isActive)

                        if photos.count > 1 {
                            Button(action: another) {
                                Label("换一张", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.7))
                            }
                            .buttonStyle(.plain)
                            .storyReveal(isActive, after: 0.9)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                Spacer(minLength: 24)

                VStack(alignment: .leading, spacing: 10) {
                    if let fav = report.favoritePlace {
                        StoryKicker(text: "除了家，你最常去", tint: Color(red: 1, green: 0.8, blue: 0.5))
                            .storyReveal(isActive, after: 0.2)
                        Text(fav.name)
                            .font(.system(size: 38, weight: .black))
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .fixedSize(horizontal: false, vertical: true)
                            .storyReveal(isActive, after: 0.35)
                        Text("去了 \(fav.visits) 次")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .storyReveal(isActive, after: 0.5)
                    }

                    if let farthest = report.farthestPlace {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "location.north.line.fill")
                            Text("离家最远到过\(farthest.name)，\(formatKm(farthest.distance))")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.16), lineWidth: 0.7)
                        )
                        .padding(.top, 8)
                        .storyReveal(isActive, after: 0.8)
                    }
                }
                .foregroundColor(.white)
                .padding(.bottom, 64)
            }
            .padding(.horizontal, 28)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
        .task(id: photos.map(\.localIdentifier)) {
            let saved = UserDefaults.standard.string(forKey: choiceKey)
            index = photos.firstIndex { $0.localIdentifier == saved } ?? 0
            await loadImage()
        }
    }

    private func another() {
        guard photos.count > 1 else { return }
        index = (index + 1) % photos.count
        UserDefaults.standard.set(photos[index].localIdentifier, forKey: choiceKey)
        UISelectionFeedbackGenerator().selectionChanged()
        Task { await loadImage() }
    }

    private func loadImage() async {
        guard photos.indices.contains(index) else { return }
        let asset = photos[index]
        let loaded = await YearAssetLoader.image(for: asset, targetSize: CGSize(width: 1200, height: 1200))
        withAnimation(.easeInOut(duration: 0.35)) {
            image = loaded
        }
    }

    private func formatKm(_ meters: Double) -> String {
        let km = meters / 1000.0
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return (f.string(from: NSNumber(value: km)) ?? "\(Int(km))") + " 公里"
    }

    private struct PolaroidPrint: View {
        let image: UIImage
        let date: Date?

        var body: some View {
            VStack(spacing: 8) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                if let date {
                    Text(zhFullDate(date))
                        .font(.system(size: 11, weight: .medium, design: .serif))
                        .foregroundColor(.black.opacity(0.55))
                }
            }
            .padding([.horizontal, .top], 9)
            .padding(.bottom, date == nil ? 9 : 10)
            .background(Color(white: 0.98), in: RoundedRectangle(cornerRadius: 3))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        }

        private func zhFullDate(_ d: Date) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "yyyy年M月d日"
            return f.string(from: d)
        }
    }
}

// MARK: - Page 7: 3x3 Polaroid Collage (Screenshot 8)

private struct YearPhotosPage: View {
    let assets: [PHAsset]
    let total: Int
    let isActive: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.1, blue: 0.08), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GeometryReader { geo in
                ForEach(Array(assets.prefix(9).enumerated()), id: \.element.localIdentifier) { index, asset in
                    let spot = Self.spot(index, in: geo.size)
                    YearPolaroidTile(asset: asset)
                        .rotationEffect(.degrees(isActive ? spot.angle : spot.angle * 3))
                        .position(x: spot.point.x, y: isActive ? spot.point.y : spot.point.y - geo.size.height)
                        .animation(
                            .spring(response: 0.7, dampingFraction: 0.72).delay(0.15 + Double(index) * 0.10),
                            value: isActive
                        )
                }
            }
            .padding(.bottom, 200)

            StoryPageText {
                StoryKicker(text: "这一年留下的画面", tint: Color(red: 1, green: 0.85, blue: 0.6))
                    .storyReveal(isActive, after: 0.2)
                StoryNumberView(value: isActive ? Double(total) : 0, unit: "张照片", size: 64)
                    .animation(.easeOut(duration: 1.5).delay(0.3), value: isActive)
            }
        }
    }

    private static func spot(_ index: Int, in size: CGSize) -> (point: CGPoint, angle: Double) {
        let col = index % 3, row = index / 3
        let jitter: [(CGFloat, CGFloat, Double)] = [
            (-6, 8, -7), (4, -6, 4), (8, 10, -3),
            (-4, -4, 6), (6, 6, -5), (-8, 2, 8),
            (2, 8, -4), (-6, -6, 5), (6, 4, -8)
        ]
        let j = jitter[index % jitter.count]
        let x = size.width * (0.2 + 0.3 * CGFloat(col)) + j.0
        let y = size.height * (0.22 + 0.27 * CGFloat(row)) + j.1
        return (CGPoint(x: x, y: y), j.2)
    }
}

private struct YearPolaroidTile: View {
    let asset: PHAsset
    @State private var thumb: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let thumb {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.gray.opacity(0.25)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 2))

            if let date = asset.creationDate {
                Text(zhMonthDay(date))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.black.opacity(0.55))
            }
        }
        .padding(.horizontal, 7)
        .padding(.top, 7)
        .padding(.bottom, 9)
        .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 3))
        .shadow(color: .black.opacity(0.45), radius: 10, y: 6)
        .task(id: asset.localIdentifier) {
            thumb = await YearAssetLoader.image(for: asset, targetSize: CGSize(width: 240, height: 240))
        }
    }

    private func zhMonthDay(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f.string(from: d)
    }
}

// MARK: - Page 8: Share Poster (Screenshot 9)

private struct YearSharePage: View {
    let data: YearReportView.StoryData
    let stampCount: Int
    let onShare: () -> Void

    var body: some View {
        ZStack {
            StoryNightGradient()

            if let cover = data.cover {
                Color.clear
                    .overlay { Image(uiImage: cover).resizable().scaledToFill() }
                    .clipped()
                    .blur(radius: 24)
                    .opacity(0.6)
                    .ignoresSafeArea()
            }

            VStack(spacing: 22) {
                Spacer(minLength: 80)

                YearPoster(data: data, stampCount: stampCount)
                    .frame(width: 390, height: 640)
                    .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
                    .scaleEffect(300.0 / 390.0)
                    .frame(width: 300, height: 492)
                    .shadow(color: .black.opacity(0.4), radius: 30, y: 14)

                Button(action: onShare) {
                    Label("分享年度足迹", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.white, in: Capsule())
                }
                .padding(.horizontal, 40)

                Spacer(minLength: 40)
            }
        }
    }
}

private struct YearPoster: View {
    let data: YearReportView.StoryData
    var stampCount: Int = 0

    var body: some View {
        let r = data.report
        let resolvedStamps = stampCount > 0 ? stampCount : YearPassportPage.stamps(for: r.year, summary: data.passportSummary).count

        ZStack(alignment: .topLeading) {
            if let cover = data.cover {
                Color.clear.overlay { Image(uiImage: cover).resizable().scaledToFill() }.clipped()
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.55), location: 0),
                        .init(color: .clear, location: 0.3),
                        .init(color: .black.opacity(0.85), location: 0.75)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.07, blue: 0.25),
                        Color(red: 0.35, green: 0.12, blue: 0.45),
                        Color(red: 0.95, green: 0.45, blue: 0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(r.year))
                        .font(.system(size: 52, weight: .black, design: .rounded))
                    Spacer()
                    Text("漫迹")
                        .font(.subheadline.weight(.bold))
                        .opacity(0.85)
                }
                Text("年度足迹")
                    .font(.title3.weight(.bold))
                    .opacity(0.85)

                Spacer()

                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                    GridRow {
                        stat(formatPosterKm(r.groundDistance), "移动距离")
                        stat("\(r.daysRecorded)", "记录天数")
                    }
                    GridRow {
                        stat("\(r.countries.count)", "国家和地区")
                        stat("\(r.cities.count)", "城市")
                    }
                    if resolvedStamps > 0 {
                        GridRow {
                            stat("\(r.provinces.count)", "省份")
                            stat("\(resolvedStamps)", "枚印章")
                        }
                    }
                }

                if !r.countries.isEmpty {
                    Text(r.countries.prefix(10).map { CountryText.flag(for: $0) }.joined(separator: " "))
                        .font(.title2)
                        .padding(.top, 12)
                }
            }
            .foregroundColor(.white)
            .padding(24)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .monospacedDigit()
            Text(label)
                .font(.caption.weight(.semibold))
                .opacity(0.75)
        }
    }

    private func formatPosterKm(_ meters: Double) -> String {
        let km = meters / 1000.0
        if km >= 10 {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 0
            return (f.string(from: NSNumber(value: km)) ?? "\(Int(km))") + " km"
        }
        return Formatters.distance(meters)
    }
}

// MARK: - PHAsset Image Loader & Share Sheet

private enum YearAssetLoader {
    static func image(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { cont in
            let req = PHImageRequestOptions()
            req.deliveryMode = .highQualityFormat
            req.resizeMode = .fast
            req.isNetworkAccessAllowed = true
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: req
            ) { img, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded && !resumed {
                    resumed = true
                    cont.resume(returning: img)
                }
            }
        }
    }
}

private struct ShareableYearImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct YearActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
