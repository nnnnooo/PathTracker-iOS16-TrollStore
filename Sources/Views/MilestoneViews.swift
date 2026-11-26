import SwiftUI
import UIKit
import SceneKit

// MARK: - Cached Formatters (Zero Per-Frame Allocation)

private enum WayMilestoneFormatters {
    static let zhDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    static let decimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    static func string(from date: Date) -> String {
        zhDate.string(from: date)
    }

    static func decimalString(_ value: Int) -> String {
        decimal.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

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

        var uiColors: (light: UIColor, dark: UIColor) {
            switch self {
            case .distance: return (UIColor(red: 0.35, green: 0.68, blue: 1.0, alpha: 1), UIColor(red: 0.10, green: 0.36, blue: 0.85, alpha: 1))
            case .countries: return (UIColor(red: 1.0, green: 0.47, blue: 0.45, alpha: 1), UIColor(red: 0.80, green: 0.12, blue: 0.24, alpha: 1))
            case .provinces: return (UIColor(red: 1.0, green: 0.74, blue: 0.30, alpha: 1), UIColor(red: 0.93, green: 0.42, blue: 0.08, alpha: 1))
            case .cities: return (UIColor(red: 0.62, green: 0.55, blue: 1.0, alpha: 1), UIColor(red: 0.36, green: 0.24, blue: 0.86, alpha: 1))
            case .days: return (UIColor(red: 0.32, green: 0.86, blue: 0.80, alpha: 1), UIColor(red: 0.05, green: 0.55, blue: 0.58, alpha: 1))
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

    var uiMetal: (light: UIColor, mid: UIColor, dark: UIColor) {
        switch tier {
        case 0: // Bronze
            return (
                UIColor(red: 0.95, green: 0.74, blue: 0.54, alpha: 1),
                UIColor(red: 0.80, green: 0.54, blue: 0.33, alpha: 1),
                UIColor(red: 0.56, green: 0.33, blue: 0.16, alpha: 1)
            )
        case 1: // Sterling Silver
            return (
                UIColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1),
                UIColor(red: 0.82, green: 0.84, blue: 0.88, alpha: 1),
                UIColor(red: 0.56, green: 0.59, blue: 0.64, alpha: 1)
            )
        case 2: // 24K Gold
            return (
                UIColor(red: 1.00, green: 0.92, blue: 0.58, alpha: 1),
                UIColor(red: 0.94, green: 0.76, blue: 0.24, alpha: 1),
                UIColor(red: 0.74, green: 0.51, blue: 0.08, alpha: 1)
            )
        default: // Platinum Titanium
            return (
                UIColor(red: 0.93, green: 0.96, blue: 1.00, alpha: 1),
                UIColor(red: 0.74, green: 0.80, blue: 0.92, alpha: 1),
                UIColor(red: 0.48, green: 0.55, blue: 0.74, alpha: 1)
            )
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
        let num = WayMilestoneFormatters.decimalString(threshold)
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
            let num = WayMilestoneFormatters.decimalString(v)
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

// MARK: - Rasterized Metallic MilestoneBadge (Smooth 60fps Grid Scrolling)

struct WayMilestoneBadge: View {
    let milestone: WayMilestone
    var isReached: Bool = true
    var progress: Double = 0
    var size: CGFloat = 72
    var shimmers: Bool = false

    @State private var sweepOffset: CGFloat = -1.2

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
        // Rasterize entire vector badge into a single Metal texture so scrolling 23 badges is 60/120fps
        .drawingGroup(opaque: false, colorMode: .nonLinear)
        .shadow(
            color: isReached ? milestone.kind.colors[1].opacity(0.28) : .clear,
            radius: size * 0.08,
            y: size * 0.05
        )
        .overlay(alignment: .top) {
            if shimmers && isReached {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.38), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: size * 0.45, height: size * 1.4)
                .rotationEffect(.degrees(22))
                .offset(x: sweepOffset * size)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .allowsHitTesting(false)
                .onAppear {
                    sweepOffset = -1.2
                    withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: false).delay(0.8)) {
                        sweepOffset = 1.2
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var rim: some View {
        if isReached {
            let light = milestone.metal[0]
            let dark = milestone.metal[1]
            let rimShine: [Color] = [light, dark, .white.opacity(0.92), light, dark, light, .white.opacity(0.85), dark, light]
            WayRosetteShape(points: 20, depth: 0.04)
                .fill(AngularGradient(colors: rimShine, center: .center, angle: .degrees(-35)))
            WayRosetteShape(points: 20, depth: 0.04)
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.75), dark.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: strokeWidth * 1.2
                )
            Circle()
                .fill(LinearGradient(colors: [dark, light, dark.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(faceInset - size * 0.032)
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
                    .fill(LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0)], startPoint: .top, endPoint: .center))
                    .mask(Ellipse().scale(x: 0.9, y: 0.55, anchor: .top))
            }
            .overlay(Circle().strokeBorder(Color.black.opacity(0.16), lineWidth: strokeWidth))
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
                    ? AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.85), milestone.metal[0], milestone.metal[1]], startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(Color(.systemGray5))
                )
                .shadow(color: .black.opacity(isReached ? 0.25 : 0.08), radius: size * 0.02, y: size * 0.015)
            WayScrollBannerShape()
                .stroke(Color.white.opacity(isReached ? 0.65 : 0.2), lineWidth: strokeWidth)
            HStack(alignment: .firstTextBaseline, spacing: size * 0.02) {
                Text(milestone.badgeNumber)
                    .font(.system(size: size * 0.15, weight: .black, design: .rounded))
                if size >= 56 {
                    Text(milestone.kind.badgeUnit)
                        .font(.system(size: size * 0.065, weight: .heavy, design: .rounded))
                        .opacity(0.8)
                }
            }
            .foregroundColor(isReached ? Color.black.opacity(0.75) : .secondary)
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
        let steps = points * 4
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

    static func uiSky(_ kind: WayMilestone.Kind, tier: Int) -> (UIColor, UIColor) {
        if kind != .cities {
            switch tier {
            case 1: return (UIColor(red: 0.25, green: 0.60, blue: 1.0, alpha: 1), UIColor(red: 0.60, green: 0.85, blue: 1.0, alpha: 1))
            case 2: return (UIColor(red: 1.0, green: 0.55, blue: 0.35, alpha: 1), UIColor(red: 1.0, green: 0.85, blue: 0.50, alpha: 1))
            case 3...: return (UIColor(red: 0.20, green: 0.15, blue: 0.45, alpha: 1), UIColor(red: 0.90, green: 0.45, blue: 0.50, alpha: 1))
            default: break
            }
        }
        switch kind {
        case .distance: return (UIColor(red: 0.45, green: 0.75, blue: 1.0, alpha: 1), UIColor(red: 0.75, green: 0.90, blue: 1.0, alpha: 1))
        case .countries: return (UIColor(red: 1.0, green: 0.55, blue: 0.50, alpha: 1), UIColor(red: 1.0, green: 0.80, blue: 0.65, alpha: 1))
        case .provinces: return (UIColor(red: 1.0, green: 0.62, blue: 0.30, alpha: 1), UIColor(red: 1.0, green: 0.85, blue: 0.55, alpha: 1))
        case .cities: return (UIColor(red: 0.12, green: 0.08, blue: 0.32, alpha: 1), UIColor(red: 0.42, green: 0.32, blue: 0.85, alpha: 1))
        case .days: return (UIColor(red: 0.20, green: 0.70, blue: 0.75, alpha: 1), UIColor(red: 1.0, green: 0.78, blue: 0.55, alpha: 1))
        }
    }
}

// MARK: - 1:1 Original MilestonesView (Pre-grouped & GPU-Rasterized)

struct WayMilestonesDetailView: View {
    let progress: WayMilestoneProgress
    private let earnedCount: Int
    private let lead: WayMilestoneProgress.Status?
    private let itemsByKind: [WayMilestone.Kind: [WayMilestoneProgress.Status]]

    @State private var selected: WayMilestoneProgress.Status?
    @State private var appeared = false

    init(progress: WayMilestoneProgress) {
        self.progress = progress
        self.earnedCount = progress.all.filter(\.isReached).count
        if let latest = progress.reached.first {
            self.lead = progress.all.first { $0.id == latest.id }
        } else {
            self.lead = progress.all.filter(\.isNext).max { $0.fraction < $1.fraction }
        }
        self.itemsByKind = Dictionary(grouping: progress.all, by: { $0.milestone.kind })
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
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
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            guard !appeared else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
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
                        .scaleEffect(appeared ? 1 : 0.82)
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
                        Text(WayMilestoneFormatters.string(from: date))
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
        let items = itemsByKind[kind] ?? []
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
                                Text(WayMilestoneFormatters.string(from: date))
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
        let num = WayMilestoneFormatters.decimalString(Int(current.rounded(.down)))
        switch kind {
        case .distance: return "已走 \(num) 公里，不含飞行"
        case .countries: return "已去过 \(num) 个国家和地区"
        case .provinces: return "已点亮 \(num) 个省份"
        case .cities: return "已去过 \(num) 座城市"
        case .days: return "已记录 \(num) 天"
        }
    }
}

private struct WayHeroGlow: View {
    let color: Color
    let isLit: Bool
    @State private var turn = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [color.opacity(isLit ? 0.40 : 0.14), color.opacity(0)], center: .center, startRadius: 10, endRadius: 130))
            if isLit {
                WayRaysShape(count: 14)
                    .fill(RadialGradient(colors: [color.opacity(0.24), color.opacity(0)], center: .center, startRadius: 30, endRadius: 130))
                    .drawingGroup()
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

// MARK: - iOS 16 Half-Sheet Detent Enforcer (Prevents Occasional Full-Screen Sheet Bug)

private struct WaySheetMediumEnforcer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> EnforcerVC {
        EnforcerVC()
    }

    func updateUIViewController(_ uiViewController: EnforcerVC, context: Context) {
        uiViewController.enforceMediumDetent()
    }

    final class EnforcerVC: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            enforceMediumDetent()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            enforceMediumDetent()
        }

        func enforceMediumDetent() {
            var current: UIViewController? = self
            while let vc = current {
                if let sheet = vc.sheetPresentationController {
                    sheet.detents = [.medium()]
                    sheet.selectedDetentIdentifier = .medium
                    sheet.prefersGrabberVisible = true
                    sheet.prefersScrollingExpandsWhenScrolledToEdge = false
                    break
                }
                current = vc.parent
            }
        }
    }
}

// MARK: - Hardware-Accelerated 3D PBR Metallic Medal (SceneKit)

private struct WayMedal3DSceneView: UIViewRepresentable {
    let status: WayMilestoneProgress.Status

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false

        let scene = Self.buildScene(for: status, coordinator: context.coordinator)
        view.scene = scene

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(pan)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        if status.isReached {
            context.coordinator.playEntranceSpin()
        }
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        guard context.coordinator.currentMedalID != status.id else { return }
        let scene = Self.buildScene(for: status, coordinator: context.coordinator)
        uiView.scene = scene
        if status.isReached {
            context.coordinator.playEntranceSpin()
        }
    }

    // MARK: - Coordinator (60fps Gesture + Inertia + Snap)

    final class Coordinator: NSObject {
        weak var medalRoot: SCNNode?
        var currentMedalID: String = ""
        private var baseYaw: Float = 0
        private var basePitch: Float = 0

        func playEntranceSpin() {
            guard let node = medalRoot else { return }
            node.removeAllActions()
            baseYaw = 0
            basePitch = 0
            node.eulerAngles = SCNVector3(0.08, -Float.pi * 1.65, 0)
            let spin = SCNAction.rotateTo(x: 0.04, y: 0, z: 0, duration: 1.05, usesShortestUnitArc: false)
            spin.timingMode = .easeOut
            node.runAction(spin)
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let node = medalRoot else { return }
            let translation = gesture.translation(in: gesture.view)
            switch gesture.state {
            case .began:
                node.removeAllActions()
                baseYaw = node.eulerAngles.y
                basePitch = node.eulerAngles.x
            case .changed:
                let yaw = baseYaw + Float(translation.x) * 0.015
                let rawPitch = basePitch + Float(translation.y) * 0.010
                let clampedPitch = max(-0.55, min(0.55, rawPitch))
                node.eulerAngles = SCNVector3(clampedPitch, yaw, 0)
            case .ended, .cancelled:
                let velocity = gesture.velocity(in: gesture.view)
                let projectedYaw = node.eulerAngles.y + Float(velocity.x) * 0.00035
                // Snap cleanly to front (0) or engraved back (pi) so user can inspect both sides
                let halfTurn = Float.pi
                let snappedYaw = (projectedYaw / halfTurn).rounded() * halfTurn
                let snap = SCNAction.rotateTo(x: 0.04, y: CGFloat(snappedYaw), z: 0, duration: 0.48, usesShortestUnitArc: false)
                snap.timingMode = .easeOut
                node.runAction(snap)
            default:
                break
            }
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let node = medalRoot else { return }
            node.removeAllActions()
            let targetY = CGFloat(node.eulerAngles.y) + .pi * 2
            let spin = SCNAction.rotateTo(x: 0.04, y: targetY, z: 0, duration: 0.9, usesShortestUnitArc: false)
            spin.timingMode = .easeInEaseOut
            node.runAction(spin)
        }
    }

    // MARK: - Scene Construction

    private static let sharedStudioEnv: UIImage = makeStudioEnvironmentMap()

    private static func buildScene(for status: WayMilestoneProgress.Status, coordinator: Coordinator) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        scene.lightingEnvironment.contents = sharedStudioEnv
        scene.lightingEnvironment.intensity = status.isReached ? 1.75 : 1.15

        // Camera
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 34
        camera.zNear = 0.1
        camera.zFar = 20
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, -0.06, 4.35)
        scene.rootNode.addChildNode(cameraNode)

        // Studio Key Light (warm crisp specular)
        let keyLight = SCNLight()
        keyLight.type = .directional
        keyLight.intensity = status.isReached ? 1150 : 700
        keyLight.color = UIColor(red: 1.0, green: 0.98, blue: 0.94, alpha: 1)
        let keyNode = SCNNode()
        keyNode.light = keyLight
        keyNode.eulerAngles = SCNVector3(-0.55, 0.45, 0)
        scene.rootNode.addChildNode(keyNode)

        // Cool Rim / Fill Light (highlights beveled edge when turning)
        let rimLight = SCNLight()
        rimLight.type = .directional
        rimLight.intensity = 650
        rimLight.color = UIColor(red: 0.85, green: 0.93, blue: 1.0, alpha: 1)
        let rimNode = SCNNode()
        rimNode.light = rimLight
        rimNode.eulerAngles = SCNVector3(0.35, -2.3, 0)
        scene.rootNode.addChildNode(rimNode)

        // Root pivot node for the 3D medal
        let medalRoot = SCNNode()
        medalRoot.position = SCNVector3(0, status.isReached ? 0.08 : 0.0, 0)
        scene.rootNode.addChildNode(medalRoot)

        let metalPalette = status.milestone.uiMetal
        let depth: CGFloat = 0.16
        let halfDepth = Float(depth / 2.0)

        // 1. Solid Extruded 20-Scallop Rosette Body with Beveled Chamfers
        let rosettePath = makeRosetteBezierPath(radius: 1.0, points: 20, depthRatio: 0.042)
        let bodyGeo = SCNShape(path: rosettePath, extrusionDepth: depth)
        bodyGeo.chamferRadius = 0.032
        bodyGeo.chamferMode = .both

        let metalMat = SCNMaterial()
        metalMat.lightingModel = .physicallyBased
        if status.isReached {
            metalMat.diffuse.contents = metalPalette.mid
            metalMat.metalness.contents = 0.94
            metalMat.roughness.contents = 0.20
        } else {
            metalMat.diffuse.contents = UIColor(white: 0.68, alpha: 1)
            metalMat.metalness.contents = 0.45
            metalMat.roughness.contents = 0.55
        }

        let rimEdgeMat = SCNMaterial()
        rimEdgeMat.lightingModel = .physicallyBased
        if status.isReached {
            rimEdgeMat.diffuse.contents = metalPalette.dark
            rimEdgeMat.metalness.contents = 0.96
            rimEdgeMat.roughness.contents = 0.26
        } else {
            rimEdgeMat.diffuse.contents = UIColor(white: 0.56, alpha: 1)
            rimEdgeMat.metalness.contents = 0.40
            rimEdgeMat.roughness.contents = 0.60
        }
        bodyGeo.materials = [metalMat, metalMat, rimEdgeMat, metalMat, metalMat]

        let bodyNode = SCNNode(geometry: bodyGeo)
        medalRoot.addChildNode(bodyNode)

        // 2. Raised 3D Metallic Inner Bezel Rings (front & back physical relief)
        let bezelGeo = SCNTorus(ringRadius: 0.745, pipeRadius: 0.026)
        bezelGeo.ringSegmentCount = 64
        bezelGeo.pipeSegmentCount = 18
        let bezelMat = SCNMaterial()
        bezelMat.lightingModel = .physicallyBased
        bezelMat.diffuse.contents = status.isReached ? metalPalette.light : UIColor(white: 0.72, alpha: 1)
        bezelMat.metalness.contents = status.isReached ? 0.96 : 0.45
        bezelMat.roughness.contents = status.isReached ? 0.16 : 0.52
        bezelGeo.materials = [bezelMat]

        let frontBezel = SCNNode(geometry: bezelGeo)
        frontBezel.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        frontBezel.position = SCNVector3(0, 0, halfDepth + 0.002)
        medalRoot.addChildNode(frontBezel)

        let backBezel = SCNNode(geometry: bezelGeo)
        backBezel.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        backBezel.position = SCNVector3(0, 0, -halfDepth - 0.002)
        medalRoot.addChildNode(backBezel)

        // 3. Front Artwork Face (PBR zoned: glossy enamel center + gleaming metallic rim/banner)
        let textures = makeFrontTextures(for: status, resolution: 512)
        let frontPlane = SCNPlane(width: 2.0, height: 2.0)
        let frontMat = SCNMaterial()
        frontMat.lightingModel = .physicallyBased
        frontMat.diffuse.contents = textures.diffuse
        frontMat.metalness.contents = textures.metalness
        frontMat.roughness.contents = textures.roughness
        frontMat.isDoubleSided = false
        frontMat.transparencyMode = .aOne
        frontPlane.materials = [frontMat]

        let frontNode = SCNNode(geometry: frontPlane)
        frontNode.position = SCNVector3(0, 0, halfDepth + 0.004)
        medalRoot.addChildNode(frontNode)

        // 4. Engraved Brushed-Metal Coin Back Face
        let backImage = makeBackEngravedTexture(for: status, resolution: 512)
        let backPlane = SCNPlane(width: 2.0, height: 2.0)
        let backMat = SCNMaterial()
        backMat.lightingModel = .physicallyBased
        backMat.diffuse.contents = backImage
        backMat.metalness.contents = status.isReached ? 0.90 : 0.42
        backMat.roughness.contents = status.isReached ? 0.25 : 0.55
        backMat.isDoubleSided = false
        backMat.transparencyMode = .aOne
        backPlane.materials = [backMat]

        let backNode = SCNNode(geometry: backPlane)
        backNode.position = SCNVector3(0, 0, -halfDepth - 0.004)
        backNode.eulerAngles = SCNVector3(0, Float.pi, 0)
        medalRoot.addChildNode(backNode)

        // 5. 3D Satin Ribbons Hanging Behind the Medal (real Z-depth parallax)
        if status.isReached {
            let ribbonColors = status.milestone.kind.uiColors
            let ribbonPath = makeRibbonTailBezierPath(width: 0.34, height: 0.85)
            let ribbonGeo = SCNShape(path: ribbonPath, extrusionDepth: 0.018)
            ribbonGeo.chamferRadius = 0.004
            let ribbonMat = SCNMaterial()
            ribbonMat.lightingModel = .physicallyBased
            ribbonMat.diffuse.contents = makeRibbonGradientTexture(top: ribbonColors.dark, bottom: ribbonColors.light)
            ribbonMat.metalness.contents = 0.12
            ribbonMat.roughness.contents = 0.48
            ribbonGeo.materials = [ribbonMat]

            let leftRibbon = SCNNode(geometry: ribbonGeo)
            leftRibbon.position = SCNVector3(-0.28, -0.78, -halfDepth - 0.035)
            leftRibbon.eulerAngles = SCNVector3(0, 0, -0.22)
            medalRoot.addChildNode(leftRibbon)

            let rightRibbon = SCNNode(geometry: ribbonGeo)
            rightRibbon.position = SCNVector3(0.28, -0.78, -halfDepth - 0.035)
            rightRibbon.eulerAngles = SCNVector3(0, 0, 0.22)
            medalRoot.addChildNode(rightRibbon)
        }

        coordinator.medalRoot = medalRoot
        coordinator.currentMedalID = status.id
        return scene
    }

    // MARK: - Procedural 3D Geometries

    private static func makeRosetteBezierPath(radius: CGFloat, points: Int, depthRatio: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let steps = points * 6
        for i in 0...steps {
            let angle = Double(i) / Double(steps) * 2.0 * Double.pi
            let wave = 1.0 - cos(Double(points) * angle)
            let r = radius * (1.0 - depthRatio * CGFloat(wave) / 2.0)
            let pt = CGPoint(x: r * CGFloat(cos(angle)), y: r * CGFloat(sin(angle)))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.close()
        return path
    }

    private static func makeRibbonTailBezierPath(width: CGFloat, height: CGFloat) -> UIBezierPath {
        let hw = width / 2.0
        let hh = height / 2.0
        let notch = width * 0.48
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -hw, y: hh))
        path.addLine(to: CGPoint(x: hw, y: hh))
        path.addLine(to: CGPoint(x: hw, y: -hh))
        path.addLine(to: CGPoint(x: 0, y: -hh + notch))
        path.addLine(to: CGPoint(x: -hw, y: -hh))
        path.close()
        return path
    }

    // MARK: - Studio Softbox Environment Reflection Map (Makes PBR Metal Gleam!)

    private static func makeStudioEnvironmentMap() -> UIImage {
        let size = CGSize(width: 256, height: 128)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()

            // Base studio gradient: bright ceiling -> soft mid horizon -> cool shadow floor
            let bgColors = [
                UIColor(white: 0.96, alpha: 1).cgColor,
                UIColor(white: 0.72, alpha: 1).cgColor,
                UIColor(white: 0.28, alpha: 1).cgColor,
                UIColor(white: 0.55, alpha: 1).cgColor
            ] as CFArray
            let locs: [CGFloat] = [0.0, 0.42, 0.54, 1.0]
            if let grad = CGGradient(colorsSpace: space, colors: bgColors, locations: locs) {
                cg.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }

            // Crisp bright softbox strips for realistic metallic specular bands
            UIColor(white: 1.0, alpha: 0.95).setFill()
            UIBezierPath(roundedRect: CGRect(x: 22, y: 12, width: 76, height: 34), cornerRadius: 10).fill()
            UIBezierPath(roundedRect: CGRect(x: 152, y: 16, width: 68, height: 28), cornerRadius: 8).fill()

            // Warm accent bounce
            UIColor(red: 1.0, green: 0.94, blue: 0.84, alpha: 0.75).setFill()
            UIBezierPath(ovalIn: CGRect(x: 92, y: 54, width: 52, height: 18)).fill()

            // Cool horizon reflection band
            UIColor(red: 0.82, green: 0.92, blue: 1.0, alpha: 0.65).setFill()
            UIBezierPath(roundedRect: CGRect(x: 10, y: 66, width: 236, height: 10), cornerRadius: 5).fill()
        }
    }

    private static func makeRibbonGradientTexture(top: UIColor, bottom: UIColor) -> UIImage {
        let size = CGSize(width: 64, height: 128)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
    }

    // MARK: - High-Res Front Artwork & PBR Metalness/Roughness Maps

    private static func makeFrontTextures(for status: WayMilestoneProgress.Status, resolution: CGFloat) -> (diffuse: UIImage, metalness: UIImage, roughness: UIImage) {
        let size = CGSize(width: resolution, height: resolution)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        let ms = status.milestone
        let isReached = status.isReached
        let palette = ms.uiMetal
        let center = CGPoint(x: resolution / 2, y: resolution / 2)
        let outerR = resolution * 0.486
        let sceneR = resolution * 0.372

        // Helper for centered rosette path in UIKit coordinates
        func uiRosette(r: CGFloat) -> UIBezierPath {
            let p = UIBezierPath()
            let pts = 20
            let steps = pts * 6
            for i in 0...steps {
                let a = Double(i) / Double(steps) * 2.0 * Double.pi
                let wave = 1.0 - cos(Double(pts) * a)
                let rr = r * (1.0 - 0.042 * CGFloat(wave) / 2.0)
                let pt = CGPoint(x: center.x + rr * CGFloat(cos(a)), y: center.y + rr * CGFloat(sin(a)))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.close()
            return p
        }

        func uiBanner(in rect: CGRect) -> UIBezierPath {
            let w = rect.width
            let h = rect.height
            let ox = rect.minX
            let oy = rect.minY
            let tail = w * 0.12
            let notch = tail * 0.45
            let lift = h * 0.18
            let p = UIBezierPath()

            p.move(to: CGPoint(x: ox + tail, y: oy + lift))
            p.addQuadCurve(to: CGPoint(x: ox + w - tail, y: oy + lift), controlPoint: CGPoint(x: ox + w / 2, y: oy - lift * 0.6))
            p.addLine(to: CGPoint(x: ox + w - tail, y: oy + h - lift))
            p.addQuadCurve(to: CGPoint(x: ox + tail, y: oy + h - lift), controlPoint: CGPoint(x: ox + w / 2, y: oy + h - lift * 1.9))
            p.close()

            for side in [0, 1] {
                let x0: CGFloat = side == 0 ? ox : ox + w
                let x1: CGFloat = side == 0 ? ox + tail * 1.2 : ox + w - tail * 1.2
                let xn: CGFloat = side == 0 ? ox + notch : ox + w - notch
                p.move(to: CGPoint(x: x1, y: oy + lift * 1.8))
                p.addLine(to: CGPoint(x: x0, y: oy + lift * 1.8))
                p.addLine(to: CGPoint(x: xn, y: oy + (h + lift * 0.8) / 2 + lift * 0.5))
                p.addLine(to: CGPoint(x: x0, y: oy + h - lift * 0.2))
                p.addLine(to: CGPoint(x: x1, y: oy + h - lift * 0.2))
                p.close()
            }
            return p
        }

        let bannerRect = CGRect(
            x: center.x - resolution * 0.45,
            y: center.y + resolution * 0.145,
            width: resolution * 0.90,
            height: resolution * 0.21
        )
        let rosettePath = uiRosette(r: outerR)
        let sceneRect = CGRect(x: center.x - sceneR, y: center.y - sceneR, width: sceneR * 2, height: sceneR * 2)
        let bannerPath = uiBanner(in: bannerRect)

        // 1) Diffuse Artwork
        let diffuse = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()

            // Outer metallic rosette
            cg.saveGState()
            rosettePath.addClip()
            if isReached {
                let rimColors = [palette.light.cgColor, palette.mid.cgColor, palette.dark.cgColor, palette.light.cgColor] as CFArray
                if let g = CGGradient(colorsSpace: space, colors: rimColors, locations: [0, 0.35, 0.72, 1]) {
                    cg.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: resolution, y: resolution), options: [])
                }
            } else {
                UIColor(white: 0.76, alpha: 1).setFill()
                cg.fill(CGRect(origin: .zero, size: size))
            }
            cg.restoreGState()

            // Subtle radial brushed lines on rim
            cg.saveGState()
            rosettePath.addClip()
            cg.setStrokeColor(UIColor.white.withAlphaComponent(isReached ? 0.16 : 0.08).cgColor)
            cg.setLineWidth(1.0)
            for i in 0..<72 {
                let a = CGFloat(i) / 72.0 * .pi * 2
                cg.move(to: CGPoint(x: center.x + sceneR * cos(a), y: center.y + sceneR * sin(a)))
                cg.addLine(to: CGPoint(x: center.x + outerR * cos(a), y: center.y + outerR * sin(a)))
            }
            cg.strokePath()
            cg.restoreGState()

            // Painted Enamel Center Scene
            cg.saveGState()
            let sceneClip = UIBezierPath(ovalIn: sceneRect)
            sceneClip.addClip()
            drawCGMedalScene(in: cg, rect: sceneRect, kind: ms.kind, tier: ms.tier, isReached: isReached)
            // Glossy enamel dome highlight
            let glossColors = [UIColor.white.withAlphaComponent(0.32).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: space, colors: glossColors, locations: [0, 1]) {
                cg.drawLinearGradient(
                    g,
                    start: CGPoint(x: sceneRect.midX, y: sceneRect.minY),
                    end: CGPoint(x: sceneRect.midX, y: sceneRect.midY + sceneR * 0.15),
                    options: []
                )
            }
            cg.restoreGState()

            // Progress arc if unreached
            if !isReached && status.fraction > 0 {
                let arc = UIBezierPath(
                    arcCenter: center,
                    radius: sceneR + resolution * 0.012,
                    startAngle: -.pi / 2,
                    endAngle: -.pi / 2 + CGFloat(min(1, status.fraction)) * .pi * 2,
                    clockwise: true
                )
                arc.lineWidth = resolution * 0.042
                arc.lineCapStyle = .round
                ms.kind.uiColors.dark.setStroke()
                arc.stroke()
            }

            // Embossed Stars at top of enamel face
            let starCount = min(ms.tier + 1, 5)
            let starSpacing = resolution * 0.068
            let startX = center.x - CGFloat(starCount - 1) * starSpacing / 2
            for idx in 0..<starCount {
                let isMid = (idx == starCount / 2)
                let starR = resolution * (isMid ? 0.036 : 0.028)
                let sy = center.y - sceneR * 0.78 + abs(CGFloat(idx) - CGFloat(starCount - 1) / 2) * resolution * 0.016
                let starPt = CGPoint(x: startX + CGFloat(idx) * starSpacing, y: sy)
                let starPath = makeStarBezierPath(center: starPt, outerRadius: starR, innerRadius: starR * 0.46)
                cg.saveGState()
                cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor.black.withAlphaComponent(0.35).cgColor)
                (isReached ? UIColor.white : UIColor(white: 0.75, alpha: 0.7)).setFill()
                starPath.fill()
                cg.restoreGState()
            }

            // Metallic Scroll Banner
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 5), blur: 8, color: UIColor.black.withAlphaComponent(0.30).cgColor)
            (isReached ? palette.mid : UIColor(white: 0.85, alpha: 1)).setFill()
            bannerPath.fill()
            cg.restoreGState()

            cg.saveGState()
            bannerPath.addClip()
            if isReached {
                let bColors = [UIColor.white.withAlphaComponent(0.92).cgColor, palette.light.cgColor, palette.mid.cgColor, palette.dark.cgColor] as CFArray
                if let g = CGGradient(colorsSpace: space, colors: bColors, locations: [0, 0.28, 0.7, 1]) {
                    cg.drawLinearGradient(g, start: CGPoint(x: bannerRect.midX, y: bannerRect.minY), end: CGPoint(x: bannerRect.midX, y: bannerRect.maxY), options: [])
                }
            }
            cg.restoreGState()

            UIColor.white.withAlphaComponent(isReached ? 0.75 : 0.3).setStroke()
            bannerPath.lineWidth = 2.0
            bannerPath.stroke()

            // Engraved Banner Number + Unit
            let numFont = UIFont.systemFont(ofSize: resolution * 0.135, weight: .black)
            let unitFont = UIFont.systemFont(ofSize: resolution * 0.058, weight: .heavy)
            let textColor = isReached ? UIColor(white: 0.16, alpha: 0.90) : UIColor(white: 0.45, alpha: 1)

            let attr = NSMutableAttributedString(
                string: ms.badgeNumber,
                attributes: [.font: numFont, .foregroundColor: textColor]
            )
            attr.append(NSAttributedString(
                string: " " + ms.kind.badgeUnit,
                attributes: [.font: unitFont, .foregroundColor: textColor.withAlphaComponent(0.82)]
            ))
            let textSize = attr.size()
            let maxW = bannerRect.width * 0.64
            let scale = min(1.0, maxW / max(1, textSize.width))
            cg.saveGState()
            cg.translateBy(x: bannerRect.midX, y: bannerRect.midY - resolution * 0.015)
            cg.scaleBy(x: scale, y: scale)
            attr.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2))
            cg.restoreGState()
        }

        // 2) PBR Metalness Map (White = pure metal, Dark = enamel glass)
        let metalness = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor(white: isReached ? 0.92 : 0.40, alpha: 1).setFill()
            rosettePath.fill()
            UIColor(white: 0.08, alpha: 1).setFill()
            UIBezierPath(ovalIn: sceneRect).fill()
            UIColor(white: isReached ? 0.90 : 0.35, alpha: 1).setFill()
            bannerPath.fill()
        }

        // 3) PBR Roughness Map (Darker = glossier specular reflection)
        let roughness = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor(white: isReached ? 0.22 : 0.55, alpha: 1).setFill()
            rosettePath.fill()
            UIColor(white: isReached ? 0.12 : 0.50, alpha: 1).setFill()
            UIBezierPath(ovalIn: sceneRect).fill()
            UIColor(white: isReached ? 0.20 : 0.55, alpha: 1).setFill()
            bannerPath.fill()
        }

        return (diffuse, metalness, roughness)
    }

    // MARK: - Engraved Brushed-Metal Coin Back Texture

    private static func makeBackEngravedTexture(for status: WayMilestoneProgress.Status, resolution: CGFloat) -> UIImage {
        let size = CGSize(width: resolution, height: resolution)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let ms = status.milestone
        let isReached = status.isReached
        let palette = ms.uiMetal
        let center = CGPoint(x: resolution / 2, y: resolution / 2)
        let outerR = resolution * 0.486

        let rosette = UIBezierPath()
        let pts = 20
        let steps = pts * 6
        for i in 0...steps {
            let a = Double(i) / Double(steps) * 2.0 * Double.pi
            let wave = 1.0 - cos(Double(pts) * a)
            let rr = outerR * (1.0 - 0.042 * CGFloat(wave) / 2.0)
            let pt = CGPoint(x: center.x + rr * CGFloat(cos(a)), y: center.y + rr * CGFloat(sin(a)))
            if i == 0 { rosette.move(to: pt) } else { rosette.addLine(to: pt) }
        }
        rosette.close()

        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()

            cg.saveGState()
            rosette.addClip()
            if isReached {
                let colors = [palette.light.cgColor, palette.mid.cgColor, palette.dark.cgColor, palette.mid.cgColor] as CFArray
                if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.35, 0.78, 1]) {
                    cg.drawLinearGradient(g, start: .zero, end: CGPoint(x: resolution, y: resolution), options: [])
                }
            } else {
                UIColor(white: 0.70, alpha: 1).setFill()
                cg.fill(CGRect(origin: .zero, size: size))
            }

            // Concentric brushed-metal lathe circles
            for r in stride(from: resolution * 0.08, through: outerR, by: 6) {
                let ring = UIBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                UIColor.white.withAlphaComponent(0.06).setStroke()
                ring.lineWidth = 1.0
                ring.stroke()
            }

            // Engraved inner decorative rings
            let engraveColor = isReached ? palette.dark.withAlphaComponent(0.85) : UIColor(white: 0.38, alpha: 0.8)
            for ringR in [resolution * 0.34, resolution * 0.31] {
                let ring = UIBezierPath(ovalIn: CGRect(x: center.x - ringR, y: center.y - ringR, width: ringR * 2, height: ringR * 2))
                engraveColor.setStroke()
                ring.lineWidth = ringR > resolution * 0.32 ? 2.5 : 1.2
                ring.stroke()
            }

            // Top brand engraving
            let pStyle = NSMutableParagraphStyle()
            pStyle.alignment = .center

            let brandAttr = NSAttributedString(
                string: "漫迹 · 里程碑",
                attributes: [
                    .font: UIFont.systemFont(ofSize: resolution * 0.044, weight: .bold),
                    .foregroundColor: engraveColor,
                    .paragraphStyle: pStyle
                ]
            )
            brandAttr.draw(in: CGRect(x: center.x - 160, y: center.y - resolution * 0.20, width: 320, height: 34))

            // Center engraved milestone number
            let bigAttr = NSAttributedString(
                string: "\(ms.badgeNumber) \(ms.kind.badgeUnit)",
                attributes: [
                    .font: UIFont.systemFont(ofSize: resolution * 0.11, weight: .black),
                    .foregroundColor: isReached ? UIColor(white: 0.16, alpha: 0.85) : UIColor(white: 0.35, alpha: 0.9),
                    .paragraphStyle: pStyle
                ]
            )
            bigAttr.draw(in: CGRect(x: center.x - 180, y: center.y - resolution * 0.065, width: 360, height: 80))

            // Bottom engraved date or remaining
            let subText = status.date.map { WayMilestoneFormatters.string(from: $0) + " 达成" } ?? status.remaining
            let subAttr = NSAttributedString(
                string: subText,
                attributes: [
                    .font: UIFont.systemFont(ofSize: resolution * 0.044, weight: .semibold),
                    .foregroundColor: engraveColor,
                    .paragraphStyle: pStyle
                ]
            )
            subAttr.draw(in: CGRect(x: center.x - 160, y: center.y + resolution * 0.11, width: 320, height: 36))

            cg.restoreGState()
        }
    }

    private static func makeStarBezierPath(center: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat) -> UIBezierPath {
        let p = UIBezierPath()
        for i in 0..<10 {
            let r = (i % 2 == 0) ? outerRadius : innerRadius
            let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let pt = CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.close()
        return p
    }

    // CoreGraphics mirror of WayMedalSceneView for crisp 512px PBR front texture
    private static func drawCGMedalScene(in cg: CGContext, rect: CGRect, kind: WayMilestone.Kind, tier: Int, isReached: Bool) {
        let s = rect.width
        let ox = rect.minX
        let oy = rect.minY
        let space = CGColorSpaceCreateDeviceRGB()

        let skyPair = WayMedalSceneView.uiSky(kind, tier: tier)
        let skyColors = isReached
            ? [skyPair.0.cgColor, skyPair.1.cgColor] as CFArray
            : [UIColor(white: 0.72, alpha: 1).cgColor, UIColor(white: 0.86, alpha: 1).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: skyColors, locations: [0, 1]) {
            cg.drawLinearGradient(g, start: CGPoint(x: ox, y: oy), end: CGPoint(x: ox, y: oy + s), options: [])
        }

        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> UIColor {
            if isReached { return UIColor(red: r, green: g, blue: b, alpha: a) }
            let luma = 0.299 * r + 0.587 * g + 0.114 * b
            return UIColor(white: luma * 0.75 + 0.2, alpha: a * 0.75)
        }

        switch kind {
        case .distance:
            UIColor.white.withAlphaComponent(0.9).setFill()
            UIBezierPath(ovalIn: CGRect(x: ox + 0.62 * s, y: oy + 0.20 * s, width: 0.18 * s, height: 0.18 * s)).fill()

            let far = UIBezierPath()
            far.move(to: pt(0, 0.56))
            far.addQuadCurve(to: pt(0.55, 0.52), controlPoint: pt(0.25, 0.40))
            far.addQuadCurve(to: pt(1, 0.50), controlPoint: pt(0.80, 0.42))
            far.addLine(to: pt(1, 1))
            far.addLine(to: pt(0, 1))
            far.close()
            color(0.45, 0.78, 0.55).setFill()
            far.fill()

            let near = UIBezierPath()
            near.move(to: pt(0, 0.66))
            near.addQuadCurve(to: pt(1, 0.62), controlPoint: pt(0.50, 0.54))
            near.addLine(to: pt(1, 1))
            near.addLine(to: pt(0, 1))
            near.close()
            color(0.24, 0.60, 0.40).setFill()
            near.fill()

            let road = UIBezierPath()
            road.move(to: pt(0.47, 0.56))
            road.addLine(to: pt(0.53, 0.56))
            road.addQuadCurve(to: pt(0.78, 1), controlPoint: pt(0.50, 0.78))
            road.addLine(to: pt(0.22, 1))
            road.addQuadCurve(to: pt(0.47, 0.56), controlPoint: pt(0.42, 0.78))
            road.close()
            color(0.28, 0.28, 0.28).setFill()
            road.fill()

            let dash = UIBezierPath()
            dash.move(to: pt(0.50, 0.58))
            dash.addQuadCurve(to: pt(0.50, 1), controlPoint: pt(0.47, 0.80))
            dash.lineWidth = s * 0.018
            dash.setLineDash([s * 0.04, s * 0.035], count: 2, phase: 0)
            UIColor.white.withAlphaComponent(0.9).setStroke()
            dash.stroke()

        case .countries:
            let gRect = CGRect(x: ox + 0.12 * s, y: oy + 0.50 * s, width: 0.76 * s, height: 0.76 * s)
            let gPath = UIBezierPath(ovalIn: gRect)
            cg.saveGState()
            gPath.addClip()
            let gColors = [color(0.40, 0.75, 1.0).cgColor, color(0.10, 0.40, 0.80).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: space, colors: gColors, locations: [0, 1]) {
                cg.drawLinearGradient(g, start: pt(0.5, 0.5), end: pt(0.5, 1.0), options: [])
            }
            color(0.40, 0.80, 0.50).setFill()
            UIBezierPath(ovalIn: CGRect(x: ox + 0.25 * s, y: oy + 0.60 * s, width: 0.22 * s, height: 0.12 * s)).fill()
            UIBezierPath(ovalIn: CGRect(x: ox + 0.52 * s, y: oy + 0.66 * s, width: 0.20 * s, height: 0.16 * s)).fill()
            UIBezierPath(ovalIn: CGRect(x: ox + 0.36 * s, y: oy + 0.78 * s, width: 0.14 * s, height: 0.10 * s)).fill()
            cg.restoreGState()

            let arc = UIBezierPath()
            arc.move(to: pt(0.20, 0.58))
            arc.addQuadCurve(to: pt(0.68, 0.33), controlPoint: pt(0.30, 0.20))
            arc.lineWidth = s * 0.014
            arc.setLineDash([s * 0.025, s * 0.025], count: 2, phase: 0)
            UIColor.white.setStroke()
            arc.stroke()

        case .provinces:
            UIColor.white.withAlphaComponent(0.85).setFill()
            UIBezierPath(ovalIn: CGRect(x: ox + 0.18 * s, y: oy + 0.20 * s, width: 0.16 * s, height: 0.16 * s)).fill()
            func range(_ peaks: [(CGFloat, CGFloat)], base: CGFloat, c: UIColor) {
                let p = UIBezierPath()
                p.move(to: pt(0, base))
                for pk in peaks { p.addLine(to: pt(pk.0, pk.1)) }
                p.addLine(to: pt(1, base))
                p.addLine(to: pt(1, 1))
                p.addLine(to: pt(0, 1))
                p.close()
                c.setFill()
                p.fill()
            }
            range([(0.20, 0.50), (0.35, 0.58), (0.60, 0.42), (0.85, 0.55)], base: 0.60, c: color(0.98, 0.72, 0.55))
            range([(0.15, 0.62), (0.42, 0.34), (0.58, 0.52), (0.78, 0.46)], base: 0.70, c: color(0.75, 0.35, 0.30))
            let snow = UIBezierPath()
            snow.move(to: pt(0.42, 0.34))
            snow.addLine(to: pt(0.50, 0.43))
            snow.addLine(to: pt(0.45, 0.41))
            snow.addLine(to: pt(0.41, 0.45))
            snow.addLine(to: pt(0.37, 0.41))
            snow.addLine(to: pt(0.35, 0.42))
            snow.close()
            UIColor.white.setFill()
            snow.fill()
            range([(0.30, 0.70), (0.55, 0.78), (0.80, 0.66)], base: 0.82, c: color(0.45, 0.18, 0.25))

        case .cities:
            color(1.0, 0.92, 0.60).setFill()
            UIBezierPath(ovalIn: CGRect(x: ox + 0.60 * s, y: oy + 0.12 * s, width: 0.20 * s, height: 0.20 * s)).fill()
            color(0.18, 0.13, 0.43).setFill()
            UIBezierPath(ovalIn: CGRect(x: ox + 0.66 * s, y: oy + 0.09 * s, width: 0.20 * s, height: 0.20 * s)).fill()

            let buildings: [(CGFloat, CGFloat, CGFloat)] = [
                (0.0, 0.62, 0.16), (0.14, 0.48, 0.14), (0.27, 0.56, 0.12), (0.38, 0.36, 0.13),
                (0.50, 0.52, 0.12), (0.61, 0.42, 0.15), (0.75, 0.58, 0.12), (0.86, 0.50, 0.14)
            ]
            let bColor = color(0.16, 0.12, 0.38)
            let wColor = color(1.0, 0.85, 0.45, 0.9)
            for (bx, top, bw) in buildings {
                bColor.setFill()
                cg.fill(CGRect(x: ox + bx * s, y: oy + top * s, width: bw * s, height: (1 - top) * s))
                wColor.setFill()
                var row = top + 0.06
                while row < 0.95 {
                    var col = bx + 0.025
                    while col < bx + bw - 0.03 {
                        if Int((col + row) * 100) % 3 != 0 {
                            cg.fill(CGRect(x: ox + col * s, y: oy + row * s, width: 0.025 * s, height: 0.03 * s))
                        }
                        col += 0.045
                    }
                    row += 0.065
                }
            }

        case .days:
            let sunRect = CGRect(x: ox + 0.27 * s, y: oy + 0.39 * s, width: 0.46 * s, height: 0.46 * s)
            cg.saveGState()
            UIBezierPath(ovalIn: sunRect).addClip()
            let sColors = [color(1.0, 0.95, 0.60).cgColor, color(1.0, 0.65, 0.30).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: space, colors: sColors, locations: [0, 1]) {
                cg.drawLinearGradient(g, start: pt(0.5, 0.39), end: pt(0.5, 0.75), options: [])
            }
            cg.restoreGState()

            let seaRect = CGRect(x: ox, y: oy + 0.64 * s, width: s, height: 0.36 * s)
            cg.saveGState()
            cg.clip(to: seaRect)
            let seaColors = [color(0.10, 0.55, 0.62).cgColor, color(0.03, 0.32, 0.42).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: space, colors: seaColors, locations: [0, 1]) {
                cg.drawLinearGradient(g, start: pt(0, 0.64), end: pt(0, 1), options: [])
            }
            cg.restoreGState()

            color(1.0, 0.85, 0.50, 0.75).setFill()
            for (ry, rw) in [(0.69, 0.40), (0.75, 0.28), (0.81, 0.18)] as [(CGFloat, CGFloat)] {
                UIBezierPath(roundedRect: CGRect(x: ox + (0.5 - rw / 2) * s, y: oy + ry * s, width: rw * s, height: 0.018 * s), cornerRadius: s * 0.01).fill()
            }
        }
    }
}

// MARK: - Medal Detail Half-Sheet (Locked Half-Screen + 60fps 3D Metallic Medal)

struct WayMilestoneDetailSheet: View {
    let status: WayMilestoneProgress.Status
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                if status.isReached {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [status.milestone.kind.colors[0].opacity(0.24), .clear],
                                center: .center,
                                startRadius: 16,
                                endRadius: 112
                            )
                        )
                        .frame(width: 224, height: 224)
                        .allowsHitTesting(false)
                }

                WayMedal3DSceneView(status: status)
                    .frame(width: 230, height: 230)
            }
            .padding(.top, 14)

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
                Label("\(WayMilestoneFormatters.string(from: date)) 达成", systemImage: "checkmark.seal.fill")
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

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WaySheetMediumEnforcer().allowsHitTesting(false))
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
}
