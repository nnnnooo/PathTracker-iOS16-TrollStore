import SwiftUI
import UIKit

struct PassportView: View {
    @EnvironmentObject private var store: DataStore

    @AppStorage("wt16.passport.theme") private var themeRaw: String = PassportTheme.burgundy.rawValue
    @State private var selectedSection = 0 // 0=出入境章, 1=省份印, 2=城市章, 3=四至与套章
    @State private var stampedID: String?
    @State private var summary: PassportSummary?

    private var theme: PassportTheme { PassportTheme(rawValue: themeRaw) ?? .burgundy }

    var body: some View {
        Group {
            if let summary {
                ScrollView {
                    VStack(spacing: 18) {
                        passportCover(summary)
                        themePicker
                        Picker("印章分类", selection: $selectedSection) {
                            Text("出入境 (\(summary.countryStamps.count))").tag(0)
                            Text("省份印 (\(summary.provinceSeals.filter(\.visited).count)/34)").tag(1)
                            Text("城市章 (\(summary.cityStamps.count))").tag(2)
                            Text("四至·套章").tag(3)
                        }
                        .pickerStyle(.segmented)

                        Group {
                            switch selectedSection {
                            case 0: countryStampsSection(summary)
                            case 1: provinceSealsSection(summary)
                            case 2: cityStampsSection(summary)
                            default: extremesAndSetsSection(summary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在整理护照与印章…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("漫迹护照")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(store.stays.count)-\(store.chunks.count)") {
            let staysSnapshot = store.stays
            let chunksSnapshot = store.chunks
            let computed = await Task.detached(priority: .userInitiated) {
                PassportEngine.build(stays: staysSnapshot, chunks: chunksSnapshot)
            }.value
            summary = computed
        }
    }

    // MARK: - Cover & Theme Picker

    private func passportCover(_ summary: PassportSummary) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.coverColor)
                .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 6)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.foilColor.opacity(0.45), lineWidth: 1.2)
                .padding(10)

            VStack(spacing: 10) {
                Text("WAYTRACE PASSPORT")
                    .font(.caption.monospaced().weight(.bold))
                    .tracking(2)
                    .foregroundColor(theme.foilColor.opacity(0.85))

                Image(systemName: "globe.asia.australia.fill")
                    .font(.system(size: 46))
                    .foregroundColor(theme.foilColor)
                    .padding(.vertical, 4)

                Text("漫迹 · 个人足迹护照")
                    .font(.title3.weight(.bold))
                    .foregroundColor(theme.foilColor)

                HStack(spacing: 16) {
                    Text("\(summary.countryStamps.count) 枚入境章")
                    Text("·")
                    Text("\(summary.provinceSeals.filter(\.visited).count) 枚省印")
                    Text("·")
                    Text("\(summary.cityStamps.count) 座城市")
                }
                .font(.caption2)
                .foregroundColor(theme.foilColor.opacity(0.8))

                if let home = summary.homeCountryName {
                    Text("签发地：\(home)")
                        .font(.caption2)
                        .foregroundColor(theme.foilColor.opacity(0.65))
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 24)
        }
    }

    private var themePicker: some View {
        HStack(spacing: 12) {
            Text("护照皮色").font(.caption).foregroundColor(.secondary)
            Spacer()
            ForEach(PassportTheme.allCases) { item in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        themeRaw = item.rawValue
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(item.coverColor)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(item.foilColor, lineWidth: 1))
                        Text(item.title).font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        theme == item ? Color.accentColor.opacity(0.15) : Color(.secondarySystemGroupedBackground),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 1. Country Entry/Exit Stamps

    private func countryStampsSection(_ summary: PassportSummary) -> some View {
        VStack(spacing: 12) {
            if summary.countryStamps.isEmpty {
                emptyPage(text: "还没有境外国家/地区的出入境记录，去过常住地以外的国家或从相册导入后将自动盖章。")
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(summary.countryStamps) { stamp in
                        countryStampTile(stamp)
                    }
                }
            }
        }
    }

    private func countryStampTile(_ stamp: CountryStamp) -> some View {
        let isPressed = stampedID == stamp.id
        let ink = Color(red: 0.16, green: 0.28, blue: 0.56)
        return VStack(spacing: 6) {
            Text(stamp.nativeName)
                .font(.caption.bold())
                .foregroundColor(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Divider().background(ink.opacity(0.4))

            Text(shortDate(stamp.entryDate))
                .font(.subheadline.monospacedDigit().bold())
                .foregroundColor(ink)

            Text("停留 \(stamp.days) 天")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .overlay(Capsule().stroke(ink.opacity(0.6), lineWidth: 1))
                .foregroundColor(ink)

            Text(stamp.portCity ?? stamp.countryName)
                .font(.caption2)
                .foregroundColor(ink.opacity(0.8))
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(theme.paperColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(ink.opacity(0.75), style: StrokeStyle(lineWidth: 1.8, dash: [6, 2]))
                .padding(5)
        )
        .rotationEffect(.degrees(isPressed ? 0 : Double((abs(stamp.id.hashValue) % 7) - 3)))
        .scaleEffect(isPressed ? 0.94 : 1.0)
        .onTapGesture { triggerStampHaptic(id: stamp.id) }
    }

    // MARK: - 2. China 34 Province Vermilion Seals

    private func provinceSealsSection(_ summary: PassportSummary) -> some View {
        let visitedCount = summary.provinceSeals.filter(\.visited).count
        let vermilion = Color(red: 0.74, green: 0.15, blue: 0.14)

        return VStack(alignment: .leading, spacing: 10) {
            Text("已点亮 \(visitedCount) / 34 个省级行政区")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 10) {
                ForEach(summary.provinceSeals) { seal in
                    let isPressed = stampedID == seal.id
                    VStack(spacing: 4) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(seal.visited ? vermilion : theme.paperColor)
                                .frame(height: 54)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(seal.visited ? Color.white.opacity(0.55) : Color.secondary.opacity(0.22), lineWidth: 1.2)
                                        .padding(3)
                                )
                            Text(seal.shortChar)
                                .font(.title2.weight(.heavy))
                                .foregroundColor(seal.visited ? .white : .secondary.opacity(0.35))
                        }
                        Text(seal.fullName)
                            .font(.system(size: 10))
                            .foregroundColor(seal.visited ? .primary : .secondary.opacity(0.6))
                            .lineLimit(1)
                    }
                    .scaleEffect(isPressed ? 0.90 : 1.0)
                    .onTapGesture {
                        if seal.visited { triggerStampHaptic(id: seal.id) }
                    }
                }
            }
            .padding(12)
            .background(theme.paperColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - 3. City Commemorative Stamps

    private func cityStampsSection(_ summary: PassportSummary) -> some View {
        VStack(spacing: 12) {
            if summary.cityStamps.isEmpty {
                emptyPage(text: "还没有已识别的城市足迹，开启定位或从相册导入后这里会自动盖上城市章。")
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(summary.cityStamps) { city in
                        let ink = Color(red: 0.20, green: 0.42, blue: 0.34)
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .stroke(ink.opacity(0.8), lineWidth: 2)
                                    .frame(width: 78, height: 78)
                                Circle()
                                    .stroke(ink.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                    .frame(width: 68, height: 68)
                                VStack(spacing: 2) {
                                    Text(city.cityName)
                                        .font(.subheadline.bold())
                                        .foregroundColor(ink)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .padding(.horizontal, 6)
                                    Text(shortDate(city.firstVisit))
                                        .font(.system(size: 9).monospacedDigit())
                                        .foregroundColor(ink.opacity(0.8))
                                }
                            }
                            Text("累计 \(city.days) 天 · \(city.visits) 次")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(theme.paperColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .scaleEffect(stampedID == city.id ? 0.94 : 1.0)
                        .onTapGesture { triggerStampHaptic(id: city.id) }
                    }
                }
            }
        }
    }

    // MARK: - 4. Four Extremes, Special Stamps & Stamp Sets

    private func extremesAndSetsSection(_ summary: PassportSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !summary.extremes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("天涯海角 · 四至与最高点").font(.headline).padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        ForEach(Array(summary.extremes.enumerated()), id: \.element.id) { idx, ext in
                            HStack {
                                Text(ext.label)
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ext.placeName).font(.subheadline.weight(.semibold))
                                    Text(shortDate(ext.date)).font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(ext.detail).font(.caption.monospacedDigit().weight(.medium)).foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            if idx < summary.extremes.count - 1 { Divider().padding(.leading, 14) }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("特殊纪念章").font(.headline).padding(.horizontal, 4)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(summary.specialStamps) { sp in
                        VStack(spacing: 6) {
                            Image(systemName: sp.symbol)
                                .font(.title2)
                                .foregroundColor(sp.unlocked ? .orange : .secondary.opacity(0.4))
                            Text(sp.title).font(.subheadline.weight(.semibold))
                            Text(sp.subtitle).font(.caption2).foregroundColor(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .opacity(sp.unlocked ? 1.0 : 0.65)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("主题套章").font(.headline).padding(.horizontal, 4)
                VStack(spacing: 10) {
                    ForEach(summary.stampSets) { set in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(set.title).font(.subheadline.weight(.semibold))
                                if set.isCompleted {
                                    Text("已集齐")
                                        .font(.caption2.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange, in: Capsule())
                                }
                                Spacer()
                                Text("\(set.matchedCities.count) / \(set.requiredCities.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                            Text(set.requiredCities.map { set.matchedCities.contains($0) ? "● \($0)" : "○ \($0)" }.joined(separator: "  "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ProgressView(value: set.progress)
                                .tint(set.isCompleted ? .orange : .accentColor)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }

    private func emptyPage(text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(28)
            .frame(maxWidth: .infinity)
            .background(theme.paperColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func triggerStampHaptic(id: String) {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
            stampedID = id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                if stampedID == id { stampedID = nil }
            }
        }
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return f.string(from: date)
    }
}
