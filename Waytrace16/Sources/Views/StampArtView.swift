import SwiftUI
import CoreLocation

// MARK: - Date Formatting for Stamps

enum StampDateFormat {
    private static let longFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "dd MMM yyyy"
        return f
    }()

    private static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "dd MMM"
        return f
    }()

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy"
        return f
    }()

    private static let dotFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy.MM.dd"
        return f
    }()

    private static let mrzFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyMMdd"
        return f
    }()

    private static let zhDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    static func long(_ date: Date) -> String { longFormatter.string(from: date).uppercased() }
    static func short(_ date: Date) -> String { shortFormatter.string(from: date).uppercased() }
    static func year(_ date: Date) -> String { yearFormatter.string(from: date) }
    static func dot(_ date: Date) -> String { dotFormatter.string(from: date) }
    static func mrz(_ date: Date) -> String { mrzFormatter.string(from: date) }
    static func zhFull(_ date: Date) -> String { zhDateFormatter.string(from: date) }
}

// MARK: - Book Corner Shape (iOS 16 safe replacement for UnevenRoundedRectangle)

struct BookCornerRect: Shape {
    var topLeading: CGFloat
    var bottomLeading: CGFloat
    var bottomTrailing: CGFloat
    var topTrailing: CGFloat

    func path(in rect: CGRect) -> Path {
        let tl = min(topLeading, min(rect.width, rect.height) / 2)
        let tr = min(topTrailing, min(rect.width, rect.height) / 2)
        let br = min(bottomTrailing, min(rect.width, rect.height) / 2)
        let bl = min(bottomLeading, min(rect.width, rect.height) / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: - Master Stamp Artwork View

struct StampArtView: View {
    let stamp: PassportStamp
    var route: [CGPoint] = []
    var inked: Bool = true

    var body: some View {
        let base = Self.size(for: stamp)
        GeometryReader { proxy in
            let scale = min(proxy.size.width / base.width, proxy.size.height / base.height)
            art
                .frame(width: base.width, height: base.height)
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(base.width / base.height, contentMode: .fit)
    }

    @ViewBuilder
    private var art: some View {
        switch stamp.kind {
        case .entry, .exit:
            BorderStampView(stamp: stamp).inkWorn(seed: stamp.seed, inked: inked)
        case .province:
            ProvinceSealArtView(id: stamp.provinceID ?? "").inkWorn(seed: stamp.seed, inked: inked, wear: 0.6)
        case .city:
            CityStampArtView(stamp: stamp, route: route).inkWorn(seed: stamp.seed, inked: inked)
        case .special:
            SpecialStampArtView(stamp: stamp).inkWorn(seed: stamp.seed, inked: inked)
        case .set:
            let isSeal: Bool = {
                if case .seal = StampSet.named(stamp.code)?.layout { return true }
                return false
            }()
            SetStampArtView(stamp: stamp).inkWorn(seed: stamp.seed, inked: inked, wear: isSeal ? 0.45 : 1.0)
        }
    }

    static func size(for stamp: PassportStamp) -> CGSize {
        switch stamp.kind {
        case .province:
            return CGSize(width: 100, height: 100)
        case .city:
            return CGSize(width: 140, height: 140)
        case .set:
            return SetStampArtView.size(StampSet.named(stamp.code))
        case .special where stamp.code == "record.high":
            return CGSize(width: 150, height: 140)
        case .special where (stamp.code ?? "").hasPrefix("record."):
            return CGSize(width: 110, height: 110)
        case .special:
            switch SpecialStampStyle.of(stamp.code ?? "").shape {
            case .ticket, .hexagon: return CGSize(width: 172, height: 110)
            default: return CGSize(width: 140, height: 140)
            }
        case .entry, .exit:
            switch CountryStampStyle.of(stamp.countryCode ?? "").shape {
            case .circle, .octagon, .scalloped: return CGSize(width: 140, height: 140)
            case .oval: return CGSize(width: 180, height: 118)
            default: return CGSize(width: 172, height: 110)
            }
        }
    }
}

// MARK: - Border Stamps (Entry / Exit)

private struct BorderStampView: View {
    let stamp: PassportStamp

    private var style: CountryStampStyle { CountryStampStyle.of(stamp.countryCode ?? "") }
    private var ink: Color { style.ink.color }
    private var isEntry: Bool { stamp.kind == .entry }
    private var symbol: String {
        stamp.byAir ? (isEntry ? "airplane.arrival" : "airplane.departure") : (isEntry ? "arrow.down.right" : "arrow.up.right")
    }
    private var label: String {
        isEntry ? "入境 · ARRIVAL" : "出境 · DEPARTURE"
    }
    private var detail: String? {
        if isEntry { return stamp.port?.uppercased() }
        let stayed = "停留 \(stamp.days) 天"
        return [stayed, stamp.port?.uppercased()].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        ZStack {
            StampOutlineShape(shape: style.shape).stroke(ink, lineWidth: 2.8)
            StampOutlineShape(shape: style.shape, inset: 5.5)
                .stroke(ink, style: StrokeStyle(lineWidth: 0.9, dash: isEntry ? [] : [3, 2]))
            switch style.shape {
            case .circle, .octagon, .scalloped: round
            default: flat
            }
        }
        .foregroundColor(ink)
    }

    private var flat: some View {
        VStack(spacing: 3) {
            Text(style.native)
                .font(.custom("AvenirNextCondensed-Heavy", fixedSize: 15))
                .tracking(1.2)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Rectangle().frame(height: 0.9).padding(.horizontal, 6)
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                Text(label).font(.custom("AvenirNextCondensed-DemiBold", fixedSize: 9.5)).tracking(0.8)
            }
            Text(StampDateFormat.long(stamp.date))
                .font(.system(size: 19, weight: .heavy, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.custom("AvenirNextCondensed-DemiBold", fixedSize: 9))
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, style.shape == .oval ? 26 : (style.shape == .hexagon ? 24 : 14))
        .padding(.vertical, 10)
    }

    private var round: some View {
        ZStack {
            Circle().inset(by: 26).stroke(ink, lineWidth: 0.8)
            StampArcText(text: style.native, radius: 56, font: .custom("AvenirNextCondensed-Heavy", fixedSize: 12.5), color: ink, tracking: 1.5)
            StampArcText(text: label, radius: 56, font: .custom("AvenirNextCondensed-DemiBold", fixedSize: 9), color: ink, bottom: true, tracking: 1)
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 13, weight: .bold))
                Text(StampDateFormat.short(stamp.date))
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                Text(StampDateFormat.year(stamp.date))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                if let port = isEntry ? stamp.port : "\(stamp.days) 天" {
                    Text(port.uppercased())
                        .font(.custom("AvenirNextCondensed-DemiBold", fixedSize: 7.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: 66)
                }
            }
        }
    }
}

// MARK: - Province Seals (白文 / 朱文)

struct ProvinceSealArtView: View {
    let id: String
    private let ink = StampInk.cinnabar.color

    var body: some View {
        let character = ChinaProvince.character(for: id)
        if ChinaProvince.isCarved(id) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(ink)
                RoundedRectangle(cornerRadius: 6, style: .continuous).inset(by: 6).stroke(.black, lineWidth: 1.4)
                    .blendMode(.destinationOut)
                Text(character)
                    .font(.system(size: 60, weight: .black))
                    .foregroundColor(.black)
                    .offset(y: -1)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .inset(by: 3)
                .stroke(ink, lineWidth: 6)
                .overlay {
                    Text(character)
                        .font(.system(size: 58, weight: .heavy))
                        .foregroundColor(ink)
                        .offset(y: -1)
                }
        }
    }
}

// MARK: - City Stamps (with First-Day Route Glyph)

private struct CityStampArtView: View {
    let stamp: PassportStamp
    let route: [CGPoint]

    private var style: CityStampStyle {
        CityStampStyle.of(city: stamp.city ?? "", countryCode: stamp.countryCode, coordinate: stamp.coordinate)
    }

    var body: some View {
        let s = style
        let ink = s.ink.color
        ZStack {
            StampOutlineShape(shape: s.shape).stroke(ink, lineWidth: 2.6)
            if s.shape == .circle || s.shape == .scalloped {
                Circle().inset(by: 9).stroke(ink, lineWidth: 0.9)
                Circle().inset(by: 30).stroke(ink, lineWidth: 0.9)
                StampArcText(text: s.title, radius: 50, font: titleFont(s.title, size: 13), color: ink, tracking: 1.6)
                StampArcText(text: s.motto ?? StampDateFormat.dot(stamp.date), radius: 50,
                             font: titleFont(s.motto ?? "", size: 9), color: ink, bottom: true, tracking: 1.2)
                Image(systemName: "star.fill").font(.system(size: 5)).offset(x: -50)
                Image(systemName: "star.fill").font(.system(size: 5)).offset(x: 50)
                center(style: s, routeSize: CGSize(width: 50, height: 36))
            } else {
                StampOutlineShape(shape: s.shape, inset: 7).stroke(ink, lineWidth: 0.9)
                VStack(spacing: 3) {
                    Text(s.title)
                        .font(titleFont(s.title, size: 15))
                        .tracking(1.2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let motto = s.motto {
                        Text(motto).font(titleFont(motto, size: 8.5)).tracking(1).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Rectangle().frame(width: 60, height: 0.8)
                    center(style: s, routeSize: CGSize(width: 64, height: 40))
                }
                .padding(.horizontal, s.shape == .hexagon ? 26 : 18)
            }
        }
        .foregroundColor(ink)
    }

    private func center(style: CityStampStyle, routeSize: CGSize) -> some View {
        VStack(spacing: 3) {
            if route.count > 1 {
                StampRouteGlyph(points: route)
                    .stroke(style.ink.color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .frame(width: routeSize.width, height: routeSize.height)
                Image(systemName: style.symbol).font(.system(size: 9, weight: .bold))
            } else {
                Image(systemName: style.symbol).font(.system(size: 26, weight: .semibold))
                    .frame(height: routeSize.height)
            }
            Text(StampDateFormat.dot(stamp.date)).font(.system(size: 8.5, weight: .bold, design: .monospaced))
        }
    }

    private func titleFont(_ text: String, size: CGFloat) -> Font {
        let latin = text.unicodeScalars.allSatisfy { $0.value < 0x0250 }
        return latin ? .custom("AvenirNextCondensed-Heavy", fixedSize: size) : .system(size: size, weight: .heavy)
    }
}

struct StampRouteGlyph: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height))
        for p in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height))
        }
        return path
    }
}

// MARK: - Special Stamps (Four Corners, Peak, Crossings, New Year)

private struct SpecialStampArtView: View {
    let stamp: PassportStamp

    @ViewBuilder
    var body: some View {
        switch stamp.code ?? "" {
        case "record.high":
            PeakStampView(stamp: stamp)
        case let code where code.hasPrefix("record."):
            DirectionSealView(direction: String(code.dropFirst("record.".count)))
        default:
            crossing
        }
    }

    private var crossing: some View {
        let style = SpecialStampStyle.of(stamp.code ?? "")
        let ink = style.ink.color
        let isNewYear = (stamp.code ?? "").hasPrefix("newyear")
        return ZStack {
            StampOutlineShape(shape: style.shape).stroke(ink, lineWidth: 2.8)
            switch style.shape {
            case .ticket, .hexagon:
                StampOutlineShape(shape: style.shape, inset: 5.5).stroke(ink, lineWidth: 0.9)
                VStack(spacing: 3) {
                    Text(style.label)
                        .font(.custom("AvenirNextCondensed-Heavy", fixedSize: 11)).tracking(1)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Rectangle().frame(height: 0.9).padding(.horizontal, 8)
                    HStack(spacing: 6) {
                        Image(systemName: style.symbol).font(.system(size: 15, weight: .bold))
                        Text(stamp.value ?? "").font(.system(size: 24, weight: .heavy, design: .monospaced))
                    }
                    Text([stamp.city, stamp.date == .distantPast ? nil : StampDateFormat.long(stamp.date)]
                        .compactMap { $0 }.joined(separator: " · ").uppercased())
                        .font(.custom("AvenirNextCondensed-DemiBold", fixedSize: 9))
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                .padding(.horizontal, style.shape == .hexagon ? 28 : 16)
            default:
                Circle().inset(by: 26).stroke(ink, lineWidth: 0.8)
                StampArcText(text: style.label, radius: 56, font: Self.font(style.label, size: 11), color: ink, tracking: 1.2)
                if stamp.date != .distantPast {
                    StampArcText(text: StampDateFormat.long(stamp.date), radius: 56,
                                 font: .custom("AvenirNextCondensed-DemiBold", fixedSize: 9), color: ink, bottom: true, tracking: 1)
                }
                if stamp.code == "equator" {
                    Rectangle().frame(width: 92, height: 1.4).offset(y: 12)
                    Rectangle().frame(width: 92, height: 0.6).offset(y: 15)
                }
                VStack(spacing: 2) {
                    Image(systemName: style.symbol).font(.system(size: isNewYear ? 11 : 13, weight: .bold))
                    Text(stamp.value ?? "")
                        .font(isNewYear ? .system(size: 28, weight: .black, design: .rounded) : .system(size: 16, weight: .heavy, design: .monospaced))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if let city = stamp.city {
                        Text(city.uppercased())
                            .font(Self.font(city, size: 8))
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .frame(width: 70)
                            .padding(.top, stamp.code == "equator" ? 9 : 0)
                    }
                }
            }
        }
        .foregroundColor(ink)
    }

    static func font(_ text: String, size: CGFloat) -> Font {
        text.unicodeScalars.allSatisfy { $0.value < 0x0250 || $0.value == 0x00B7 }
            ? .custom("AvenirNextCondensed-Heavy", fixedSize: size) : .system(size: size, weight: .heavy)
    }
}

struct DirectionSealView: View {
    let direction: String

    private var char: String {
        switch direction {
        case "north": return "北"
        case "south": return "南"
        case "east": return "东"
        default: return "西"
        }
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let carved = direction == "north" || direction == "south"
            let ink = StampInk.cinnabar.color
            ZStack {
                if carved {
                    RoundedRectangle(cornerRadius: side * 0.1, style: .continuous).fill(ink)
                    RoundedRectangle(cornerRadius: side * 0.06, style: .continuous).inset(by: side * 0.07)
                        .stroke(.black, lineWidth: side * 0.015)
                        .blendMode(.destinationOut)
                } else {
                    RoundedRectangle(cornerRadius: side * 0.08, style: .continuous).inset(by: side * 0.03)
                        .stroke(ink, lineWidth: side * 0.07)
                }
                Text(char)
                    .font(.system(size: side * 0.62, weight: .black))
                    .foregroundColor(carved ? .black : ink)
                    .blendMode(carved ? .destinationOut : .normal)
                    .offset(y: -side * 0.01)
            }
            .compositingGroup()
            .frame(width: side, height: side)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

private struct PeakStampView: View {
    let stamp: PassportStamp

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                PeakShape().stroke(StampInk.slate.color, lineWidth: 2.8)
                PeakShape(inset: 6.5).stroke(StampInk.slate.color, lineWidth: 0.9)
                VStack(spacing: 2) {
                    Image(systemName: "mountain.2.fill").font(.system(size: 15, weight: .bold))
                    Text(stamp.value ?? "").font(.system(size: 20, weight: .heavy, design: .monospaced))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("最高 · HIGHEST")
                        .font(.custom("AvenirNextCondensed-DemiBold", fixedSize: 8.5)).tracking(1.5)
                    if let city = stamp.city {
                        Text(city).font(SpecialStampArtView.font(city, size: 8)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                .padding(.top, w * 0.12)
                .padding(.horizontal, w * 0.12)
            }
            .foregroundColor(StampInk.slate.color)
        }
    }

    private struct PeakShape: Shape {
        var inset: CGFloat = 1.5
        func path(in full: CGRect) -> Path {
            let r = full.insetBy(dx: inset, dy: inset)
            var path = Path()
            path.move(to: CGPoint(x: r.minX, y: r.maxY))
            path.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.42))
            path.addLine(to: CGPoint(x: r.midX, y: r.minY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.42))
            path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            path.closeSubpath()
            return path
        }
    }
}

// MARK: - Set Stamps (Seal / Route Map / Luggage Label)

private struct SetStampArtView: View {
    let stamp: PassportStamp

    var body: some View {
        let set = StampSet.named(stamp.code)
        let ink = (set?.ink ?? .crimson).color
        Group {
            if let set {
                switch set.layout {
                case .seal(let carved): SetSealView(set: set, carved: carved, ink: ink)
                case .map(let shape): SetRouteStampView(set: set, shape: shape, date: stamp.date, ink: ink)
                case .label(let shape): SetLabelView(set: set, shape: shape, date: stamp.date, ink: ink)
                }
            }
        }
        .foregroundColor(ink)
    }

    static func size(_ set: StampSet?) -> CGSize {
        switch set?.layout {
        case .seal:
            return (set?.title.count ?? 0) >= 4 ? CGSize(width: 160, height: 160) : CGSize(width: 116, height: 176)
        case .map(let shape), .label(let shape):
            switch shape {
            case .circle, .scalloped, .octagon: return CGSize(width: 176, height: 176)
            case .oval: return CGSize(width: 196, height: 134)
            default: return CGSize(width: 196, height: 128)
            }
        case nil:
            return CGSize(width: 176, height: 176)
        }
    }

    static func font(_ text: String, size: CGFloat) -> Font {
        text.unicodeScalars.allSatisfy { $0.value < 0x0250 || $0.value == 0x00B7 }
            ? .custom("AvenirNextCondensed-Heavy", fixedSize: size) : .system(size: size, weight: .heavy)
    }

    static func date(_ date: Date) -> String {
        date == .distantPast ? "" : StampDateFormat.long(date)
    }
}

private struct SetSealView: View {
    let set: StampSet
    let carved: Bool
    let ink: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let chars = set.title.map(String.init)
            ZStack {
                if carved {
                    RoundedRectangle(cornerRadius: w * 0.07, style: .continuous).fill(ink)
                    RoundedRectangle(cornerRadius: w * 0.04, style: .continuous).inset(by: w * 0.05)
                        .stroke(.black, lineWidth: w * 0.012)
                        .blendMode(.destinationOut)
                } else {
                    RoundedRectangle(cornerRadius: w * 0.06, style: .continuous).inset(by: w * 0.02)
                        .stroke(ink, lineWidth: w * 0.055)
                    RoundedRectangle(cornerRadius: w * 0.03, style: .continuous).inset(by: w * 0.1)
                        .stroke(ink, lineWidth: w * 0.012)
                }
                Group {
                    if chars.count >= 4 {
                        HStack(spacing: w * 0.02) {
                            column([chars[2], chars[3]], size: w * 0.34)
                            column([chars[0], chars[1]], size: w * 0.34)
                        }
                    } else {
                        column(chars, size: min(w * 0.62, h * 0.78 / CGFloat(max(chars.count, 1))))
                    }
                }
                .foregroundColor(carved ? .black : ink)
                .blendMode(carved ? .destinationOut : .normal)
            }
            .compositingGroup()
        }
    }

    private func column(_ chars: [String], size: CGFloat) -> some View {
        VStack(spacing: -size * 0.08) {
            ForEach(Array(chars.enumerated()), id: \.offset) { _, char in
                Text(char).font(.system(size: size, weight: .black))
            }
        }
    }
}

private struct SetRouteStampView: View {
    let set: StampSet
    let shape: StampShape
    let date: Date
    let ink: Color

    private var round: Bool { shape == .circle || shape == .scalloped || shape == .octagon }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                StampOutlineShape(shape: shape).stroke(ink, lineWidth: 2.8)
                StampOutlineShape(shape: shape, inset: 6.5).stroke(ink, lineWidth: 0.9)
                if round {
                    StampArcText(text: set.title, radius: w / 2 - 22, font: SetStampArtView.font(set.title, size: 14), color: ink, tracking: 2)
                    StampArcText(text: set.motto, radius: w / 2 - 22, font: SetStampArtView.font(set.motto, size: 9), color: ink, bottom: true, tracking: 1.4)
                    routeCanvas.frame(width: w * 0.48, height: h * 0.38)
                    Text(SetStampArtView.date(date)).font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .offset(y: h * 0.25)
                } else {
                    VStack(spacing: 4) {
                        Text(set.title).font(SetStampArtView.font(set.title, size: 15)).tracking(1.5)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        routeCanvas.frame(width: w * 0.62, height: h * 0.34)
                        HStack(spacing: 5) {
                            Image(systemName: set.symbol).font(.system(size: 8, weight: .bold))
                            Text(set.motto).font(SetStampArtView.font(set.motto, size: 8.5)).tracking(1)
                            if !SetStampArtView.date(date).isEmpty {
                                Text("· " + SetStampArtView.date(date)).font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            }
                        }
                        .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .padding(.horizontal, shape == .hexagon ? w * 0.16 : w * 0.09)
                }
            }
            .frame(width: w, height: h)
        }
    }

    private var routeCanvas: some View {
        Canvas { context, size in
            let entries = set.members.compactMap { title in CityStampStyle.catalog.first { $0.title == title } }
            guard entries.count > 1 else { return }
            let k = cos(entries[0].latitude * .pi / 180)
            let xs = entries.map { $0.longitude * k }, ys = entries.map { -$0.latitude }
            let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
            let scale = min(size.width / max(maxX - minX, 0.01), size.height / max(maxY - minY, 0.01)) * 0.86
            let ox = (size.width - (maxX - minX) * scale) / 2, oy = (size.height - (maxY - minY) * scale) / 2
            let points = zip(xs, ys).map { CGPoint(x: ox + ($0 - minX) * scale, y: oy + ($1 - minY) * scale) }
            var line = Path()
            line.addLines(points)
            context.stroke(line, with: .color(ink), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [3, 2.5]))
            for (index, point) in points.enumerated() {
                let r: CGFloat = (index == 0 || index == points.count - 1) ? 3.6 : 2.8
                context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)), with: .color(ink))
                if index == 0 {
                    let ring = r + 2.4
                    context.stroke(Path(ellipseIn: CGRect(x: point.x - ring, y: point.y - ring, width: ring * 2, height: ring * 2)),
                                   with: .color(ink), lineWidth: 0.9)
                }
            }
        }
    }
}

private struct SetLabelView: View {
    let set: StampSet
    let shape: StampShape
    let date: Date
    let ink: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                StampOutlineShape(shape: shape).stroke(ink, lineWidth: 3.2)
                StampOutlineShape(shape: shape, inset: 7).stroke(ink, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                VStack(spacing: 3) {
                    Text(set.motto).font(SetStampArtView.font(set.motto, size: 8)).tracking(2.5)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(set.title).font(SetStampArtView.font(set.title, size: 26)).tracking(1)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    HStack(spacing: 6) {
                        Rectangle().frame(height: 0.9)
                        Image(systemName: set.symbol).font(.system(size: 10, weight: .bold))
                        Rectangle().frame(height: 0.9)
                    }
                    .frame(width: w * 0.5)
                    Text(set.members.joined(separator: " · "))
                        .font(SetStampArtView.font(set.members.joined(), size: 7.5)).tracking(0.6)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    if !SetStampArtView.date(date).isEmpty {
                        Text(SetStampArtView.date(date)).font(.system(size: 7, weight: .bold, design: .monospaced))
                    }
                }
                .padding(.horizontal, shape == .oval ? w * 0.17 : (shape == .hexagon ? w * 0.18 : w * 0.11))
            }
        }
    }
}

// MARK: - Stamp Outline Shapes

struct StampOutlineShape: Shape {
    let shape: StampShape
    var inset: CGFloat = 1.5

    func path(in full: CGRect) -> Path {
        let rect = full.insetBy(dx: inset, dy: inset)
        let m = min(rect.width, rect.height)
        switch shape {
        case .rectangle:
            return Path(roundedRect: rect, cornerRadius: 3)
        case .rounded:
            return Path(roundedRect: rect, cornerRadius: m * 0.2, style: .continuous)
        case .circle:
            return Path(ellipseIn: CGRect(x: rect.midX - m / 2, y: rect.midY - m / 2, width: m, height: m))
        case .oval:
            return Path(ellipseIn: rect)
        case .octagon:
            let c = m * 0.29
            return polygon([
                CGPoint(x: rect.minX + c, y: rect.minY), CGPoint(x: rect.maxX - c, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY + c), CGPoint(x: rect.maxX, y: rect.maxY - c),
                CGPoint(x: rect.maxX - c, y: rect.maxY), CGPoint(x: rect.minX + c, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY - c), CGPoint(x: rect.minX, y: rect.minY + c)
            ])
        case .hexagon:
            let c = rect.height * 0.3
            return polygon([
                CGPoint(x: rect.minX + c, y: rect.minY), CGPoint(x: rect.maxX - c, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: rect.maxX - c, y: rect.maxY),
                CGPoint(x: rect.minX + c, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY)
            ])
        case .ticket:
            let r = m * 0.13
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX, y: rect.minY), radius: r, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(center: CGPoint(x: rect.maxX, y: rect.maxY), radius: r, startAngle: .degrees(270), endAngle: .degrees(180), clockwise: true)
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX, y: rect.maxY), radius: r, startAngle: .degrees(0), endAngle: .degrees(270), clockwise: true)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX, y: rect.minY), radius: r, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
            path.closeSubpath()
            return path
        case .scalloped:
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = m / 2
            var path = Path()
            let steps = 200
            for i in 0...steps {
                let a = Double(i) / Double(steps) * 2 * .pi
                let r = radius - 2.2 + 2.2 * cos(a * 28)
                let point = CGPoint(x: center.x + r * sin(a), y: center.y - r * cos(a))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            return path
        }
    }

    private func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

// MARK: - Curved Arc Text

struct StampArcText: View {
    let text: String
    let radius: CGFloat
    let font: Font
    let color: Color
    var bottom: Bool = false
    var tracking: CGFloat = 1
    var span: CGFloat = 2.1

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let glyphs = text.map { context.resolve(Text(String($0)).font(font).foregroundColor(color)) }
            let widths = glyphs.map { $0.measure(in: CGSize(width: 100, height: 100)).width + tracking }
            let sum = widths.reduce(0, +)
            guard sum > 0 else { return }
            let total = min(sum, radius * span)
            let squeeze = total / max(sum, 1)
            var arc = -total / 2
            for (glyph, width) in zip(glyphs, widths) {
                let w = width * squeeze
                let mid = (arc + w / 2) / radius
                var copy = context
                if bottom {
                    copy.translateBy(x: center.x + radius * sin(mid), y: center.y + radius * cos(mid))
                    copy.rotate(by: .radians(-mid))
                } else {
                    copy.translateBy(x: center.x + radius * sin(mid), y: center.y - radius * cos(mid))
                    copy.rotate(by: .radians(mid))
                }
                copy.scaleBy(x: squeeze, y: 1)
                copy.draw(glyph, at: .zero, anchor: .center)
                arc += w
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Ink Wear & Blind Emboss

private struct InkWornModifier: ViewModifier {
    let seed: UInt64
    let inked: Bool
    let wear: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        if inked {
            let density: Double = {
                var r = SeededRandom(seed)
                return 0.84 + r.unit() * 0.12
            }()
            content
                .mask {
                    Canvas { context, size in
                        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
                        var random = SeededRandom(seed &+ 7)
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                        context.blendMode = .destinationOut
                        let grain = min(size.width, size.height) / 140
                        let speckCount = min(220, Int(Double(size.width * size.height) / 90.0 * wear))
                        var specks = Path()
                        for _ in 0..<speckCount {
                            let r = (0.3 + random.unit() * 0.9) * grain
                            let pt = CGPoint(x: random.unit() * size.width, y: random.unit() * size.height)
                            specks.addEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
                        }
                        context.fill(specks, with: .color(.black))
                        for _ in 0..<2 {
                            let r = min(size.width, size.height) * (0.06 + random.unit() * 0.08)
                            let pt = CGPoint(x: random.unit() * size.width, y: random.unit() * size.height)
                            context.fill(
                                Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                                with: .radialGradient(Gradient(colors: [.black.opacity(0.2), .clear]), center: pt, startRadius: 0, endRadius: r)
                            )
                        }
                    }
                }
                .opacity(density)
                .drawingGroup()
        } else {
            ZStack {
                Color.white.opacity(0.85).mask(content).offset(x: -0.8, y: -0.8)
                Color(red: 0.52, green: 0.47, blue: 0.40).opacity(0.55).mask(content).offset(x: 0.8, y: 0.8)
                Color(red: 0.75, green: 0.71, blue: 0.62).mask(content)
            }
            .drawingGroup()
        }
    }
}

extension View {
    func inkWorn(seed: UInt64, inked: Bool = true, wear: Double = 1.0) -> some View {
        modifier(InkWornModifier(seed: seed, inked: inked, wear: wear))
    }
}

// MARK: - Paper & Security Patterns

struct StampPaperView: View {
    enum Style { case passport, seals, book }
    var style: Style = .passport
    var paper: Color = Self.defaultPaper
    var ink: Color = Self.defaultLine
    var pattern: StampPaperPattern = .waves

    static let defaultPaper = Color(red: 0.965, green: 0.945, blue: 0.895)
    static let defaultLine = Color(red: 0.86, green: 0.82, blue: 0.72)

    init(style: Style = .passport) {
        self.style = style
    }

    init(theme: PassportTheme) {
        self.style = .passport
        self.paper = theme.paperColor
        self.ink = theme.guilloche
        self.pattern = theme.pattern
    }

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paper))
            switch style {
            case .passport:
                Self.draw(pattern, in: &context, size: size, ink: ink)
            case .seals:
                for x in stride(from: size.width / 6, to: size.width, by: size.width / 6) {
                    context.stroke(
                        Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                        with: .color(StampInk.cinnabar.color.opacity(0.08)),
                        lineWidth: 0.6
                    )
                }
            case .book:
                guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
                let maxW = min(size.width, 4000)
                let maxH = min(size.height, 20000)
                var dots = Path()
                for y in stride(from: 12, to: maxH, by: 16) {
                    for x in stride(from: 12, to: maxW, by: 16) {
                        dots.addEllipse(in: CGRect(x: x, y: y, width: 1.4, height: 1.4))
                    }
                }
                context.fill(dots, with: .color(ink.opacity(0.6)))
            }
        }
    }

    private static func wave(from start: CGFloat, to end: CGFloat, step: CGFloat, _ point: (CGFloat) -> CGPoint) -> Path {
        var path = Path()
        for t in stride(from: start, through: end, by: step) {
            if t == start { path.move(to: point(t)) } else { path.addLine(to: point(t)) }
        }
        return path
    }

    private static func draw(_ pattern: StampPaperPattern, in context: inout GraphicsContext, size: CGSize, ink: Color) {
        let stroke = GraphicsContext.Shading.color(ink.opacity(0.35))
        switch pattern {
        case .waves:
            for row in stride(from: 0, through: size.height, by: 9) {
                context.stroke(wave(from: 0, to: size.width, step: 4) { x in
                    CGPoint(x: x, y: row + 3 * sin(x / 26 + row / 40) + 1.5 * sin(x / 9 + row))
                }, with: stroke, lineWidth: 0.5)
            }
        case .lattice:
            for row in stride(from: -size.width, through: size.height, by: 11) {
                context.stroke(wave(from: 0, to: size.width, step: 4) { x in
                    CGPoint(x: x, y: row + x * 0.45 + 2.5 * sin(x / 14))
                }, with: stroke, lineWidth: 0.45)
                context.stroke(wave(from: 0, to: size.width, step: 4) { x in
                    CGPoint(x: x, y: row + (size.width - x) * 0.45 + 2.5 * sin(x / 14 + 1.6))
                }, with: stroke, lineWidth: 0.45)
            }
        case .ripples:
            for row in stride(from: -20, through: size.height + 20, by: 7) {
                context.stroke(wave(from: 0, to: size.width, step: 3) { x in
                    CGPoint(x: x, y: row + 9 * sin(x / 48 + row / 23) * cos(row / 70))
                }, with: stroke, lineWidth: 0.45)
            }
        case .rosette:
            let center = CGPoint(x: size.width / 2, y: size.height * 0.55)
            let reach = hypot(size.width, size.height) * 0.62
            for radius in stride(from: 14, through: reach, by: 8) {
                context.stroke(wave(from: 0, to: 2 * .pi + 0.02, step: 0.04) { angle in
                    let r = radius + 2.6 * sin(angle * 18 + radius / 11)
                    return CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
                }, with: stroke, lineWidth: 0.45)
            }
        }
    }
}

// MARK: - Compass Rose (for Four Corners)

struct CompassRoseView: View {
    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2
            let ink = Color(red: 0.32, green: 0.29, blue: 0.26)
            for (radius, width) in [(r - 1, 0.9), (r - 6, 0.5), (r * 0.36, 0.6)] {
                context.stroke(
                    Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(ink.opacity(0.7)),
                    lineWidth: width
                )
            }
            for i in 0..<32 {
                let a: CGFloat = CGFloat(i) / 32 * 2 * .pi
                let inner = r - (i % 4 == 0 ? 12 : 9)
                var tick = Path()
                tick.move(to: CGPoint(x: c.x + inner * sin(a), y: c.y - inner * cos(a)))
                tick.addLine(to: CGPoint(x: c.x + (r - 6) * sin(a), y: c.y - (r - 6) * cos(a)))
                context.stroke(tick, with: .color(ink.opacity(0.6)), lineWidth: 0.6)
            }
            func point(angle: CGFloat, length: CGFloat, width: CGFloat) {
                let tip = CGPoint(x: c.x + length * sin(angle), y: c.y - length * cos(angle))
                let left = CGPoint(x: c.x + width * sin(angle - .pi / 2), y: c.y - width * cos(angle - .pi / 2))
                let right = CGPoint(x: c.x + width * sin(angle + .pi / 2), y: c.y - width * cos(angle + .pi / 2))
                var dark = Path(); dark.addLines([c, tip, right]); dark.closeSubpath()
                var light = Path(); light.addLines([c, tip, left]); light.closeSubpath()
                context.fill(dark, with: .color(ink.opacity(0.85)))
                context.fill(light, with: .color(StampPaperView.defaultPaper))
                context.stroke(light, with: .color(ink.opacity(0.85)), lineWidth: 0.6)
            }
            for i in 0..<4 { point(angle: CGFloat(i) * .pi / 2 + .pi / 4, length: r * 0.5, width: r * 0.09) }
            for i in 0..<4 { point(angle: CGFloat(i) * .pi / 2, length: r - 14, width: r * 0.12) }
            context.fill(Path(ellipseIn: CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5)), with: .color(ink))
        }
    }
}
