import SwiftUI
import MapKit
import CoreLocation
import Photos
import UIKit

// MARK: - 1. 旅人画像 (1:1 Original PortraitScene + PortraitView, iOS 16 Compatible)

struct WayTravellerPortrait {
    enum Archetype: String, CaseIterable {
        case nightWalker, earlyRiser, cityCollector, globetrotter, explorer, homebody, rider, wanderer, commuter, slowWalker

        var title: String {
            switch self {
            case .nightWalker: return "夜行的散步者"
            case .earlyRiser: return "早起的人"
            case .cityCollector: return "城市收藏家"
            case .globetrotter: return "世界旅人"
            case .explorer: return "好奇的探索者"
            case .homebody: return "恋家的人"
            case .rider: return "风一样的骑行者"
            case .wanderer: return "用双脚丈量的人"
            case .commuter: return "城市的通勤者"
            case .slowWalker: return "慢慢走的人"
            }
        }

        var symbol: String {
            switch self {
            case .nightWalker: return "moon.stars.fill"
            case .earlyRiser: return "sunrise.fill"
            case .cityCollector: return "building.2.crop.circle.fill"
            case .globetrotter: return "globe.asia.australia.fill"
            case .explorer: return "binoculars.fill"
            case .homebody: return "house.fill"
            case .rider: return "bicycle"
            case .wanderer: return "figure.walk"
            case .commuter: return "tram.fill"
            case .slowWalker: return "leaf.fill"
            }
        }
    }

    var night: Double = 0
    var early: Double = 0
    var onFoot: Double = 0
    var cycling: Double = 0
    var riding: Double = 0
    var newPlaces: Double = 0
    var atHome: Double = 0
    var cities: Int = 0
    var countries: Int = 0
    var distance: Double = 0

    var ranked: [Archetype] {
        let scores: [(Archetype, Double)] = [
            (.nightWalker, night / 0.3),
            (.earlyRiser, early / 0.2),
            (.cityCollector, Double(cities) / 15.0),
            (.globetrotter, Double(countries) / 8.0),
            (.explorer, newPlaces / 0.4),
            (.homebody, atHome / 0.7),
            (.rider, cycling / 0.3),
            (.wanderer, onFoot / 0.5),
            (.commuter, riding / 0.65)
        ]
        let fitting = scores.filter { $0.1 >= 1.0 }.sorted { $0.1 > $1.1 }.map(\.0)
        return fitting.isEmpty ? [.slowWalker] : fitting
    }

    var archetype: Archetype { ranked[0] }
    var traits: [Archetype] { Array(ranked.dropFirst().prefix(2)) }

    var reason: String {
        func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
        switch archetype {
        case .nightWalker: return "过去一年 \(pct(night)) 的路，是晚上九点以后走的。"
        case .earlyRiser: return "过去一年 \(pct(early)) 的路，是早上八点以前走的。"
        case .cityCollector: return "过去一年去了 \(cities) 座城市，每一座都留下了你的名字。"
        case .globetrotter: return "过去一年走过 \(countries) 个国家和地区，世界在你脚下变小了。"
        case .explorer: return "最近三个月去的地方，\(pct(newPlaces)) 是第一次去。"
        case .homebody: return "最近三个月，\(pct(atHome)) 的时间在家。家是最好的地方。"
        case .rider: return "过去一年 \(pct(cycling)) 的路是骑车走的，风一直在你身边。"
        case .wanderer: return "过去一年 \(pct(onFoot)) 的路是一步一步走出来的。"
        case .commuter: return "过去一年 \(pct(riding)) 的路在车上和地铁里，城市在窗外流过。"
        case .slowWalker: return "不急不忙，每一段路都慢慢走。"
        }
    }

    static func build(stays: [Stay], chunks: [TrackChunk], privacyZones: [PrivacyZone]) -> WayTravellerPortrait {
        let now = Date()
        let cal = Calendar.current
        let yearAgo = now.addingTimeInterval(-365 * 86_400)
        let ground = chunks.filter { $0.startDate >= yearAgo && $0.mode != .flying }
        let total = ground.reduce(0.0) { $0 + $1.distance }

        var p = WayTravellerPortrait()
        p.distance = total
        if total > 0 {
            func share(_ include: (TrackChunk) -> Bool) -> Double {
                ground.filter(include).reduce(0.0) { $0 + $1.distance } / total
            }
            p.night = share {
                let h = cal.component(.hour, from: $0.startDate)
                return h >= 21 || h < 4
            }
            p.early = share {
                let h = cal.component(.hour, from: $0.startDate)
                return h >= 4 && h < 8
            }
            p.onFoot = share { $0.mode == .walking || $0.mode == .running }
            p.cycling = share { $0.mode == .cycling }
            p.riding = share { $0.mode == .automotive || $0.mode == .subway }
        }

        let yearStays = stays.filter { $0.arrival >= yearAgo }
        p.cities = Set(yearStays.compactMap(\.city).filter { !$0.isEmpty }).count
        p.countries = Set(yearStays.compactMap(\.countryCode).filter { !$0.isEmpty }).count

        let homeLoc: CLLocation? = {
            if let h = stays.first(where: { $0.category == .home }) { return h.location }
            if let z = privacyZones.first { return z.location }
            return nil
        }()

        let quarterAgo = now.addingTimeInterval(-90 * 86_400)
        let recent = stays.filter { $0.arrival >= quarterAgo && !$0.isFromPhotos }
        if !recent.isEmpty {
            func cell(_ s: Stay) -> Int64 {
                Int64((s.latitude / 0.002).rounded(.down)) &* 1_000_003 &+ Int64((s.longitude / 0.002).rounded(.down))
            }
            let before = Set(stays.filter { $0.arrival < quarterAgo }.map(cell))
            if !before.isEmpty {
                let places = Set(recent.map(cell))
                p.newPlaces = Double(places.subtracting(before).count) / Double(max(1, places.count))
            }
            if let homeLoc {
                let totalTime = recent.reduce(0.0) { $0 + min($1.duration, 3 * 86_400) }
                let homeTime = recent.filter { $0.location.distance(from: homeLoc) < 250 }
                    .reduce(0.0) { $0 + min($1.duration, 3 * 86_400) }
                p.atHome = totalTime > 0 ? homeTime / totalTime : 0
            }
        }
        return p
    }
}

/// 1:1 Original PortraitScene (all 10 illustrated scenes, split helpers for fast compilation)
struct WayPortraitSceneView: View {
    let archetype: WayTravellerPortrait.Archetype

    var body: some View {
        Canvas { context, size in
            drawScene(in: context, size: size)
        }
    }

    private func drawScene(in context: GraphicsContext, size: CGSize) {
        switch archetype {
        case .cityCollector: drawCityCollector(in: context, size: size)
        case .nightWalker: drawNightWalker(in: context, size: size)
        case .earlyRiser: drawEarlyRiser(in: context, size: size)
        case .globetrotter: drawGlobetrotter(in: context, size: size)
        case .explorer: drawExplorer(in: context, size: size)
        case .homebody: drawHomebody(in: context, size: size)
        case .rider: drawRider(in: context, size: size)
        case .wanderer: drawWanderer(in: context, size: size)
        case .commuter: drawCommuter(in: context, size: size)
        case .slowWalker: drawSlowWalker(in: context, size: size)
        }
        drawGrain(in: context, size: size)
    }

    private func drawSky(in context: GraphicsContext, size: CGSize, top: Color, bottom: Color) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
        )
    }

    private func drawStars(in context: GraphicsContext, size: CGSize, count: Int, below: CGFloat, seed: UInt64 = 7) {
        var x = seed
        for _ in 0..<count {
            x = x &* 6364136223846793005 &+ 1442695040888963407
            let px = CGFloat(x >> 33 % 1000) / 1000.0
            x = x &* 6364136223846793005 &+ 1442695040888963407
            let py = CGFloat(x >> 33 % 1000) / 1000.0 * below
            let r = (CGFloat(x >> 40 % 3) + 1.0) * 0.6
            context.fill(Path(ellipseIn: CGRect(x: px * size.width, y: py * size.height, width: r, height: r)), with: .color(.white.opacity(0.75)))
        }
    }

    private func drawGlow(in context: GraphicsContext, at pt: CGPoint, radius: CGFloat, color: Color) {
        context.fill(
            Path(ellipseIn: CGRect(x: pt.x - radius, y: pt.y - radius, width: radius * 2, height: radius * 2)),
            with: .radialGradient(Gradient(colors: [color, color.opacity(0)]), center: pt, startRadius: 0, endRadius: radius)
        )
    }

    private func drawHills(in context: GraphicsContext, size: CGSize, base: CGFloat, amp: CGFloat, phase: CGFloat, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        for i in 0...40 {
            let x = CGFloat(i) / 40.0
            let y = base - amp * (sin(x * 5.0 + phase) * 0.6 + sin(x * 11.0 + phase * 2.0) * 0.4)
            path.addLine(to: CGPoint(x: x * size.width, y: y * size.height))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }

    private func drawSkyline(in context: GraphicsContext, size: CGSize, buildings: [(CGFloat, CGFloat, CGFloat)], base: CGFloat, fill: Color, windows: Color?) {
        let w = size.width, h = size.height
        for (bx, bw, btop) in buildings {
            context.fill(Path(CGRect(x: bx * w, y: btop * h, width: bw * w, height: (base - btop + 0.01) * h)), with: .color(fill))
            guard let windows else { continue }
            var row = btop + 0.025
            var n = Int(bx * 100)
            while row < base - 0.02 {
                var col = bx + 0.012
                while col < bx + bw - 0.015 {
                    n = (n &* 1103515245 &+ 12345) & 0x7fffffff
                    if n % 3 != 0 {
                        context.fill(Path(CGRect(x: col * w, y: row * h, width: 0.008 * w, height: 0.012 * h)), with: .color(windows.opacity(0.85)))
                    }
                    col += 0.018
                }
                row += 0.028
            }
        }
        context.fill(Path(CGRect(x: 0, y: base * h, width: w, height: (1.0 - base) * h)), with: .color(fill))
    }

    private func drawCityCollector(in context: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        drawSky(in: context, size: size, top: Color(red: 0.24, green: 0.2, blue: 0.55), bottom: Color(red: 0.95, green: 0.62, blue: 0.62))
        drawStars(in: context, size: size, count: 25, below: 0.3)
        drawGlow(in: context, at: CGPoint(x: 0.5 * w, y: 0.62 * h), radius: w * 0.45, color: Color(red: 1, green: 0.72, blue: 0.6).opacity(0.6))

        drawSkyline(
            in: context, size: size,
            buildings: [(0.05, 0.06, 0.3), (0.12, 0.04, 0.38), (0.18, 0.07, 0.24), (0.27, 0.05, 0.34), (0.66, 0.06, 0.28), (0.74, 0.05, 0.36), (0.82, 0.07, 0.3)],
            base: 0.62, fill: Color(red: 0.55, green: 0.42, blue: 0.75).opacity(0.7), windows: nil
        )

        let pagodas: [(CGFloat, CGFloat)] = [(0.42, 0.4), (0.55, 0.45)]
        for (px, top) in pagodas {
            for tier in 0..<4 {
                let t = CGFloat(tier)
                let rw = 0.10 - t * 0.018
                let y = top + 0.20 - t * 0.055
                var roof = Path()
                roof.move(to: CGPoint(x: (px - rw / 2.0 - 0.015) * w, y: y * h))
                roof.addQuadCurve(to: CGPoint(x: (px + rw / 2.0 + 0.015) * w, y: y * h), control: CGPoint(x: px * w, y: (y - 0.03) * h))
                roof.addLine(to: CGPoint(x: (px + rw / 2.0) * w, y: (y + 0.04) * h))
                roof.addLine(to: CGPoint(x: (px - rw / 2.0) * w, y: (y + 0.04) * h))
                roof.closeSubpath()
                context.fill(roof, with: .color(Color(red: 0.42, green: 0.26, blue: 0.55)))
            }
        }

        drawSkyline(
            in: context, size: size,
            buildings: [(0, 0.14, 0.7), (0.12, 0.1, 0.64), (0.3, 0.16, 0.72), (0.58, 0.12, 0.66), (0.7, 0.14, 0.7), (0.85, 0.15, 0.62)],
            base: 0.80, fill: Color(red: 0.24, green: 0.15, blue: 0.38), windows: Color(red: 1, green: 0.85, blue: 0.55)
        )
        context.fill(Path(ellipseIn: CGRect(x: 0.43 * w, y: 0.66 * h, width: 0.14 * w, height: 0.14 * w)), with: .color(Color(red: 0.24, green: 0.15, blue: 0.38)))

        let pins: [(CGFloat, CGFloat)] = [(0.15, 0.2), (0.49, 0.3), (0.8, 0.22)]
        for (px, py) in pins {
            var pin = Path()
            pin.addEllipse(in: CGRect(x: px * w - 7, y: py * h - 7, width: 14, height: 14))
            pin.move(to: CGPoint(x: px * w - 5, y: py * h + 4))
            pin.addLine(to: CGPoint(x: px * w, y: py * h + 13))
            pin.addLine(to: CGPoint(x: px * w + 5, y: py * h + 4))
            context.fill(pin, with: .color(Color(red: 1, green: 0.84, blue: 0.4)))
            context.fill(Path(ellipseIn: CGRect(x: px * w - 3, y: py * h - 3, width: 6, height: 6)), with: .color(Color(red: 0.4, green: 0.2, blue: 0.5)))
        }
    }

    private func drawNightWalker(in context: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        drawSky(in: context, size: size, top: Color(red: 0.06, green: 0.07, blue: 0.2), bottom: Color(red: 0.28, green: 0.2, blue: 0.45))
        drawStars(in: context, size: size, count: 60, below: 0.55)
        drawGlow(in: context, at: CGPoint(x: 0.78 * w, y: 0.2 * h), radius: w * 0.16, color: Color(red: 1, green: 0.95, blue: 0.75).opacity(0.35))
        context.fill(Path(ellipseIn: CGRect(x: 0.72 * w, y: 0.13 * h, width: 0.12 * w, height: 0.12 * w)), with: .color(Color(red: 1, green: 0.94, blue: 0.72)))
        context.fill(Path(ellipseIn: CGRect(x: 0.755 * w, y: 0.115 * h, width: 0.12 * w, height: 0.12 * w)), with: .color(Color(red: 0.12, green: 0.11, blue: 0.28)))
        drawSkyline(
            in: context, size: size,
            buildings: [(0, 0.12, 0.5), (0.1, 0.08, 0.42), (0.17, 0.1, 0.55), (0.3, 0.07, 0.38), (0.36, 0.12, 0.5), (0.5, 0.09, 0.45), (0.58, 0.13, 0.36), (0.72, 0.1, 0.5), (0.83, 0.17, 0.44)],
            base: 0.72, fill: Color(red: 0.1, green: 0.09, blue: 0.22), windows: Color(red: 1, green: 0.82, blue: 0.45)
        )
        for lx in [0.18, 0.46, 0.74] as [CGFloat] {
            var post = Path()
            post.move(to: CGPoint(x: lx * w, y: 0.98 * h))
            post.addLine(to: CGPoint(x: lx * w, y: 0.8 * h))
            context.stroke(post, with: .color(Color(red: 0.05, green: 0.05, blue: 0.12)), lineWidth: 2)
            drawGlow(in: context, at: CGPoint(x: lx * w, y: 0.8 * h), radius: w * 0.07, color: Color(red: 1, green: 0.8, blue: 0.45).opacity(0.7))
        }
    }

    private func drawEarlyRiser(in context: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        drawSky(in: context, size: size, top: Color(red: 0.98, green: 0.62, blue: 0.48), bottom: Color(red: 1, green: 0.88, blue: 0.62))
        drawGlow(in: context, at: CGPoint(x: 0.5 * w, y: 0.66 * h), radius: w * 0.5, color: Color(red: 1, green: 0.96, blue: 0.8).opacity(0.7))
        context.fill(Path(ellipseIn: CGRect(x: 0.36 * w, y: 0.52 * h, width: 0.28 * w, height: 0.28 * w)), with: .color(Color(red: 1, green: 0.96, blue: 0.82)))
        drawHills(in: context, size: size, base: 0.72, amp: 0.04, phase: 0.5, color: Color(red: 0.93, green: 0.55, blue: 0.45))
        drawHills(in: context, size: size, base: 0.82, amp: 0.05, phase: 2.0, color: Color(red: 0.78, green: 0.38, blue: 0.38))
        drawHills(in: context, size: size, base: 0.92, amp: 0.03, phase: 3.5, color: Color(red: 0.55, green: 0.24, blue: 0.3))
    }

    private func drawGlobetrotter(in context: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        drawSky(in: context, size: size, top: Color(red: 0.03, green: 0.2, blue: 0.45), bottom: Color(red: 0.3, green: 0.62, blue: 0.9))
        drawStars(in: context, size: size, count: 30, below: 0.4)
        let globe = CGRect(x: -0.15 * w, y: 0.55 * h, width: 1.3 * w, height: 1.3 * w)
        drawGlow(in: context, at: CGPoint(x: 0.5 * w, y: 0.6 * h), radius: w * 0.6, color: Color(red: 0.6, green: 0.85, blue: 1).opacity(0.5))
        context.fill(
            Path(ellipseIn: globe),
            with: .linearGradient(Gradient(colors: [Color(red: 0.2, green: 0.55, blue: 0.85), Color(red: 0.05, green: 0.25, blue: 0.55)]),
                                  startPoint: CGPoint(x: 0.5 * w, y: 0.55 * h), endPoint: CGPoint(x: 0.5 * w, y: h))
        )
        var arc = Path()
        arc.move(to: CGPoint(x: 0.12 * w, y: 0.62 * h))
        arc.addQuadCurve(to: CGPoint(x: 0.82 * w, y: 0.58 * h), control: CGPoint(x: 0.47 * w, y: 0.3 * h))
        context.stroke(arc, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [4, 5]))
    }

    private func drawExplorer(in context: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        drawSky(in: context, size: size, top: Color(red: 0.2, green: 0.5, blue: 0.55), bottom: Color(red: 0.86, green: 0.9, blue: 0.75))
        context.fill(Path(ellipseIn: CGRect(x: 0.12 * w, y: 0.14 * h, width: 0.1 * w, height: 0.1 * w)), with: .color(.white.opacity(0.9)))
        var mt = Path()
        mt.move(to: CGPoint(x: 0, y: 0.6 * h))
        for (px, py) in [(0.15, 0.5), (0.32, 0.38), (0.5, 0.52), (0.7, 0.3), (0.9, 0.48)] as [(CGFloat, CGFloat)] {
            mt.addLine(to: CGPoint(x: px * w, y: py * h))
        }
        mt.addLine(to: CGPoint(x: w, y: 0.6 * h))
        mt.addLine(to: CGPoint(x: w, y: h))
        mt.addLine(to: CGPoint(x: 0, y: h))
        mt.closeSubpath()
        context.fill(mt, with: .color(Color(red: 0.45, green: 0.62, blue: 0.6)))
        drawHills(in: context, size: size, base: 0.68, amp: 0.05, phase: 1.0, color: Color(red: 0.25, green: 0.5, blue: 0.42))
        drawHills(in: context, size: size, base: 0.82, amp: 0.04, phase: 3.0, color: Color(red: 0.12, green: 0.36, blue: 0.3))
    }

    private func drawHomebody(in context: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        drawSky(in: context, size: size, top: Color(red: 0.3, green: 0.18, blue: 0.4), bottom: Color(red: 0.95, green: 0.6, blue: 0.5))
        drawStars(in: context, size: size, count: 25, below: 0.35)
        drawHills(in: context, size: size, base: 0.74, amp: 0.05, phase: 1.5, color: Color(red: 0.45, green: 0.25, blue: 0.4))
        drawGlow(in: context, at: CGPoint(x: 0.5 * w, y: 0.64 * h), radius: w * 0.35, color: Color(red: 1, green: 0.8, blue: 0.5).opacity(0.45))
        context.fill(Path(CGRect(x: 0.38 * w, y: 0.52 * h, width: 0.24 * w, height: 0.22 * h)), with: .color(Color(red: 0.32, green: 0.17, blue: 0.3)))
        var roof = Path()
        roof.move(to: CGPoint(x: 0.34 * w, y: 0.53 * h))
        roof.addLine(to: CGPoint(x: 0.5 * w, y: 0.4 * h))
        roof.addLine(to: CGPoint(x: 0.66 * w, y: 0.53 * h))
        roof.closeSubpath()
        context.fill(roof, with: .color(Color(red: 0.25, green: 0.12, blue: 0.24)))
        context.fill(Path(CGRect(x: 0.42 * w, y: 0.57 * h, width: 0.06 * w, height: 0.06 * h)), with: .color(Color(red: 1, green: 0.84, blue: 0.5)))
        context.fill(Path(CGRect(x: 0.52 * w, y: 0.57 * h, width: 0.06 * w, height: 0.06 * h)), with: .color(Color(red: 1, green: 0.84, blue: 0.5)))
        drawHills(in: context, size: size, base: 0.86, amp: 0.03, phase: 4.0, color: Color(red: 0.28, green: 0.13, blue: 0.26))
    }

    private func drawRider(in context: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        drawSky(in: context, size: size, top: Color(red: 0.0, green: 0.55, blue: 0.62), bottom: Color(red: 0.75, green: 0.95, blue: 0.88))
        context.fill(Path(ellipseIn: CGRect(x: 0.7 * w, y: 0.16 * h, width: 0.14 * w, height: 0.14 * w)), with: .color(Color(red: 1, green: 0.98, blue: 0.85)))
        drawHills(in: context, size: size, base: 0.6, amp: 0.05, phase: 0.2, color: Color(red: 0.4, green: 0.75, blue: 0.6))
        drawHills(in: context, size: size, base: 0.7, amp: 0.03, phase: 2.0, color: Color(red: 0.2, green: 0.55, blue: 0.45))
        var road = Path()
        road.move(to: CGPoint(x: 0.47 * w, y: 0.6 * h))
        road.addLine(to: CGPoint(x: 0.53 * w, y: 0.6 * h))
        road.addLine(to: CGPoint(x: 0.85 * w, y: h))
        road.addLine(to: CGPoint(x: 0.15 * w, y: h))
        road.closeSubpath()
        context.fill(road, with: .color(Color(red: 0.25, green: 0.3, blue: 0.33)))
    }

    private func drawWanderer(in context: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        drawSky(in: context, size: size, top: Color(red: 0.55, green: 0.78, blue: 0.95), bottom: Color(red: 0.95, green: 0.95, blue: 0.82))
        context.fill(Path(ellipseIn: CGRect(x: 0.15 * w, y: 0.15 * h, width: 0.12 * w, height: 0.12 * w)), with: .color(Color(red: 1, green: 0.95, blue: 0.7)))
        drawHills(in: context, size: size, base: 0.58, amp: 0.05, phase: 0.4, color: Color(red: 0.55, green: 0.78, blue: 0.5))
        drawHills(in: context, size: size, base: 0.70, amp: 0.06, phase: 1.8, color: Color(red: 0.35, green: 0.65, blue: 0.38))
        drawHills(in: context, size: size, base: 0.84, amp: 0.04, phase: 3.1, color: Color(red: 0.20, green: 0.50, blue: 0.28))
    }

    private func drawCommuter(in context: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        drawSky(in: context, size: size, top: Color(red: 0.1, green: 0.16, blue: 0.36), bottom: Color(red: 0.4, green: 0.55, blue: 0.85))
        drawStars(in: context, size: size, count: 20, below: 0.3)
        drawSkyline(
            in: context, size: size,
            buildings: [(0, 0.1, 0.35), (0.12, 0.08, 0.28), (0.22, 0.12, 0.4), (0.4, 0.09, 0.3), (0.52, 0.13, 0.38), (0.7, 0.1, 0.26), (0.84, 0.16, 0.36)],
            base: 0.62, fill: Color(red: 0.16, green: 0.22, blue: 0.42), windows: Color(red: 0.75, green: 0.85, blue: 1)
        )
        context.fill(Path(CGRect(x: 0, y: 0.66 * h, width: w, height: 0.025 * h)), with: .color(Color(red: 0.1, green: 0.13, blue: 0.28)))
        context.fill(Path(roundedRect: CGRect(x: 0.18 * w, y: 0.565 * h, width: 0.62 * w, height: 0.09 * h), cornerRadius: 8), with: .color(Color(red: 0.92, green: 0.94, blue: 0.98)))
        context.fill(Path(CGRect(x: 0.18 * w, y: 0.635 * h, width: 0.62 * w, height: 0.012 * h)), with: .color(Color(red: 0.25, green: 0.5, blue: 0.95)))
    }

    private func drawSlowWalker(in context: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        drawSky(in: context, size: size, top: Color(red: 0.62, green: 0.72, blue: 0.55), bottom: Color(red: 0.96, green: 0.92, blue: 0.78))
        context.fill(Path(ellipseIn: CGRect(x: 0.66 * w, y: 0.16 * h, width: 0.13 * w, height: 0.13 * w)), with: .color(.white.opacity(0.85)))
        drawHills(in: context, size: size, base: 0.66, amp: 0.05, phase: 1.0, color: Color(red: 0.5, green: 0.62, blue: 0.42))
        drawHills(in: context, size: size, base: 0.80, amp: 0.04, phase: 2.5, color: Color(red: 0.36, green: 0.48, blue: 0.3))
    }

    private func drawGrain(in context: GraphicsContext, size: CGSize) {
        var n: UInt64 = 99
        let count = min(800, Int(size.width * size.height / 200))
        let maxW = UInt64(max(size.width, 1))
        let maxH = UInt64(max(size.height, 1))
        for _ in 0..<count {
            n = n &* 6364136223846793005 &+ 1442695040888963407
            let x = CGFloat(n >> 33 % maxW)
            n = n &* 6364136223846793005 &+ 1442695040888963407
            let y = CGFloat(n >> 33 % maxH)
            context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.white.opacity(0.06)))
        }
    }
}

struct WayPortraitFaceView: View {
    let portrait: WayTravellerPortrait
    var large: Bool = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            WayPortraitSceneView(archetype: portrait.archetype)
            LinearGradient(
                stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.62), location: 1.0)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: large ? 10 : 7) {
                Text("旅人画像 · 过去一年")
                    .font(.caption.weight(.semibold))
                    .tracking(2)
                    .opacity(0.85)
                Spacer(minLength: 0)
                Text("过去一年，你是")
                    .font(.subheadline.weight(.medium))
                    .opacity(0.85)
                Text(portrait.archetype.title)
                    .font(.system(size: large ? 40 : 32, weight: .bold, design: .serif))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                Text(portrait.reason)
                    .font(large ? .callout : .footnote)
                    .opacity(0.92)
                    .fixedSize(horizontal: false, vertical: true)
                if !portrait.traits.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(portrait.traits, id: \.self) { trait in
                            Label(trait.title, systemImage: trait.symbol)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.18), in: Capsule())
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 2)
                }
            }
            .foregroundColor(.white)
            .padding(large ? 24 : 20)
        }
        .frame(height: large ? 450 : 330)
        .clipShape(RoundedRectangle(cornerRadius: large ? 32 : 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: large ? 32 : 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

struct WayPortraitCardView: View {
    let portrait: WayTravellerPortrait
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            WayPortraitFaceView(portrait: portrait, large: false)
        }
        .buttonStyle(PressableStyle())
        .sheet(isPresented: $showing) {
            WayPortraitDetailSheet(portrait: portrait)
        }
    }
}

struct WayPortraitDetailSheet: View {
    let portrait: WayTravellerPortrait
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false
    @State private var shareItem: StoriesShareImage?

    private func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    WayPortraitFaceView(portrait: portrait, large: true)
                        .scaleEffect(appeared ? 1 : 0.94)
                        .opacity(appeared ? 1 : 0)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("你的过去一年")
                            .font(.system(.title3, design: .serif).weight(.bold))

                        HStack(spacing: 12) {
                            skyTile(
                                title: "夜里九点以后",
                                value: portrait.night,
                                symbol: "moon.stars.fill",
                                colors: [Color(red: 0.1, green: 0.1, blue: 0.3), Color(red: 0.35, green: 0.25, blue: 0.6)],
                                ink: .white
                            )
                            skyTile(
                                title: "早上八点以前",
                                value: portrait.early,
                                symbol: "sunrise.fill",
                                colors: [Color(red: 0.98, green: 0.55, blue: 0.4), Color(red: 1, green: 0.82, blue: 0.55)],
                                ink: Color(red: 0.4, green: 0.16, blue: 0.1)
                            )
                        }

                        modesTile

                        HStack(spacing: 12) {
                            ringTile(title: "新去的地方", detail: "最近三个月", value: portrait.newPlaces, tint: .mint, symbol: "binoculars.fill")
                            ringTile(title: "在家的时间", detail: "最近三个月", value: portrait.atHome, tint: .pink, symbol: "house.fill")
                        }

                        HStack(spacing: 12) {
                            numberTile(value: portrait.cities, unit: "座城市", symbol: "building.2.fill", tint: .indigo)
                            numberTile(value: portrait.countries, unit: "个国家和地区", symbol: "globe.asia.australia.fill", tint: .blue)
                        }
                    }

                    Text("画像根据过去一年的轨迹和地点算出，只在你的手机上计算。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("旅人画像")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { sharePortrait() } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(item: $shareItem) { item in
                StoriesActivityShareSheet(items: [item.image])
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) { appeared = true }
        }
    }

    @MainActor
    private func sharePortrait() {
        let content = WayPortraitFaceView(portrait: portrait, large: true)
            .frame(width: 360)
            .padding(20)
            .background(Color.black)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        if let img = renderer.uiImage {
            shareItem = StoriesShareImage(image: img)
        }
    }

    private func skyTile(title: String, value: Double, symbol: String, colors: [Color], ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.title2)
            Spacer(minLength: 8)
            Text(pct(value))
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text(title).font(.caption.weight(.semibold)).opacity(0.85)
            Text("的路").font(.caption2).opacity(0.7)
        }
        .foregroundColor(ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 156)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var modesTile: some View {
        let parts: [(String, Double, Color, String)] = [
            ("步行", portrait.onFoot, .green, "figure.walk"),
            ("骑行", portrait.cycling, .teal, "bicycle"),
            ("乘车和地铁", portrait.riding, .blue, "tram.fill")
        ]
        return VStack(alignment: .leading, spacing: 12) {
            Text("怎么走的").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        if part.1 > 0.005 {
                            Capsule()
                                .fill(part.2)
                                .frame(width: max(8, (geo.size.width - 8) * CGFloat(appeared ? part.1 : 0.33)))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 14)
            HStack(spacing: 16) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(part.0, systemImage: part.3).font(.caption).foregroundColor(part.2)
                        Text(pct(part.1)).font(.system(.headline, design: .rounded)).monospacedDigit()
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func ringTile(title: String, detail: String, value: Double, tint: Color, symbol: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(tint.opacity(0.16), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(appeared ? min(1, value) : 0))
                    .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Image(systemName: symbol).font(.caption).foregroundColor(tint)
                    Text(pct(value)).font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
                }
            }
            .frame(width: 92, height: 92)
            VStack(spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func numberTile(value: Int, unit: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3).foregroundColor(.white)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint))
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)").font(.system(size: 28, weight: .bold, design: .rounded))
                Text(unit).font(.caption).foregroundColor(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - 2. 丝绸之路 / 虚拟旅程 (1:1 Original JourneyCard + JourneyView + Satellite Map)

struct WayClassicRoute: Identifiable, Hashable {
    struct Stop: Hashable {
        let name: String
        let latitude: Double
        let longitude: Double
        let note: String
        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    }

    enum Scenery { case water, peaks, dunes, mesas }

    let id: String
    let name: String
    let tint: Color
    let sky: [Color]
    let scenery: Scenery
    let stops: [Stop]

    var marks: [Double] {
        var total = 0.0
        return stops.indices.map { i in
            if i > 0 {
                total += CLLocation(latitude: stops[i - 1].latitude, longitude: stops[i - 1].longitude)
                    .distance(from: CLLocation(latitude: stops[i].latitude, longitude: stops[i].longitude))
            }
            return total
        }
    }

    var length: Double { marks.last ?? 0 }

    func path(upTo distance: Double) -> [CLLocationCoordinate2D] {
        let m = marks
        var pts = [stops[0].coordinate]
        for i in 1..<stops.count {
            if m[i] <= distance {
                pts.append(stops[i].coordinate)
            } else {
                let t = (distance - m[i - 1]) / max(m[i] - m[i - 1], 1)
                let a = stops[i - 1], b = stops[i]
                pts.append(CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                                  longitude: a.longitude + (b.longitude - a.longitude) * t))
                break
            }
        }
        return pts
    }

    func layout(aspect: CGFloat, margin: CGFloat = 0.12) -> [CGPoint] {
        let midLat = stops.map(\.latitude).reduce(0, +) / Double(stops.count)
        let raw = stops.map { CGPoint(x: $0.longitude * cos(midLat * .pi / 180), y: -$0.latitude) }
        let minX = raw.map(\.x).min()!, maxX = raw.map(\.x).max()!, minY = raw.map(\.y).min()!, maxY = raw.map(\.y).max()!
        let spanX = max(maxX - minX, 0.01), spanY = max(maxY - minY, 0.01)
        let fitX = (1 - 2 * margin) / spanX, fitY = (1 - 2 * margin) * aspect / spanY
        let scale = min(fitX, fitY)
        let scaleY = min(fitY, scale * 5)
        let offX = (1 - spanX * scale) / 2, offY = (1 - spanY * scaleY / aspect) / 2 + margin * 0.5
        return raw.map { CGPoint(x: offX + ($0.x - minX) * scale, y: offY + ($0.y - minY) * scaleY / aspect) }
    }

    static let all: [WayClassicRoute] = [canal, highway318, silkRoad, route66]

    static func choose(id: String, distance: Double) -> WayClassicRoute {
        if let found = all.first(where: { $0.id == id }) { return found }
        let order: [WayClassicRoute] = [canal, highway318, route66].sorted { $0.length < $1.length } + [silkRoad]
        return order.first { $0.length > distance } ?? silkRoad
    }

    static let canal = WayClassicRoute(
        id: "canal", name: "京杭大运河", tint: .teal,
        sky: [Color(red: 0.12, green: 0.3, blue: 0.38), Color(red: 0.42, green: 0.64, blue: 0.64)],
        scenery: .water,
        stops: [
            Stop(name: "杭州", latitude: 30.27, longitude: 120.16, note: "运河的南端，拱宸桥下船来船往了几百年。"),
            Stop(name: "嘉兴", latitude: 30.75, longitude: 120.76, note: "南湖烟雨，一船红色的历史。"),
            Stop(name: "苏州", latitude: 31.30, longitude: 120.59, note: "枫桥夜泊，园林里藏着整个江南。"),
            Stop(name: "无锡", latitude: 31.49, longitude: 120.31, note: "太湖边的清名桥，运河人家枕水而居。"),
            Stop(name: "常州", latitude: 31.81, longitude: 119.97, note: "老城门外，运河穿城而过。"),
            Stop(name: "镇江", latitude: 32.19, longitude: 119.43, note: "运河在这里与长江相遇。"),
            Stop(name: "扬州", latitude: 32.39, longitude: 119.41, note: "烟花三月下扬州，瘦西湖最温柔。"),
            Stop(name: "淮安", latitude: 33.61, longitude: 119.02, note: "南船北马的分界，漕运总督曾在这里。"),
            Stop(name: "徐州", latitude: 34.26, longitude: 117.18, note: "五省通衢，楚汉故地。"),
            Stop(name: "济宁", latitude: 35.41, longitude: 116.59, note: "运河之都，离孔子的家乡很近。"),
            Stop(name: "聊城", latitude: 36.46, longitude: 115.99, note: "江北水城，光岳楼守着东昌湖。"),
            Stop(name: "德州", latitude: 37.44, longitude: 116.36, note: "九达天衢，扒鸡的香味飘了几百年。"),
            Stop(name: "沧州", latitude: 38.30, longitude: 116.84, note: "武术之乡，铁狮子还在。"),
            Stop(name: "天津", latitude: 39.13, longitude: 117.20, note: "三岔河口，九河下梢。"),
            Stop(name: "北京通州", latitude: 39.91, longitude: 116.66, note: "运河的北端，燃灯塔下，一路走到了终点。")
        ]
    )

    static let highway318 = WayClassicRoute(
        id: "318", name: "318 国道", tint: .orange,
        sky: [Color(red: 0.16, green: 0.18, blue: 0.4), Color(red: 0.93, green: 0.55, blue: 0.38)],
        scenery: .peaks,
        stops: [
            Stop(name: "上海", latitude: 31.23, longitude: 121.47, note: "零公里，从人民广场出发。"),
            Stop(name: "宣城", latitude: 30.94, longitude: 118.76, note: "宣纸的故乡，敬亭山相看两不厌。"),
            Stop(name: "武汉", latitude: 30.59, longitude: 114.31, note: "过长江，黄鹤楼上看江城。"),
            Stop(name: "宜昌", latitude: 30.69, longitude: 111.29, note: "三峡的门口，江水从这里变得开阔。"),
            Stop(name: "重庆", latitude: 29.56, longitude: 106.55, note: "山城，路在楼顶，轻轨穿楼。"),
            Stop(name: "成都", latitude: 30.57, longitude: 104.07, note: "川藏线从这里真正开始。"),
            Stop(name: "雅安", latitude: 29.98, longitude: 103.01, note: "雨城，进藏前最后的温柔。"),
            Stop(name: "康定", latitude: 30.05, longitude: 101.96, note: "跑马溜溜的山上，折多山在等你。"),
            Stop(name: "理塘", latitude: 30.00, longitude: 100.27, note: "世界高城，天空近得伸手可及。"),
            Stop(name: "巴塘", latitude: 30.00, longitude: 99.10, note: "金沙江畔，过江就是西藏。"),
            Stop(name: "芒康", latitude: 29.68, longitude: 98.59, note: "进藏第一站，盐井的盐田在澜沧江边。"),
            Stop(name: "八宿", latitude: 30.05, longitude: 96.92, note: "怒江七十二拐，一圈一圈绕下去。"),
            Stop(name: "然乌", latitude: 29.50, longitude: 96.77, note: "然乌湖倒映着雪山。"),
            Stop(name: "波密", latitude: 29.86, longitude: 95.77, note: "冰川和森林，西藏的江南。"),
            Stop(name: "林芝", latitude: 29.65, longitude: 94.36, note: "春天桃花开满雅鲁藏布江。"),
            Stop(name: "拉萨", latitude: 29.65, longitude: 91.13, note: "布达拉宫就在眼前。你走到了日光城。")
        ]
    )

    static let silkRoad = WayClassicRoute(
        id: "silk", name: "丝绸之路", tint: Color(red: 0.65, green: 0.48, blue: 0.35),
        sky: [Color(red: 0.5, green: 0.28, blue: 0.16), Color(red: 0.95, green: 0.76, blue: 0.47)],
        scenery: .dunes,
        stops: [
            Stop(name: "西安", latitude: 34.34, longitude: 108.94, note: "长安，驼队从这里出发。"),
            Stop(name: "天水", latitude: 34.58, longitude: 105.72, note: "麦积山的佛像看了一千多年的路人。"),
            Stop(name: "兰州", latitude: 36.06, longitude: 103.83, note: "黄河穿城，一碗牛肉面。"),
            Stop(name: "武威", latitude: 37.93, longitude: 102.64, note: "马踏飞燕从这里出土。"),
            Stop(name: "张掖", latitude: 38.93, longitude: 100.45, note: "七彩丹霞，像打翻了颜料。"),
            Stop(name: "酒泉", latitude: 39.73, longitude: 98.49, note: "嘉峪关，长城的西端。"),
            Stop(name: "敦煌", latitude: 40.14, longitude: 94.66, note: "莫高窟和鸣沙山，月牙泉在沙里。"),
            Stop(name: "吐鲁番", latitude: 42.95, longitude: 89.19, note: "火焰山下，葡萄沟里很凉快。"),
            Stop(name: "乌鲁木齐", latitude: 43.83, longitude: 87.62, note: "离海最远的城市。"),
            Stop(name: "喀什", latitude: 39.47, longitude: 75.99, note: "古城的巷子里，馕坑冒着热气。"),
            Stop(name: "撒马尔罕", latitude: 39.65, longitude: 66.96, note: "雷吉斯坦广场的蓝色穹顶。"),
            Stop(name: "布哈拉", latitude: 39.77, longitude: 64.42, note: "两千年的老城，驼队在这里歇脚。"),
            Stop(name: "德黑兰", latitude: 35.69, longitude: 51.39, note: "厄尔布尔士山下的波斯。"),
            Stop(name: "巴格达", latitude: 33.31, longitude: 44.36, note: "一千零一夜的故乡。"),
            Stop(name: "大马士革", latitude: 33.51, longitude: 36.29, note: "世界上最古老的城市之一。"),
            Stop(name: "伊斯坦布尔", latitude: 41.01, longitude: 28.98, note: "欧亚之间，博斯普鲁斯海峡。"),
            Stop(name: "罗马", latitude: 41.90, longitude: 12.50, note: "条条大路通罗马，丝绸到了终点。")
        ]
    )

    static let route66 = WayClassicRoute(
        id: "66", name: "66 号公路", tint: .red,
        sky: [Color(red: 0.32, green: 0.11, blue: 0.24), Color(red: 0.97, green: 0.5, blue: 0.32)],
        scenery: .mesas,
        stops: [
            Stop(name: "芝加哥", latitude: 41.88, longitude: -87.63, note: "起点牌就在密歇根湖边。"),
            Stop(name: "圣路易斯", latitude: 38.63, longitude: -90.20, note: "大拱门，西部的门户。"),
            Stop(name: "斯普林菲尔德", latitude: 37.21, longitude: -93.29, note: "66 号公路的诞生地。"),
            Stop(name: "塔尔萨", latitude: 36.15, longitude: -95.99, note: "霓虹和装饰艺术。"),
            Stop(name: "俄克拉何马城", latitude: 35.47, longitude: -97.52, note: "牛仔和草原。"),
            Stop(name: "阿马里洛", latitude: 35.22, longitude: -101.83, note: "凯迪拉克牧场，车尾插在地里。"),
            Stop(name: "阿尔伯克基", latitude: 35.08, longitude: -106.65, note: "热气球飞过沙漠。"),
            Stop(name: "弗拉格斯塔夫", latitude: 35.20, longitude: -111.65, note: "离大峡谷很近，星空很亮。"),
            Stop(name: "金曼", latitude: 35.19, longitude: -114.05, note: "公路最长的一段原样路面。"),
            Stop(name: "巴斯托", latitude: 34.90, longitude: -117.02, note: "莫哈韦沙漠的中转站。"),
            Stop(name: "洛杉矶", latitude: 34.05, longitude: -118.24, note: "天使之城就在眼前。"),
            Stop(name: "圣莫尼卡", latitude: 34.01, longitude: -118.50, note: "路的尽头是太平洋。你走完了。")
        ]
    )
}

struct WayJourneyProgress {
    let route: WayClassicRoute
    let travelled: Double

    var isComplete: Bool { travelled >= route.length }
    var shown: Double { min(travelled, route.length) }
    var fraction: Double { shown / max(route.length, 1) }
    var lastStopIndex: Int { route.marks.lastIndex { $0 <= shown } ?? 0 }
    var lastStop: WayClassicRoute.Stop { route.stops[lastStopIndex] }
    var nextStop: WayClassicRoute.Stop? { route.stops.indices.contains(lastStopIndex + 1) ? route.stops[lastStopIndex + 1] : nil }
    var toNext: Double { nextStop == nil ? 0 : route.marks[lastStopIndex + 1] - shown }

    var stationPosition: Double {
        guard nextStop != nil else { return Double(route.stops.count - 1) }
        let m = route.marks
        let from = m[lastStopIndex], to = m[lastStopIndex + 1]
        return Double(lastStopIndex) + (shown - from) / max(to - from, 1)
    }
}

/// 1:1 Original MetroLine & JourneyCard (Matches Screenshot 2)
struct WayJourneyCardView: View {
    let groundMeters: Double
    @AppStorage("wt16.journey.route") private var routeID = ""

    private func formatKm(_ m: Double) -> String {
        let km = Int((m / 1000.0).rounded())
        return NumberFormatter.localizedString(from: NSNumber(value: km), number: .decimal) + " 公里"
    }

    var body: some View {
        let route = WayClassicRoute.choose(id: routeID, distance: groundMeters)
        let progress = WayJourneyProgress(route: route, travelled: groundMeters)
        let tint = route.tint
        let pct = Int((progress.fraction * 100).rounded())

        NavigationLink {
            WayJourneyDetailView(groundMeters: groundMeters)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("你的里程能走多远")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Text(progress.isComplete ? "相当于走完了\(route.name)" : "相当于走到了\(progress.lastStop.name)")
                            .font(.system(.title2, design: .serif).weight(.bold))
                            .foregroundColor(.primary)
                        Text("沿着\(route.name)")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(tint)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(pct)%")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(tint)
                            .monospacedDigit()
                        Text("已走")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                WayMetroLineView(progress: progress)
                    .frame(height: 82)
                    .padding(.horizontal, -18)

                HStack {
                    Text("\(formatKm(progress.shown)) / \(formatKm(route.length))")
                        .monospacedDigit()
                    Spacer()
                    if let next = progress.nextStop {
                        Text("下一站\(next.name) · \(formatKm(progress.toNext))")
                    }
                }
                .font(.footnote)
                .foregroundColor(.secondary)

                Text("按地面里程换算，不是你实际到过的地方")
                    .font(.caption)
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(tint.opacity(0.14))
                            .frame(width: 220, height: 220)
                            .blur(radius: 50)
                            .offset(x: 60, y: -80)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        }
        .buttonStyle(PressableStyle())
    }
}

private struct WayMetroLineView: View {
    let progress: WayJourneyProgress
    var spacing: CGFloat = 68

    var body: some View {
        let stops = progress.route.stops
        let tint = progress.route.tint
        let totalW = spacing * CGFloat(max(1, stops.count - 1))
        let here = spacing * CGFloat(progress.stationPosition)

        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: totalW, height: 6)
                    .offset(y: 35)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, here), height: 6)
                    .offset(y: 35)

                ForEach(Array(stops.enumerated()), id: \.offset) { idx, stop in
                    let reached = idx <= progress.lastStopIndex
                    let isNext = idx == progress.lastStopIndex + 1 && !progress.isComplete
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(reached ? tint : Color(.systemBackground))
                            Circle()
                                .strokeBorder(reached ? Color.white : (isNext ? tint : Color.secondary.opacity(0.35)), lineWidth: reached ? 3.5 : (isNext ? 3 : 2))
                        }
                        .frame(width: 22, height: 22)
                        .shadow(color: reached ? tint.opacity(0.4) : .clear, radius: 4, y: 1)

                        Text(stop.name)
                            .font(.caption.weight(reached || isNext ? .semibold : .regular))
                            .foregroundColor(reached ? .primary : (isNext ? tint : .secondary))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: spacing)
                    .offset(x: spacing * CGFloat(idx) - spacing / 2, y: 27)
                }

                if !progress.isComplete {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(tint))
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .shadow(color: tint.opacity(0.5), radius: 6, y: 2)
                        .offset(x: here - 13, y: 0)
                }
            }
            .frame(width: totalW, height: 82, alignment: .topLeading)
            .padding(.horizontal, spacing / 2)
        }
    }
}

/// 1:1 Original Journey Detail Page (Screenshot 4)
struct WayJourneyDetailView: View {
    let groundMeters: Double
    @AppStorage("wt16.journey.route") private var routeID = ""

    private var route: WayClassicRoute { WayClassicRoute.choose(id: routeID, distance: groundMeters) }

    private func formatKm(_ m: Double) -> String {
        let km = Int((m / 1000.0).rounded())
        return NumberFormatter.localizedString(from: NSNumber(value: km), number: .decimal) + " 公里"
    }

    var body: some View {
        let progress = WayJourneyProgress(route: route, travelled: groundMeters)
        let pct = Int((progress.fraction * 100).rounded())

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ZStack(alignment: .topLeading) {
                    WayJourneySatelliteMapView(progress: progress)
                        .id(route.id)
                    LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 110)
                        .allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(route.name)
                            .font(.system(size: 26, weight: .bold, design: .serif))
                        Text("直线约 \(formatKm(route.length)) · \(route.stops.count) 站")
                            .font(.caption.weight(.medium))
                            .tracking(1)
                            .opacity(0.82)
                    }
                    .foregroundColor(.white)
                    .padding(20)
                    .allowsHitTesting(false)
                }
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                Text("这是一段虚拟旅程：你在地面上走过的路（不含飞行），按城市之间的直线距离铺在这条路上，不代表你真的到过这些地方。")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                HStack(spacing: 0) {
                    figureTile(formatKm(progress.shown), "已走")
                        .frame(maxWidth: .infinity)
                    Divider().frame(height: 34)
                    figureTile("\(pct)%", "完成")
                        .frame(width: 92)
                    Divider().frame(height: 34)
                    figureTile("\(progress.lastStopIndex + 1) / \(route.stops.count)", "相当于第几站")
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text("换一条路")
                        .font(.system(.title3, design: .serif).weight(.bold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(WayClassicRoute.all) { option in
                                Button {
                                    Haptics.selection()
                                    withAnimation(.easeInOut(duration: 0.2)) { routeID = option.id }
                                } label: {
                                    WayRoutePosterCard(route: option, travelled: groundMeters, selected: option.id == route.id)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                WayJourneyStopsList(progress: progress)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func figureTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
    }
}

private struct WayJourneySatelliteMapView: UIViewRepresentable {
    let progress: WayJourneyProgress

    func makeCoordinator() -> Coordinator { Coordinator(progress: progress) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType = .satellite
        map.showsCompass = true
        map.isPitchEnabled = false
        map.delegate = context.coordinator
        context.coordinator.attach(to: map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {}

    static func dismantleUIView(_ uiView: MKMapView, coordinator: Coordinator) {
        coordinator.stopAnimation()
    }

    final class JourneyRoutePoly: MKGeodesicPolyline {
        enum Style { case dashed, halo, walked, core }
        var style: Style = .walked
    }

    final class JourneyStopPin: NSObject, MKAnnotation {
        let index: Int
        let stop: WayClassicRoute.Stop
        var reached: Bool
        let showLabel: Bool
        dynamic var coordinate: CLLocationCoordinate2D
        var title: String? { showLabel ? stop.name : nil }
        init(index: Int, stop: WayClassicRoute.Stop, reached: Bool, showLabel: Bool) {
            self.index = index
            self.stop = stop
            self.reached = reached
            self.showLabel = showLabel
            self.coordinate = stop.coordinate
        }
    }

    final class JourneyWalkerPin: NSObject, MKAnnotation {
        dynamic var coordinate: CLLocationCoordinate2D
        init(coordinate: CLLocationCoordinate2D) {
            self.coordinate = coordinate
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let progress: WayJourneyProgress
        let tint: UIColor
        private weak var mapView: MKMapView?
        private var animTimer: Timer?
        private var stepIndex = 0
        private let totalSteps = 78 // ~2.6s at 30fps

        // Persistent CAShapeLayer route view (placed strictly BELOW annotation dots) + walker overlay (ABOVE dots)
        private var routeAnimView: UIView?
        private var walkerOverlayView: UIView?
        private var dashedLayer: CAShapeLayer?
        private var haloLayer: CAShapeLayer?
        private var mainLayer: CAShapeLayer?
        private var coreLayer: CAShapeLayer?
        private var walkerLayer: CALayer?

        private var fullGeoCoords: [CLLocationCoordinate2D] = []
        private var walkedGeoCoords: [CLLocationCoordinate2D] = []
        private var screenPoints: [CGPoint] = []
        private var screenCumLengths: [CGFloat] = []
        private var screenTotalLength: CGFloat = 0
        private var currentFraction: Double = 0
        private var framedMapRect: MKMapRect = .null
        private var animPrepared = false
        private var placedBelowAnnotations = false

        private var stopPins: [JourneyStopPin] = []
        private var highestLitIndex: Int = -1

        init(progress: WayJourneyProgress) {
            self.progress = progress
            self.tint = UIColor(progress.route.tint)
        }

        func stopAnimation() {
            animTimer?.invalidate()
            animTimer = nil
            routeAnimView?.removeFromSuperview()
            routeAnimView = nil
            walkerOverlayView?.removeFromSuperview()
            walkerOverlayView = nil
        }

        private static func sampleGeodesic(_ coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
            guard coords.count > 1 else { return coords }
            var copy = coords
            let poly = MKGeodesicPolyline(coordinates: &copy, count: copy.count)
            let count = poly.pointCount
            let ptr = poly.points()
            var result: [CLLocationCoordinate2D] = []
            result.reserveCapacity(count)
            for i in 0..<count {
                result.append(ptr[i].coordinate)
            }
            return result
        }

        func attach(to map: MKMapView) {
            self.mapView = map
            let route = progress.route
            fullGeoCoords = Self.sampleGeodesic(route.stops.map(\.coordinate))
            walkedGeoCoords = Self.sampleGeodesic(route.path(upTo: progress.shown))

            var rect = MKMapRect.null
            for s in route.stops {
                rect = rect.union(MKMapRect(origin: MKMapPoint(s.coordinate), size: MKMapSize(width: 0, height: 0)))
            }
            let pad = max(rect.width, rect.height) * 0.22
            let framed = MKMapRect(x: rect.minX - pad, y: rect.minY - pad * 1.9, width: rect.width + pad * 2, height: rect.height + pad * 2.8)
            framedMapRect = framed
            map.setVisibleMapRect(framed, animated: false)

            // Add all stop pins once in fixed order so labels never swap or flicker during animation
            let initialPins = route.stops.enumerated().map { idx, stop in
                JourneyStopPin(
                    index: idx,
                    stop: stop,
                    reached: idx == 0 && progress.shown >= 0,
                    showLabel: (idx == 0 || idx == route.stops.count - 1)
                )
            }
            stopPins = initialPins
            highestLitIndex = 0
            map.addAnnotations(initialPins)

            stepIndex = 0
            currentFraction = 0
            animPrepared = false
            placedBelowAnnotations = false
            animTimer?.invalidate()
            animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
                guard let self, let map = self.mapView else { timer.invalidate(); return }
                if !self.animPrepared {
                    guard map.bounds.width > 10 && map.bounds.height > 10 else { return }
                    self.prepareRouteLayers(on: map)
                }
                if !self.placedBelowAnnotations {
                    self.ensureRouteViewBelowAnnotations(on: map)
                }
                if self.walkedGeoCoords.count <= 1 {
                    timer.invalidate()
                    self.animTimer = nil
                    return
                }
                self.stepIndex += 1
                let raw = min(1.0, Double(self.stepIndex) / Double(self.totalSteps))
                let eased = raw * raw * (3.0 - 2.0 * raw)
                self.renderFrame(fraction: eased, on: map)
                if self.stepIndex >= self.totalSteps {
                    timer.invalidate()
                    self.animTimer = nil
                    self.finishAnimation(on: map)
                }
            }
        }

        private func findAnnotationContainer(in view: UIView) -> UIView? {
            if let existing = stopPins.compactMap({ mapView?.view(for: $0)?.superview }).first {
                return existing
            }
            for sub in view.subviews {
                if String(describing: type(of: sub)).contains("AnnotationContainer") {
                    return sub
                }
                if let found = findAnnotationContainer(in: sub) {
                    return found
                }
            }
            return nil
        }

        private func ensureRouteViewBelowAnnotations(on map: MKMapView) {
            guard let routeView = routeAnimView else { return }
            if let annContainer = findAnnotationContainer(in: map), let parent = annContainer.superview {
                if routeView.superview !== parent {
                    routeView.removeFromSuperview()
                    routeView.frame = parent.bounds
                    parent.insertSubview(routeView, belowSubview: annContainer)
                } else {
                    parent.insertSubview(routeView, belowSubview: annContainer)
                }
                placedBelowAnnotations = true
                rebuildPaths(on: map)
            }
        }

        private func prepareRouteLayers(on map: MKMapView) {
            animPrepared = true
            if !framedMapRect.isNull {
                map.setVisibleMapRect(framedMapRect, animated: false)
            }

            let routeView = UIView(frame: map.bounds)
            routeView.backgroundColor = .clear
            routeView.isUserInteractionEnabled = false
            routeView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            map.addSubview(routeView)
            routeAnimView = routeView

            let dashed = CAShapeLayer()
            dashed.fillColor = UIColor.clear.cgColor
            dashed.strokeColor = UIColor.white.withAlphaComponent(0.65).cgColor
            dashed.lineWidth = 2.0
            dashed.lineCap = .round
            dashed.lineJoin = .round
            dashed.lineDashPattern = [3, 6]
            routeView.layer.addSublayer(dashed)
            dashedLayer = dashed

            let halo = CAShapeLayer()
            halo.fillColor = UIColor.clear.cgColor
            halo.strokeColor = tint.withAlphaComponent(0.35).cgColor
            halo.lineWidth = 13
            halo.lineCap = .round
            halo.lineJoin = .round
            halo.strokeEnd = 0
            routeView.layer.addSublayer(halo)
            haloLayer = halo

            let main = CAShapeLayer()
            main.fillColor = UIColor.clear.cgColor
            main.strokeColor = tint.cgColor
            main.lineWidth = 4.6
            main.lineCap = .round
            main.lineJoin = .round
            main.strokeEnd = 0
            routeView.layer.addSublayer(main)
            mainLayer = main

            let core = CAShapeLayer()
            core.fillColor = UIColor.clear.cgColor
            core.strokeColor = UIColor.white.withAlphaComponent(0.85).cgColor
            core.lineWidth = 1.4
            core.lineCap = .round
            core.lineJoin = .round
            core.strokeEnd = 0
            routeView.layer.addSublayer(core)
            coreLayer = core

            // Separate walker overlay on top of map so the walking figure renders above stop dots
            let walkerView = UIView(frame: map.bounds)
            walkerView.backgroundColor = .clear
            walkerView.isUserInteractionEnabled = false
            walkerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            map.addSubview(walkerView)
            walkerOverlayView = walkerView

            let badgeImg = renderWalkerBadge()
            let wLayer = CALayer()
            wLayer.contents = badgeImg.cgImage
            wLayer.contentsScale = UIScreen.main.scale
            wLayer.bounds = CGRect(origin: .zero, size: badgeImg.size)
            walkerView.layer.addSublayer(wLayer)
            walkerLayer = wLayer

            ensureRouteViewBelowAnnotations(on: map)
            rebuildPaths(on: map)
        }

        private func rebuildPaths(on map: MKMapView) {
            guard let routeView = routeAnimView else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)

            if fullGeoCoords.count > 1 {
                let fullPath = UIBezierPath()
                for (i, coord) in fullGeoCoords.enumerated() {
                    let pt = map.convert(coord, toPointTo: routeView)
                    if i == 0 { fullPath.move(to: pt) } else { fullPath.addLine(to: pt) }
                }
                dashedLayer?.path = fullPath.cgPath
            }

            if walkedGeoCoords.count > 1 {
                var pts: [CGPoint] = []
                var cum: [CGFloat] = []
                pts.reserveCapacity(walkedGeoCoords.count)
                cum.reserveCapacity(walkedGeoCoords.count)
                var total: CGFloat = 0
                let bezier = UIBezierPath()
                for (i, coord) in walkedGeoCoords.enumerated() {
                    let p = map.convert(coord, toPointTo: routeView)
                    if i == 0 {
                        bezier.move(to: p)
                    } else {
                        let prev = pts[i - 1]
                        total += hypot(p.x - prev.x, p.y - prev.y)
                        bezier.addLine(to: p)
                    }
                    pts.append(p)
                    cum.append(total)
                }
                screenPoints = pts
                screenCumLengths = cum
                screenTotalLength = total

                let cgPath = bezier.cgPath
                haloLayer?.path = cgPath
                mainLayer?.path = cgPath
                coreLayer?.path = cgPath

                let f = CGFloat(currentFraction)
                haloLayer?.strokeEnd = f
                mainLayer?.strokeEnd = f
                coreLayer?.strokeEnd = f

                if let tipInRoute = screenPoint(at: currentFraction),
                   let walkerView = walkerOverlayView {
                    walkerLayer?.position = routeView.convert(tipInRoute, to: walkerView)
                }
            }
            CATransaction.commit()
        }

        private func screenPoint(at fraction: Double) -> CGPoint? {
            guard !screenPoints.isEmpty else { return nil }
            if fraction <= 0 { return screenPoints.first }
            if fraction >= 1 || screenTotalLength <= 0 { return screenPoints.last }
            let target = screenTotalLength * CGFloat(fraction)
            for i in 1..<screenCumLengths.count {
                if screenCumLengths[i] >= target {
                    let prevLen = screenCumLengths[i - 1]
                    let segLen = max(screenCumLengths[i] - prevLen, 0.0001)
                    let t = (target - prevLen) / segLen
                    let a = screenPoints[i - 1]
                    let b = screenPoints[i]
                    return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                }
            }
            return screenPoints.last
        }

        private func renderFrame(fraction: Double, on map: MKMapView) {
            currentFraction = fraction
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let f = CGFloat(fraction)
            haloLayer?.strokeEnd = f
            mainLayer?.strokeEnd = f
            coreLayer?.strokeEnd = f
            if let tipInRoute = screenPoint(at: fraction),
               let routeView = routeAnimView,
               let walkerView = walkerOverlayView {
                walkerLayer?.position = routeView.convert(tipInRoute, to: walkerView)
            }
            CATransaction.commit()

            // Light up stops strictly in sequential route order (0, 1, 2, ...) as the line reaches each stop
            let route = progress.route
            let drawnDistance = progress.shown * fraction
            let marks = route.marks
            var nextIdx = highestLitIndex + 1
            while nextIdx < stopPins.count && marks[nextIdx] <= drawnDistance + 1 {
                let pin = stopPins[nextIdx]
                pin.reached = true
                highestLitIndex = nextIdx
                if let view = map.view(for: pin) {
                    applyPinAppearance(view: view, pin: pin)
                    view.transform = CGAffineTransform(scaleX: 1.32, y: 1.32)
                    UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.65, initialSpringVelocity: 0.5, options: [.allowUserInteraction]) {
                        view.transform = .identity
                    }
                }
                nextIdx += 1
            }
        }

        private func finishAnimation(on map: MKMapView) {
            currentFraction = 1.0
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            haloLayer?.strokeEnd = 1.0
            mainLayer?.strokeEnd = 1.0
            coreLayer?.strokeEnd = 1.0
            CATransaction.commit()

            // Ensure all reached stops are lit
            let marks = progress.route.marks
            for idx in (highestLitIndex + 1)..<stopPins.count where marks[idx] <= progress.shown + 1 {
                let pin = stopPins[idx]
                pin.reached = true
                highestLitIndex = idx
                if let view = map.view(for: pin) {
                    applyPinAppearance(view: view, pin: pin)
                }
            }

            // Keep the glowing route line permanently visible; only fade out the walker badge when 100% complete
            if progress.isComplete, let walkerView = walkerOverlayView {
                UIView.animate(withDuration: 0.25, delay: 0.1, options: [.allowUserInteraction]) {
                    walkerView.alpha = 0
                } completion: { _ in
                    walkerView.removeFromSuperview()
                }
                walkerOverlayView = nil
                walkerLayer = nil
            }
        }

        private func isUserInteracting(with mapView: MKMapView) -> Bool {
            let allRecognizers = (mapView.gestureRecognizers ?? []) + mapView.subviews.flatMap { $0.gestureRecognizers ?? [] }
            return allRecognizers.contains { $0.state == .began || $0.state == .changed }
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if animTimer != nil && animPrepared && stepIndex > 3 && isUserInteracting(with: mapView) {
                animTimer?.invalidate()
                animTimer = nil
                finishAnimation(on: mapView)
            }
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            guard animPrepared else { return }
            rebuildPaths(on: mapView)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let walker = annotation as? JourneyWalkerPin {
                let id = "jWalkerPin"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: walker, reuseIdentifier: id)
                view.annotation = walker
                view.displayPriority = .required
                view.zPriority = .max
                view.image = renderWalkerBadge()
                return view
            }
            guard let pin = annotation as? JourneyStopPin else { return nil }
            let id = "jPin_\(pin.index)"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: pin, reuseIdentifier: id)
            view.annotation = pin
            view.displayPriority = .required
            applyPinAppearance(view: view, pin: pin)
            return view
        }

        private func applyPinAppearance(view: MKAnnotationView, pin: JourneyStopPin) {
            let label = pin.showLabel ? pin.stop.name : nil
            let rendered = renderDot(reached: pin.reached, label: label)
            view.image = rendered.image
            view.centerOffset = rendered.centerOffset
        }

        private func renderWalkerBadge() -> UIImage {
            let size: CGFloat = 28
            return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
                let rect = CGRect(x: 2, y: 2, width: size - 4, height: size - 4)
                let path = UIBezierPath(ovalIn: rect)
                tint.setFill()
                path.fill()
                UIColor.white.setStroke()
                path.lineWidth = 2.2
                path.stroke()
                if let sym = UIImage(systemName: "figure.walk", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                    let s = sym.size
                    sym.draw(in: CGRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
                }
            }
        }

        private func renderDot(reached: Bool, label: String?) -> (image: UIImage, centerOffset: CGPoint) {
            let dotSize: CGFloat = reached ? 14 : 9
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let textSize = label.map { ($0 as NSString).size(withAttributes: labelAttrs) } ?? .zero
            let dotAreaH = dotSize + 4
            let w = max(dotAreaH, textSize.width + 6)
            let h = dotAreaH + (label != nil ? textSize.height + 4 : 0)
            let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { _ in
                let dotRect = CGRect(x: (w - dotSize) / 2, y: 2, width: dotSize, height: dotSize)
                let path = UIBezierPath(ovalIn: dotRect)
                (reached ? tint : UIColor.white.withAlphaComponent(0.85)).setFill()
                path.fill()
                if reached {
                    UIColor.white.setStroke()
                    path.lineWidth = 2.2
                    path.stroke()
                }
                if let label {
                    (label as NSString).draw(
                        at: CGPoint(x: (w - textSize.width) / 2, y: dotSize + 5),
                        withAttributes: labelAttrs
                    )
                }
            }
            // Keep the dot center aligned with the exact map coordinate even when a label is drawn below it
            let offsetY = (h - dotAreaH) / 2
            return (img, CGPoint(x: 0, y: offsetY))
        }
    }
}

private struct WayRoutePosterCard: View {
    let route: WayClassicRoute
    let travelled: Double
    let selected: Bool

    var body: some View {
        let fraction = min(travelled / max(route.length, 1), 1.0)
        let points = route.layout(aspect: 150.0 / 70.0, margin: 0.1)
        let shape = WayRouteLineShape(points: points)
        let kmText = NumberFormatter.localizedString(from: NSNumber(value: Int((route.length / 1000.0).rounded())), number: .decimal)

        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                shape.stroke(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [2, 4]))
                shape.trim(from: 0, to: CGFloat(fraction))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    .shadow(color: .white.opacity(0.8), radius: 4)
                GeometryReader { geo in
                    if let first = points.first, let last = points.last {
                        Circle().fill(Color.white).frame(width: 6, height: 6)
                            .position(x: first.x * geo.size.width, y: first.y * geo.size.height)
                        Circle().fill(Color.white).frame(width: 6, height: 6)
                            .position(x: last.x * geo.size.width, y: last.y * geo.size.height)
                    }
                }
            }
            .frame(height: 70)
            .padding(.top, 14)
            .padding(.horizontal, 10)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 3) {
                Text(route.name)
                    .font(.system(.subheadline, design: .serif).weight(.bold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text("约 \(kmText) 公里")
                    Text("·")
                    if fraction >= 1.0 {
                        Image(systemName: "checkmark.seal.fill")
                    } else {
                        Text("\(Int((fraction * 100).rounded()))%")
                    }
                }
                .font(.caption2.weight(.semibold))
                .opacity(0.85)
            }
            .padding(12)
        }
        .foregroundColor(.white)
        .frame(width: 150, height: 170)
        .background {
            ZStack {
                LinearGradient(colors: route.sky, startPoint: .top, endPoint: .bottom)
                WayRouteSceneryView(scenery: route.scenery)
                LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(selected ? 0.95 : 0.12), lineWidth: selected ? 2.5 : 1)
        )
        .scaleEffect(selected ? 1.0 : 0.94)
        .opacity(selected ? 1.0 : 0.85)
    }
}

private struct WayRouteLineShape: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        let pts = points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for i in 1..<pts.count {
            let p0 = pts[max(i - 2, 0)], p1 = pts[i - 1], p2 = pts[i], p3 = pts[min(i + 1, pts.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}

private struct WayRouteSceneryView: View {
    let scenery: WayClassicRoute.Scenery
    var body: some View {
        Canvas { context, size in
            drawScenery(in: context, size: size)
        }
    }

    private func drawScenery(in context: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        switch scenery {
        case .water:
            var bridge = Path()
            bridge.move(to: CGPoint(x: w * 0.08, y: h * 0.78))
            bridge.addQuadCurve(to: CGPoint(x: w * 0.62, y: h * 0.78), control: CGPoint(x: w * 0.35, y: h * 0.42))
            bridge.addLine(to: CGPoint(x: w * 0.62, y: h * 0.82))
            bridge.addQuadCurve(to: CGPoint(x: w * 0.08, y: h * 0.82), control: CGPoint(x: w * 0.35, y: h * 0.5))
            bridge.closeSubpath()
            context.fill(bridge, with: .color(.black.opacity(0.28)))
            context.fill(Path(CGRect(x: 0, y: h * 0.82, width: w, height: h * 0.18)), with: .color(.black.opacity(0.18)))
        case .peaks:
            let peaks: [(CGFloat, CGFloat, CGFloat)] = [(0.05, 0.62, 0.32), (0.32, 0.5, 0.38), (0.62, 0.58, 0.34), (0.85, 0.66, 0.3)]
            for (x, top, half) in peaks {
                var p = Path()
                p.move(to: CGPoint(x: w * (x - half), y: h))
                p.addLine(to: CGPoint(x: w * x, y: h * top))
                p.addLine(to: CGPoint(x: w * (x + half), y: h))
                context.fill(p, with: .color(.black.opacity(0.22)))
                var cap = Path()
                cap.move(to: CGPoint(x: w * (x - half * 0.22), y: h * (top + 0.07)))
                cap.addLine(to: CGPoint(x: w * x, y: h * top))
                cap.addLine(to: CGPoint(x: w * (x + half * 0.22), y: h * (top + 0.07)))
                cap.addLine(to: CGPoint(x: w * x, y: h * (top + 0.05)))
                context.fill(cap, with: .color(.white.opacity(0.8)))
            }
        case .dunes:
            context.fill(Path(ellipseIn: CGRect(x: w * 0.62, y: h * 0.5, width: w * 0.2, height: w * 0.2)), with: .color(.white.opacity(0.35)))
            for (idx, base) in [0.74, 0.84].enumerated() {
                var dune = Path()
                dune.move(to: CGPoint(x: 0, y: h * CGFloat(base)))
                dune.addCurve(
                    to: CGPoint(x: w, y: h * CGFloat(base - 0.04)),
                    control1: CGPoint(x: w * 0.3, y: h * CGFloat(base - 0.14)),
                    control2: CGPoint(x: w * 0.6, y: h * CGFloat(base + 0.08))
                )
                dune.addLine(to: CGPoint(x: w, y: h))
                dune.addLine(to: CGPoint(x: 0, y: h))
                context.fill(dune, with: .color(.black.opacity(idx == 0 ? 0.16 : 0.26)))
            }
        case .mesas:
            context.fill(Path(ellipseIn: CGRect(x: w * 0.38, y: h * 0.52, width: w * 0.24, height: w * 0.24)), with: .color(.yellow.opacity(0.4)))
            let mesas: [(CGFloat, CGFloat, CGFloat)] = [(0.0, 0.32, 0.66), (0.55, 0.38, 0.62), (0.3, 0.18, 0.72)]
            for (x, mw, top) in mesas {
                var m = Path()
                m.move(to: CGPoint(x: w * x, y: h))
                m.addLine(to: CGPoint(x: w * (x + 0.04), y: h * top))
                m.addLine(to: CGPoint(x: w * (x + mw - 0.04), y: h * top))
                m.addLine(to: CGPoint(x: w * (x + mw), y: h))
                context.fill(m, with: .color(.black.opacity(0.3)))
            }
        }
    }
}

private struct WayJourneyStopsList: View {
    let progress: WayJourneyProgress

    private func formatKm(_ m: Double) -> String {
        let km = Int((m / 1000.0).rounded())
        return NumberFormatter.localizedString(from: NSNumber(value: km), number: .decimal) + " 公里"
    }

    var body: some View {
        let route = progress.route
        let marks = route.marks
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("沿途 \(route.stops.count) 站")
                    .font(.system(.title3, design: .serif).weight(.bold))
                Spacer()
                Text("相当于到第 \(progress.lastStopIndex + 1) 站")
                    .font(.subheadline)
                    .foregroundColor(route.tint)
            }

            VStack(spacing: 0) {
                ForEach(Array(route.stops.enumerated()), id: \.offset) { idx, stop in
                    let isLast = idx == route.stops.count - 1
                    let passed = idx <= progress.lastStopIndex
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            Image(systemName: passed ? (isLast ? "flag.checkered" : "checkmark") : "circle")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(passed ? .white : .secondary)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(passed ? route.tint : Color(.secondarySystemGroupedBackground)))
                            if !isLast {
                                Rectangle()
                                    .fill(passed ? route.tint : Color.secondary.opacity(0.25))
                                    .frame(width: 3)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(stop.name)
                                    .font(.system(.headline, design: .serif).weight(.semibold))
                                    .foregroundColor(passed ? .primary : .secondary)
                                Spacer()
                                Text(idx == 0 ? "起点" : formatKm(marks[idx]))
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(Color(.tertiaryLabel))
                            }
                            Text(stop.note)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.bottom, isLast ? 0 : 18)
                    }
                }
            }
        }
    }
}

// MARK: - 3. 第一次 (1:1 Original FirstsCard + FirstsView + CompassCard, Screenshot 5)

struct WayLifeFirst: Identifiable {
    enum Kind: String {
        case beginning, abroad, country, city, mustSee

        var symbol: String {
            switch self {
            case .beginning: return "sparkles"
            case .abroad: return "airplane.departure"
            case .country: return "flag.fill"
            case .city: return "building.2.fill"
            case .mustSee: return "star.fill"
            }
        }

        var tint: Color {
            switch self {
            case .beginning: return Color(red: 0.95, green: 0.68, blue: 0.15)
            case .abroad, .country: return Color(red: 0.88, green: 0.30, blue: 0.32)
            case .city: return .indigo
            case .mustSee: return .orange
            }
        }

        var label: String {
            switch self {
            case .beginning: return "开始"
            case .abroad: return "出国"
            case .country: return "新的国家"
            case .city: return "新的城市"
            case .mustSee: return "此生必去"
            }
        }
    }

    let id: String
    let kind: Kind
    let date: Date
    let title: String
    let place: String?
    var latitude: Double? = nil
    var longitude: Double? = nil
    var countryCode: String? = nil
}

struct WayLifeExtremes {
    struct Point {
        let name: String
        let detail: String
        let latitude: Double
        let longitude: Double
    }
    var north: Point?
    var south: Point?
    var east: Point?
    var west: Point?
}

enum WayLifeFirstsEngine {
    static func build(stays: [Stay]) -> (firsts: [WayLifeFirst], extremes: WayLifeExtremes) {
        let ordered = stays.sorted { $0.arrival < $1.arrival }
        var extremes = WayLifeExtremes()
        guard let first = ordered.first else { return ([], extremes) }

        var list: [WayLifeFirst] = []
        list.append(WayLifeFirst(
            id: "begin-\(first.id.uuidString)",
            kind: .beginning,
            date: first.arrival,
            title: "故事从这里开始",
            place: [first.displayName, first.city].compactMap { $0 }.removingDuplicates().joined(separator: " · "),
            latitude: first.latitude,
            longitude: first.longitude,
            countryCode: first.countryCode
        ))

        let homeCountry: String? = {
            let counts = Dictionary(grouping: ordered.compactMap(\.countryCode)) { $0 }.mapValues(\.count)
            return counts.max { $0.value < $1.value }?.key
        }()

        var seenCountries = Set<String>()
        var seenCities = Set<String>()
        var wentAbroad = false

        for s in ordered {
            if let code = s.countryCode, !code.isEmpty, seenCountries.insert(code).inserted, code != homeCountry {
                let cname = CountryText.localizedName(code: code)
                let title = wentAbroad ? "第一次到\(cname)" : "第一次出国，去了\(cname)"
                list.append(WayLifeFirst(
                    id: "ctry-\(code)",
                    kind: wentAbroad ? .country : .abroad,
                    date: s.arrival,
                    title: title,
                    place: s.city,
                    latitude: s.latitude,
                    longitude: s.longitude,
                    countryCode: code
                ))
                wentAbroad = true
            }
            if let city = s.city, !city.isEmpty {
                let key = "\(s.countryCode ?? "")|\(city)"
                if seenCities.insert(key).inserted {
                    list.append(WayLifeFirst(
                        id: "city-\(key)",
                        kind: .city,
                        date: s.arrival,
                        title: "第一次到\(city)",
                        place: nil,
                        latitude: s.latitude,
                        longitude: s.longitude,
                        countryCode: s.countryCode
                    ))
                }
            }
        }

        // MustSee first visits
        let allMustSee = MustSee.allPlaces
        let matched = MustSee.visitedMap(places: allMustSee, stays: ordered, manual: [:])
        for place in allMustSee {
            if let visitDate = matched[place.id] {
                list.append(WayLifeFirst(
                    id: "mustsee-\(place.id)",
                    kind: .mustSee,
                    date: visitDate,
                    title: "第一次到\(place.name)",
                    place: place.region,
                    latitude: place.latitude,
                    longitude: place.longitude
                ))
            }
        }

        func makePoint(_ s: Stay) -> WayLifeExtremes.Point {
            let name = (s.isLandmark ? s.placeName : nil) ?? s.customName ?? s.city ?? s.displayName
            let flag = s.countryCode.map { CountryText.flag(for: $0) } ?? "🏳️"
            let cName = s.countryCode.map { CountryText.localizedName(code: $0) } ?? (s.country ?? "")
            return WayLifeExtremes.Point(name: name, detail: "\(flag) \(cName)".trimmingCharacters(in: .whitespaces), latitude: s.latitude, longitude: s.longitude)
        }
        if let n = ordered.max(by: { $0.latitude < $1.latitude }) { extremes.north = makePoint(n) }
        if let s = ordered.min(by: { $0.latitude < $1.latitude }) { extremes.south = makePoint(s) }
        if let e = ordered.max(by: { $0.longitude < $1.longitude }) { extremes.east = makePoint(e) }
        if let w = ordered.min(by: { $0.longitude < $1.longitude }) { extremes.west = makePoint(w) }

        return (list.sorted { $0.date > $1.date }, extremes)
    }
}

struct WayFirstsCardView: View {
    let firsts: [WayLifeFirst]
    let extremes: WayLifeExtremes

    var body: some View {
        NavigationLink {
            WayFirstsDetailView(firsts: firsts, extremes: extremes)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("第一次")
                        .font(.system(.title2, design: .serif).weight(.bold))
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(firsts.count)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                        .padding(.leading, 4)
                }

                if let latest = firsts.first {
                    WayFirstTicketView(first: latest)
                }

                if firsts.count > 1 {
                    HStack(spacing: 10) {
                        HStack(spacing: -8) {
                            ForEach(Array(firsts.dropFirst().prefix(5))) { item in
                                Image(systemName: item.kind.symbol)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(item.kind.tint))
                                    .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                            }
                        }
                        Text("还有 \(firsts.count - 1) 个第一次")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(18)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

private struct WayFirstTicketView: View {
    let first: WayLifeFirst

    var body: some View {
        let cal = Calendar.current
        let tint = first.kind.tint
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Text("\(cal.component(.month, from: first.date))月")
                    .font(.caption.weight(.bold))
                    .foregroundColor(tint)
                Text("\(cal.component(.day, from: first.date))")
                    .font(.system(size: 32, weight: .bold, design: .serif))
                    .foregroundColor(.primary)
                Text(String(cal.component(.year, from: first.date)))
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
            }
            .frame(width: 76)
            .padding(.vertical, 10)

            Rectangle()
                .fill(Color.clear)
                .frame(width: 2)
                .overlay(
                    Path { p in
                        p.move(to: CGPoint(x: 1, y: 10))
                        p.addLine(to: CGPoint(x: 1, y: 74))
                    }
                    .stroke(tint.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                )

            VStack(alignment: .leading, spacing: 4) {
                Label(first.kind.label, systemImage: first.kind.symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(tint)
                Text(first.title)
                    .font(.system(.headline, design: .serif))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let place = first.place {
                    Text(place)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Spacer(minLength: 0)
        }
        .background(
            LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.07)], startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}

struct WayFirstsDetailView: View {
    let firsts: [WayLifeFirst]
    let extremes: WayLifeExtremes

    private var years: [(year: Int, items: [WayLifeFirst])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: firsts) { cal.component(.year, from: $0.date) }
        return grouped.keys.sorted(by: >).map { y in (y, grouped[y]!.sorted { $0.date > $1.date }) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("第一次")
                        .font(.system(size: 38, weight: .bold, design: .serif))
                    Text("这些第一次，是你自己一步一步走出来的。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if extremes.north != nil {
                    WayCompassCardView(extremes: extremes)
                }

                ForEach(years, id: \.year) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .lastTextBaseline, spacing: 10) {
                            Text(String(group.year))
                                .font(.system(size: 52, weight: .heavy, design: .serif))
                                .foregroundStyle(LinearGradient(colors: [.primary.opacity(0.85), .primary.opacity(0.22)], startPoint: .top, endPoint: .bottom))
                            Text("\(group.items.count) 个第一次")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }

                        ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, item in
                            NavigationLink {
                                DayDetailPage(date: item.date)
                            } label: {
                                WayFirstTimelineRow(first: item, isLast: idx == group.items.count - 1)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WayFirstTimelineRow: View {
    let first: WayLifeFirst
    let isLast: Bool
    @State private var thumb: UIImage?

    var body: some View {
        let cal = Calendar.current
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(cal.component(.month, from: first.date))月")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                Text("\(cal.component(.day, from: first.date))")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundColor(.primary)
            }
            .frame(width: 38, alignment: .trailing)
            .padding(.top, 10)

            VStack(spacing: 0) {
                Image(systemName: first.kind.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(first.kind.tint))
                    .padding(.top, 10)
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(first.kind.label)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(first.kind.tint)
                    Text(first.title)
                        .font(.system(.body, design: .serif).weight(.semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    if let place = first.place {
                        Text(place)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Group {
                    if let thumb {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                    } else if let code = first.countryCode, first.kind == .country || first.kind == .abroad {
                        Text(CountryText.flag(for: code))
                            .font(.system(size: 28))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(first.kind.tint.opacity(0.12))
                    } else {
                        Image(systemName: first.kind.symbol)
                            .font(.title3)
                            .foregroundColor(first.kind.tint)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(first.kind.tint.opacity(0.12))
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.bottom, 10)
        }
        .task(id: first.id) {
            thumb = await StintPhotoFetcher.shared.dayThumbnail(around: first.date)
        }
    }
}

private struct WayCompassCardView: View {
    let extremes: WayLifeExtremes
    @State private var turn: Double = -35.0
    private let gold = Color(red: 1, green: 0.8, blue: 0.45)

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("你到过的天涯海角")
                    .font(.system(.headline, design: .serif))
                Spacer()
            }
            .foregroundColor(.white)

            ZStack {
                WayGoldCompassRose()
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(turn))
                VStack {
                    pointLabel(extremes.north, title: "最北", vertical: true)
                    Spacer()
                    pointLabel(extremes.south, title: "最南", vertical: true)
                }
                HStack {
                    pointLabel(extremes.west, title: "最西", vertical: false)
                    Spacer()
                    pointLabel(extremes.east, title: "最东", vertical: false)
                }
            }
            .frame(height: 310)
        }
        .padding(18)
        .background {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.07, green: 0.09, blue: 0.18), Color(red: 0.13, green: 0.12, blue: 0.24)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(colors: [gold.opacity(0.18), .clear], center: .center, startRadius: 10, endRadius: 220)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onAppear {
            withAnimation(.spring(response: 1.4, dampingFraction: 0.6)) { turn = 0 }
        }
    }

    private func pointLabel(_ pt: WayLifeExtremes.Point?, title: String, vertical: Bool) -> some View {
        VStack(spacing: 2) {
            if let pt {
                Text(title).font(.caption2.weight(.bold)).foregroundColor(gold).tracking(1)
                Text(pt.name).font(.footnote.weight(.semibold)).foregroundColor(.white).lineLimit(2)
                Text(pt.detail).font(.caption2).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                Text(coordText(pt, vertical: vertical))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .multilineTextAlignment(.center)
        .frame(width: vertical ? 210 : 84)
    }

    private func coordText(_ pt: WayLifeExtremes.Point, vertical: Bool) -> String {
        let val = vertical ? pt.latitude : pt.longitude
        let deg = String(format: "%.1f°", abs(val))
        if vertical { return val >= 0 ? "北纬 \(deg)" : "南纬 \(deg)" }
        return val >= 0 ? "东经 \(deg)" : "西经 \(deg)"
    }
}

private struct WayGoldCompassRose: View {
    var body: some View {
        Canvas { context, size in
            drawCompass(in: context, size: size)
        }
    }

    private func drawCompass(in context: GraphicsContext, size: CGSize) {
        let c = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        let r = min(size.width, size.height) / 2.0
        let gold = Color(red: 1, green: 0.8, blue: 0.45)

        let rings: [(CGFloat, Double)] = [(1.0, 0.35), (0.82, 0.2), (0.4, 0.2)]
        for (scale, opacity) in rings {
            context.stroke(
                Path(ellipseIn: CGRect(x: c.x - r * scale, y: c.y - r * scale, width: r * 2 * scale, height: r * 2 * scale)),
                with: .color(gold.opacity(opacity)),
                lineWidth: 1
            )
        }

        for i in 0..<72 {
            let a = Double(i) / 72.0 * 2.0 * Double.pi
            let inner = r * (i % 9 == 0 ? 0.86 : 0.93)
            var tick = Path()
            tick.move(to: CGPoint(x: c.x + CGFloat(cos(a)) * inner, y: c.y + CGFloat(sin(a)) * inner))
            tick.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * r * 0.99, y: c.y + CGFloat(sin(a)) * r * 0.99))
            context.stroke(tick, with: .color(gold.opacity(i % 9 == 0 ? 0.6 : 0.25)), lineWidth: 1)
        }

        for i in 0..<8 {
            let a = Double(i) / 8.0 * 2.0 * Double.pi - Double.pi / 2.0
            let length = i % 2 == 0 ? r * 0.80 : r * 0.42
            let width = i % 2 == 0 ? r * 0.12 : r * 0.08
            let tip = CGPoint(x: c.x + CGFloat(cos(a)) * length, y: c.y + CGFloat(sin(a)) * length)
            let left = CGPoint(x: c.x + CGFloat(cos(a - Double.pi / 2.0)) * width, y: c.y + CGFloat(sin(a - Double.pi / 2.0)) * width)
            let right = CGPoint(x: c.x + CGFloat(cos(a + Double.pi / 2.0)) * width, y: c.y + CGFloat(sin(a + Double.pi / 2.0)) * width)
            var h1 = Path(); h1.move(to: c); h1.addLine(to: left); h1.addLine(to: tip); h1.closeSubpath()
            var h2 = Path(); h2.move(to: c); h2.addLine(to: right); h2.addLine(to: tip); h2.closeSubpath()
            context.fill(h1, with: .color(i == 0 ? gold : gold.opacity(i % 2 == 0 ? 0.75 : 0.45)))
            context.fill(h2, with: .color(i == 0 ? gold.opacity(0.7) : gold.opacity(i % 2 == 0 ? 0.4 : 0.25)))
        }

        context.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(gold))
        context.fill(Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)), with: .color(Color(red: 0.07, green: 0.09, blue: 0.18)))
    }
}

// MARK: - Share Sheet Helper

private struct StoriesShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct StoriesActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
