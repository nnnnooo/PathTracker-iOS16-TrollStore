import SwiftUI
import UIKit
import MapKit

struct PassportTabView: View {
    @Binding var showingSettings: Bool

    var body: some View {
        NavigationStack {
            PassportView(isRootTab: true, showingSettings: $showingSettings)
        }
    }
}

struct PassportView: View {
    var isRootTab: Bool = false
    var showingSettings: Binding<Bool>? = nil

    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var tagger: PlaceTagger
    @AppStorage("wt16.passport.theme") private var themeRaw: String = PassportTheme.burgundy.rawValue
    @AppStorage("wt16.passport.themeChosenOnce") private var themeChosenOnce: Bool = false

    enum Scope: Int, Hashable { case passport = 0, provinces = 1, cities = 2, keepsakes = 3 }

    @State private var scope: Scope = .passport
    @State private var summary: PassportSummary?
    @State private var selectedUnvisitedProvince: ChinaProvince?
    @State private var navigatedProvince: ChinaProvince?
    @State private var isProvinceNavActive = false
    @State private var showDataEditor = false
    @State private var dataRefreshToken = 0
    @State private var chosenThemeAlertName: String?
    @State private var shareItem: ShareablePassportImage?

    private var theme: PassportTheme { PassportTheme(rawValue: themeRaw) ?? .burgundy }

    var body: some View {
        Group {
            if let summary {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Picker("范围", selection: $scope) {
                            Text("护照").tag(Scope.passport)
                            Text("省份").tag(Scope.provinces)
                            Text("城市").tag(Scope.cities)
                            Text("纪念").tag(Scope.keepsakes)
                        }
                        .pickerStyle(.segmented)

                        switch scope {
                        case .passport:
                            passportTab(summary)
                        case .provinces:
                            provincesTab(summary)
                        case .cities:
                            citiesTab(summary)
                        case .keepsakes:
                            keepsakesTab(summary)
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
        .navigationTitle("护照与印章")
        .navigationBarTitleDisplayMode(isRootTab ? .large : .inline)
        .navigationDestination(isPresented: $isProvinceNavActive) {
            if let province = navigatedProvince {
                ProvinceDetailView(province: province)
            }
        }
        .onChange(of: scope) { _ in
            UISelectionFeedbackGenerator().selectionChanged()
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    showDataEditor = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("编辑识别数据")
                if scope == .provinces, let summary {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        renderProvinceShareCard(summary)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                if isRootTab, let binding = showingSettings {
                    ProfileToolbarButton(showingSettings: binding)
                }
            }
        }
        .sheet(isPresented: $showDataEditor) {
            PassportDataEditorSheet()
        }
        .onChange(of: showDataEditor) { isShowing in
            if !isShowing {
                // 等待弹窗下滑关闭动画完全结束后再重建护照本，避免关闭时卡顿瞬移
                Task {
                    try? await Task.sleep(nanoseconds: 380_000_000)
                    await MainActor.run { dataRefreshToken &+= 1 }
                }
            }
        }
        .alert(
            "已选定护照皮色",
            isPresented: Binding(get: { chosenThemeAlertName != nil }, set: { if !$0 { chosenThemeAlertName = nil } })
        ) {
            Button("知道了", role: .cancel) { chosenThemeAlertName = nil }
        } message: {
            Text("已切换为「\(chosenThemeAlertName ?? "")」皮色，之后可随时在「设置 → 护照样式」中更换。")
        }
        .sheet(item: $selectedUnvisitedProvince) { province in
            VStack(spacing: 14) {
                ProvinceSealArtView(id: province.id)
                    .frame(width: 64, height: 64)
                    .inkWorn(seed: StampSeed.of(province.id), inked: false)
                Text("还没盖上“\(province.shortChar)”")
                    .font(.headline)
                Text("去过\(province.name)之后，这枚印会盖上。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(28)
            .presentationDetents([.height(260)])
        }
        .sheet(item: $shareItem) { item in
            PassportActivityShareSheet(items: [item.image])
        }
        .task(id: "\(store.stays.count)-\(store.chunks.count)-\(tagger.pendingCount)-\(dataRefreshToken)") {
            let staysSnapshot = store.stays
            let chunksSnapshot = store.chunks
            let computed = await Task.detached(priority: .userInitiated) {
                PassportEngine.build(stays: staysSnapshot, chunks: chunksSnapshot)
            }.value
            summary = computed
        }
    }

    // MARK: - Tab 1: 护照 + 签证夹 + 深色世界地图

    private func passportTab(_ summary: PassportSummary) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            PassportBookSection(summary: summary, theme: theme)
            if !themeChosenOnce {
                firstTimePassportThemeCard
            }
            visaShelfCard
            WorldStampMapSection(summary: summary)
                .padding(.top, 4)
        }
    }

    private var firstTimePassportThemeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("选择你的护照皮色")
                    .font(.subheadline.weight(.semibold))
                Text("封面和内页的纸张、底纹会一起换")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 14) {
                ForEach(PassportTheme.allCases) { item in
                    let isSelected = theme == item
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            themeRaw = item.rawValue
                            themeChosenOnce = true
                        }
                        chosenThemeAlertName = item.title
                    } label: {
                        VStack(spacing: 7) {
                            miniPassportCover(item, selected: isSelected)
                                .frame(width: 56, height: 78)
                                .scaleEffect(isSelected ? 1.05 : 0.96)
                                .shadow(color: .black.opacity(isSelected ? 0.28 : 0.14), radius: isSelected ? 7 : 3, y: 3)
                            Text(item.title)
                                .font(.caption.weight(isSelected ? .bold : .regular))
                                .foregroundColor(isSelected ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func miniPassportCover(_ theme: PassportTheme, selected: Bool) -> some View {
        let shape = BookCornerRect(topLeading: 2, bottomLeading: 2, bottomTrailing: 6, topTrailing: 6)
        return ZStack {
            shape.fill(theme.leather)
            VStack(spacing: 3) {
                Text("护照")
                    .font(.system(size: 7.5, weight: .semibold))
                    .tracking(1.5)
                Text("PASSPORT")
                    .font(.system(size: 4.5, weight: .medium, design: .serif))
                    .tracking(0.8)
                ZStack {
                    Circle().stroke(lineWidth: 0.7)
                    Image(systemName: theme.emblem)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                }
                .frame(width: 24, height: 24)
                .padding(.vertical, 2)
                Text("漫迹")
                    .font(.system(size: 5, weight: .semibold))
                    .tracking(1)
            }
            .foregroundStyle(theme.foilGradient)
            Rectangle()
                .fill(Color.black.opacity(0.22))
                .frame(width: 2.5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(shape)
        .overlay {
            if selected {
                shape.stroke(Color.accentColor, lineWidth: 2)
            }
        }
    }

    private var visaShelfCard: some View {
        VisaShelfCard()
    }

    // MARK: - Tab 2: 省份 (8x8 方位朱砂印图 + 列表)

    private func provincesTab(_ summary: PassportSummary) -> some View {
        let litProvinces = ChinaProvince.all
            .compactMap { summary.provinceVisits[$0.id] }
            .sorted { $0.days > $1.days }

        return VStack(alignment: .leading, spacing: 18) {
            PassportProgressHeader(
                lit: litProvinces.count,
                total: ChinaProvince.all.count,
                title: "盖上的省份印",
                tint: StampInk.cinnabar.color,
                detail: nil
            )

            ProvinceTileMapView(visits: summary.provinceVisits) { province in
                if summary.provinceVisits[province.id] == nil {
                    selectedUnvisitedProvince = province
                } else {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    navigatedProvince = province
                    isProvinceNavActive = true
                }
            }
            .padding(14)
            .background(StampPaperView(style: .seals))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            if !litProvinces.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(litProvinces.enumerated()), id: \.element.province.id) { idx, item in
                        NavigationLink {
                            ProvinceDetailView(province: item.province)
                        } label: {
                            HStack(spacing: 12) {
                                StampArtView(
                                    stamp: PassportStamp(
                                        id: "province.\(item.province.id)",
                                        kind: .province,
                                        date: item.firstVisit,
                                        provinceID: item.province.id
                                    )
                                )
                                .frame(width: 30, height: 30)

                                Text(item.province.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(.primary)

                                if !item.topCities.isEmpty {
                                    Text(item.topCities.joined(separator: "、"))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text("\(item.days) 天")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundColor(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Color(.tertiaryLabel))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        if idx < litProvinces.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    // MARK: - Tab 3: 城市 (按国家分组 + 3 列圆章/邮戳网格 + 首日轨迹)

    private func citiesTab(_ summary: PassportSummary) -> some View {
        let groups = groupedCityStamps(summary)
        return VStack(alignment: .leading, spacing: 18) {
            if summary.cityStamps.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "seal")
                        .font(.system(size: 38))
                        .foregroundColor(.secondary)
                    Text("还没有城市章")
                        .font(.headline)
                    Text("每到一座新城市，就会得到一枚它的纪念章，中间印着你那天走过的路。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                PassportProgressHeader(
                    lit: summary.cityStamps.count,
                    total: nil,
                    title: "收集的城市章",
                    tint: .indigo,
                    detail: "中间的线条，是你第一天在那里走过的路"
                )

                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(groups, id: \.code) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            NavigationLink {
                                CountryDetailView(countryCode: group.code)
                            } label: {
                                HStack {
                                    Text("\(CountryText.flag(for: group.code)) \(CountryText.localizedName(code: group.code))")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text("\(group.stamps.count) 枚")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundColor(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(Color(.tertiaryLabel))
                                }
                                .padding(.horizontal, 4)
                            }
                            .buttonStyle(.plain)

                            LazyVGrid(
                                columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                                spacing: 14
                            ) {
                                ForEach(group.stamps.reversed()) { stamp in
                                    let cityName = stamp.city ?? ""
                                    NavigationLink {
                                        CityAllVisitsView(
                                            city: cityName,
                                            countryCode: stamp.countryCode,
                                            stays: store.stays.filter { $0.city == cityName && ($0.countryCode == stamp.countryCode || stamp.countryCode == nil) }
                                        )
                                    } label: {
                                        VStack(spacing: 6) {
                                            StampArtView(stamp: stamp, route: summary.cityRoutes[stamp.id] ?? [])
                                                .frame(height: 92)
                                                .rotationEffect(.degrees(stamp.tilt * 0.55))
                                            Text(CityStampStyle.displayName(stamp))
                                                .font(.footnote.weight(.semibold))
                                                .foregroundColor(Color(red: 0.25, green: 0.22, blue: 0.2))
                                                .lineLimit(1)
                                            Text(StampDateFormat.zhFull(stamp.date))
                                                .font(.caption2)
                                                .foregroundColor(Color(red: 0.45, green: 0.42, blue: 0.38))
                                                .lineLimit(1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 16)
                            .padding(.horizontal, 10)
                            .background(StampPaperView(style: .book))
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private func groupedCityStamps(_ summary: PassportSummary) -> [(code: String, stamps: [PassportStamp])] {
        var order: [String] = []
        var byCountry: [String: [PassportStamp]] = [:]
        for stamp in summary.cityStamps {
            let code = stamp.countryCode ?? ""
            if byCountry[code] == nil { order.append(code) }
            byCountry[code, default: []].append(stamp)
        }
        return order.map { ($0, byCountry[$0] ?? []) }
            .sorted { ($0.code == summary.homeCountryCode ? 1 : 0, $0.stamps.count) > ($1.code == summary.homeCountryCode ? 1 : 0, $1.stamps.count) }
    }

    // MARK: - Tab 4: 纪念 (你的四至罗盘 + 跨越 + 跨年 + 14套章)

    private func keepsakesTab(_ summary: PassportSummary) -> some View {
        CommemorativeTabSection(summary: summary)
    }

    // MARK: - Share Card

    @MainActor
    private func renderProvinceShareCard(_ summary: PassportSummary) {
        let card = VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("我的省份印").font(.title2.bold())
                Spacer()
                Text("漫迹16").font(.subheadline.weight(.semibold)).foregroundColor(.secondary)
            }
            HStack(spacing: 24) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(summary.provinceVisits.count)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                    Text("个省级行政区").font(.subheadline).foregroundColor(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(summary.visitedCountries.count)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                    Text("个国家和地区").font(.subheadline).foregroundColor(.secondary)
                }
            }
            ProvinceTileMapView(visits: summary.provinceVisits) { _ in }
                .padding(12)
                .background(StampPaperView(style: .seals))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(24)
        .frame(width: 390)
        .background(Color(.systemBackground))

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let uiImage = renderer.uiImage {
            shareItem = ShareablePassportImage(image: uiImage)
        }
    }
}

// MARK: - Progress Header Card

private struct PassportProgressHeader: View {
    let lit: Int
    let total: Int?
    let title: String
    let tint: Color
    let detail: String?

    var body: some View {
        HStack(spacing: 16) {
            if let total {
                ZStack {
                    Circle().stroke(tint.opacity(0.15), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: total > 0 ? CGFloat(lit) / CGFloat(total) : 0)
                        .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int((Double(lit) / Double(max(total, 1)) * 100).rounded()))%")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
                .frame(width: 64, height: 64)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(lit)").font(.system(size: 34, weight: .bold, design: .rounded))
                    if let total {
                        Text("/ \(total)").font(.title3).foregroundColor(.secondary)
                    }
                }
                if let detail {
                    Text(detail).font(.footnote).foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - Flippable Passport Book (Real UIPageViewController Page Curl)

private struct PassportBookSection: View {
    let summary: PassportSummary
    let theme: PassportTheme

    @State private var page = 0
    private static let perPage = 4

    private var stampPages: [[PassportStamp]] {
        let all = summary.passportStamps
        return stride(from: 0, to: all.count, by: Self.perPage).map {
            Array(all[$0..<min($0 + Self.perPage, all.count)])
        }
    }

    var body: some View {
        let groups = stampPages
        let blankAtBack = groups.last.map { $0.count == Self.perPage } ?? true
        var pages: [AnyView] = [
            AnyView(PassportCoverPage(theme: theme)),
            AnyView(PassportDataPage(summary: summary, theme: theme))
        ]
        for (index, stamps) in groups.enumerated() {
            pages.append(AnyView(PassportStampPage(stamps: stamps, number: index + 1, theme: theme)))
        }
        if blankAtBack {
            pages.append(AnyView(PassportStampPage(stamps: [], number: groups.count + 1, theme: theme)))
        }

        let bookKey = "\(theme.rawValue)-\(summary.passportStamps.count)-\(summary.cityStamps.count)"
        let bookWidth: CGFloat = min(UIScreen.main.bounds.width - 80, 272)
        let bookHeight: CGFloat = (bookWidth / 0.70).rounded()

        let bookSize = CGSize(width: bookWidth, height: bookHeight)

        return VStack(spacing: 12) {
            PageCurlContainer(pages: pages, bookSize: bookSize, current: $page)
                .frame(width: bookWidth, height: bookHeight)
                .shadow(color: .black.opacity(0.10), radius: 3, y: 2)
                .shadow(color: .black.opacity(0.16), radius: 18, y: 12)
                .id(bookKey)
                .frame(maxWidth: .infinity)

            Text(page == 0 ? "向左轻扫，翻开护照" : "第 \(page) / \(max(1, pages.count - 1)) 页")
                .font(.footnote.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .onChange(of: theme) { _ in page = 0 }
    }
}

private struct PassportCoverPage: View {
    let theme: PassportTheme
    @State private var shine = false

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 300
            let shape = BookCornerRect(topLeading: 4 * unit, bottomLeading: 4 * unit, bottomTrailing: 18 * unit, topTrailing: 18 * unit)
            ZStack {
                shape
                    .fill(
                        LinearGradient(
                            colors: [theme.leather.opacity(0.95), theme.leather],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        LeatherGrainView()
                            .opacity(0.25)
                            .clipShape(shape)
                    }

                foil(unit: unit)
                    .foregroundStyle(theme.foilGradient)

                ZStack {
                    LinearGradient(colors: [.clear, .white.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.35, height: proxy.size.height * 1.4)
                        .rotationEffect(.degrees(20))
                        .offset(x: shine ? proxy.size.width : -proxy.size.width)
                        .animation(.easeInOut(duration: 2.6).delay(0.8).repeatForever(autoreverses: false), value: shine)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .mask { foil(unit: unit) }
                .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.black.opacity(0.18))
                    .frame(width: 6 * unit)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .clipShape(shape)
        }
        .onAppear {
            shine = true
        }
    }

    private func foil(unit: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text("护照").font(.system(size: 34 * unit, weight: .semibold)).tracking(14 * unit)
            Text("PASSPORT").font(.custom("AcademyEngravedLetPlain", fixedSize: 22 * unit)).tracking(7 * unit).padding(.top, 4 * unit)
            ZStack {
                Circle().stroke(lineWidth: 2.2 * unit)
                Circle().inset(by: 9 * unit).stroke(lineWidth: 0.8 * unit)
                Image(systemName: theme.emblem)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64 * unit, height: 64 * unit)
                ForEach(0..<12, id: \.self) { i in
                    Image(systemName: "star.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 6 * unit, height: 6 * unit)
                        .offset(y: -63 * unit)
                        .rotationEffect(.degrees(Double(i) * 30))
                }
            }
            .frame(width: 142 * unit, height: 142 * unit)
            .padding(.vertical, 30 * unit)
            Text("漫迹").font(.system(size: 17 * unit, weight: .semibold)).tracking(6 * unit)
            Text("WAYTRACE").font(.custom("AcademyEngravedLetPlain", fixedSize: 12 * unit)).tracking(5 * unit).padding(.top, 2 * unit)
            Spacer(minLength: 0)
            Image(systemName: "dot.radiowaves.left.and.right")
                .resizable()
                .scaledToFit()
                .frame(width: 22 * unit, height: 14 * unit)
                .padding(.bottom, 22 * unit)
        }
    }
}

private struct LeatherGrainView: View {
    var body: some View {
        Canvas { context, size in
            var random = SeededRandom(42)
            let count = min(1400, Int(size.width * size.height / 40))
            for _ in 0..<count {
                let pt = CGPoint(x: random.unit() * size.width, y: random.unit() * size.height)
                context.fill(
                    Path(ellipseIn: CGRect(x: pt.x, y: pt.y, width: 1.2, height: 1.2)),
                    with: .color(random.unit() > 0.5 ? .white.opacity(0.25) : .black.opacity(0.35))
                )
            }
        }
    }
}

private struct PassportDataPage: View {
    let summary: PassportSummary
    let theme: PassportTheme

    private var printed: Color { theme.printed }

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 300
            let shape = BookCornerRect(topLeading: 3, bottomLeading: 3, bottomTrailing: 16 * unit, topTrailing: 16 * unit)
            ZStack(alignment: .topLeading) {
                StampPaperView(theme: theme)
                VStack(alignment: .leading, spacing: 12 * unit) {
                    HStack {
                        Text("漫迹护照 · WAYTRACE PASSPORT")
                            .font(.custom("AvenirNextCondensed-DemiBold", fixedSize: 10 * unit))
                            .tracking(1.5 * unit)
                        Spacer()
                        Text("P").font(.system(size: 12 * unit, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(printed)

                    HStack(alignment: .top, spacing: 14 * unit) {
                        Text(summary.homeCountryCode.map { CountryText.flag(for: $0) } ?? "🌏")
                            .font(.system(size: 54 * unit))
                            .frame(width: 92 * unit, height: 118 * unit)
                            .background(printed.opacity(0.08), in: RoundedRectangle(cornerRadius: 6 * unit, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6 * unit, style: .continuous).stroke(printed.opacity(0.3), lineWidth: 0.6))

                        VStack(alignment: .leading, spacing: 8 * unit) {
                            field("签发国 / ISSUED BY", summary.homeCountryName ?? "—", unit: unit)
                            field("签发日期 / DATE OF ISSUE", summary.since.map { StampDateFormat.long($0) } ?? "—", unit: unit)
                            field("国家和地区 / COUNTRIES", "\(summary.visitedCountries.count)", unit: unit)
                            field("入境章 / ENTRY STAMPS", "\(summary.passportStamps.filter { $0.kind == .entry }.count)", unit: unit)
                        }
                    }

                    HStack(spacing: 18 * unit) {
                        field("省份 / PROVINCES", "\(summary.provinceVisits.count)", unit: unit)
                        field("城市 / CITIES", "\(summary.cityStamps.count)", unit: unit)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 2 * unit) {
                        Text("持照人签名 / SIGNATURE")
                            .font(.custom("AvenirNextCondensed-Medium", fixedSize: 8 * unit))
                            .foregroundColor(printed.opacity(0.6))
                        Text("Waytrace Traveller")
                            .font(.custom("SnellRoundhand-Bold", fixedSize: 24 * unit))
                            .foregroundColor(Color(red: 0.12, green: 0.2, blue: 0.45))
                            .rotationEffect(.degrees(-3))
                        Rectangle().fill(printed.opacity(0.3)).frame(width: 170 * unit, height: 0.6)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 2 * unit) {
                        Text(mrz.0)
                        Text(mrz.1)
                    }
                    .font(.system(size: 10.5 * unit, weight: .medium, design: .monospaced))
                    .foregroundColor(printed.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                }
                .padding(20 * unit)
            }
            .clipShape(shape)
        }
    }

    private func field(_ label: String, _ value: String, unit: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1 * unit) {
            Text(label).font(.custom("AvenirNextCondensed-Medium", fixedSize: 8 * unit)).foregroundColor(printed.opacity(0.6))
            Text(value).font(.system(size: 14 * unit, weight: .semibold)).foregroundColor(printed).lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private var mrz: (String, String) {
        func pad(_ text: String) -> String { String((text + String(repeating: "<", count: 44)).prefix(44)) }
        let home = summary.homeCountryCode ?? "XXX"
        let issued = summary.since.map { StampDateFormat.mrz($0) } ?? "000000"
        return (
            pad("P<\(home)<WAYTRACE<<TRAVELLER"),
            pad("\(String(format: "%04d", summary.passportStamps.count))<\(issued)<\(summary.provinceVisits.count)<\(summary.cityStamps.count)")
        )
    }
}

private struct PassportStampPage: View {
    let stamps: [PassportStamp]
    let number: Int
    let theme: PassportTheme

    private static let slots: [CGPoint] = [
        CGPoint(x: 0.30, y: 0.23),
        CGPoint(x: 0.70, y: 0.36),
        CGPoint(x: 0.32, y: 0.60),
        CGPoint(x: 0.69, y: 0.78)
    ]

    private static func jitter(_ seed: UInt64) -> CGPoint {
        var r = SeededRandom(seed)
        return CGPoint(x: (r.unit() - 0.5) * 0.08, y: (r.unit() - 0.5) * 0.05)
    }

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 300
            let shape = BookCornerRect(topLeading: 3, bottomLeading: 3, bottomTrailing: 16 * unit, topTrailing: 16 * unit)
            ZStack {
                StampPaperView(theme: theme)
                VStack {
                    Text("签证 · VISAS")
                        .font(.custom("AvenirNextCondensed-DemiBold", fixedSize: 9 * unit))
                        .tracking(3 * unit)
                    Spacer()
                    Text("— \(number) —")
                        .font(.system(size: 9 * unit, design: .monospaced))
                }
                .foregroundColor(theme.guilloche)
                .padding(.vertical, 12 * unit)

                if stamps.isEmpty {
                    VStack(spacing: 8 * unit) {
                        RoundedRectangle(cornerRadius: 10 * unit)
                            .stroke(theme.guilloche, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            .frame(width: 150 * unit, height: 96 * unit)
                        Text("出国旅行时，入境的那一刻会自动盖在这里")
                            .font(.system(size: 11 * unit))
                            .multilineTextAlignment(.center)
                            .foregroundColor(theme.printed.opacity(0.55))
                            .frame(width: 180 * unit)
                    }
                }

                ForEach(Array(stamps.enumerated()), id: \.element.id) { index, stamp in
                    let slot = Self.slots[index % Self.slots.count]
                    let j = Self.jitter(stamp.seed)
                    StampArtView(stamp: stamp)
                        .frame(width: 138 * unit, height: 118 * unit)
                        .rotationEffect(.degrees(stamp.tilt))
                        .position(x: (slot.x + j.x) * proxy.size.width, y: (slot.y + j.y) * proxy.size.height)
                }
            }
            .clipShape(shape)
        }
    }
}

private struct PageCurlContainer: UIViewControllerRepresentable {
    let pages: [AnyView]
    let bookSize: CGSize
    @Binding var current: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)]
        )
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.isDoubleSided = false
        controller.view.backgroundColor = .clear
        controller.view.insetsLayoutMarginsFromSafeArea = false
        let initial = min(max(0, current), max(0, pages.count - 1))
        controller.setViewControllers([context.coordinator.page(initial)], direction: .forward, animated: false)
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.parent = self
    }

    /// 普通 UIViewController 包装层：阻断滚动到导航栏下方时 UIPageViewController 向下传递 safeAreaInsets 导致内页被压扁下移
    final class Page: UIViewController {
        let index: Int
        private let host: UIHostingController<AnyView>
        private let fixedSize: CGSize

        init(index: Int, content: AnyView, fixedSize: CGSize) {
            self.index = index
            self.fixedSize = fixedSize
            let wrapped = AnyView(
                content
                    .frame(width: fixedSize.width, height: fixedSize.height)
                    .ignoresSafeArea(.all)
            )
            let hc = UIHostingController(rootView: wrapped)
            hc.sizingOptions = []
            hc.view.backgroundColor = .clear
            hc.view.insetsLayoutMarginsFromSafeArea = false
            self.host = hc
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.insetsLayoutMarginsFromSafeArea = false
            view.clipsToBounds = false
            // 不作为 child VC 加入，彻底隔断 UIKit safeAreaInsets 传递到 UIHostingController
            host.view.frame = CGRect(origin: .zero, size: fixedSize)
            view.addSubview(host.view)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            let target = CGRect(origin: .zero, size: fixedSize)
            if host.view.frame != target {
                host.view.frame = target
            }
        }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageCurlContainer
        private var made: [Int: Page] = [:]

        init(_ parent: PageCurlContainer) {
            self.parent = parent
        }

        func page(_ index: Int) -> Page {
            if let existing = made[index] { return existing }
            let vc = Page(index: index, content: parent.pages[index], fixedSize: parent.bookSize)
            made = made.filter { abs($0.key - index) <= 3 }
            made[index] = vc
            return vc
        }

        func pageViewController(_ controller: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let index = (viewController as? Page)?.index, index > 0 else { return nil }
            return page(index - 1)
        }

        func pageViewController(_ controller: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let index = (viewController as? Page)?.index, index + 1 < parent.pages.count else { return nil }
            return page(index + 1)
        }

        func pageViewController(_ controller: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let index = (controller.viewControllers?.first as? Page)?.index else { return }
            parent.current = index
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
        }
    }
}

// MARK: - Dark World Stamp Map (iOS 16 MKMapView with Glowing Gold Country Outlines)

private struct WorldStampMapSection: View {
    let summary: PassportSummary

    @State private var selectedContinentID: String? = nil
    @State private var showsUnvisited = false
    @State private var isFullScreen = false
    @State private var overlays: [WorldPolygonData] = []
    @State private var flagPins: [WorldFlagPin] = []

    private static let glow = Color(red: 1.0, green: 0.78, blue: 0.36)

    private var continents: [WorldContinent] {
        WorldContinent.all.sorted {
            let a = $0.regions.filter(summary.visitedCountries.contains).count
            let b = $0.regions.filter(summary.visitedCountries.contains).count
            return a != b ? a > b : $0.id < $1.id
        }
    }

    private var totalRegions: Int { WorldContinent.all.reduce(0) { $0 + $1.regions.count } }
    private var selectedContinent: WorldContinent? { selectedContinentID.flatMap { id in WorldContinent.all.first { $0.id == id } } }
    private var scopeCodes: [String] { selectedContinent?.regions ?? WorldContinent.all.flatMap(\.regions) }

    private var listedCountries: [PassportCountrySummary] {
        let codes = Set(scopeCodes)
        return summary.countrySummaries.filter { codes.contains($0.code) }.sorted { $0.days > $1.days }
    }

    private var unvisitedCodes: [String] {
        scopeCodes.filter { !summary.visitedCountries.contains($0) }.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(summary.visitedCountries.count)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("/ \(totalRegions)")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("去过的国家和地区").font(.subheadline.weight(.semibold))
                    Text("跨越 \(summary.continentsVisited) 个大洲").font(.footnote).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)

            continentChips

            WorldFootprintMKMapView(
                overlays: overlays,
                flagPins: flagPins,
                cityStamps: summary.cityStamps,
                targetRegion: region(for: selectedContinentID),
                interactive: false
            )
            .frame(height: 330)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .overlay(alignment: .bottomLeading) { legendPill.padding(12) }
            .overlay(alignment: .topTrailing) {
                Button { isFullScreen = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.black.opacity(0.55), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 0.8))
                }
                .padding(12)
            }

            if listedCountries.isEmpty {
                Text(selectedContinent == nil ? "出国旅行后，去过的国家会在地图上亮起来。" : "这片大陆还在等你。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(listedCountries.enumerated()), id: \.element.id) { idx, country in
                        NavigationLink {
                            CountryDetailView(countryCode: country.code, fallbackName: country.name)
                        } label: {
                            HStack(spacing: 12) {
                                Text(country.flag).font(.system(size: 30))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(country.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundColor(.primary)
                                    if !country.topCities.isEmpty {
                                        Text(country.topCities.joined(separator: "、"))
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(country.days) 天")
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                        .foregroundColor(.primary)
                                    Text("\(StampDateFormat.year(country.firstVisit))年")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Color(.tertiaryLabel))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                        }
                        .buttonStyle(.plain)
                        if idx < listedCountries.count - 1 { Divider().padding(.leading, 58) }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }

            if !unvisitedCodes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showsUnvisited.toggle() }
                    } label: {
                        HStack {
                            Text("还没去过的 \(unvisitedCodes.count) 个").font(.subheadline.weight(.medium))
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                                .rotationEffect(.degrees(showsUnvisited ? 180 : 0))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)

                    if showsUnvisited {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 6)], spacing: 6) {
                            ForEach(unvisitedCodes, id: \.self) { code in
                                Text(CountryText.flag(for: code))
                                    .font(.system(size: 26))
                                    .grayscale(1)
                                    .opacity(0.32)
                            }
                        }
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
            }
        }
        .task(id: summary.visitedCountries.count + summary.cityStamps.count) {
            let visited = summary.visitedCountries
            let cities = summary.cityStamps
            let built = await Task.detached(priority: .userInitiated) { () -> ([WorldPolygonData], [WorldFlagPin]) in
                var polys: [WorldPolygonData] = []
                var pins: [WorldFlagPin] = []
                for code in visited.sorted() {
                    let mine = cities.filter { $0.countryCode == code }.map { $0.coordinate.onMap }
                    let rings = CountryBorders.pieces(of: code, visited: mine)
                    for (idx, ring) in rings.enumerated() where ring.count >= 3 {
                        polys.append(WorldPolygonData(id: "\(code).\(idx)", coordinates: ring))
                    }
                    if let spot = Self.centre(of: mine) ?? rings.first.flatMap(Self.centre(of:)) {
                        pins.append(WorldFlagPin(code: code, coordinate: spot))
                    }
                }
                return (polys, pins)
            }.value
            overlays = built.0
            flagPins = built.1
        }
        .fullScreenCover(isPresented: $isFullScreen) {
            ZStack {
                WorldFootprintMKMapView(
                    overlays: overlays,
                    flagPins: flagPins,
                    cityStamps: summary.cityStamps,
                    targetRegion: region(for: selectedContinentID),
                    interactive: true
                )
                .ignoresSafeArea()

                VStack {
                    HStack(alignment: .top, spacing: 10) {
                        continentChips
                        Button { isFullScreen = false } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.black.opacity(0.6), in: Circle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    Spacer()
                    HStack {
                        legendPill
                        Spacer()
                    }
                    .padding(16)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var continentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "全部", count: "\(summary.visitedCountries.count)", id: nil)
                ForEach(continents) { continent in
                    let lit = continent.regions.filter(summary.visitedCountries.contains).count
                    chip(title: continent.name, count: "\(lit)/\(continent.regions.count)", id: continent.id)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func chip(title: String, count: String, id: String?) -> some View {
        let on = selectedContinentID == id
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedContinentID = id
            }
        } label: {
            HStack(spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(count).font(.caption.weight(.semibold).monospacedDigit()).opacity(0.75)
            }
            .foregroundColor(on ? .black : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(on ? Self.glow : Color(.secondarySystemGroupedBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var legendPill: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Circle().fill(Self.glow).frame(width: 7, height: 7)
                Text("去过的国家").font(.caption2.weight(.semibold)).foregroundColor(.white.opacity(0.9))
            }
            HStack(spacing: 5) {
                Circle().fill(Color.white).frame(width: 7, height: 7)
                Text("城市").font(.caption2.weight(.semibold)).foregroundColor(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.6), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.7))
    }

    private nonisolated static func centre(of points: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        guard !points.isEmpty else { return nil }
        let lats = points.map(\.latitude), lons = points.map(\.longitude)
        return CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
    }

    private func region(for continent: String?) -> MKCoordinateRegion {
        func make(_ lat: Double, _ lon: Double, _ dLat: Double, _ dLon: Double) -> MKCoordinateRegion {
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                span: MKCoordinateSpan(latitudeDelta: dLat, longitudeDelta: dLon)
            )
        }
        switch continent {
        case "142": return make(30, 95, 72, 100)
        case "150": return make(52, 15, 40, 58)
        case "002": return make(2, 20, 78, 78)
        case "019": return make(12, -88, 120, 110)
        case "009": return make(-22, 150, 56, 80)
        default:
            let points = flagPins.map(\.coordinate) + overlays.filter { $0.coordinates.count >= 60 }.flatMap(\.coordinates)
            let lats = points.map(\.latitude), lons = points.map(\.longitude)
            guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else {
                return make(28, 105, 85, 110)
            }
            if maxLon - minLon >= 200 {
                let flags = flagPins.map(\.coordinate)
                guard !flags.isEmpty else { return make(20, 20, 120, 280) }
                let midLat = flags.map(\.latitude).sorted()[flags.count / 2]
                let midLon = flags.map(\.longitude).sorted()[flags.count / 2]
                return make(min(max(midLat, -30), 45), midLon, 120, 280)
            }
            return make(
                (minLat + maxLat) / 2,
                (minLon + maxLon) / 2,
                min(max((maxLat - minLat) * 1.35, 36), 130),
                min(max((maxLon - minLon) * 1.25, 45), 300)
            )
        }
    }
}

private struct WorldPolygonData: Identifiable, Sendable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
}

private struct WorldFlagPin: Identifiable, Sendable {
    let code: String
    let coordinate: CLLocationCoordinate2D
    var id: String { code }
}

private final class WorldFlagAnnotation: NSObject, MKAnnotation {
    let code: String
    dynamic var coordinate: CLLocationCoordinate2D
    init(code: String, coordinate: CLLocationCoordinate2D) {
        self.code = code
        self.coordinate = coordinate
    }
}

private final class WorldCityDotAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

private struct WorldFootprintMKMapView: UIViewRepresentable {
    let overlays: [WorldPolygonData]
    let flagPins: [WorldFlagPin]
    let cityStamps: [PassportStamp]
    let targetRegion: MKCoordinateRegion
    let interactive: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.overrideUserInterfaceStyle = .dark
        map.mapType = .mutedStandard
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsScale = false
        map.isScrollEnabled = interactive
        map.isZoomEnabled = interactive
        map.isRotateEnabled = interactive
        map.isPitchEnabled = false
        map.delegate = context.coordinator
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let sig = "\(overlays.count)-\(flagPins.count)-\(cityStamps.count)"
        if context.coordinator.lastSignature != sig {
            context.coordinator.lastSignature = sig
            map.removeOverlays(map.overlays)
            map.removeAnnotations(map.annotations)

            let polys = overlays.map { item -> MKPolygon in
                var coords = item.coordinates
                return MKPolygon(coordinates: &coords, count: coords.count)
            }
            map.addOverlays(polys, level: .aboveRoads)

            let cityAnns = cityStamps.map { WorldCityDotAnnotation(coordinate: $0.coordinate.onMap) }
            let flagAnns = flagPins.map { WorldFlagAnnotation(code: $0.code, coordinate: $0.coordinate) }
            map.addAnnotations(cityAnns)
            map.addAnnotations(flagAnns)
        }

        let regKey = String(format: "%.2f,%.2f,%.2f", targetRegion.center.latitude, targetRegion.center.longitude, targetRegion.span.latitudeDelta)
        if context.coordinator.lastRegionKey != regKey {
            context.coordinator.lastRegionKey = regKey
            map.setRegion(targetRegion, animated: context.coordinator.hasInitializedRegion)
            context.coordinator.hasInitializedRegion = true
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var lastSignature: String = ""
        var lastRegionKey: String = ""
        var hasInitializedRegion = false

        private let glowUIColor = UIColor(red: 1.0, green: 0.78, blue: 0.36, alpha: 1.0)
        private let nightUIColor = UIColor(red: 0.06, green: 0.07, blue: 0.12, alpha: 1.0)
        private lazy var cityGlowImage: UIImage = {
            let size = CGSize(width: 18, height: 18)
            return UIGraphicsImageRenderer(size: size).image { ctx in
                let colors = [glowUIColor.withAlphaComponent(0.75).cgColor, glowUIColor.withAlphaComponent(0).cgColor] as CFArray
                if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
                    ctx.cgContext.drawRadialGradient(
                        grad,
                        startCenter: CGPoint(x: 9, y: 9), startRadius: 1,
                        endCenter: CGPoint(x: 9, y: 9), endRadius: 9,
                        options: []
                    )
                }
                UIColor.white.setFill()
                UIBezierPath(ovalIn: CGRect(x: 6.75, y: 6.75, width: 4.5, height: 4.5)).fill()
            }
        }()

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let poly = overlay as? MKPolygon {
                let r = MKPolygonRenderer(polygon: poly)
                r.fillColor = glowUIColor.withAlphaComponent(0.28)
                r.strokeColor = glowUIColor.withAlphaComponent(0.95)
                r.lineWidth = 1.4
                r.lineJoin = .round
                r.lineCap = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is WorldCityDotAnnotation {
                let id = "wt.cityDot"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.image = cityGlowImage
                view.canShowCallout = false
                view.displayPriority = .defaultLow
                return view
            }

            if let flagAnn = annotation as? WorldFlagAnnotation {
                let id = "wt.flagPin"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.image = renderFlagPin(code: flagAnn.code)
                view.centerOffset = CGPoint(x: 0, y: -18)
                view.canShowCallout = false
                view.displayPriority = .required
                return view
            }
            return nil
        }

        private var flagCache: [String: UIImage] = [:]

        private func renderFlagPin(code: String) -> UIImage {
            if let cached = flagCache[code] { return cached }
            let size = CGSize(width: 34, height: 40)
            let img = UIGraphicsImageRenderer(size: size).image { ctx in
                // Stem
                glowUIColor.setFill()
                ctx.fill(CGRect(x: 16.25, y: 29, width: 1.5, height: 9))
                // Circle badge
                let circleRect = CGRect(x: 2, y: 2, width: 30, height: 30)
                let path = UIBezierPath(ovalIn: circleRect)
                nightUIColor.setFill()
                path.fill()
                glowUIColor.setStroke()
                path.lineWidth = 1.8
                path.stroke()
                // Flag emoji
                let str = CountryText.flag(for: code) as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 17)]
                let textSize = str.size(withAttributes: attrs)
                str.draw(at: CGPoint(x: circleRect.midX - textSize.width / 2, y: circleRect.midY - textSize.height / 2), withAttributes: attrs)
            }
            flagCache[code] = img
            return img
        }
    }
}

// MARK: - 8x8 Geographic Province Tile Map

private struct ProvinceTileMapView: View {
    let visits: [String: PassportProvinceVisit]
    let onSelect: (ChinaProvince) -> Void

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 6
            let side = (proxy.size.width - spacing * CGFloat(ChinaProvince.columns - 1)) / CGFloat(ChinaProvince.columns)
            ZStack(alignment: .topLeading) {
                ForEach(ChinaProvince.all) { province in
                    let visit = visits[province.id]
                    Button { onSelect(province) } label: {
                        tile(province, visit: visit, side: side)
                    }
                    .buttonStyle(.plain)
                    .offset(x: CGFloat(province.column) * (side + spacing), y: CGFloat(province.row) * (side + spacing))
                }
            }
        }
        .aspectRatio(CGFloat(ChinaProvince.columns) / CGFloat(ChinaProvince.rows), contentMode: .fit)
    }

    @ViewBuilder
    private func tile(_ province: ChinaProvince, visit: PassportProvinceVisit?, side: CGFloat) -> some View {
        if let visit {
            let stamp = PassportStamp(id: "province.\(province.id)", kind: .province, date: visit.firstVisit, provinceID: province.id)
            StampArtView(stamp: stamp)
                .frame(width: side, height: side)
                .rotationEffect(.degrees(stamp.tilt * 0.35))
        } else {
            RoundedRectangle(cornerRadius: side * 0.16, style: .continuous)
                .stroke(StampPaperView.defaultLine, style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                .overlay {
                    Text(province.shortChar)
                        .font(.system(size: side * 0.5, weight: .heavy))
                        .foregroundColor(StampPaperView.defaultLine)
                }
                .frame(width: side, height: side)
        }
    }
}

// MARK: - Tab 4: Commemorative (Four Corners + Crossings + New Year + 14 Stamp Sets)

private struct CommemorativeTabSection: View {
    let summary: PassportSummary
    @State private var showsOtherSets = false

    private let printed = Color(red: 0.25, green: 0.22, blue: 0.2)

    private func special(_ code: String) -> PassportStamp? {
        summary.specials.first { $0.code == code }
    }

    private var newYears: [PassportStamp] {
        summary.specials.filter { ($0.code ?? "").hasPrefix("newyear") }.reversed()
    }

    private var startedSets: [StampSet.Progress] {
        summary.stampSets
            .filter { !$0.visited.isEmpty }
            .sorted {
                ($0.isComplete ? 1 : 0, Double($0.visited.count) / Double($0.group.members.count))
                    > ($1.isComplete ? 1 : 0, Double($1.visited.count) / Double($1.group.members.count))
            }
    }

    private var unstartedSets: [StampSet.Progress] {
        summary.stampSets.filter { $0.visited.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            fourCornersSection
            crossingsSection
            if !newYears.isEmpty { newYearsSection }
            setsSection
        }
    }

    private var fourCornersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("你的四至", detail: "去过的最北、最南、最东、最西，和最高的地方")
            VStack(spacing: 0) {
                ZStack {
                    CompassRoseView()
                        .frame(width: 132, height: 132)
                    VStack {
                        cornerTile("north")
                        Spacer(minLength: 0)
                        cornerTile("south")
                    }
                    HStack {
                        cornerTile("west")
                        Spacer(minLength: 0)
                        cornerTile("east")
                    }
                }
                .frame(height: 368)
                .padding(.horizontal, 6)

                if let highest = special("record.high") {
                    Rectangle()
                        .fill(StampPaperView.defaultLine)
                        .frame(height: 0.8)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)

                    HStack(spacing: 16) {
                        StampArtView(stamp: highest)
                            .frame(width: 104, height: 96)
                            .rotationEffect(.degrees(highest.tilt * 0.35))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("最高")
                                .font(.caption.weight(.bold))
                                .tracking(2)
                                .foregroundColor(printed.opacity(0.6))
                            Text(highest.value ?? "")
                                .font(.system(.title2, design: .serif).weight(.bold))
                                .foregroundColor(printed)
                            Text(CityStampStyle.displayName(highest).nilIfEmpty ?? "海拔记录")
                                .font(.subheadline)
                                .foregroundColor(printed.opacity(0.75))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(StampPaperView(style: .book))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func cornerTile(_ direction: String) -> some View {
        let stamp = special("record.\(direction)")
        let reach: String = {
            switch direction {
            case "north": return "北至"
            case "south": return "南至"
            case "east": return "东至"
            default: return "西至"
            }
        }()
        return VStack(spacing: 5) {
            Group {
                if let stamp {
                    StampArtView(stamp: stamp)
                        .rotationEffect(.degrees(stamp.tilt * 0.3))
                } else {
                    StampArtView(
                        stamp: PassportStamp(id: "special.record.\(direction)", kind: .special, date: .distantPast, code: "record.\(direction)"),
                        inked: false
                    )
                }
            }
            .frame(width: 56, height: 56)

            VStack(spacing: 1) {
                Text(reach)
                    .font(.caption2.weight(.bold))
                    .tracking(1.5)
                    .foregroundColor(printed.opacity(0.55))
                Text(stamp.map { CityStampStyle.displayName($0) }.flatMap(\.nilIfEmpty) ?? "—")
                    .font(.system(.footnote, design: .serif).weight(.semibold))
                    .foregroundColor(printed)
                    .lineLimit(1)
                if let value = stamp?.value {
                    Text(value)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(printed.opacity(0.6))
                }
            }
        }
        .frame(width: 104)
    }

    private var crossingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("跨越", detail: "一生可能只有一次")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(["equator", "dateline", "arctic", "antarctic"], id: \.self) { code in
                    if let stamp = special(code) {
                        crossingTile(stamp, earned: true)
                    } else if code == "equator" || code == "dateline" {
                        crossingTile(
                            PassportStamp(
                                id: "special.\(code)",
                                kind: .special,
                                date: .distantPast,
                                code: code,
                                value: code == "equator" ? "0°00′" : "180°"
                            ),
                            earned: false
                        )
                    }
                }
            }
            .padding(14)
            .background(StampPaperView(style: .book))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func crossingTile(_ stamp: PassportStamp, earned: Bool) -> some View {
        VStack(spacing: 6) {
            StampArtView(stamp: stamp, inked: earned)
                .frame(height: 104)
                .rotationEffect(.degrees(earned ? stamp.tilt * 0.55 : 0))
            Text(earned ? CityStampStyle.displayName(stamp) : (stamp.code == "equator" ? "还没跨过赤道" : "还没越过日期变更线"))
                .font(.caption.weight(earned ? .semibold : .regular))
                .foregroundColor(Color(red: 0.3, green: 0.27, blue: 0.24).opacity(earned ? 1 : 0.55))
                .lineLimit(1)
        }
    }

    private var newYearsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("跨年", detail: "每一年，从哪里开始")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(newYears) { stamp in
                        VStack(spacing: 4) {
                            StampArtView(stamp: stamp)
                                .frame(width: 104, height: 104)
                                .rotationEffect(.degrees(stamp.tilt * 0.55))
                            Text(CityStampStyle.displayName(stamp))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Color(red: 0.3, green: 0.27, blue: 0.24))
                                .lineLimit(1)
                                .frame(width: 104)
                        }
                    }
                }
                .padding(14)
            }
            .background(StampPaperView(style: .book))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var setsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("套章", detail: "集齐一组城市，盖一枚联合章")
            if startedSets.isEmpty {
                Text("去过其中任何一座城市，这一套就会出现在这里。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
            ForEach(startedSets) { progress in
                StampSetRow(progress: progress)
            }
            if !unstartedSets.isEmpty {
                DisclosureGroup(isExpanded: $showsOtherSets) {
                    VStack(spacing: 10) {
                        ForEach(unstartedSets) { progress in
                            StampSetRow(progress: progress)
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    Text("还有 \(unstartedSets.count) 套").font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 4)
                .tint(.secondary)
            }
        }
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.bold())
            Text(detail).font(.footnote).foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }
}

private struct StampSetRow: View {
    let progress: StampSet.Progress

    private var ghost: PassportStamp {
        PassportStamp(id: "set.\(progress.group.id)", kind: .set, date: .distantPast, code: progress.group.id)
    }

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let stamp = progress.stamp {
                    StampArtView(stamp: stamp)
                        .rotationEffect(.degrees(stamp.tilt * 0.4))
                } else {
                    StampArtView(stamp: ghost, inked: false)
                }
            }
            .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(progress.group.localizedName).font(.headline)
                    Spacer()
                    Text("\(progress.visited.count) / \(progress.group.members.count)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundColor(progress.isComplete ? progress.group.ink.color : .secondary)
                }
                ProgressView(value: Double(progress.visited.count), total: Double(progress.group.members.count))
                    .tint(progress.group.ink.color)
                memberText
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var memberText: some View {
        progress.group.members.enumerated().reduce(Text("")) { acc, item in
            let visited = progress.visited[item.element] != nil
            let piece = Text(StampSet.memberName(item.element))
                .foregroundColor(visited ? .primary : Color(.tertiaryLabel))
                .fontWeight(visited ? .semibold : .regular)
            return item.offset == 0 ? piece : acc + Text("  ") + piece
        }
        .font(.footnote)
        .lineLimit(2)
    }
}

// MARK: - Share Sheet Helper

private struct ShareablePassportImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct PassportActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
