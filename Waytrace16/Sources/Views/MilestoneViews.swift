import SwiftUI
import UIKit

// MARK: - 1:1 Original PathTracker Milestones Engine (23 Badges across 5 Categories)

struct WayMilestone: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case distance, countries, provinces, cities, days

        var thresholds: [Int] {
            switch self {
            case .distance: return [100, 500, 1_000, 5_000, 10_000, 40_075]
            case .countries: return [3, 5, 10, 20, 50]
            case .provinces: return [5, 10, 20, 34]
            case .cities: return [10, 25, 50, 100]
            case .days: return [30, 100, 365, 1_000]
            }
        }

        var symbol: String {
            switch self {
            case .distance: return "point.topleft.down.curvedto.point.bottomright.up"
            case .countries: return "flag.fill"
            case .provinces: return "square.grid.3x3.fill"
            case .cities: return "building.2.fill"
            case .days: return "calendar"
            }
        }

        var title: String {
            switch self {
            case .distance: return "移动距离"
            case .countries: return "国家和地区"
            case .provinces: return "省份"
            case .cities: return "城市"
            case .days: return "记录天数"
            }
        }

        var colors: [Color] {
            switch self {
            case .distance: return [Color(red: 0.35, green: 0.68, blue: 1.0), Color(red: 0.10, green: 0.36, blue: 0.85)]
            case .countries: return [Color(red: 1.0, green: 0.47, blue: 0.45), Color(red: 0.80, green: 0.12, blue: 0.24)]
            case .provinces: return [Color(red: 1.0, green: 0.74, blue: 0.30), Color(red: 0.93, green: 0.42, blue: 0.08)]
            case .cities: return [Color(red: 0.62, green: 0.55, blue: 1.0), Color(red: 0.36, green: 0.24, blue: 0.86)]
            case .days: return [Color(red: 0.32, green: 0.86, blue: 0.80), Color(red: 0.05, green: 0.55, blue: 0.58)]
            }
        }

        var badgeUnit: String {
            switch self {
            case .distance: return "公里"
            case .countries: return "国家"
            case .provinces: return "省份"
            case .cities: return "城市"
            case .days: return "天"
            }
        }
    }

    let kind: Kind
    let threshold: Int

    var id: String { "\(kind.rawValue).\(threshold)" }
    var tier: Int { kind.thresholds.firstIndex(of: threshold) ?? 0 }

    var metal: [Color] {
        switch tier {
        case 0: return [Color(red: 0.93, green: 0.72, blue: 0.52), Color(red: 0.62, green: 0.38, blue: 0.20)]
        case 1: return [Color(white: 0.96), Color(white: 0.62)]
        case 2: return [Color(red: 1.0, green: 0.90, blue: 0.55), Color(red: 0.82, green: 0.60, blue: 0.10)]
        default: return [Color(red: 0.92, green: 0.95, blue: 1.0), Color(red: 0.55, green: 0.62, blue: 0.80)]
        }
    }

    var badgeNumber: String {
        if threshold >= 1000 {
            return (threshold % 1000 == 0 || threshold >= 10_000)
                ? "\(threshold / 1000)K"
                : String(format: "%.1fK", Double(threshold) / 1000.0)
        }
        return "\(threshold)"
    }

    var scale: String? {
        guard kind == .distance else { return nil }
        switch threshold {
        case 100: return "差不多是两个半马拉松"
        case 500: return "比北京到青岛的直线距离还远"
        case 1_000: return "大约是北京到上海的直线距离"
        case 5_000: return "比北京到新加坡的直线距离还远"
        case 10_000: return "从北极到赤道的距离"
        case 40_075: return "赤道一圈的长度"
        default: return nil
        }
    }

    var title: String {
        let num = NumberFormatter.localizedString(from: NSNumber(value: threshold), number: .decimal)
        switch kind {
        case .distance where threshold == 40_075: return "绕地球一圈"
        case .distance: return "移动 \(num) 公里"
        case .countries: return "去过 \(num) 个国家和地区"
        case .provinces where threshold == 34: return "走遍全国省级行政区"
        case .provinces: return "点亮 \(num) 个省份"
        case .cities: return "去过 \(num) 座城市"
        case .days: return "记录 \(num) 天"
        }
    }
}

struct WayMilestoneProgress {
    struct Status: Identifiable {
        let milestone: WayMilestone
        let date: Date?
        let current: Double
        var subject: String? = nil
        var isNext: Bool = false

        var id: String { milestone.id }
        var isReached: Bool { date != nil }
        var fraction: Double { min(1.0, max(0.0, current / Double(max(milestone.threshold, 1)))) }

        var remaining: String {
            let left = max(0, Double(milestone.threshold) - current)
            let v = milestone.kind == .distance ? Int(left.rounded(.up)) : Int(left)
            let num = NumberFormatter.localizedString(from: NSNumber(value: v), number: .decimal)
            switch milestone.kind {
            case .distance: return "还差 \(num) 公里"
            case .countries: return "还差 \(num) 个国家和地区"
            case .provinces: return "还差 \(num) 个省份"
            case .cities: return "还差 \(num) 座城市"
            case .days: return "还差 \(num) 天"
            }
        }

        var subjectLine: String? {
            guard let subject else { return nil }
            switch milestone.kind {
            case .countries: return "第 \(milestone.threshold) 个国家和地区：\(subject)"
            case .provinces: return "第 \(milestone.threshold) 个省份：\(subject)"
            case .cities: return "第 \(milestone.threshold) 座城市：\(subject)"
            default: return nil
            }
        }
    }

    var reached: [Status] = []
    var next: [Status] = []
    var all: [Status] = []

    static func build(stays: [Stay], chunks: [TrackChunk]) -> WayMilestoneProgress {
        let cal = Calendar.current
        var countryFirst: [String: Date] = [:]
        var provinceFirst: [String: Date] = [:]
        var provinceNames: [String: String] = [:]
        var cityFirst: [String: Date] = [:]
        var cityNames: [String: String] = [:]
        var daySet = Set<Date>()

        for stay in stays {
            let startDay = cal.startOfDay(for: stay.arrival)
            daySet.insert(startDay)
            if let dep = stay.departure, dep > stay.arrival {
                let endDay = cal.startOfDay(for: min(dep, Date()))
                var cur = startDay
                var guardCount = 0
                while cur <= endDay && guardCount < 60 {
                    daySet.insert(cur)
                    guard let nxt = cal.date(byAdding: .day, value: 1, to: cur) else { break }
                    cur = nxt
                    guardCount += 1
                }
            }
            if let code = stay.countryCode, !code.isEmpty {
                countryFirst[code] = min(countryFirst[code] ?? .distantFuture, stay.arrival)
            }
            if let prov = ChinaProvince.containing(countryCode: stay.countryCode, region: stay.region, city: stay.city) {
                provinceFirst[prov.id] = min(provinceFirst[prov.id] ?? .distantFuture, stay.arrival)
                provinceNames[prov.id] = prov.name
            }
            if let city = stay.city, !city.isEmpty {
                let key = "\(stay.countryCode ?? "")|\(city)"
                cityFirst[key] = min(cityFirst[key] ?? .distantFuture, stay.arrival)
                cityNames[key] = city
            }
        }
        for chunk in chunks {
            daySet.insert(cal.startOfDay(for: chunk.startDate))
        }

        let orderedCountries = countryFirst.sorted { $0.value < $1.value }
            .map { (date: $0.value, name: Optional(CountryText.localizedName(code: $0.key))) }
        let orderedProvinces = provinceFirst.sorted { $0.value < $1.value }
            .map { (date: $0.value, name: provinceNames[$0.key]) }
        let orderedCities = cityFirst.sorted { $0.value < $1.value }
            .map { (date: $0.value, name: cityNames[$0.key]) }
        let orderedDays = daySet.filter { $0 <= Date() }.sorted()
            .map { (date: $0, name: Optional<String>.none) }

        let firstsByKind: [WayMilestone.Kind: [(date: Date, name: String?)]] = [
            .countries: orderedCountries,
            .provinces: orderedProvinces,
            .cities: orderedCities,
            .days: orderedDays
        ]

        let groundChunks = chunks.filter { $0.mode != .flying }.sorted { $0.startDate < $1.startDate }

        var progress = WayMilestoneProgress()
        for kind in WayMilestone.Kind.allCases {
            let current: Double
            var reachedDates: [Int: Date] = [:]
            var subjects: [Int: String] = [:]

            if kind == .distance {
                var totalKm = 0.0
                for chunk in groundChunks {
                    totalKm += chunk.distance / 1000.0
                    for threshold in kind.thresholds where reachedDates[threshold] == nil && totalKm >= Double(threshold) {
                        reachedDates[threshold] = chunk.startDate
                    }
                }
                current = totalKm
            } else {
                let list = firstsByKind[kind] ?? []
                for threshold in kind.thresholds where list.count >= threshold {
                    reachedDates[threshold] = list[threshold - 1].date
                    subjects[threshold] = list[threshold - 1].name
                }
                current = Double(list.count)
            }

            let upcoming = kind.thresholds.first { reachedDates[$0] == nil }
            var addedNext = false
            for threshold in kind.thresholds {
                let ms = WayMilestone(kind: kind, threshold: threshold)
                let status = Status(
                    milestone: ms,
                    date: reachedDates[threshold],
                    current: current,
                    subject: subjects[threshold],
                    isNext: threshold == upcoming
                )
                progress.all.append(status)
                if status.isReached {
                    progress.reached.append(status)
                } else if !addedNext {
                    progress.next.append(status)
                    addedNext = true
                }
            }
        }

        progress.reached.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        progress.next.sort { $0.fraction > $1.fraction }
        return progress
    }
}

// MARK: - 1:1 Original Illustrated MilestoneBadge

struct WayMilestoneBadge: View {
    let milestone: WayMilestone
    var isReached: Bool = true
    var progress: Double = 0
    var size: CGFloat = 72
    var shimmers: Bool = false

    @State private var shine = false

    private var faceInset: CGFloat { size * 0.12 }
    private var strokeWidth: CGFloat { max(0.75, size * 0.01) }

    var body: some View {
        ZStack(alignment: .top) {
            if isReached {
                ribbon.offset(y: size * 0.6)
            }
            ZStack {
                rim
                scene
                if !isReached && progress > 0 {
                    progressRing
                }
                stars.offset(y: -size * 0.33)
                banner.offset(y: size * 0.27)
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size * (isReached ? 1.16 : 1.0), alignment: .top)
        .onAppear {
            guard shimmers else { return }
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
                shine = true
            }
        }
    }

    @ViewBuilder
    private var rim: some View {
        if isReached {
            let light = milestone.metal[0]
            let dark = milestone.metal[1]
            let rimShine: [Color] = [light, dark, light, .white.opacity(0.9), light, dark, light]
            WayRosetteShape(points: 20, depth: 0.04)
                .fill(AngularGradient(colors: rimShine, center: .center, angle: .degrees(shine ? 360 : 0)))
                .shadow(color: milestone.kind.colors[1].opacity(0.35), radius: size * 0.09, y: size * 0.06)
            WayRosetteShape(points: 20, depth: 0.04)
                .stroke(Color.white.opacity(0.4), lineWidth: strokeWidth)
            Circle()
                .fill(LinearGradient(colors: [dark, light], startPoint: .top, endPoint: .bottom))
                .padding(faceInset - size * 0.028)
        } else {
            WayRosetteShape(points: 20, depth: 0.04)
                .fill(Color.secondary.opacity(0.12))
            WayRosetteShape(points: 20, depth: 0.04)
                .stroke(Color.secondary.opacity(0.18), lineWidth: strokeWidth)
        }
    }

    private var scene: some View {
        WayMedalSceneView(kind: milestone.kind, tier: milestone.tier)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .fill(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0)], startPoint: .top, endPoint: .center))
                    .mask(Ellipse().scale(x: 0.9, y: 0.55, anchor: .top))
            }
            .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: strokeWidth))
            .grayscale(isReached ? 0 : 1)
            .opacity(isReached ? 1 : 0.4)
            .padding(faceInset)
    }

    private var progressRing: some View {
        Circle()
            .trim(from: 0, to: CGFloat(min(1, progress)))
            .stroke(
                LinearGradient(colors: milestone.kind.colors, startPoint: .top, endPoint: .bottom),
                style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .padding(faceInset - size * 0.01)
    }

    private var stars: some View {
        let count = min(milestone.tier + 1, 5)
        return HStack(spacing: size * 0.008) {
            ForEach(0..<count, id: \.self) { index in
                Image(systemName: "star.fill")
                    .font(.system(size: size * (index == count / 2 ? 0.085 : 0.068), weight: .black))
                    .offset(y: abs(CGFloat(index) - CGFloat(count - 1) / 2.0) * size * 0.018)
            }
        }
        .foregroundStyle(
            isReached
            ? AnyShapeStyle(LinearGradient(colors: [.white, milestone.metal[0]], startPoint: .top, endPoint: .bottom))
            : AnyShapeStyle(Color.secondary.opacity(0.5))
        )
        .shadow(color: .black.opacity(isReached ? 0.35 : 0), radius: size * 0.01, y: size * 0.008)
    }

    private var banner: some View {
        ZStack {
            WayScrollBannerShape()
                .fill(
                    isReached
                    ? AnyShapeStyle(LinearGradient(colors: [milestone.metal[0], milestone.metal[1]], startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(Color(.systemGray5))
                )
                .shadow(color: .black.opacity(isReached ? 0.25 : 0.08), radius: size * 0.02, y: size * 0.015)
            WayScrollBannerShape()
                .stroke(Color.white.opacity(isReached ? 0.5 : 0.2), lineWidth: strokeWidth)
            HStack(alignment: .firstTextBaseline, spacing: size * 0.02) {
                Text(milestone.badgeNumber)
                    .font(.system(size: size * 0.15, weight: .black, design: .rounded))
                if size >= 56 {
                    Text(milestone.kind.badgeUnit)
                        .font(.system(size: size * 0.065, weight: .heavy, design: .rounded))
                        .opacity(0.8)
                }
            }
            .foregroundColor(isReached ? Color.black.opacity(0.72) : .secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: size * 0.62)
            .offset(y: -size * 0.022)
        }
        .frame(width: size * 0.94, height: size * 0.22)
    }

    private var ribbon: some View {
        HStack(spacing: size * 0.06) {
            WayRibbonTailShape()
                .fill(LinearGradient(colors: [milestone.kind.colors[1], milestone.kind.colors[0]], startPoint: .top, endPoint: .bottom))
                .rotationEffect(.degrees(14), anchor: .top)
            WayRibbonTailShape()
                .fill(LinearGradient(colors: [milestone.kind.colors[0], milestone.kind.colors[1]], startPoint: .top, endPoint: .bottom))
                .rotationEffect(.degrees(-14), anchor: .top)
        }
        .frame(width: size * 0.5, height: size * 0.5)
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }
}

private struct WayRosetteShape: Shape {
    var points: Int = 20
    var depth: CGFloat = 0.04

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2.0
        var path = Path()
        let steps = points * 10
        for i in 0...steps {
            let angle = Double(i) / Double(steps) * 2.0 * Double.pi
            let wave = 1.0 - cos(Double(points) * angle)
            let r = radius * (1.0 - depth * CGFloat(wave) / 2.0)
            let pt = CGPoint(x: center.x + r * CGFloat(cos(angle)), y: center.y + r * CGFloat(sin(angle)))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}

private struct WayScrollBannerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let tail = w * 0.12
        let notch = tail * 0.45
        let lift = h * 0.18
        var path = Path()

        path.move(to: CGPoint(x: tail, y: lift))
        path.addQuadCurve(to: CGPoint(x: w - tail, y: lift), control: CGPoint(x: w / 2.0, y: -lift * 0.6))
        path.addLine(to: CGPoint(x: w - tail, y: h - lift))
        path.addQuadCurve(to: CGPoint(x: tail, y: h - lift), control: CGPoint(x: w / 2.0, y: h - lift * 1.9))
        path.closeSubpath()

        for side in [0, 1] {
            let x0: CGFloat = side == 0 ? 0 : w
            let x1: CGFloat = side == 0 ? tail * 1.2 : w - tail * 1.2
            let xn: CGFloat = side == 0 ? notch : w - notch
            path.move(to: CGPoint(x: x1, y: lift * 1.8))
            path.addLine(to: CGPoint(x: x0, y: lift * 1.8))
            path.addLine(to: CGPoint(x: xn, y: (h + lift * 0.8) / 2.0 + lift * 0.5))
            path.addLine(to: CGPoint(x: x0, y: h - lift * 0.2))
            path.addLine(to: CGPoint(x: x1, y: h - lift * 0.2))
            path.closeSubpath()
        }
        return path
    }
}

private struct WayRibbonTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width * 0.42
        path.move(to: CGPoint(x: rect.midX - w / 2.0, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + w / 2.0, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + w / 2.0, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - w * 0.55))
        path.addLine(to: CGPoint(x: rect.midX - w / 2.0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct WayFlightArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.2, y: rect.height * 0.58))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.68, y: rect.height * 0.33),
                          control: CGPoint(x: rect.width * 0.3, y: rect.height * 0.2))
        return path
    }
}

// MARK: - Medal Painted Scene (Split Helpers for Fast Release Compilation)

private struct WayMedalSceneView: View {
    let kind: WayMilestone.Kind
    let tier: Int

    var body: some View {
        Canvas { context, size in
            drawScene(in: context, size: size)
        }
        .overlay {
            if kind == .countries {
                WayFlightArcShape()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [3, 3]))
            }
        }
        .overlay {
            if kind == .countries {
                GeometryReader { geo in
                    Image(systemName: "airplane")
                        .font(.system(size: geo.size.width * 0.14, weight: .bold))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(-20))
                        .position(x: geo.size.width * 0.74, y: geo.size.height * 0.30)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                }
            }
        }
    }

    private func drawScene(in context: GraphicsContext, size: CGSize) {
        let s = size.width
        let skyColors = Self.sky(kind, tier: tier)
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(Gradient(colors: skyColors), startPoint: .zero, endPoint: CGPoint(x: 0, y: s))
        )
        if tier >= 3 && kind != .cities {
            let pts: [(CGFloat, CGFloat)] = [(0.15, 0.14), (0.3, 0.26), (0.48, 0.1), (0.86, 0.3), (0.38, 0.06)]
            for (x, y) in pts {
                context.fill(Path(ellipseIn: CGRect(x: x * s, y: y * s, width: 0.016 * s, height: 0.016 * s)), with: .color(.white.opacity(0.8)))
            }
        }

        switch kind {
        case .distance: drawDistance(in: context, s: s)
        case .countries: drawCountries(in: context, s: s)
        case .provinces: drawProvinces(in: context, s: s)
        case .cities: drawCities(in: context, s: s)
        case .days: drawDays(in: context, s: s)
        }
    }

    private func drawDistance(in context: GraphicsContext, s: CGFloat) {
        context.fill(Path(ellipseIn: CGRect(x: 0.62 * s, y: 0.2 * s, width: 0.18 * s, height: 0.18 * s)), with: .color(.white.opacity(0.9)))
        var far = Path()
        far.move(to: CGPoint(x: 0, y: 0.56 * s))
        far.addQuadCurve(to: CGPoint(x: 0.55 * s, y: 0.52 * s), control: CGPoint(x: 0.25 * s, y: 0.4 * s))
        far.addQuadCurve(to: CGPoint(x: s, y: 0.5 * s), control: CGPoint(x: 0.8 * s, y: 0.42 * s))
        far.addLine(to: CGPoint(x: s, y: s))
        far.addLine(to: CGPoint(x: 0, y: s))
        far.closeSubpath()
        context.fill(far, with: .color(Color(red: 0.45, green: 0.78, blue: 0.55)))

        var near = Path()
        near.move(to: CGPoint(x: 0, y: 0.66 * s))
        near.addQuadCurve(to: CGPoint(x: s, y: 0.62 * s), control: CGPoint(x: 0.5 * s, y: 0.54 * s))
        near.addLine(to: CGPoint(x: s, y: s))
        near.addLine(to: CGPoint(x: 0, y: s))
        near.closeSubpath()
        context.fill(near, with: .color(Color(red: 0.24, green: 0.6, blue: 0.4)))

        var road = Path()
        road.move(to: CGPoint(x: 0.47 * s, y: 0.56 * s))
        road.addLine(to: CGPoint(x: 0.53 * s, y: 0.56 * s))
        road.addQuadCurve(to: CGPoint(x: 0.78 * s, y: s), control: CGPoint(x: 0.5 * s, y: 0.78 * s))
        road.addLine(to: CGPoint(x: 0.22 * s, y: s))
        road.addQuadCurve(to: CGPoint(x: 0.47 * s, y: 0.56 * s), control: CGPoint(x: 0.42 * s, y: 0.78 * s))
        context.fill(road, with: .color(Color(white: 0.28)))

        var line = Path()
        line.move(to: CGPoint(x: 0.5 * s, y: 0.58 * s))
        line.addQuadCurve(to: CGPoint(x: 0.5 * s, y: s), control: CGPoint(x: 0.47 * s, y: 0.8 * s))
        context.stroke(line, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: s * 0.018, dash: [s * 0.04, s * 0.035]))
    }

    private func drawCountries(in context: GraphicsContext, s: CGFloat) {
        let globeRect = CGRect(x: 0.12 * s, y: 0.5 * s, width: 0.76 * s, height: 0.76 * s)
        let globePath = Path(ellipseIn: globeRect)
        context.fill(
            globePath,
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.4, green: 0.75, blue: 1), Color(red: 0.1, green: 0.4, blue: 0.8)]),
                startPoint: CGPoint(x: 0.5 * s, y: 0.5 * s),
                endPoint: CGPoint(x: 0.5 * s, y: s)
            )
        )
        var clipped = context
        clipped.clip(to: globePath)
        var land = Path()
        land.addEllipse(in: CGRect(x: 0.25 * s, y: 0.6 * s, width: 0.22 * s, height: 0.12 * s))
        land.addEllipse(in: CGRect(x: 0.52 * s, y: 0.66 * s, width: 0.20 * s, height: 0.16 * s))
        land.addEllipse(in: CGRect(x: 0.36 * s, y: 0.78 * s, width: 0.14 * s, height: 0.10 * s))
        clipped.fill(land, with: .color(Color(red: 0.4, green: 0.8, blue: 0.5)))
        for i in 1...3 {
            let inset = CGFloat(i) * 0.1
            clipped.stroke(
                Path(ellipseIn: CGRect(x: (0.12 + inset) * s, y: 0.5 * s, width: (0.76 - inset * 2) * s, height: 0.76 * s)),
                with: .color(.white.opacity(0.25)),
                lineWidth: s * 0.008
            )
        }
        clipped.stroke(
            Path(ellipseIn: CGRect(x: 0.12 * s, y: 0.66 * s, width: 0.76 * s, height: 0.14 * s)),
            with: .color(.white.opacity(0.25)),
            lineWidth: s * 0.008
        )
    }

    private func drawProvinces(in context: GraphicsContext, s: CGFloat) {
        context.fill(Path(ellipseIn: CGRect(x: 0.18 * s, y: 0.2 * s, width: 0.16 * s, height: 0.16 * s)), with: .color(.white.opacity(0.85)))
        func drawRange(_ peaks: [(CGFloat, CGFloat)], base: CGFloat, color: Color) {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: base * s))
            for pk in peaks { path.addLine(to: CGPoint(x: pk.0 * s, y: pk.1 * s)) }
            path.addLine(to: CGPoint(x: s, y: base * s))
            path.addLine(to: CGPoint(x: s, y: s))
            path.addLine(to: CGPoint(x: 0, y: s))
            path.closeSubpath()
            context.fill(path, with: .color(color))
        }
        drawRange([(0.2, 0.5), (0.35, 0.58), (0.6, 0.42), (0.85, 0.55)], base: 0.6, color: Color(red: 0.98, green: 0.72, blue: 0.55))
        drawRange([(0.15, 0.62), (0.42, 0.34), (0.58, 0.52), (0.78, 0.46)], base: 0.7, color: Color(red: 0.75, green: 0.35, blue: 0.3))
        var snow = Path()
        snow.move(to: CGPoint(x: 0.42 * s, y: 0.34 * s))
        snow.addLine(to: CGPoint(x: 0.50 * s, y: 0.43 * s))
        snow.addLine(to: CGPoint(x: 0.45 * s, y: 0.41 * s))
        snow.addLine(to: CGPoint(x: 0.41 * s, y: 0.45 * s))
        snow.addLine(to: CGPoint(x: 0.37 * s, y: 0.41 * s))
        snow.addLine(to: CGPoint(x: 0.35 * s, y: 0.42 * s))
        snow.closeSubpath()
        context.fill(snow, with: .color(.white))
        drawRange([(0.3, 0.7), (0.55, 0.78), (0.8, 0.66)], base: 0.82, color: Color(red: 0.45, green: 0.18, blue: 0.25))
    }

    private func drawCities(in context: GraphicsContext, s: CGFloat) {
        let starPts: [(CGFloat, CGFloat)] = [(0.2, 0.2), (0.35, 0.32), (0.55, 0.18), (0.8, 0.36), (0.28, 0.42), (0.7, 0.26)]
        for (x, y) in starPts {
            context.fill(Path(ellipseIn: CGRect(x: x * s, y: y * s, width: 0.02 * s, height: 0.02 * s)), with: .color(.white.opacity(0.85)))
        }
        // Crescent moon (iOS 16 compatible without Path.subtracting)
        let moonColor = Color(red: 1, green: 0.92, blue: 0.6)
        context.fill(Path(ellipseIn: CGRect(x: 0.6 * s, y: 0.12 * s, width: 0.2 * s, height: 0.2 * s)), with: .color(moonColor))
        let skyCut = Color(red: 0.18, green: 0.13, blue: 0.43)
        context.fill(Path(ellipseIn: CGRect(x: 0.66 * s, y: 0.09 * s, width: 0.2 * s, height: 0.2 * s)), with: .color(skyCut))

        let buildings: [(CGFloat, CGFloat, CGFloat)] = [
            (0.0, 0.62, 0.16), (0.14, 0.48, 0.14), (0.27, 0.56, 0.12), (0.38, 0.36, 0.13),
            (0.5, 0.52, 0.12), (0.61, 0.42, 0.15), (0.75, 0.58, 0.12), (0.86, 0.5, 0.14)
        ]
        let bColor = Color(red: 0.16, green: 0.12, blue: 0.38)
        let wColor = Color(red: 1, green: 0.85, blue: 0.45).opacity(0.9)
        for (x, top, w) in buildings {
            context.fill(Path(CGRect(x: x * s, y: top * s, width: w * s, height: (1 - top) * s)), with: .color(bColor))
            var row = top + 0.06
            while row < 0.95 {
                var col = x + 0.025
                while col < x + w - 0.03 {
                    if Int((col + row) * 100) % 3 != 0 {
                        context.fill(Path(CGRect(x: col * s, y: row * s, width: 0.025 * s, height: 0.03 * s)), with: .color(wColor))
                    }
                    col += 0.045
                }
                row += 0.065
            }
        }
        var spire = Path()
        spire.move(to: CGPoint(x: 0.445 * s, y: 0.36 * s))
        spire.addLine(to: CGPoint(x: 0.445 * s, y: 0.24 * s))
        context.stroke(spire, with: .color(bColor), lineWidth: s * 0.015)
    }

    private func drawDays(in context: GraphicsContext, s: CGFloat) {
        let center = CGPoint(x: 0.5 * s, y: 0.62 * s)
        for i in 0..<12 {
            let angle = Double(i) / 12.0 * Double.pi * 2.0
            var ray = Path()
            ray.move(to: center)
            ray.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle - 0.08)) * s, y: center.y + CGFloat(sin(angle - 0.08)) * s))
            ray.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle + 0.08)) * s, y: center.y + CGFloat(sin(angle + 0.08)) * s))
            ray.closeSubpath()
            context.fill(ray, with: .color(.white.opacity(0.14)))
        }
        context.fill(
            Path(ellipseIn: CGRect(x: 0.27 * s, y: 0.39 * s, width: 0.46 * s, height: 0.46 * s)),
            with: .linearGradient(
                Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.6), Color(red: 1, green: 0.65, blue: 0.3)]),
                startPoint: CGPoint(x: 0.5 * s, y: 0.39 * s),
                endPoint: CGPoint(x: 0.5 * s, y: 0.75 * s)
            )
        )
        context.fill(
            Path(CGRect(x: 0, y: 0.64 * s, width: s, height: 0.36 * s)),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.1, green: 0.55, blue: 0.62), Color(red: 0.03, green: 0.32, blue: 0.42)]),
                startPoint: CGPoint(x: 0, y: 0.64 * s),
                endPoint: CGPoint(x: 0, y: s)
            )
        )
        let reflections: [(CGFloat, CGFloat)] = [(0.69, 0.40), (0.75, 0.28), (0.81, 0.18)]
        for (y, w) in reflections {
            context.fill(
                Path(roundedRect: CGRect(x: (0.5 - w / 2.0) * s, y: y * s, width: w * s, height: 0.018 * s), cornerRadius: s * 0.01),
                with: .color(Color(red: 1, green: 0.85, blue: 0.5).opacity(0.7))
            )
        }
    }

    static func sky(_ kind: WayMilestone.Kind, tier: Int) -> [Color] {
        if kind != .cities {
            switch tier {
            case 1: return [Color(red: 0.25, green: 0.6, blue: 1), Color(red: 0.6, green: 0.85, blue: 1)]
            case 2: return [Color(red: 1, green: 0.55, blue: 0.35), Color(red: 1, green: 0.85, blue: 0.5)]
            case 3...: return [Color(red: 0.2, green: 0.15, blue: 0.45), Color(red: 0.9, green: 0.45, blue: 0.5)]
            default: break
            }
        }
        switch kind {
        case .distance: return [Color(red: 0.45, green: 0.75, blue: 1), Color(red: 0.75, green: 0.9, blue: 1)]
        case .countries: return [Color(red: 1, green: 0.55, blue: 0.5), Color(red: 1, green: 0.8, blue: 0.65)]
        case .provinces: return [Color(red: 1, green: 0.62, blue: 0.3), Color(red: 1, green: 0.85, blue: 0.55)]
        case .cities: return [Color(red: 0.12, green: 0.08, blue: 0.32), Color(red: 0.42, green: 0.32, blue: 0.85)]
        case .days: return [Color(red: 0.2, green: 0.7, blue: 0.75), Color(red: 1, green: 0.78, blue: 0.55)]
        }
    }
}

// MARK: - 1:1 Original MilestonesView & MilestoneDetailSheet (Screenshots 6 & 7)

struct WayMilestonesDetailView: View {
    let progress: WayMilestoneProgress
    @State private var selected: WayMilestoneProgress.Status?
    @State private var appeared = false

    private var earnedCount: Int { progress.all.filter(\.isReached).count }

    private var lead: WayMilestoneProgress.Status? {
        if let latest = progress.reached.first {
            return progress.all.first { $0.id == latest.id }
        }
        return progress.all.filter(\.isNext).max { $0.fraction < $1.fraction }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                heroSection
                ForEach(WayMilestone.Kind.allCases, id: \.self) { kind in
                    categorySection(kind)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("里程碑")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { status in
            WayMilestoneDetailSheet(status: status)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) {
                appeared = true
            }
        }
    }

    private var heroSection: some View {
        VStack(spacing: 14) {
            if let lead {
                Button { selected = lead } label: {
                    ZStack {
                        WayHeroGlow(color: lead.milestone.kind.colors[0], isLit: lead.isReached)
                            .frame(width: 260, height: 260)
                        WayMilestoneBadge(
                            milestone: lead.milestone,
                            isReached: lead.isReached,
                            progress: lead.fraction,
                            size: 128,
                            shimmers: lead.isReached
                        )
                        .scaleEffect(appeared ? 1 : 0.75)
                        .opacity(appeared ? 1 : 0)
                    }
                    .frame(height: 190)
                }
                .buttonStyle(PressableStyle())

                VStack(spacing: 4) {
                    Text(lead.isReached ? "最近获得" : "第一枚奖章就在前面")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(lead.milestone.title)
                        .font(.title3.bold())
                    if let date = lead.date {
                        Text(Self.zhFullDate(date))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text(lead.remaining)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(earnedCount)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("/ \(progress.all.count) 枚")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)

            HStack(spacing: 3) {
                ForEach(progress.all) { item in
                    Capsule()
                        .fill(
                            item.isReached
                            ? AnyShapeStyle(LinearGradient(colors: item.milestone.kind.colors, startPoint: .top, endPoint: .bottom))
                            : AnyShapeStyle(Color.secondary.opacity(0.16))
                        )
                        .frame(height: 6)
                }
            }
            .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func categorySection(_ kind: WayMilestone.Kind) -> some View {
        let items = progress.all.filter { $0.milestone.kind == kind }
        let reachedInKind = items.filter(\.isReached).count
        let currentVal = items.first?.current ?? 0

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: kind.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(LinearGradient(colors: kind.colors, startPoint: .top, endPoint: .bottom)))

                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.title).font(.title3.bold())
                    Text(soFarText(kind, current: currentVal))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Text("\(reachedInKind) / \(items.count)")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 22
            ) {
                ForEach(items) { item in
                    Button { selected = item } label: {
                        VStack(spacing: 4) {
                            WayMilestoneBadge(
                                milestone: item.milestone,
                                isReached: item.isReached,
                                progress: item.isNext ? item.fraction : 0,
                                size: 82
                            )
                            .opacity(item.isReached || item.isNext ? 1 : 0.55)
                            .padding(.bottom, 4)

                            Text(item.milestone.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(item.isReached ? .primary : .secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)

                            if let date = item.date {
                                Text(Self.zhFullDate(date))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(Color(.tertiaryLabel))
                                    .lineLimit(1)
                            } else {
                                Text(item.remaining)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(item.isNext ? item.milestone.kind.colors[1] : Color(.tertiaryLabel))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private func soFarText(_ kind: WayMilestone.Kind, current: Double) -> String {
        let num = NumberFormatter.localizedString(from: NSNumber(value: Int(current.rounded(.down))), number: .decimal)
        switch kind {
        case .distance: return "已走 \(num) 公里，不含飞行"
        case .countries: return "已去过 \(num) 个国家和地区"
        case .provinces: return "已点亮 \(num) 个省份"
        case .cities: return "已去过 \(num) 座城市"
        case .days: return "已记录 \(num) 天"
        }
    }

    private static func zhFullDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: date)
    }
}

private struct WayHeroGlow: View {
    let color: Color
    let isLit: Bool
    @State private var turn = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [color.opacity(isLit ? 0.42 : 0.15), color.opacity(0)], center: .center, startRadius: 10, endRadius: 130))
            if isLit {
                WayRaysShape(count: 14)
                    .fill(RadialGradient(colors: [color.opacity(0.26), color.opacity(0)], center: .center, startRadius: 30, endRadius: 130))
                    .rotationEffect(.degrees(turn ? 360 : 0))
                    .animation(.linear(duration: 60).repeatForever(autoreverses: false), value: turn)
            }
        }
        .allowsHitTesting(false)
        .onAppear { turn = true }
    }
}

private struct WayRaysShape: Shape {
    let count: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2.0
        var path = Path()
        for idx in 0..<count {
            let angle = Double(idx) / Double(count) * 2.0 * Double.pi
            let half = Double.pi / Double(count) * 0.35
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + radius * CGFloat(cos(angle - half)), y: center.y + radius * CGFloat(sin(angle - half))))
            path.addLine(to: CGPoint(x: center.x + radius * CGFloat(cos(angle + half)), y: center.y + radius * CGFloat(sin(angle + half))))
            path.closeSubpath()
        }
        return path
    }
}

struct WayMilestoneDetailSheet: View {
    let status: WayMilestoneProgress.Status
    @Environment(\.dismiss) private var dismiss
    @State private var tilt: CGSize = .zero
    @State private var spin: Double = 0

    var body: some View {
        VStack(spacing: 18) {
            WayMilestoneBadge(
                milestone: status.milestone,
                isReached: status.isReached,
                progress: status.fraction,
                size: 168,
                shimmers: status.isReached
            )
            .rotation3DEffect(.degrees(spin + Double(tilt.width) / 3.0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(-Double(tilt.height) / 5.0), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .gesture(
                DragGesture()
                    .onChanged { tilt = $0.translation }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { tilt = .zero }
                    }
            )
            .padding(.top, 30)
            .onAppear {
                guard status.isReached else { return }
                withAnimation(.spring(response: 1.2, dampingFraction: 0.72).delay(0.15)) { spin = 360 }
            }

            VStack(spacing: 6) {
                Text(status.milestone.title)
                    .font(.title2.bold())
                Text(status.milestone.scale ?? status.subjectLine ?? status.milestone.kind.title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)

            if let date = status.date {
                Label("\(zhFullDate(date)) 达成", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(status.milestone.kind.colors[1])
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(status.milestone.kind.colors[1].opacity(0.12), in: Capsule())
            } else {
                VStack(spacing: 8) {
                    ProgressView(value: status.fraction)
                        .tint(status.milestone.kind.colors[1])
                        .frame(width: 220)
                    Text(status.remaining)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .padding(16)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func zhFullDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: date)
    }
}
