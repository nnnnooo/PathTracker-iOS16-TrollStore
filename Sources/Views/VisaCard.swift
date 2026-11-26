import SwiftUI
import UIKit

/// Realistic visa & passport card matching the original PathTracker (漫迹) design:
/// US foil with Golden Gate Bridge, Schengen 12-star sticker, Japan sakura label,
/// AU/NZ electronic grant notice, generic country sticker, and dark leather/foil passport card.
struct VisaCard: View {
    let document: VisaRecord
    var showSheen: Bool = false

    /// Close to a machine-readable visa's 120 × 80 mm.
    static let aspect: CGFloat = 1.52

    var body: some View {
        GeometryReader { proxy in
            let u = proxy.size.width / 360
            ZStack(alignment: .topLeading) {
                switch VisaTemplate(document) {
                case .passport: PassportFace(document: document, u: u)
                case .unitedStates: UnitedStatesFace(document: document, u: u)
                case .schengen: StickerFace(document: document, u: u, style: .schengen)
                case .japan: JapanFace(document: document, u: u)
                case .grantNotice: GrantNoticeFace(document: document, u: u)
                case .generic: StickerFace(document: document, u: u, style: .generic)
                }

                if showSheen {
                    LinearGradient(
                        colors: [.clear, .white.opacity(document.kind == .passport ? 0.14 : 0.22), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .rotationEffect(.degrees(18))
                    .offset(x: proxy.size.width * 0.28)
                    .allowsHitTesting(false)
                }

                CountdownBadge(document: document, u: u)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                    .padding(.top, 10 * u)
                    .padding(.trailing, 12 * u)

                if document.isExpired {
                    ExpiredStamp(u: u)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 16 * u, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16 * u, style: .continuous)
                    .strokeBorder(Color.white.opacity(document.kind == .passport ? 0.08 : 0.6), lineWidth: 0.8)
            }
            .saturation(document.isExpired ? 0.3 : 1)
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let days = document.remainingDays
        let left = days < 0 ? "已过期" : "还剩 \(days) 天"
        return "\(document.kind == .passport ? "护照" : document.countryName) \(document.visaType) \(left)"
    }
}

private enum VisaTemplate {
    case passport, unitedStates, schengen, japan, grantNotice, generic

    init(_ document: VisaRecord) {
        if document.kind == .passport {
            self = .passport
        } else if document.kind == .eVisa || ["AU", "NZ"].contains(document.countryCode) {
            self = .grantNotice
        } else if document.countryCode == "US" {
            self = .unitedStates
        } else if document.isSchengen {
            self = .schengen
        } else if document.countryCode == "JP" {
            self = .japan
        } else {
            self = .generic
        }
    }
}

// MARK: - Shared Formatting & Pieces

enum VisaDate {
    private static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    private static func parts(_ date: Date) -> (Int, Int, Int) {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return (c.day ?? 1, c.month ?? 1, c.year ?? 2000)
    }

    /// 15MAR2034, as on a US visa.
    static func compact(_ date: Date?) -> String {
        guard let date else { return "" }
        let (d, m, y) = parts(date)
        return String(format: "%02d%@%04d", d, months[max(0, min(11, m - 1))], y)
    }

    /// 15-03-34, as on a Schengen sticker.
    static func short(_ date: Date?) -> String {
        guard let date else { return "" }
        let (d, m, y) = parts(date)
        return String(format: "%02d-%02d-%02d", d, m, y % 100)
    }

    /// 15 MAR 2034.
    static func spaced(_ date: Date?) -> String {
        guard let date else { return "" }
        let (d, m, y) = parts(date)
        return String(format: "%02d %@ %04d", d, months[max(0, min(11, m - 1))], y)
    }

    /// 271123 (YYMMDD) for MRZ.
    static func yymmdd(_ date: Date) -> String {
        let (d, m, y) = parts(date)
        return String(format: "%02d%02d%02d", y % 100, m, d)
    }
}

private struct MachineLines: View {
    let document: VisaRecord
    let u: CGFloat
    var color: Color = .black

    var body: some View {
        let lines = Self.lines(document)
        VStack(alignment: .leading, spacing: 1.5 * u) {
            Text(verbatim: lines.0)
            Text(verbatim: lines.1)
        }
        .font(.system(size: 9.6 * u, weight: .semibold, design: .monospaced))
        .tracking(0.2 * u)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .foregroundColor(color.opacity(0.78))
    }

    static func lines(_ document: VisaRecord) -> (String, String) {
        func pad(_ text: String) -> String { String((text + String(repeating: "<", count: 44)).prefix(44)) }
        let type = document.kind == .passport ? "P<" : document.isSchengen ? "VC" : "VN"
        let issuer = document.isSchengen ? "EUE" : VisaCatalog.alpha3(document.countryCode)
        let parts = document.holder.uppercased().split(separator: " ").map(String.init)
        let name = parts.isEmpty ? "WAYTRACE<<TRAVELLER" : parts[0] + "<<" + parts.dropFirst().joined(separator: "<")
        let number = String((document.visaNumber.uppercased().filter { $0.isLetter || $0.isNumber } + "<<<<<<<<<").prefix(9))
        let nationality = "CHN"
        let expiry = VisaDate.yymmdd(document.expiryDate)
        return (
            pad(type + issuer + name),
            pad(number + String(VisaCatalog.mrzCheckDigit(number)) + nationality + "<<<<<<<<" + expiry + String(VisaCatalog.mrzCheckDigit(expiry)))
        )
    }
}

private struct VisaField: View {
    let label: String
    let value: String
    let u: CGFloat
    var ink: Color = .black
    var valueSize: CGFloat = 11

    var body: some View {
        VStack(alignment: .leading, spacing: 0.5 * u) {
            Text(verbatim: label)
                .font(.system(size: 6.4 * u, weight: .medium))
                .foregroundColor(ink.opacity(0.62))
                .lineLimit(1)
            Text(verbatim: value.isEmpty ? " " : value)
                .font(.system(size: valueSize * u, weight: .bold, design: .monospaced))
                .foregroundColor(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

private struct PhotoSlot: View {
    let u: CGFloat
    var tint: Color = .black

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 3 * u).fill(tint.opacity(0.07))
            Image(systemName: "person.fill")
                .resizable()
                .scaledToFit()
                .padding(.horizontal, 10 * u)
                .padding(.top, 14 * u)
                .offset(y: 6 * u)
                .foregroundColor(tint.opacity(0.16))
            RoundedRectangle(cornerRadius: 3 * u).stroke(tint.opacity(0.18), lineWidth: 0.6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 3 * u))
    }
}

private struct CountdownBadge: View {
    let document: VisaRecord
    let u: CGFloat

    var body: some View {
        let days = document.remainingDays
        if days >= 0 {
            let leather = document.kind == .passport
            let tint: Color = document.isExpiringSoon
                ? .orange
                : (leather ? Color(red: 0.95, green: 0.86, blue: 0.62) : Color(red: 0.14, green: 0.55, blue: 0.24))
            let borderTint: Color = document.isExpiringSoon
                ? .orange
                : (leather ? Color(red: 0.95, green: 0.86, blue: 0.62) : .green)

            HStack(alignment: .firstTextBaseline, spacing: 2 * u) {
                Text(days == 0 ? "今天到期" : "还剩")
                    .font(.system(size: 8.5 * u, weight: .semibold))
                if days > 0 {
                    Text(Self.formattedDays(days))
                        .font(.system(size: 13 * u, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("天")
                        .font(.system(size: 8.5 * u, weight: .semibold))
                }
            }
            .foregroundColor(tint)
            .padding(.horizontal, 8 * u)
            .padding(.vertical, 3.5 * u)
            .background(Color.white.opacity(leather ? 0.10 : 0.86), in: Capsule())
            .overlay(Capsule().stroke(borderTint.opacity(0.5), lineWidth: 0.6))
        }
    }

    private static func formattedDays(_ n: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
    }
}

private struct ExpiredStamp: View {
    let u: CGFloat

    var body: some View {
        let red = Color(red: 0.75, green: 0.12, blue: 0.14)
        VStack(spacing: 0) {
            Text("已过期").font(.system(size: 20 * u, weight: .black)).tracking(4 * u)
            Text(verbatim: "EXPIRED").font(.system(size: 9 * u, weight: .heavy)).tracking(3 * u)
        }
        .foregroundColor(red)
        .padding(.horizontal, 14 * u)
        .padding(.vertical, 6 * u)
        .overlay(RoundedRectangle(cornerRadius: 6 * u).stroke(red, lineWidth: 2.2 * u))
        .rotationEffect(.degrees(-14))
        .opacity(0.8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(x: 70 * u, y: 10 * u)
    }
}

private struct Guilloche: View {
    let ink: Color
    let u: CGFloat
    var spacing: CGFloat = 5.5
    var slope: CGFloat = 0.12

    var body: some View {
        Canvas { context, size in
            drawLines(in: context, size: size)
        }
    }

    private func drawLines(in context: GraphicsContext, size: CGSize) {
        let step: CGFloat = max(1.0, spacing * u)
        let amp: CGFloat = 2.6 * u
        let denomX: Double = Double(max(1.0, 13.0 * u))
        let denomY: Double = Double(max(1.0, 19.0 * u))
        var row: CGFloat = -size.height * 0.5
        let maxRow: CGFloat = size.height * 1.2
        while row <= maxRow {
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                let wave = CGFloat(sin(Double(x) / denomX + Double(row) / denomY))
                let y: CGFloat = row + x * slope + amp * wave
                if x == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                x += 3
            }
            context.stroke(path, with: .color(ink), lineWidth: 0.45)
            row += step
        }
    }
}

private struct VisaWatermark: View {
    let u: CGFloat
    var color: Color = .black

    var body: some View {
        Text(verbatim: "WAYTRACE · 漫迹")
            .font(.system(size: 7 * u, weight: .heavy))
            .tracking(2.5 * u)
            .foregroundColor(color.opacity(0.22))
    }
}

private struct VisaHeader<Content: View>: View {
    let u: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7 * u) { content }
            .frame(height: 30 * u, alignment: .bottom)
            .padding(.leading, 14 * u)
    }
}

private struct StickerLayout<Fields: View, Foot: View>: View {
    let document: VisaRecord
    let u: CGFloat
    let ink: Color
    @ViewBuilder var fields: Fields
    @ViewBuilder var foot: Foot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10 * u) {
                PhotoSlot(u: u, tint: ink).frame(width: 64 * u, height: 84 * u)
                VStack(alignment: .leading, spacing: 4 * u) { fields }
            }
            .padding(.horizontal, 14 * u)
            .padding(.top, 7 * u)
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                foot
                Spacer()
                VisaWatermark(u: u, color: ink)
            }
            .padding(.horizontal, 14 * u)
            MachineLines(document: document, u: u, color: ink)
                .padding(.horizontal, 14 * u)
                .padding(.top, 4 * u)
                .padding(.bottom, 9 * u)
        }
    }
}

// MARK: - United States

private struct UnitedStatesFace: View {
    let document: VisaRecord
    let u: CGFloat

    private let ink = Color(red: 0.10, green: 0.13, blue: 0.24)

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.99, green: 0.86, blue: 0.86),
                    Color(red: 0.99, green: 0.93, blue: 0.86),
                    Color(red: 0.86, green: 0.95, blue: 0.90),
                    Color(red: 0.84, green: 0.90, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Guilloche(ink: Color(red: 0.55, green: 0.35, blue: 0.55).opacity(0.13), u: u)
            BridgeShape(u: u).stroke(Color(red: 0.70, green: 0.25, blue: 0.20).opacity(0.14), lineWidth: 1.1 * u)
            VStack(alignment: .leading, spacing: 0) {
                VisaHeader(u: u) {
                    Text(verbatim: "UNITED STATES OF AMERICA")
                        .font(.custom("Georgia-Bold", fixedSize: 12.5 * u))
                        .tracking(0.8 * u)
                    Text(document.flag).font(.system(size: 11 * u))
                }
                .foregroundColor(ink)
                StickerLayout(document: document, u: u, ink: ink) {
                    HStack(alignment: .top) {
                        VisaField(label: "Issuing Post Name", value: document.issuingPost, u: u, ink: ink)
                        Spacer()
                        VisaField(label: "Control Number", value: controlNumber, u: u, ink: ink)
                    }
                    VisaField(label: "Surname", value: surname, u: u, ink: ink)
                    VisaField(label: "Given Name", value: given, u: u, ink: ink)
                    HStack(alignment: .top, spacing: 14 * u) {
                        VisaField(label: "Visa Type/Class", value: "R " + (document.visaType.isEmpty ? "—" : document.visaType), u: u, ink: ink)
                        VisaField(label: "Entries", value: entries, u: u, ink: ink)
                    }
                    HStack(alignment: .top, spacing: 14 * u) {
                        VisaField(label: "Issue Date", value: VisaDate.compact(document.issuedDate), u: u, ink: ink)
                        VisaField(label: "Expiration Date", value: VisaDate.compact(document.expiryDate), u: u, ink: ink)
                    }
                } foot: {
                    VisaField(label: "Annotation", value: document.notes.uppercased(), u: u, ink: ink, valueSize: 9)
                    Spacer()
                    Text(verbatim: document.visaNumber.uppercased())
                        .font(.system(size: 13 * u, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.78, green: 0.10, blue: 0.12))
                }
            }
        }
    }

    private var parts: [String] { document.holder.uppercased().split(separator: " ").map(String.init) }
    private var surname: String { parts.first ?? "" }
    private var given: String { parts.dropFirst().joined(separator: " ") }
    private var entries: String { document.entries == .multiple ? "M" : document.entries == .double ? "2" : "1" }
    private var controlNumber: String {
        guard let issued = document.issuedDate else { return "" }
        let cal = Calendar(identifier: .gregorian)
        let year = cal.component(.year, from: issued)
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: issued) ?? 1
        return String(format: "%04d%03d0000", year, dayOfYear)
    }
}

private struct BridgeShape: Shape {
    let u: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let deck = rect.height * 0.70
        let left = rect.width * 0.50, right = rect.width * 0.86
        let top = rect.height * 0.24
        for x in [left, right] {
            path.addRect(CGRect(x: x - 3 * u, y: top, width: 6 * u, height: rect.height - top))
            for level in stride(from: top + 12 * u, to: deck, by: 22 * u) {
                path.move(to: CGPoint(x: x - 3 * u, y: level))
                path.addLine(to: CGPoint(x: x + 3 * u, y: level))
            }
        }
        let sag = deck * 1.05
        path.move(to: CGPoint(x: rect.width * 0.30, y: deck))
        path.addQuadCurve(to: CGPoint(x: left, y: top), control: CGPoint(x: left - 20 * u, y: deck - 4 * u))
        path.addQuadCurve(to: CGPoint(x: right, y: top), control: CGPoint(x: (left + right) / 2, y: sag))
        path.addQuadCurve(to: CGPoint(x: rect.width * 1.02, y: deck), control: CGPoint(x: right + 20 * u, y: deck - 4 * u))
        path.move(to: CGPoint(x: rect.width * 0.28, y: deck))
        path.addLine(to: CGPoint(x: rect.width, y: deck))
        path.move(to: CGPoint(x: rect.width * 0.28, y: deck + 4 * u))
        path.addLine(to: CGPoint(x: rect.width, y: deck + 4 * u))
        for x in stride(from: left + 12 * u, to: right, by: 12 * u) {
            let t = (x - left) / (right - left)
            let cable = (1 - t) * (1 - t) * top + 2 * (1 - t) * t * sag + t * t * top
            path.move(to: CGPoint(x: x, y: cable))
            path.addLine(to: CGPoint(x: x, y: deck))
        }
        return path
    }
}

// MARK: - Schengen & Generic Stickers

private struct StickerFace: View {
    enum Style { case schengen, generic }
    let document: VisaRecord
    let u: CGFloat
    let style: Style

    private var hue: Double {
        Double(document.countryCode.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) } % 360) / 360
    }

    private var ink: Color {
        style == .schengen
            ? Color(red: 0.12, green: 0.15, blue: 0.38)
            : Color(hue: hue, saturation: 0.6, brightness: 0.28)
    }

    private var ground: [Color] {
        style == .schengen
            ? [Color(red: 0.97, green: 0.88, blue: 0.93), Color(red: 0.88, green: 0.90, blue: 0.99), Color(red: 0.88, green: 0.97, blue: 0.93)]
            : [Color(hue: hue, saturation: 0.12, brightness: 0.99), Color(hue: (hue + 0.1).truncatingRemainder(dividingBy: 1), saturation: 0.14, brightness: 0.96)]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: ground, startPoint: .topLeading, endPoint: .bottomTrailing)
            Guilloche(ink: ink.opacity(0.10), u: u, spacing: 5, slope: -0.08)
            if style == .schengen {
                StarRing(u: u)
                    .frame(width: 96 * u, height: 96 * u)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 22 * u)
                    .offset(y: -4 * u)
            }
            VStack(alignment: .leading, spacing: 0) {
                VisaHeader(u: u) {
                    Text(verbatim: "VISA").font(.system(size: 17 * u, weight: .heavy)).tracking(3 * u)
                    Text(verbatim: style == .schengen ? "SCHENGEN" : document.englishName)
                        .font(.system(size: 8 * u, weight: .bold))
                        .tracking(1.5 * u)
                        .opacity(0.7)
                    Text(document.flag).font(.system(size: 11 * u))
                }
                .foregroundColor(ink)
                StickerLayout(document: document, u: u, ink: ink) {
                    VisaField(label: "VALID FOR / VALABLE POUR", value: style == .schengen ? "ETATS SCHENGEN" : document.englishName, u: u, ink: ink)
                    HStack(spacing: 14 * u) {
                        VisaField(label: "FROM / DU", value: VisaDate.short(document.issuedDate), u: u, ink: ink)
                        VisaField(label: "UNTIL / AU", value: VisaDate.short(document.expiryDate), u: u, ink: ink)
                    }
                    HStack(spacing: 12 * u) {
                        VisaField(label: "TYPE OF VISA", value: document.visaType.isEmpty ? "C" : document.visaType.uppercased(), u: u, ink: ink)
                        VisaField(label: "NUMBER OF ENTRIES", value: entries, u: u, ink: ink)
                        VisaField(label: "DURATION OF STAY", value: document.stayDays.map { "\($0) DAYS" } ?? "", u: u, ink: ink)
                    }
                    HStack(spacing: 14 * u) {
                        VisaField(label: "ISSUED IN / DELIVRE A", value: document.issuingPost, u: u, ink: ink)
                        VisaField(label: "ON / LE", value: VisaDate.short(document.issuedDate), u: u, ink: ink)
                    }
                    VisaField(label: "SURNAME, NAME / NOM, PRENOMS", value: holder, u: u, ink: ink)
                } foot: {
                    VisaField(label: "REMARKS / REMARQUES", value: document.notes.uppercased(), u: u, ink: ink, valueSize: 9)
                }
            }
        }
    }

    private var entries: String { document.entries == .multiple ? "MULT" : document.entries == .double ? "02" : "01" }
    private var holder: String {
        let parts = document.holder.uppercased().split(separator: " ")
        guard let first = parts.first else { return "" }
        return parts.count > 1 ? "\(first), \(parts.dropFirst().joined(separator: " "))" : String(first)
    }
}

private struct StarRing: View {
    let u: CGFloat

    var body: some View {
        Canvas { context, size in
            drawStars(in: context, size: size)
        }
    }

    private func drawStars(in context: GraphicsContext, size: CGSize) {
        let cx: CGFloat = size.width * 0.5
        let cy: CGFloat = size.height * 0.5
        let radius: CGFloat = min(size.width, size.height) * 0.40
        let outerR: CGFloat = 5.5 * u
        let innerR: CGFloat = 2.3 * u
        let gold = Color(red: 0.86, green: 0.66, blue: 0.12).opacity(0.38)

        for i in 0..<12 {
            let angle: Double = Double(i) / 12.0 * 2.0 * .pi - .pi / 2.0
            let px: CGFloat = cx + CGFloat(cos(angle)) * radius
            let py: CGFloat = cy + CGFloat(sin(angle)) * radius
            var star = Path()
            for k in 0..<10 {
                let r: CGFloat = (k % 2 == 0) ? outerR : innerR
                let a: Double = Double(k) / 10.0 * 2.0 * .pi - .pi / 2.0
                let qx: CGFloat = px + r * CGFloat(cos(a))
                let qy: CGFloat = py + r * CGFloat(sin(a))
                let q = CGPoint(x: qx, y: qy)
                if k == 0 { star.move(to: q) } else { star.addLine(to: q) }
            }
            star.closeSubpath()
            context.fill(star, with: .color(gold))
        }
    }
}

// MARK: - Japan

private struct JapanFace: View {
    let document: VisaRecord
    let u: CGFloat

    private let ink = Color(red: 0.28, green: 0.12, blue: 0.26)

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(red: 1, green: 0.91, blue: 0.94),
                    Color(red: 0.94, green: 0.90, blue: 0.99),
                    Color(red: 0.90, green: 0.95, blue: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Guilloche(ink: ink.opacity(0.08), u: u, spacing: 6, slope: 0.05)
            Blossoms(u: u)
            VStack(alignment: .leading, spacing: 0) {
                VisaHeader(u: u) {
                    Text(verbatim: "査証").font(.custom("HiraMinProN-W6", fixedSize: 17 * u))
                    Text(verbatim: "VISA").font(.system(size: 13 * u, weight: .heavy)).tracking(3 * u)
                    Text(verbatim: "日本国 JAPAN").font(.system(size: 8 * u, weight: .bold)).tracking(1.2 * u).opacity(0.7)
                }
                .foregroundColor(ink)
                StickerLayout(document: document, u: u, ink: ink) {
                    VisaField(label: "種類 / TYPE", value: type, u: u, ink: ink)
                    HStack(spacing: 14 * u) {
                        VisaField(label: "回数 / ENTRIES", value: entries, u: u, ink: ink)
                        VisaField(label: "在留期間 / DURATION", value: document.stayDays.map { "\($0) DAYS" } ?? "", u: u, ink: ink)
                    }
                    HStack(spacing: 14 * u) {
                        VisaField(label: "発給日 / DATE OF ISSUE", value: VisaDate.spaced(document.issuedDate), u: u, ink: ink)
                        VisaField(label: "有効期限 / VALID UNTIL", value: VisaDate.spaced(document.expiryDate), u: u, ink: ink)
                    }
                    HStack(spacing: 14 * u) {
                        VisaField(label: "発給地 / PLACE", value: document.issuingPost, u: u, ink: ink)
                        VisaField(label: "氏名 / NAME", value: document.holder.uppercased(), u: u, ink: ink)
                    }
                } foot: {
                    VisaField(label: "備考 / REMARKS", value: document.notes.uppercased(), u: u, ink: ink, valueSize: 9)
                }
            }
        }
    }

    private var type: String {
        let cat = document.visaType.uppercased()
        if cat.isEmpty || cat.contains("短期") { return "TEMPORARY VISITOR" }
        return cat
    }
    private var entries: String { document.entries == .multiple ? "MULTIPLE" : document.entries == .double ? "DOUBLE" : "SINGLE" }
}

private struct Blossoms: View {
    let u: CGFloat

    var body: some View {
        Canvas { context, size in
            drawBlossoms(in: context, size: size)
        }
    }

    private func drawBlossoms(in context: GraphicsContext, size: CGSize) {
        var random = SeededRandom(11)
        let pink = Color(red: 0.95, green: 0.55, blue: 0.68).opacity(0.15)
        for _ in 0..<11 {
            let cx: CGFloat = size.width * CGFloat(0.45 + random.unit() * 0.6)
            let cy: CGFloat = size.height * CGFloat(random.unit())
            let radius: CGFloat = CGFloat(7.0 + random.unit() * 10.0) * u
            let rotation: Double = random.unit() * .pi
            let petalRect = CGRect(x: -radius * 0.32, y: -radius, width: radius * 0.64, height: radius)
            for i in 0..<5 {
                let angle: CGFloat = CGFloat(rotation + Double(i) / 5.0 * 2.0 * .pi)
                let transform = CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: cx, y: cy))
                let petal = Path(ellipseIn: petalRect).applying(transform)
                context.fill(petal, with: .color(pink))
            }
        }
    }
}

// MARK: - Electronic Grant Notice (AU / NZ / eVisa)

private struct GrantNoticeFace: View {
    let document: VisaRecord
    let u: CGFloat

    private var band: [Color] {
        switch document.countryCode {
        case "AU": return [Color(red: 0.86, green: 0.55, blue: 0.20), Color(red: 0.12, green: 0.45, blue: 0.42)]
        case "NZ": return [Color(red: 0.05, green: 0.12, blue: 0.14), Color(red: 0.10, green: 0.42, blue: 0.38)]
        default: return [Color(red: 0.20, green: 0.30, blue: 0.55), Color(red: 0.35, green: 0.55, blue: 0.75)]
        }
    }
    private let ink = Color(red: 0.12, green: 0.13, blue: 0.16)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .leading) {
                LinearGradient(colors: band, startPoint: .leading, endPoint: .trailing)
                HStack(spacing: 7 * u) {
                    Text(document.flag).font(.system(size: 13 * u))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: document.countryCode == "NZ" ? "Visa approval notice" : "Visa grant notice")
                            .font(.system(size: 12.5 * u, weight: .bold))
                        Text(verbatim: "\(document.englishName) · ELECTRONIC VISA")
                            .font(.system(size: 6.5 * u, weight: .bold))
                            .tracking(1.2 * u)
                            .opacity(0.8)
                    }
                }
                .foregroundColor(.white)
                .padding(.leading, 14 * u)
            }
            .frame(height: 40 * u)

            ZStack(alignment: .topLeading) {
                Color(red: 0.995, green: 0.99, blue: 0.98)
                Guilloche(ink: band[1].opacity(0.06), u: u, spacing: 7, slope: 0.02)
                VStack(alignment: .leading, spacing: 0) {
                    row("Visa holder", document.holder.isEmpty ? "—" : document.holder.uppercased())
                    row("Visa", visaLabel)
                    row("Visa grant number", document.visaNumber.isEmpty ? "—" : document.visaNumber.uppercased())
                    row("Date of grant", VisaDate.spaced(document.issuedDate))
                    row("Must not arrive after", VisaDate.spaced(document.expiryDate))
                    row("Period of stay", document.stayDays.map { "\($0) days from each arrival" } ?? "—")
                    row("Travel", document.entries == .multiple ? "Multiple entries" : document.entries == .double ? "Two entries" : "Single entry", last: true)
                    Spacer(minLength: 0)
                    HStack {
                        Text(verbatim: "No label is placed in the passport. Keep this notice.")
                            .font(.system(size: 6.5 * u, weight: .medium))
                            .foregroundColor(ink.opacity(0.45))
                        Spacer()
                        VisaWatermark(u: u, color: ink)
                    }
                    .padding(.bottom, 9 * u)
                }
                .padding(.horizontal, 14 * u)
                .padding(.top, 6 * u)
            }
        }
    }

    private var visaLabel: String {
        let cat = document.visaType
        if cat.isEmpty { return "Visitor" }
        return cat.allSatisfy(\.isNumber) ? "Visitor (subclass \(cat))" : cat
    }

    private func row(_ label: String, _ value: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: label)
                    .font(.system(size: 8 * u, weight: .medium))
                    .foregroundColor(ink.opacity(0.55))
                    .frame(width: 104 * u, alignment: .leading)
                Text(verbatim: value)
                    .font(.system(size: 9.5 * u, weight: .semibold))
                    .foregroundColor(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3.6 * u)
            if !last { Rectangle().fill(ink.opacity(0.08)).frame(height: 0.5) }
        }
    }
}

// MARK: - Passport Card Face

private struct PassportFace: View {
    let document: VisaRecord
    let u: CGFloat
    @AppStorage("wt16.passport.theme") private var themeRaw: String = PassportTheme.obsidian.rawValue

    private var theme: PassportTheme { PassportTheme(rawValue: themeRaw) ?? .obsidian }

    var body: some View {
        let foil = Color(red: 0.95, green: 0.86, blue: 0.62)
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [theme.leather.opacity(0.92), theme.leather],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Canvas { context, size in
                var random = SeededRandom(3)
                let count = min(1400, Int(size.width * size.height / 40))
                for _ in 0..<count {
                    let p = CGPoint(x: random.unit() * size.width, y: random.unit() * size.height)
                    context.fill(
                        Path(ellipseIn: CGRect(x: p.x, y: p.y, width: 1.1, height: 1.1)),
                        with: .color(random.unit() > 0.5 ? .white.opacity(0.07) : .black.opacity(0.18))
                    )
                }
            }
            Image(systemName: theme.emblem)
                .resizable()
                .scaledToFit()
                .frame(width: 110 * u, height: 110 * u)
                .foregroundStyle(theme.foilGradient)
                .opacity(0.16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 24 * u)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8 * u) {
                    Text("护照").font(.system(size: 16 * u, weight: .semibold)).tracking(4 * u)
                    Text(verbatim: "PASSPORT").font(.custom("AcademyEngravedLetPlain", fixedSize: 12 * u)).tracking(3 * u)
                }
                .foregroundStyle(theme.foilGradient)
                .frame(height: 30 * u, alignment: .bottom)

                Rectangle().fill(foil.opacity(0.35)).frame(height: 0.7).padding(.top, 6 * u)
                Spacer(minLength: 0)

                HStack(alignment: .bottom, spacing: 22 * u) {
                    VisaField(label: "TYPE / 类型", value: "P", u: u, ink: foil, valueSize: 13)
                    VisaField(label: "ISSUING STATE / 签发国", value: VisaCatalog.alpha3(document.countryCode), u: u, ink: foil, valueSize: 13)
                    VisaField(label: "PASSPORT NO. / 护照号", value: document.visaNumber.uppercased(), u: u, ink: foil, valueSize: 13)
                }
                .padding(.bottom, 10 * u)

                HStack(alignment: .bottom, spacing: 22 * u) {
                    VisaField(label: "DATE OF ISSUE / 签发日期", value: VisaDate.spaced(document.issuedDate), u: u, ink: foil, valueSize: 12)
                    VisaField(label: "DATE OF EXPIRY / 有效期至", value: VisaDate.spaced(document.expiryDate), u: u, ink: foil, valueSize: 12)
                }

                Spacer(minLength: 0)
                MachineLines(document: document, u: u, color: foil)
                    .padding(.bottom, 9 * u)
            }
            .padding(.horizontal, 16 * u)
        }
    }
}
