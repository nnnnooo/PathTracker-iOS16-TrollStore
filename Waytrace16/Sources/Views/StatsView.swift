import SwiftUI
import Charts

struct StatsView: View {
    @Binding var showingSettings: Bool
    @EnvironmentObject private var store: DataStore

    enum Period: String, CaseIterable, Identifiable {
        case week = "近 7 天"
        case month = "近 30 天"
        case year = "近 12 个月"
        var id: String { rawValue }
    }

    @State private var period: Period = .week

    private struct ChartBucket: Identifiable {
        let id: String
        let label: String
        let km: Double
    }

    private var buckets: [ChartBucket] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        switch period {
        case .week:
            return (0..<7).reversed().map { offset in
                let day = cal.date(byAdding: .day, value: -offset, to: today)!
                let next = cal.date(byAdding: .day, value: 1, to: day)!
                let dist = store.chunks.filter { $0.startDate >= day && $0.startDate < next }.reduce(0.0) { $0 + $1.distance }
                let f = DateFormatter()
                f.locale = Locale(identifier: "zh_CN")
                f.dateFormat = "E"
                return ChartBucket(id: "\(offset)", label: f.string(from: day), km: dist / 1000.0)
            }
        case .month:
            return (0..<30).reversed().map { offset in
                let day = cal.date(byAdding: .day, value: -offset, to: today)!
                let next = cal.date(byAdding: .day, value: 1, to: day)!
                let dist = store.chunks.filter { $0.startDate >= day && $0.startDate < next }.reduce(0.0) { $0 + $1.distance }
                let d = cal.component(.day, from: day)
                return ChartBucket(id: "\(offset)", label: "\(d)", km: dist / 1000.0)
            }
        case .year:
            let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: today))!
            return (0..<12).reversed().map { offset in
                let m = cal.date(byAdding: .month, value: -offset, to: startOfMonth)!
                let next = cal.date(byAdding: .month, value: 1, to: m)!
                let dist = store.chunks.filter { $0.startDate >= m && $0.startDate < next }.reduce(0.0) { $0 + $1.distance }
                let monthNum = cal.component(.month, from: m)
                return ChartBucket(id: "\(offset)", label: "\(monthNum)月", km: dist / 1000.0)
            }
        }
    }

    private var modeStats: [(mode: MovementMode, km: Double, ratio: Double)] {
        let grouped = Dictionary(grouping: store.chunks) { $0.mode }
        let totals = grouped.map { ($0.key, $0.value.reduce(0.0) { $0 + $1.distance } / 1000.0) }
            .filter { $0.1 > 0.01 }
            .sorted { $0.1 > $1.1 }
        let sum = max(0.01, totals.reduce(0.0) { $0 + $1.1 })
        return totals.map { ($0.0, $0.1, $0.1 / sum) }
    }

    private var medals: [MilestoneMedal] {
        MilestonesEngine.computeMedals(chunks: store.chunks, stays: store.stays, recordedDays: store.recordedDaysCount)
    }

    private var persona: TravelerPersona {
        MilestonesEngine.persona(chunks: store.chunks, stays: store.stays)
    }

    private var groundKm: Double {
        store.chunks.filter { $0.mode != .flying }.reduce(0.0) { $0 + $1.distance } / 1000.0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    personaCard
                    distanceChartCard
                    modeBreakdownCard
                    virtualRoutesCard
                    medalsSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("统计")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProfileToolbarButton(showingSettings: $showingSettings)
                }
            }
        }
    }

    private var personaCard: some View {
        HStack(spacing: 14) {
            Image(systemName: persona.symbol)
                .font(.system(size: 40))
                .foregroundColor(persona.color)
            VStack(alignment: .leading, spacing: 4) {
                Text("旅人画像 · \(persona.title)")
                    .font(.headline)
                Text(persona.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var distanceChartCard: some View {
        let periodTotal = buckets.reduce(0.0) { $0 + $1.km }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("移动距离").font(.headline)
                    Text(String(format: "合计 %.1f km", periodTotal))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Picker("周期", selection: $period) {
                    ForEach(Period.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            }

            Chart(buckets) { item in
                BarMark(
                    x: .value("时间", item.label),
                    y: .value("公里", item.km)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(4)
            }
            .frame(height: 170)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var modeBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("出行方式占比").font(.headline)
            if modeStats.isEmpty {
                Text("开始记录轨迹后将按出行方式自动统计")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(modeStats, id: \.mode) { item in
                    VStack(spacing: 4) {
                        HStack {
                            Label(item.mode.title, systemImage: item.mode.symbol)
                                .font(.subheadline)
                                .foregroundColor(item.mode.color)
                            Spacer()
                            Text(String(format: "%.1f km (%.0f%%)", item.km, item.ratio * 100))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.tertiarySystemFill))
                                Capsule().fill(item.mode.color)
                                    .frame(width: max(6, geo.size.width * item.ratio))
                            }
                        }
                        .frame(height: 7)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var virtualRoutesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("你的地面里程能走多远").font(.headline)
                Spacer()
                Text(String(format: "%.1f km", groundKm))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            ForEach(MilestonesEngine.virtualRoutes) { route in
                let ratio = min(1.0, groundKm / route.totalKm)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(route.name).font(.subheadline.weight(.medium))
                        Spacer()
                        Text(String(format: "%.0f%% · %.0f km", ratio * 100, route.totalKm))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: ratio)
                        .tint(ratio >= 1 ? .green : .orange)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var medalsSection: some View {
        let unlockedCount = medals.filter(\.isUnlocked).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("里程碑奖牌").font(.headline)
                Spacer()
                Text("已达成 \(unlockedCount) / \(medals.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(medals) { medal in
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .stroke(medal.isUnlocked ? medal.tier.color : Color(.tertiarySystemFill), lineWidth: 3)
                                .frame(width: 48, height: 48)
                            Image(systemName: medal.symbol)
                                .font(.title3)
                                .foregroundColor(medal.isUnlocked ? medal.tier.color : .secondary.opacity(0.45))
                        }
                        Text(medal.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(medal.subtitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        if !medal.isUnlocked {
                            ProgressView(value: medal.progress)
                                .tint(medal.tier.color)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .opacity(medal.isUnlocked ? 1.0 : 0.72)
                }
            }
        }
    }
}
