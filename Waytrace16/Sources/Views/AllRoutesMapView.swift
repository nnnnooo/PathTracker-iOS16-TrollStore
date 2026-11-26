import SwiftUI
import MapKit
import UIKit

/// 走过的路：全屏深色轨迹总览地图（1:1 复原原版 RouteAtlasScreen / RouteAtlasView，适配 iOS 16）
struct AllRoutesMapScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var engine: LocationEngine

    enum RouteSpan: Hashable {
        case today, week, month, year, all
        case past(Int)

        static let quick: [RouteSpan] = [.today, .week, .month, .year, .all]

        var title: String {
            switch self {
            case .today: return "今天"
            case .week: return "本周"
            case .month: return "本月"
            case .year: return "今年"
            case .all: return "全部"
            case .past(let y): return "\(y)"
            }
        }

        func interval(now: Date = Date(), calendar: Calendar = .current) -> DateInterval? {
            switch self {
            case .today: return calendar.dateInterval(of: .day, for: now)
            case .week: return calendar.dateInterval(of: .weekOfYear, for: now)
            case .month: return calendar.dateInterval(of: .month, for: now)
            case .year: return calendar.dateInterval(of: .year, for: now)
            case .all: return nil
            case .past(let y):
                return calendar.date(from: DateComponents(year: y)).flatMap { calendar.dateInterval(of: .year, for: $0) }
            }
        }

        var fitsWhole: Bool {
            switch self {
            case .today, .week, .month: return true
            case .year, .all, .past: return false
            }
        }
    }

    enum RouteKind: String, CaseIterable, Identifiable {
        case all, onFoot, cycling, driving, flying
        var id: String { rawValue }

        func includes(_ mode: MovementMode) -> Bool {
            switch self {
            case .all: return true
            case .onFoot: return mode == .walking || mode == .running
            case .cycling: return mode == .cycling
            case .driving: return mode == .automotive || mode == .subway
            case .flying: return mode == .flying
            }
        }

        var title: String {
            switch self {
            case .all: return "全部"
            case .onFoot: return "步行"
            case .cycling: return "骑行"
            case .driving: return "乘车"
            case .flying: return "飞行"
            }
        }

        var symbol: String {
            switch self {
            case .all: return "sparkles"
            case .onFoot: return "figure.walk"
            case .cycling: return "bicycle"
            case .driving: return "car.fill"
            case .flying: return "airplane"
            }
        }

        var tint: Color {
            Color(lineColor(for: self == .flying ? .flying : .walking))
        }

        func lineColor(for mode: MovementMode) -> UIColor {
            switch self {
            case .all:
                return mode == .flying
                    ? UIColor(red: 0.72, green: 0.78, blue: 1.0, alpha: 1.0)
                    : UIColor(red: 1.0, green: 0.80, blue: 0.42, alpha: 1.0)
            case .onFoot: return UIColor(red: 0.45, green: 0.95, blue: 0.55, alpha: 1.0)
            case .cycling: return UIColor(red: 0.35, green: 0.92, blue: 0.95, alpha: 1.0)
            case .driving: return UIColor(red: 0.45, green: 0.68, blue: 1.0, alpha: 1.0)
            case .flying: return UIColor(red: 0.80, green: 0.62, blue: 1.0, alpha: 1.0)
            }
        }
    }

    struct AtlasLine: Identifiable {
        let id: String
        let start: Date
        let distance: Double
        let mode: MovementMode
        let minLat: Double
        let maxLat: Double
        let minLon: Double
        let maxLon: Double
        let countryCoords: [CLLocationCoordinate2D]
        let cityCoords: [CLLocationCoordinate2D]
        let streetCoords: [CLLocationCoordinate2D]

        func coordinates(for detail: Detail) -> [CLLocationCoordinate2D] {
            switch detail {
            case .country: return countryCoords
            case .city: return cityCoords
            case .street: return streetCoords
            }
        }

        enum Detail: String { case country, city, street }
    }

    @State private var span: RouteSpan = .all
    @State private var kind: RouteKind = .all
    @State private var allLines: [AtlasLine] = []
    @State private var isLoaded = false

    private var shown: [AtlasLine] {
        let interval = span.interval()
        return everything.filter { line in
            kind.includes(line.mode) && (interval.map { line.start >= $0.start && line.start < $0.end } ?? true)
        }
    }

    private var liveLine: AtlasLine? {
        let pts = engine.pendingPoints
        guard engine.isRecording, pts.count > 1 else { return nil }
        let coords = pts.map { $0.coordinate.onMap }
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        return AtlasLine(
            id: "live",
            start: pts.first?.timestamp ?? Date(),
            distance: TrackPoint.distance(of: pts),
            mode: MotionClassifier.mode(forSpeeds: pts.map(\.speed)),
            minLat: lats.min() ?? 0,
            maxLat: lats.max() ?? 0,
            minLon: lons.min() ?? 0,
            maxLon: lons.max() ?? 0,
            countryCoords: coords,
            cityCoords: coords,
            streetCoords: coords
        )
    }

    private var everything: [AtlasLine] {
        allLines + (liveLine.map { [$0] } ?? [])
    }

    private var pastYears: [Int] {
        let cal = Calendar.current
        let current = cal.component(.year, from: Date())
        return Set(allLines.map { cal.component(.year, from: $0.start) })
            .filter { $0 != current }
            .sorted(by: >)
    }

    private var availableKinds: [RouteKind] {
        let interval = span.interval()
        let inSpan = everything.filter { line in
            interval.map { line.start >= $0.start && line.start < $0.end } ?? true
        }
        return RouteKind.allCases.filter { k in
            k == .all || inSpan.contains { k.includes($0.mode) }
        }
    }

    private var daysCount: Int {
        let cal = Calendar.current
        return Set(shown.map { cal.startOfDay(for: $0.start) }).count
    }

    private var totalDistanceText: String {
        let meters = shown.reduce(0.0) { $0 + $1.distance }
        let km = meters / 1000.0
        if km >= 100 {
            let formatted = NumberFormatter.localizedString(from: NSNumber(value: Int(km.rounded())), number: .decimal)
            return "\(formatted) 公里"
        } else if km >= 1 {
            return String(format: "%.1f 公里", km)
        }
        return "\(Int(meters.rounded())) 米"
    }

    private var rangeText: String? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        guard let interval = span.interval() else {
            guard let first = allLines.map(\.start).min() else { return nil }
            f.dateFormat = "yyyy年M月"
            return "从 \(f.string(from: first)) 至今"
        }
        let end = interval.end.addingTimeInterval(-1)
        switch span {
        case .today:
            f.dateFormat = "M月d日 EEEE"
            return f.string(from: interval.start)
        case .week:
            f.dateFormat = "M月d日"
            let s1 = f.string(from: interval.start)
            let s2 = f.string(from: end)
            return "\(s1) – \(s2)"
        case .month:
            f.dateFormat = "yyyy年M月"
            return f.string(from: interval.start)
        case .year, .past:
            f.dateFormat = "yyyy年"
            return f.string(from: interval.start)
        case .all:
            return nil
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoaded {
                AllRoutesMKMapView(
                    lines: shown,
                    kind: kind,
                    focus: "\(span)",
                    fitsWhole: span.fitsWhole,
                    everywhere: allLines
                )
                .ignoresSafeArea()

                if shown.isEmpty {
                    emptyOverlay
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("正在整理全部路线…")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            topHeader
        }
        .safeAreaInset(edge: .bottom) {
            if isLoaded {
                bottomControls
            }
        }
        .task(id: store.chunks.count) {
            await buildAtlasLines()
        }
    }

    private var topHeader: some View {
        ZStack {
            Text("走过的路")
                .font(.headline.weight(.bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 4)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                }
                .accessibilityLabel("关闭")
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var bottomControls: some View {
        VStack(spacing: 10) {
            spanPicker

            if availableKinds.count > 2 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableKinds) { option in
                            let selected = (kind == option)
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    kind = option
                                }
                            } label: {
                                Label(option.title, systemImage: option.symbol)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(selected ? .black : .white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(
                                        selected ? AnyShapeStyle(option.tint) : AnyShapeStyle(.ultraThinMaterial),
                                        in: Capsule()
                                    )
                                    .overlay(
                                        Capsule().stroke(Color.white.opacity(selected ? 0 : 0.16), lineWidth: 0.7)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 20) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(totalDistanceText)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text("走过")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.62))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(daysCount)")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                    Text("天")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.62))
                }

                Spacer(minLength: 4)

                if let rangeText {
                    Text(rangeText)
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.white.opacity(0.70))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
            )
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    private var spanPicker: some View {
        let goldTint = RouteKind.all.tint
        return HStack(spacing: 2) {
            ForEach(RouteSpan.quick, id: \.self) { option in
                let selected = (span == option)
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        span = option
                    }
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(selected ? .black : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if selected { Capsule().fill(goldTint) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if !pastYears.isEmpty {
                Menu {
                    Picker("年份", selection: $span) {
                        ForEach(pastYears, id: \.self) { y in
                            Text(String(y)).tag(RouteSpan.past(y))
                        }
                    }
                } label: {
                    let pickedYear: Int? = {
                        if case .past(let y) = span { return y }
                        return nil
                    }()
                    HStack(spacing: 3) {
                        if let pickedYear {
                            Text(String(pickedYear))
                                .monospacedDigit()
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        Image(systemName: pickedYear == nil ? "calendar" : "chevron.up.chevron.down")
                            .font(pickedYear == nil ? .subheadline.weight(.semibold) : .caption2.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(pickedYear == nil ? .white : .black)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background {
                        if pickedYear != nil { Capsule().fill(goldTint) }
                    }
                    .contentShape(Capsule())
                }
                .layoutPriority(2)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.8))
        .padding(.horizontal, 16)
    }

    private var emptyOverlay: some View {
        VStack(spacing: 8) {
            Image(systemName: "point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath")
                .font(.largeTitle)
                .foregroundColor(.white.opacity(0.5))
            Text(span == .all ? "这里还没有路线" : "这段时间还没有路线")
                .font(.headline)
                .foregroundColor(.white)
            Text("出门走走，路线会在这里亮起来。")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
        }
        .multilineTextAlignment(.center)
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func buildAtlasLines() async {
        let chunks = store.chunks
        let built = await Task.detached(priority: .userInitiated) { () -> [AtlasLine] in
            chunks.compactMap { chunk -> AtlasLine? in
                let pts = chunk.points
                guard pts.count >= 2 else { return nil }
                let street = pts.simplified(tolerance: 12).map { $0.coordinate.onMap }
                let city = pts.simplified(tolerance: 60).map { $0.coordinate.onMap }
                let country = pts.simplified(tolerance: 400).map { $0.coordinate.onMap }
                guard street.count >= 2 else { return nil }
                let lats = street.map(\.latitude)
                let lons = street.map(\.longitude)
                return AtlasLine(
                    id: chunk.id.uuidString,
                    start: chunk.startDate,
                    distance: chunk.distance,
                    mode: chunk.mode,
                    minLat: lats.min() ?? 0,
                    maxLat: lats.max() ?? 0,
                    minLon: lons.min() ?? 0,
                    maxLon: lons.max() ?? 0,
                    countryCoords: country.count >= 2 ? country : street,
                    cityCoords: city.count >= 2 ? city : street,
                    streetCoords: street
                )
            }
            .sorted { $0.start < $1.start }
        }.value
        allLines = built
        isLoaded = true
    }
}

// MARK: - Multi-Layer Glowing MKMapView (Matches Screenshot 1)

private struct AllRoutesMKMapView: UIViewRepresentable {
    let lines: [AllRoutesMapScreen.AtlasLine]
    let kind: AllRoutesMapScreen.RouteKind
    let focus: String
    let fitsWhole: Bool
    let everywhere: [AllRoutesMapScreen.AtlasLine]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        config.showsTraffic = false
        map.preferredConfiguration = config
        map.showsUserLocation = false
        map.isPitchEnabled = false
        map.showsCompass = true
        map.showsScale = true
        map.layoutMargins = UIEdgeInsets(top: 60, left: 8, bottom: 200, right: 8)
        map.addOverlay(AtlasDuskOverlay.world(), level: .aboveRoads)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.update(map, lines: lines, kind: kind, focus: focus, fitsWhole: fitsWhole, everywhere: everywhere)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var lines: [AllRoutesMapScreen.AtlasLine] = []
        private var kind: AllRoutesMapScreen.RouteKind = .all
        private var focus = ""
        private var framed = false
        private var atHome = false
        private var drawnKey: String?
        private var countryCache: [String: [MKOverlay]] = [:]
        private static let layers = 4

        func update(_ map: MKMapView, lines: [AllRoutesMapScreen.AtlasLine], kind: AllRoutesMapScreen.RouteKind,
                    focus: String, fitsWhole: Bool, everywhere: [AllRoutesMapScreen.AtlasLine]) {
            let changed = lines.count != self.lines.count
                || lines.first?.id != self.lines.first?.id
                || lines.last?.id != self.lines.last?.id
                || kind != self.kind
                || lines.last?.distance != self.lines.last?.distance

            let refilter = framed && (kind != self.kind || focus != self.focus) && !lines.isEmpty
            self.lines = lines
            self.kind = kind
            self.focus = focus
            if changed {
                countryCache = [:]
                drawnKey = nil
            }

            let padding = UIEdgeInsets(top: 70, left: 30, bottom: 210, right: 30)
            if !framed, !lines.isEmpty {
                framed = true
                map.setVisibleMapRect(fitsWhole ? Self.whole(lines) : Self.framing(lines), edgePadding: padding, animated: atHome)
            } else if !framed, !atHome, !everywhere.isEmpty {
                atHome = true
                map.setVisibleMapRect(Self.framing(everywhere), edgePadding: padding, animated: false)
            } else if refilter {
                let rect = fitsWhole
                    ? Self.whole(lines)
                    : (kind == .onFoot || kind == .cycling ? Self.busiestPlace(lines) : Self.framing(lines))
                map.setVisibleMapRect(rect, edgePadding: padding, animated: true)
            }
            redraw(map)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            redraw(mapView)
        }

        private func detail(for map: MKMapView) -> AllRoutesMapScreen.AtlasLine.Detail {
            let span = map.region.span.latitudeDelta
            return span > 5 ? .country : (span > 0.3 ? .city : .street)
        }

        private func redraw(_ map: MKMapView) {
            let det = detail(for: map)
            var box: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)?
            var key = "\(det.rawValue)"
            if det != .country {
                let region = map.region
                let step = max(0.005, region.span.latitudeDelta)
                let lat = (region.center.latitude / step).rounded() * step
                let lon = (region.center.longitude / step).rounded() * step
                box = (lat - step * 1.6, lat + step * 1.6,
                       lon - region.span.longitudeDelta * 1.6, lon + region.span.longitudeDelta * 1.6)
                key += "|\(lat)|\(lon)|\(step)"
            }
            guard key != drawnKey else { return }
            drawnKey = key

            let overlays: [MKOverlay]
            if det == .country, let cached = countryCache[key] {
                overlays = cached
            } else {
                let visible: [AllRoutesMapScreen.AtlasLine]
                if let b = box {
                    visible = lines.filter { $0.maxLat >= b.minLat && $0.minLat <= b.maxLat && $0.maxLon >= b.minLon && $0.minLon <= b.maxLon }
                } else {
                    visible = lines
                }
                let level: AllRoutesMapScreen.AtlasLine.Detail = (det == .street && visible.count > 3_000) ? .city : det
                overlays = Self.buildOverlays(visible, detail: level, kind: kind)
                if det == .country { countryCache[key] = overlays }
            }

            let old = map.overlays.filter { !($0 is AtlasDuskOverlay) }
            map.addOverlays(overlays, level: .aboveRoads)
            map.removeOverlays(old)
        }

        private static func buildOverlays(_ lines: [AllRoutesMapScreen.AtlasLine],
                                          detail: AllRoutesMapScreen.AtlasLine.Detail,
                                          kind: AllRoutesMapScreen.RouteKind) -> [MKOverlay] {
            var groups: [String: (color: UIColor, flying: Bool, lines: [MKPolyline])] = [:]
            for (index, line) in lines.enumerated() {
                var coords = line.coordinates(for: detail)
                guard coords.count > 1 else { continue }
                let flying = (line.mode == .flying)
                let poly = flying
                    ? MKGeodesicPolyline(coordinates: &coords, count: coords.count)
                    : MKPolyline(coordinates: &coords, count: coords.count)
                let color = kind.lineColor(for: line.mode)
                let key = "\(flying)|\(index % layers)"
                groups[key, default: (color, flying, [])].lines.append(poly)
            }
            return groups.values.flatMap { group -> [MKOverlay] in
                [
                    AtlasRouteOverlay(group.lines, color: group.color, halo: true, flying: group.flying, detail: detail),
                    AtlasRouteOverlay(group.lines, color: group.color, halo: false, flying: group.flying, detail: detail)
                ]
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is AtlasDuskOverlay {
                let r = MKPolygonRenderer(overlay: overlay)
                r.fillColor = UIColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 0.55)
                return r
            }
            guard let overlay = overlay as? AtlasRouteOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let r = MKMultiPolylineRenderer(multiPolyline: overlay)
            let fine = overlay.detail == .street
            r.strokeColor = overlay.color.withAlphaComponent(overlay.halo ? 0.12 : (overlay.flying ? 0.35 : 0.45))
            r.lineWidth = overlay.halo ? (fine ? 7.0 : 5.0) : (overlay.flying ? 1.2 : (fine ? 2.2 : 1.6))
            r.lineCap = .round
            r.lineJoin = .round
            if overlay.flying, !overlay.halo {
                r.lineDashPattern = [3, 6]
            }
            return r
        }

        private static func whole(_ lines: [AllRoutesMapScreen.AtlasLine]) -> MKMapRect {
            let ground = lines.filter { $0.mode != .flying }
            var rect = MKMapRect.null
            for line in (ground.isEmpty ? lines : ground) {
                for c in [
                    CLLocationCoordinate2D(latitude: line.minLat, longitude: line.minLon),
                    CLLocationCoordinate2D(latitude: line.maxLat, longitude: line.maxLon)
                ] {
                    rect = rect.union(MKMapRect(origin: MKMapPoint(c), size: MKMapSize(width: 0, height: 0)))
                }
            }
            let minimum = 1_500 * MKMapPointsPerMeterAtLatitude(rect.origin.coordinate.latitude)
            guard rect.width < minimum, rect.height < minimum else { return rect }
            return MKMapRect(x: rect.midX - minimum / 2, y: rect.midY - minimum / 2, width: minimum, height: minimum)
        }

        private static func busiestPlace(_ lines: [AllRoutesMapScreen.AtlasLine]) -> MKMapRect {
            let cells = Dictionary(grouping: lines) { line in
                [Int(((line.minLat + line.maxLat) / 2).rounded()), Int(((line.minLon + line.maxLon) / 2).rounded())]
            }
            var rect = MKMapRect.null
            for line in cells.values.max(by: { $0.count < $1.count }) ?? [] {
                for c in [
                    CLLocationCoordinate2D(latitude: line.minLat, longitude: line.minLon),
                    CLLocationCoordinate2D(latitude: line.maxLat, longitude: line.maxLon)
                ] {
                    rect = rect.union(MKMapRect(origin: MKMapPoint(c), size: MKMapSize(width: 0, height: 0)))
                }
            }
            let minimum = 2_000 * MKMapPointsPerMeterAtLatitude(rect.origin.coordinate.latitude)
            guard rect.width < minimum, rect.height < minimum else { return rect }
            return MKMapRect(x: rect.midX - minimum / 2, y: rect.midY - minimum / 2, width: minimum, height: minimum)
        }

        private static func framing(_ lines: [AllRoutesMapScreen.AtlasLine]) -> MKMapRect {
            let yearAgo = Date().addingTimeInterval(-365 * 86_400)
            let recent = lines.filter { $0.start >= yearAgo && $0.mode != .flying }
            let pool = recent.isEmpty ? lines : recent
            guard !pool.isEmpty else { return MKMapRect.world }

            let lats = pool.map { ($0.minLat + $0.maxLat) / 2 }.sorted()
            let lons = pool.map { ($0.minLon + $0.maxLon) / 2 }.sorted()
            let medLat = lats[lats.count / 2]
            let medLon = lons[lons.count / 2]
            let main = pool.filter {
                abs(($0.minLat + $0.maxLat) / 2 - medLat) < 25 && abs(($0.minLon + $0.maxLon) / 2 - medLon) < 35
            }
            let target = main.isEmpty ? pool : main
            var rect = MKMapRect.null
            for line in target {
                for c in [
                    CLLocationCoordinate2D(latitude: line.minLat, longitude: line.minLon),
                    CLLocationCoordinate2D(latitude: line.maxLat, longitude: line.maxLon)
                ] {
                    rect = rect.union(MKMapRect(origin: MKMapPoint(c), size: MKMapSize(width: 0, height: 0)))
                }
            }
            let minimum = 4_000 * MKMapPointsPerMeterAtLatitude(medLat)
            if rect.width < minimum || rect.height < minimum {
                let side = max(rect.width, rect.height, minimum)
                rect = MKMapRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
            }
            return rect
        }
    }
}

private final class AtlasDuskOverlay: MKPolygon {
    static func world() -> AtlasDuskOverlay {
        let w = MKMapRect.world
        var corners = [
            MKMapPoint(x: w.minX, y: w.minY),
            MKMapPoint(x: w.maxX, y: w.minY),
            MKMapPoint(x: w.maxX, y: w.maxY),
            MKMapPoint(x: w.minX, y: w.maxY)
        ]
        return AtlasDuskOverlay(points: &corners, count: corners.count)
    }
}

private final class AtlasRouteOverlay: MKMultiPolyline {
    let color: UIColor
    let halo: Bool
    let flying: Bool
    let detail: AllRoutesMapScreen.AtlasLine.Detail

    init(_ lines: [MKPolyline], color: UIColor, halo: Bool, flying: Bool, detail: AllRoutesMapScreen.AtlasLine.Detail) {
        self.color = color
        self.halo = halo
        self.flying = flying
        self.detail = detail
        super.init(lines)
    }
}
