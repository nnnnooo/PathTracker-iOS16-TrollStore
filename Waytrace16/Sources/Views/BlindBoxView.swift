import SwiftUI
import MapKit
import UIKit

struct BlindBoxView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var engine: LocationEngine
    @ObservedObject private var userStore = MustSeeUserStore.shared
    @ObservedObject private var boxStore = BlindBoxStore.shared

    @State private var horizon: BlindBoxEngine.Horizon = .weekend
    @State private var vibe: BlindBoxEngine.Vibe = .any
    @State private var currentPass: BoardingPass?
    @State private var isPressing = false
    @State private var pressProgress: CGFloat = 0
    @State private var shakePhase = false
    @State private var visitedIDs: Set<String> = []

    private let nightTop = Color(red: 0.08, green: 0.09, blue: 0.17)
    private let nightBottom = Color(red: 0.13, green: 0.12, blue: 0.22)
    private let gold = Color(red: 0.98, green: 0.78, blue: 0.36)

    var body: some View {
        ZStack {
            LinearGradient(colors: [nightTop, nightBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            BlindBoxStarfield()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 22) {
                    if let pass = currentPass {
                        boardingPassSection(pass)
                    } else {
                        headerGreeting
                        parcelHero
                        selectorCard
                    }

                    if !boxStore.savedPasses.isEmpty {
                        savedPassesSection
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(currentPass != nil)
        .toolbar {
            if currentPass != nil {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.easeInOut(duration: 0.25)) {
                            currentPass = nil
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                            Text("盲盒")
                        }
                        .foregroundColor(.white)
                    }
                }
            }
            ToolbarItem(placement: .principal) {
                Text("旅行盲盒")
                    .font(.headline)
                    .foregroundColor(.white)
            }
        }
        .task(id: "\(store.stays.count)-\(userStore.revision)") {
            let staysSnapshot = store.stays
            let manualSnapshot = userStore.manualVisits
            let excludedSnapshot = userStore.excludedAutoIDs
            let computed = await Task.detached(priority: .userInitiated) {
                Set(MustSee.visitedMap(places: MustSee.allPlaces, stays: staysSnapshot, manual: manualSnapshot, excluded: excludedSnapshot).keys)
            }.value
            visitedIDs = computed
        }
    }

    // MARK: - Greeting Header

    private var headerGreeting: some View {
        VStack(spacing: 6) {
            Text(todayDateLabel)
                .font(.caption.weight(.semibold))
                .foregroundColor(gold.opacity(0.9))
            Text(greetingLine)
                .font(.title2.bold())
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    private var todayDateLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: Date())
    }

    private var greetingLine: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 11 { return "新的一天，去一个没去过的地方。" }
        if hour < 17 { return "换个方向走走，风景就在路上。" }
        return "今天有点晚了，明天还来得及。"
    }

    // MARK: - Kraft-Paper Parcel Hero (1:1 Upstream blind-box.jpg)

    private var parcelHero: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.08), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 155
                        )
                    )
                    .frame(width: 290, height: 290)

                KraftParcelArt()
                    .frame(width: 224, height: 196)
                    .scaleEffect(isPressing ? 0.94 : 1.0)
                    .rotationEffect(.degrees(shakePhase ? 2.8 : (isPressing ? -1.5 : 0)))
                    .animation(.spring(response: 0.25, dampingFraction: 0.55), value: isPressing)
                    .animation(.easeInOut(duration: 0.09).repeatCount(isPressing ? 6 : 0, autoreverses: true), value: shakePhase)
            }
            .contentShape(Rectangle())
            .onTapGesture { drawNewPass() }
            .onLongPressGesture(minimumDuration: 0.45, pressing: { pressing in
                isPressing = pressing
                if pressing {
                    shakePhase.toggle()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }, perform: {
                drawNewPass()
            })

            Button {
                drawNewPass()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                        .font(.subheadline)
                    Text("长按或轻点拆开")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.14), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
            }
            .buttonStyle(PressableStyle())

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(gold)
                        .frame(width: 14, height: 4)
                }
                Text("只抽你还没去过的地方")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.leading, 4)
            }
        }
    }

    // MARK: - Dark Glass Selector Card

    private var selectorCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("你有多少时间")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                Text(horizonSubtitle(horizon))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }

            HStack(spacing: 8) {
                ForEach(BlindBoxEngine.Horizon.allCases) { item in
                    let on = horizon == item
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.easeInOut(duration: 0.2)) { horizon = item }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: horizonSymbol(item))
                                .font(.title3)
                                .foregroundColor(on ? gold : .white.opacity(0.6))
                            Text(item.title)
                                .font(.caption.weight(on ? .semibold : .regular))
                                .foregroundColor(on ? .white : .white.opacity(0.7))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            on ? Color.white.opacity(0.14) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(on ? Color.white.opacity(0.28) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Divider().background(Color.white.opacity(0.12))

            Text("想要什么感觉")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.75))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BlindBoxEngine.Vibe.allCases) { item in
                        let on = vibe == item
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.easeInOut(duration: 0.2)) { vibe = item }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: vibeSymbol(item))
                                    .font(.caption)
                                    .foregroundColor(on ? gold : .white.opacity(0.65))
                                Text(item.title)
                                    .font(.subheadline.weight(on ? .semibold : .regular))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(on ? Color.white.opacity(0.16) : Color.white.opacity(0.06), in: Capsule())
                            .overlay(Capsule().stroke(on ? Color.white.opacity(0.32) : Color.white.opacity(0.08), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    // MARK: - Cream Boarding Pass Ticket (1:1 Upstream blind-box-ticket.jpg)

    private func boardingPassSection(_ pass: BoardingPass) -> some View {
        let alreadySaved = boxStore.savedPasses.contains { $0.placeID == pass.placeID }
        let cream = Color(red: 0.97, green: 0.95, blue: 0.90)
        let ink = Color(red: 0.16, green: 0.15, blue: 0.14)

        return VStack(spacing: 16) {
            // Ticket card with semicircular side cutouts
            VStack(spacing: 0) {
                // Top scenic header
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.15, green: 0.24, blue: 0.34), Color(red: 0.09, green: 0.14, blue: 0.22)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    HStack {
                        Text("WAYTRACE")
                            .font(.caption.monospaced().weight(.bold))
                            .tracking(3)
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                        Label(horizon.title, systemImage: horizonSymbol(horizon))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(gold)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .frame(maxHeight: .infinity, alignment: .top)

                    Image(systemName: "airplane.departure")
                        .font(.system(size: 42))
                        .foregroundColor(.white.opacity(0.18))
                        .offset(y: 12)
                }
                .frame(height: 112)

                // Main destination body
                VStack(alignment: .leading, spacing: 6) {
                    Text(originLabel)
                        .font(.caption.weight(.medium))
                        .foregroundColor(ink.opacity(0.55))
                    Text(pass.placeName)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(ink)
                    Text(pass.region)
                        .font(.subheadline)
                        .foregroundColor(ink.opacity(0.65))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 16)
                .background(cream)

                // Perforated tear line with side notches
                ZStack {
                    cream
                    LineSeparator()
                        .stroke(ink.opacity(0.18), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                        .frame(height: 1)
                        .padding(.horizontal, 18)
                    HStack {
                        Circle().fill(nightBottom).frame(width: 20, height: 20).offset(x: -10)
                        Spacer()
                        Circle().fill(nightBottom).frame(width: 20, height: 20).offset(x: 10)
                    }
                }
                .frame(height: 22)

                // Bottom info + editorial line
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("距离")
                                .font(.caption2)
                                .foregroundColor(ink.opacity(0.5))
                            Text(pass.distanceKm.map { String(format: "约 %.1f 公里", $0) } ?? "待出发")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundColor(ink)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("氛围")
                                .font(.caption2)
                                .foregroundColor(ink.opacity(0.5))
                            Text(vibe.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(ink)
                        }
                        Spacer()
                    }

                    Text(pass.reason)
                        .font(.body)
                        .foregroundColor(ink.opacity(0.88))
                        .lineSpacing(4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 22)
                .background(cream)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)

            // Suggestion card (dark glass)
            VStack(alignment: .leading, spacing: 10) {
                Label("到了可以这样玩", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(gold)
                Text(pass.suggestion)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            // Actions
            HStack(spacing: 10) {
                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    boxStore.save(pass)
                    userStore.addWish(pass.placeID)
                } label: {
                    Label(alreadySaved ? "已收下登机牌" : "收下登机牌", systemImage: alreadySaved ? "checkmark.circle.fill" : "ticket.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(gold)
                .foregroundColor(.black)
                .disabled(alreadySaved)

                Button {
                    drawNewPass()
                } label: {
                    Label("再拆一个", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }

            HStack(spacing: 12) {
                if let place = MustSee.allPlaces.first(where: { $0.id == pass.placeID }) {
                    Button {
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate.onMap))
                        item.name = place.name
                        item.openInMaps()
                    } label: {
                        Label("在 Apple 地图中查看", systemImage: "map")
                            .font(.footnote.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.8))
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { currentPass = nil }
                } label: {
                    Text("返回盲盒")
                        .font(.footnote.weight(.medium))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Saved Boarding Passes Wallet

    private var savedPassesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("你的登机牌")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                Text("在等你 \(boxStore.savedPasses.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.10), in: Capsule())
                Spacer()
            }
            .padding(.horizontal, 2)

            VStack(spacing: 10) {
                ForEach(boxStore.savedPasses) { pass in
                    let arrived = visitedIDs.contains(pass.placeID)
                    HStack(spacing: 12) {
                        Image(systemName: "ticket.fill")
                            .font(.title3)
                            .foregroundColor(arrived ? .green : gold)
                            .frame(width: 40, height: 40)
                            .background((arrived ? Color.green : gold).opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(pass.placeName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                Text(arrived ? "已经到了" : "在等你")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((arrived ? Color.green : gold).opacity(0.22), in: Capsule())
                                    .foregroundColor(arrived ? .green : gold)
                            }
                            Text("\(pass.region) · \(Formatters.dayTitle(pass.drawnAt)) 拆出")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.58))
                        }
                        Spacer()
                        Button {
                            boxStore.remove(id: pass.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.45))
                                .padding(8)
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            currentPass = pass
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var originLabel: String {
        if let city = store.stays.first?.city, !city.isEmpty {
            return "从\(city)出发"
        }
        return "从这里出发"
    }

    private func horizonSubtitle(_ h: BlindBoxEngine.Horizon) -> String {
        switch h {
        case .dayTrip: return "当天来回"
        case .weekend: return "两天一夜"
        case .shortHoliday: return "三到五天"
        case .longHoliday: return "说走就走"
        }
    }

    private func horizonSymbol(_ h: BlindBoxEngine.Horizon) -> String {
        switch h {
        case .dayTrip: return "sun.max.fill"
        case .weekend: return "tent.fill"
        case .shortHoliday: return "suitcase.fill"
        case .longHoliday: return "airplane"
        }
    }

    private func vibeSymbol(_ v: BlindBoxEngine.Vibe) -> String {
        switch v {
        case .any: return "sparkles"
        case .relax: return "water.waves"
        case .active: return "mountain.2.fill"
        case .culture: return "building.columns.fill"
        case .city: return "building.2.fill"
        case .wild: return "leaf.fill"
        }
    }

    private func drawNewPass() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            currentPass = BlindBoxEngine.draw(
                horizon: horizon,
                vibe: vibe,
                userLocation: engine.currentLocation ?? store.stays.first?.location,
                visitedIDs: visitedIDs,
                wishIDs: userStore.wishIDs,
                excludingPlaceID: currentPass?.placeID
            )
        }
    }
}

// MARK: - Vector Kraft Parcel Art (Matching blind-box.jpg)

struct KraftParcelArt: View {
    var body: some View {
        ZStack {
            // Parcel body
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.76, green: 0.62, blue: 0.45), Color(red: 0.64, green: 0.49, blue: 0.34)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 196, height: 150)
                .offset(y: 16)
                .shadow(color: .black.opacity(0.42), radius: 14, y: 10)

            // Postal airplane stamp bottom-left
            ZStack {
                Circle().stroke(Color(red: 0.48, green: 0.22, blue: 0.16).opacity(0.55), lineWidth: 2)
                Circle().inset(by: 5).stroke(Color(red: 0.48, green: 0.22, blue: 0.16).opacity(0.45), lineWidth: 0.9)
                Image(systemName: "airplane")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(red: 0.48, green: 0.22, blue: 0.16).opacity(0.6))
                    .rotationEffect(.degrees(-25))
            }
            .frame(width: 48, height: 48)
            .offset(x: -54, y: 58)

            // Airmail red-white-blue stripe under lid
            AirmailStripeView()
                .frame(width: 196, height: 9)
                .offset(y: -48)

            // Parcel lid
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.80, green: 0.66, blue: 0.49), Color(red: 0.71, green: 0.56, blue: 0.40)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 212, height: 34)
                .offset(y: -66)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 3)

            // Cream twine cross
            Rectangle()
                .fill(Color(red: 0.94, green: 0.89, blue: 0.80))
                .frame(width: 5, height: 174)
                .offset(y: 4)
            Rectangle()
                .fill(Color(red: 0.94, green: 0.89, blue: 0.80))
                .frame(width: 196, height: 5)
                .offset(y: 38)

            // Ribbon bow on top
            HStack(spacing: -2) {
                Capsule()
                    .stroke(Color(red: 0.94, green: 0.89, blue: 0.80), lineWidth: 4.5)
                    .frame(width: 34, height: 18)
                    .rotationEffect(.degrees(22))
                Capsule()
                    .stroke(Color(red: 0.94, green: 0.89, blue: 0.80), lineWidth: 4.5)
                    .frame(width: 34, height: 18)
                    .rotationEffect(.degrees(-22))
            }
            .offset(y: -88)

            // Dangling cream luggage tag "?"
            VStack(spacing: 4) {
                Circle()
                    .fill(Color(red: 0.55, green: 0.43, blue: 0.30))
                    .frame(width: 6, height: 6)
                Text("?")
                    .font(.system(size: 24, weight: .black, design: .serif))
                    .foregroundColor(Color(red: 0.24, green: 0.18, blue: 0.14))
            }
            .frame(width: 38, height: 54)
            .background(Color(red: 0.97, green: 0.94, blue: 0.88), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 3)
            .rotationEffect(.degrees(9))
            .offset(x: 78, y: -12)
        }
    }
}

private struct AirmailStripeView: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let colors: [Color] = [Color(red: 0.76, green: 0.22, blue: 0.22), Color(red: 0.16, green: 0.36, blue: 0.68)]
            var idx = 0
            for x in stride(from: -10.0, to: size.width + 16, by: 16) {
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + 8, y: size.height))
                p.addLine(to: CGPoint(x: x + 14, y: 0))
                p.addLine(to: CGPoint(x: x + 6, y: 0))
                p.closeSubpath()
                context.fill(p, with: .color(colors[idx % 2]))
                idx += 1
            }
        }
        .clipped()
    }
}

private struct BlindBoxStarfield: View {
    var body: some View {
        Canvas { context, size in
            var r = SeededRandom(777)
            for _ in 0..<55 {
                let pt = CGPoint(x: r.unit() * size.width, y: r.unit() * size.height)
                let radius = CGFloat(0.6 + r.unit() * 1.3)
                context.fill(
                    Path(ellipseIn: CGRect(x: pt.x, y: pt.y, width: radius * 2, height: radius * 2)),
                    with: .color(.white.opacity(0.18 + r.unit() * 0.45))
                )
            }
        }
    }
}

private struct LineSeparator: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return p
    }
}
