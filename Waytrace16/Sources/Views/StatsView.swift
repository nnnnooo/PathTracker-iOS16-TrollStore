import SwiftUI
import Charts
import UIKit

/// 1:1 Original PathTracker (漫迹) Stats Page adapted for iOS 16.
struct StatsView: View {
    @Binding var showingSettings: Bool
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var tagger: PlaceTagger

    enum Period: String, CaseIterable, Identifiable {
        case week = "周"
        case month = "月"
        case year = "年"
        var id: String { rawValue }
    }

    @State private var period: Period = .week
    @State private var selectedMode: MovementMode?
    @State private var showAllRoutesMap = false
    @State private var showYearReport = false

    private struct StackedBarItem: Identifiable {
        let id: String
        let label: String
        let mode: MovementMode
        let km: Double
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var periodWindow: (start: Date, end: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: today) ?? Date()
        switch period {
        case .week:
            let start = cal.date(byAdding: .day, value: -6, to: today) ?? today
            return (start, end)
        case .month:
            let start = cal.date(byAdding: .day, value: -29, to: today) ?? today
            return (start, end)
        case .year:
            let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today
            let start = cal.date(byAdding: .month, value: -11, to: startOfMonth) ?? today
            return (start, end)
        }
    }

    private var periodAllChunks: [TrackChunk] {
        let win = periodWindow
        return store.chunks.filter { $0.startDate >= win.start && $0.startDate < win.end }
    }

    private var periodGroundChunks: [TrackChunk] {
        periodAllChunks.filter { $0.mode != .flying }
    }

    private var periodFlightKm: Double {
        periodAllChunks.filter { $0.mode == .flying }.reduce(0.0) { $0 + $1.distance } / 1000.0
    }

    private var periodModeStats: [(mode: MovementMode, km: Double, ratio: Double)] {
        let grouped = Dictionary(grouping: periodGroundChunks) { $0.mode }
        let totals = grouped.map { ($0.key, $0.value.reduce(0.0) { $0 + $1.distance } / 1000.0) }
            .filter { $0.1 > 0.05 }
            .sorted { $0.1 > $1.1 }
        let sum = max(0.01, totals.reduce(0.0) { $0 + $1.1 })
        return totals.map { ($0.0, $0.1, $0.1 / sum) }
    }

    private var periodTotalKm: Double {
        periodGroundChunks.reduce(0.0) { $0 + $1.distance } / 1000.0
    }

    private var stackedChartItems: [StackedBarItem] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let ground = periodGroundChunks
        let weekdayNames = ["", "日", "一", "二", "三", "四", "五", "六"]
        var items: [StackedBarItem] = []

        switch period {
        case .week:
            for offset in (0..<7).reversed() {
                let day = cal.date(byAdding: .day, value: -offset, to: today)!
                let next = cal.date(byAdding: .day, value: 1, to: day)!
                let wd = cal.component(.weekday, from: day)
                let label = (wd >= 1 && wd <= 7) ? weekdayNames[wd] : "\(wd)"
                let dayChunks = ground.filter { $0.startDate >= day && $0.startDate < next }
                let byMode = Dictionary(grouping: dayChunks) { $0.mode }
                if byMode.isEmpty {
                    items.append(StackedBarItem(id: "w-\(offset)-empty", label: label, mode: .walking, km: 0))
                } else {
                    for (mode, list) in byMode.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                        let km = list.reduce(0.0) { $0 + $1.distance } / 1000.0
                        items.append(StackedBarItem(id: "w-\(offset)-\(mode.rawValue)", label: label, mode: mode, km: km))
                    }
                }
            }
        case .month:
            for offset in (0..<30).reversed() {
                let day = cal.date(byAdding: .day, value: -offset, to: today)!
                let next = cal.date(byAdding: .day, value: 1, to: day)!
                let label = "\(cal.component(.day, from: day))"
                let dayChunks = ground.filter { $0.startDate >= day && $0.startDate < next }
                let byMode = Dictionary(grouping: dayChunks) { $0.mode }
                if byMode.isEmpty {
                    items.append(StackedBarItem(id: "m-\(offset)-empty", label: label, mode: .walking, km: 0))
                } else {
                    for (mode, list) in byMode.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                        let km = list.reduce(0.0) { $0 + $1.distance } / 1000.0
                        items.append(StackedBarItem(id: "m-\(offset)-\(mode.rawValue)", label: label, mode: mode, km: km))
                    }
                }
            }
        case .year:
            let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: today))!
            for offset in (0..<12).reversed() {
                let m = cal.date(byAdding: .month, value: -offset, to: startOfMonth)!
                let next = cal.date(byAdding: .month, value: 1, to: m)!
                let label = "\(cal.component(.month, from: m))月"
                let mChunks = ground.filter { $0.startDate >= m && $0.startDate < next }
                let byMode = Dictionary(grouping: mChunks) { $0.mode }
                if byMode.isEmpty {
                    items.append(StackedBarItem(id: "y-\(offset)-empty", label: label, mode: .walking, km: 0))
                } else {
                    for (mode, list) in byMode.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                        let km = list.reduce(0.0) { $0 + $1.distance } / 1000.0
                        items.append(StackedBarItem(id: "y-\(offset)-\(mode.rawValue)", label: label, mode: mode, km: km))
                    }
                }
            }
        }
        return items
    }

    private var groundLifetimeMeters: Double {
        store.chunks.filter { $0.mode != .flying }.reduce(0.0) { $0 + $1.distance }
    }

    private var portrait: WayTravellerPortrait {
        WayTravellerPortrait.build(stays: store.stays, chunks: store.chunks, privacyZones: store.privacyZones)
    }

    private var firstsData: (firsts: [WayLifeFirst], extremes: WayLifeExtremes) {
        WayLifeFirstsEngine.build(stays: store.stays)
    }

    private var milestoneProgress: WayMilestoneProgress {
        WayMilestoneProgress.build(stays: store.stays, chunks: store.chunks)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("周期", selection: $period) {
                        ForEach(Period.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)

                    allRoutesBannerCard
                    yearBannerCard
                    stepsCard
                    distanceChartCard
                    if !periodModeStats.isEmpty {
                        modeDonutCard
                    }
                    allTimeSection
                    storiesSection
                    milestonesSummaryCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("统计")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProfileToolbarButton(showingSettings: $showingSettings)
                }
            }
            .onChange(of: period) { _ in selectedMode = nil }
            .fullScreenCover(isPresented: $showAllRoutesMap) {
                AllRoutesMapScreen()
            }
            .fullScreenCover(isPresented: $showYearReport) {
                YearReportView()
            }
        }
    }

    // MARK: - 1. 走过的路 Dark Gold-Trails Card

    private var allRoutesBannerCard: some View {
        Button {
            showAllRoutesMap = true
        } label: {
            ZStack(alignment: .trailing) {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.07, blue: 0.15), Color(red: 0.09, green: 0.11, blue: 0.22)],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                AllRoutesGoldArtwork()
                    .frame(width: 170, height: 104)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("走过的路")
                            .font(.system(.title3, design: .serif).weight(.bold))
                            .foregroundColor(.white)
                        Text("今天、本周、本月、今年，\n所有轨迹叠在一张地图上")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.72))
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.55))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
            .frame(minHeight: 96)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - 2. 年度足迹 Card

    private var yearBannerCard: some View {
        Button {
            showYearReport = true
        } label: {
            HStack(spacing: 14) {
                Text(String(currentYear))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 68, height: 56)
                    .background(
                        LinearGradient(colors: [Color(red: 1.0, green: 0.65, blue: 0.22), Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("年度足迹")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("这一年走了多远、去了哪里，\n可以分享")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - 3. 步数 Card

    private var stepsCard: some View {
        let walkMeters = periodGroundChunks.filter { $0.mode == .walking || $0.mode == .running }.reduce(0.0) { $0 + $1.distance }
        let daysInPeriod = period == .week ? 7 : (period == .month ? 30 : 365)
        let estimatedDailySteps = Int((walkMeters / 0.72 / Double(daysInPeriod)).rounded())

        return VStack(alignment: .leading, spacing: 6) {
            Label("步数", systemImage: "figure.walk")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.orange)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Self.formattedInt(estimatedDailySteps))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("日均")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - 4. 移动距离 Stacked Bar Chart Card

    private var distanceChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label("移动距离", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.blue)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Self.formatKm(periodTotalKm))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("合计 · 不含飞行")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            if !periodModeStats.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(periodModeStats, id: \.mode) { item in
                            HStack(spacing: 5) {
                                Image(systemName: item.mode.symbol)
                                    .font(.caption.weight(.bold))
                                Text(Self.formatKm(item.km))
                                    .font(.caption.weight(.semibold).monospacedDigit())
                            }
                            .foregroundColor(item.mode.color)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(item.mode.color.opacity(0.14), in: Capsule())
                        }
                    }
                }
            }

            Chart(stackedChartItems) { item in
                BarMark(
                    x: .value("时间", item.label),
                    y: .value("公里", item.km)
                )
                .foregroundStyle(item.mode.color)
                .cornerRadius(4)
            }
            .frame(height: 195)
            .chartYAxis {
                AxisMarks(position: .trailing) { val in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = val.as(Double.self) {
                            Text("\(Int(v.rounded())) 公里")
                                .font(.caption2)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - 5. 出行方式 1:1 Original Segmented Sector Donut Ring (Screenshot 1)

    private var modeDonutCard: some View {
        let stats = periodModeStats
        let focus = selectedMode.flatMap { m in stats.first { $0.mode == m } }

        return VStack(alignment: .leading, spacing: 14) {
            Text("出行方式")
                .font(.headline)

            HStack(spacing: 20) {
                ZStack {
                    OriginalModeDonutView(
                        slices: stats.map { (mode: $0.mode, color: $0.mode.color, ratio: $0.ratio) },
                        selectedMode: selectedMode
                    )
                    .frame(width: 132, height: 132)

                    VStack(spacing: 1) {
                        if let focus {
                            Image(systemName: focus.mode.symbol)
                                .font(.caption.weight(.bold))
                                .foregroundColor(focus.mode.color)
                            Text("\(Int((focus.ratio * 100).rounded()))%")
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .monospacedDigit()
                        } else {
                            Text(Self.formatKm(periodTotalKm))
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .monospacedDigit()
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.65)
                            Text("地面合计")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 72)
                }

                VStack(spacing: 6) {
                    ForEach(stats.prefix(5), id: \.mode) { item in
                        let isSelected = (selectedMode == item.mode)
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                selectedMode = isSelected ? nil : item.mode
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.mode.symbol)
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.white)
                                    .frame(width: 26, height: 26)
                                    .background(
                                        LinearGradient(colors: [item.mode.color.opacity(0.85), item.mode.color], startPoint: .top, endPoint: .bottom),
                                        in: Circle()
                                    )
                                Text(item.mode.title)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Spacer(minLength: 4)
                                Text(Self.formatKm(item.km))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? item.mode.color.opacity(0.14) : Color.clear)
                            )
                            .opacity(selectedMode == nil || isSelected ? 1.0 : 0.45)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if periodFlightKm > 0.5 {
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: MovementMode.flying.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .background(MovementMode.flying.color, in: Circle())
                    Text("另有飞行")
                        .font(.subheadline)
                    Spacer(minLength: 4)
                    Text(Self.formatKm(periodFlightKm))
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - 6. 一直以来 Section

    private var allTimeSection: some View {
        let countriesCount = Set(store.stays.compactMap(\.countryCode)).count
        let citiesCount = Set(store.stays.compactMap(\.city)).count
        let firstDate = store.stays.map(\.arrival).min()

        return VStack(alignment: .leading, spacing: 10) {
            Text("一直以来")
                .font(.title3.bold())
                .padding(.horizontal, 4)

            MetricGrid2x2 {
                MetricTile(title: "国家与地区", value: "\(countriesCount)", symbol: "flag.fill", tint: .red)
            } topRight: {
                MetricTile(title: "城市", value: "\(citiesCount)", symbol: "building.2.fill", tint: .indigo)
            } bottomLeft: {
                MetricTile(title: "记录天数", value: "\(store.recordedDaysCount)", symbol: "calendar", tint: .teal)
            } bottomRight: {
                MetricTile(title: "到访次数", value: "\(store.stays.count)", symbol: "mappin.and.ellipse", tint: .pink)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let firstDate {
                    Text("从 \(Self.zhFullDate(firstDate)) 开始记录")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if tagger.pendingCount > 0 {
                    Text("⏳ 还有 \(Self.formattedInt(tagger.pendingCount)) 个地点正在识别，国家和城市的数字还会增加。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 6)
        }
    }

    // MARK: - 7. 你的故事 Section (1:1 Original Portrait + Silk Road Journey + Firsts)

    private var storiesSection: some View {
        let fd = firstsData
        return VStack(alignment: .leading, spacing: 14) {
            Text("你的故事")
                .font(.title3.bold())
                .padding(.horizontal, 4)

            WayPortraitCardView(portrait: portrait)
            WayJourneyCardView(groundMeters: groundLifetimeMeters)
            if !fd.firsts.isEmpty {
                WayFirstsCardView(firsts: fd.firsts, extremes: fd.extremes)
            }
        }
    }

    // MARK: - 8. 里程碑 Summary Card (1:1 Original Illustrated Badges)

    private var milestonesSummaryCard: some View {
        let mp = milestoneProgress
        return NavigationLink {
            WayMilestonesDetailView(progress: mp)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("里程碑")
                        .font(.title3.bold())
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(mp.reached.count) / \(mp.all.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                }

                HStack(alignment: .top, spacing: 6) {
                    ForEach(mp.reached.prefix(4)) { item in
                        WayMilestoneBadge(milestone: item.milestone, isReached: true, size: 58)
                    }
                    if let next = mp.next.first {
                        WayMilestoneBadge(milestone: next.milestone, isReached: false, progress: next.fraction, size: 58)
                            .padding(.leading, mp.reached.isEmpty ? 0 : 8)
                    }
                    Spacer(minLength: 0)
                }

                if let next = mp.next.first {
                    let curVal = next.milestone.kind == .distance ? Int(next.current.rounded(.down)) : Int(next.current)
                    HStack(spacing: 6) {
                        Text("下一个")
                            .foregroundColor(.secondary)
                        Text(next.milestone.title)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(Self.formattedInt(curVal)) / \(Self.formattedInt(next.milestone.threshold))")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private static func formattedInt(_ n: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
    }

    private static func formatKm(_ km: Double) -> String {
        if km >= 10 {
            return "\(formattedInt(Int(km.rounded()))) 公里"
        }
        return String(format: "%.1f 公里", km)
    }

    private static func zhFullDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: date)
    }
}

// MARK: - 1:1 Original Thick Rounded Sector Donut (Replicating iOS 17 SectorMark on iOS 16)

private struct OriginalModeDonutView: View {
    let slices: [(mode: MovementMode, color: Color, ratio: Double)]
    let selectedMode: MovementMode?

    var body: some View {
        Canvas { context, size in
            drawSectors(in: context, size: size)
        }
    }

    private func drawSectors(in context: GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        let maxR = min(size.width, size.height) / 2.0
        let gapRad: Double = slices.count > 1 ? 0.065 : 0.0
        let cornerR: CGFloat = 5.0
        var startAngle = -Double.pi / 2.0

        for slice in slices {
            let sweep = slice.ratio * 2.0 * Double.pi
            let endAngle = startAngle + sweep
            let isSelected = (selectedMode == slice.mode)
            let isDimmed = (selectedMode != nil && !isSelected)
            let outerR = maxR * (isSelected ? 0.98 : 0.90)
            let innerR = maxR * 0.58

            let a0 = startAngle + gapRad / 2.0
            let a1 = max(a0 + 0.03, endAngle - gapRad / 2.0)
            let sectorPath = roundedSectorPath(
                center: center,
                innerRadius: innerR,
                outerRadius: outerR,
                startAngle: a0,
                endAngle: a1,
                cornerRadius: cornerR
            )

            let topColor = slice.color.opacity(isDimmed ? 0.28 : 0.88)
            let bottomColor = slice.color.opacity(isDimmed ? 0.28 : 1.0)
            context.fill(
                sectorPath,
                with: .linearGradient(
                    Gradient(colors: [topColor, bottomColor]),
                    startPoint: CGPoint(x: center.x, y: center.y - outerR),
                    endPoint: CGPoint(x: center.x, y: center.y + outerR)
                )
            )
            startAngle = endAngle
        }
    }

    private func roundedSectorPath(
        center: CGPoint,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        startAngle: Double,
        endAngle: Double,
        cornerRadius: CGFloat
    ) -> Path {
        let span = endAngle - startAngle
        let cr = min(cornerRadius, (outerRadius - innerRadius) * 0.42, CGFloat(span) * innerRadius * 0.35)
        let outerInset = Double(cr / max(outerRadius, 1))
        let innerInset = Double(cr / max(innerRadius, 1))

        func pt(_ r: CGFloat, _ a: Double) -> CGPoint {
            CGPoint(x: center.x + r * CGFloat(cos(a)), y: center.y + r * CGFloat(sin(a)))
        }

        var path = Path()
        if span >= 2.0 * Double.pi - 0.02 {
            path.addArc(center: center, radius: outerRadius, startAngle: .radians(0), endAngle: .radians(2 * .pi), clockwise: false)
            path.addArc(center: center, radius: innerRadius, startAngle: .radians(2 * .pi), endAngle: .radians(0), clockwise: true)
            path.closeSubpath()
            return path
        }

        path.move(to: pt(outerRadius - cr, startAngle))
        path.addQuadCurve(to: pt(outerRadius, startAngle + outerInset), control: pt(outerRadius, startAngle))
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .radians(startAngle + outerInset),
            endAngle: .radians(endAngle - outerInset),
            clockwise: false
        )
        path.addQuadCurve(to: pt(outerRadius - cr, endAngle), control: pt(outerRadius, endAngle))
        path.addLine(to: pt(innerRadius + cr, endAngle))
        path.addQuadCurve(to: pt(innerRadius, endAngle - innerInset), control: pt(innerRadius, endAngle))
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .radians(endAngle - innerInset),
            endAngle: .radians(startAngle + innerInset),
            clockwise: true
        )
        path.addQuadCurve(to: pt(innerRadius + cr, startAngle), control: pt(innerRadius, startAngle))
        path.closeSubpath()
        return path
    }
}

private struct AllRoutesGoldArtwork: View {
    var body: some View {
        Canvas { context, size in
            drawGoldRoutes(in: context, size: size)
        }
    }

    private func drawGoldRoutes(in context: GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let hub = CGPoint(x: w * 0.56, y: h * 0.50)
        let gold = Color(red: 1.0, green: 0.78, blue: 0.36)

        let curves: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: 0, y: h * 0.12), CGPoint(x: w * 0.30, y: h * 0.42), hub),
            (CGPoint(x: 0, y: h * 0.86), CGPoint(x: w * 0.34, y: h * 0.62), hub),
            (hub, CGPoint(x: w * 0.78, y: h * 0.20), CGPoint(x: w, y: h * 0.08)),
            (hub, CGPoint(x: w * 0.76, y: h * 0.74), CGPoint(x: w, y: h * 0.94)),
            (CGPoint(x: w * 0.22, y: 0), CGPoint(x: w * 0.48, y: h * 0.25), hub),
            (hub, CGPoint(x: w * 0.66, y: h * 0.80), CGPoint(x: w * 0.74, y: h))
        ]
        for (start, ctrl, end) in curves {
            var p = Path()
            p.move(to: start)
            p.addQuadCurve(to: end, control: ctrl)
            context.stroke(p, with: .color(gold.opacity(0.35)), lineWidth: 1.4)
        }

        let glowRect = CGRect(x: hub.x - 24, y: hub.y - 24, width: 48, height: 48)
        context.fill(Path(ellipseIn: glowRect), with: .color(gold.opacity(0.18)))
        let dotRect = CGRect(x: hub.x - 4, y: hub.y - 4, width: 8, height: 8)
        context.fill(Path(ellipseIn: dotRect), with: .color(gold))
    }
}
