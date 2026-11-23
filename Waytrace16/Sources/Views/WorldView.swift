import SwiftUI
import Photos

struct WorldView: View {
    @Binding var showingSettings: Bool
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var tagger: PlaceTagger

    @AppStorage("wt16.passport.theme") private var themeRaw: String = PassportTheme.burgundy.rawValue
    @State private var showFullMap = false
    @State private var fullMapLayer = 0 // 0=地点, 1=路线
    @State private var showPhotoImport = false
    @State private var searchText = ""

    private struct RegionStat: Identifiable {
        let id: String
        let name: String
        let stayCount: Int
        let dayCount: Int
        let stays: [Stay]
    }

    private var theme: PassportTheme { PassportTheme(rawValue: themeRaw) ?? .burgundy }

    private var countryStats: [RegionStat] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: store.stays.filter { $0.country != nil }) { $0.country! }
        return grouped.map { key, list in
            let days = Set(list.map { cal.startOfDay(for: $0.arrival) }).count
            return RegionStat(id: key, name: key, stayCount: list.count, dayCount: days, stays: list)
        }.sorted { $0.dayCount > $1.dayCount }
    }

    private var cityStats: [RegionStat] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: store.stays.filter { $0.city != nil }) { $0.city! }
        return grouped.map { key, list in
            let days = Set(list.map { cal.startOfDay(for: $0.arrival) }).count
            return RegionStat(id: key, name: key, stayCount: list.count, dayCount: days, stays: list)
        }.sorted { $0.dayCount > $1.dayCount }
    }

    private var landmarkCount: Int {
        store.stays.filter(\.isLandmark).count
    }

    private var searchResults: [Stay] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return Array(store.stays.filter { stay in
            stay.displayName.localizedCaseInsensitiveContains(q)
            || (stay.city?.localizedCaseInsensitiveContains(q) ?? false)
            || (stay.country?.localizedCaseInsensitiveContains(q) ?? false)
            || (stay.street?.localizedCaseInsensitiveContains(q) ?? false)
        }.prefix(50))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !searchText.isEmpty {
                        searchResultsSection
                    } else {
                        summaryGrid
                        passportFullCard
                        featureCards
                        mapCard
                        photoImportCard
                        if !countryStats.isEmpty {
                            regionSection(title: "国家和地区", stats: countryStats)
                        }
                        if !cityStats.isEmpty {
                            regionSection(title: "去过的城市", stats: cityStats)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("足迹")
            .searchable(text: $searchText, prompt: "搜索地点、城市或国家")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showPhotoImport = true
                    } label: {
                        Image(systemName: "photo.on.rectangle.angled")
                    }
                    ProfileToolbarButton(showingSettings: $showingSettings)
                }
            }
            .sheet(isPresented: $showPhotoImport) {
                PhotoImportSheet()
            }
            .fullScreenCover(isPresented: $showFullMap) {
                NavigationStack {
                    WorldFootprintMapView(
                        stays: store.stays,
                        chunks: store.chunks,
                        showRoutes: fullMapLayer == 1
                    )
                    .ignoresSafeArea()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { showFullMap = false }
                        }
                        ToolbarItem(placement: .principal) {
                            Picker("图层", selection: $fullMapLayer) {
                                Text("地点").tag(0)
                                Text("路线").tag(1)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }
                    }
                }
            }
        }
    }

    // Matches upstream 2x2 hairline MetricGrid
    private var summaryGrid: some View {
        MetricGrid2x2 {
            MetricTile(title: "国家与地区", value: "\(countryStats.count)", symbol: "flag.fill", tint: .red)
        } topRight: {
            MetricTile(title: "城市", value: "\(cityStats.count)", symbol: "building.2.fill", tint: .indigo)
        } bottomLeft: {
            MetricTile(title: "景点", value: "\(landmarkCount)", symbol: "star.fill", tint: .yellow)
        } bottomRight: {
            MetricTile(title: "记录天数", value: "\(store.recordedDaysCount)", symbol: "calendar", tint: .teal)
        }
    }

    // Matches upstream leather PassportCard
    private var passportFullCard: some View {
        NavigationLink {
            PassportView()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.coverColor)
                        .frame(width: 48, height: 62)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(theme.foilColor.opacity(0.55), lineWidth: 1)
                                .padding(3)
                        )
                    Image(systemName: "globe.asia.australia.fill")
                        .font(.title3)
                        .foregroundColor(theme.foilColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("漫迹护照与印章")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("国家出入境章 · 中国 34 省朱砂印 · 城市章 · 四至与套章")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private var featureCards: some View {
        VStack(spacing: 12) {
            NavigationLink {
                MustSeeView()
            } label: {
                featureRowCard(
                    icon: "star.fill",
                    iconColor: .orange,
                    title: "此生必去",
                    subtitle: "中国 100 处 · 世界 100 处夜空星图与自动点亮"
                )
            }
            .buttonStyle(PressableStyle())

            HStack(spacing: 12) {
                NavigationLink {
                    BlindBoxView()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "gift.fill").foregroundColor(.pink)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                        }
                        Text("旅行盲盒").font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                        Text("拆登机牌去未知之地").font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(PressableStyle())

                NavigationLink {
                    VisaWalletView()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "creditcard.and.123").foregroundColor(.blue)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                        }
                        Text("签证夹").font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                        Text("扫机读码 · 申根 90/180").font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private func featureRowCard(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(iconColor.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // Matches upstream 240pt / 28pt cornerRadius WorldMap card
    private var mapCard: some View {
        Button {
            showFullMap = true
        } label: {
            WorldFootprintMapView(
                stays: store.stays,
                chunks: store.chunks,
                showRoutes: false
            )
            .allowsHitTesting(false)
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Label("全部足迹", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
            }
        }
        .buttonStyle(PressableStyle())
    }

    private var photoImportCard: some View {
        Button {
            showPhotoImport = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "photo.stack.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("从相册找回历史足迹")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text(tagger.progressText ?? "本地读取照片拍摄地点，点亮去过的城市与国家")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if tagger.isTagging {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private func regionSection(title: String, stats: [RegionStat]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, trailing: "\(stats.count)")
            VStack(spacing: 0) {
                ForEach(Array(stats.prefix(12).enumerated()), id: \.element.id) { index, item in
                    NavigationLink {
                        RegionStaysListView(title: item.name, stays: item.stays)
                    } label: {
                        HStack {
                            Text(item.name)
                                .font(.body.weight(.medium))
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(item.dayCount) 天 · \(item.stayCount) 次")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    if index < min(stats.count, 12) - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "搜索结果", trailing: "\(searchResults.count)")
            if searchResults.isEmpty {
                WaytraceCard {
                    Text("没有找到匹配的地点").font(.subheadline).foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(searchResults.enumerated()), id: \.element.id) { idx, stay in
                        HStack(spacing: 12) {
                            PlaceIcon(category: stay.category, isLandmark: stay.isLandmark, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stay.displayName).font(.subheadline.weight(.semibold))
                                Text([stay.subtitle, Formatters.dayTitle(stay.arrival)].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        if idx < searchResults.count - 1 { Divider().padding(.leading, 62) }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }
}

private struct RegionStaysListView: View {
    let title: String
    let stays: [Stay]

    var body: some View {
        List(stays) { stay in
            VStack(alignment: .leading, spacing: 4) {
                Text(stay.displayName).font(.subheadline.weight(.semibold))
                Text("\(Formatters.dayTitle(stay.arrival)) \(Formatters.timeHM(stay.arrival)) · \(Formatters.duration(stay.duration))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        }
        .navigationTitle(title)
    }
}

struct PhotoImportSheet: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var tagger: PlaceTagger
    @Environment(\.dismiss) private var dismiss

    @State private var isScanning = false
    @State private var scannedCount = 0
    @State private var totalCount = 0
    @State private var summary: PhotoFootprints.Summary?
    @State private var permissionDenied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                    .padding(.top, 20)

                Text("从相册导入历史足迹")
                    .font(.title3.bold())

                Text("仅在本地读取照片和视频的拍摄时间与 GPS 坐标，自动聚合成停留记录并在后台按区域批量识别城市与国家，照片本身不会上传。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if isScanning {
                    VStack(spacing: 8) {
                        ProgressView(value: totalCount > 0 ? Double(scannedCount) / Double(totalCount) : 0)
                        Text("正在扫描相册：\(scannedCount) / \(totalCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 32)
                } else if let s = summary {
                    VStack(spacing: 6) {
                        Text("导入完成")
                            .font(.headline)
                            .foregroundColor(.green)
                        Text("共扫描 \(s.scanned) 项，含位置 \(s.withLocation) 项，新增 \(s.visits) 条历史足迹（已自动跳过重复记录 \(s.skippedAlreadyRecorded) 条）。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Text("城市与国家名称正在后台按 10km 网格快速识别中。")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24)
                }

                if permissionDenied {
                    Text("没有相册读取权限，请前往系统设置授予权限。")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Spacer()

                Button {
                    startImport()
                } label: {
                    Text(isScanning ? "正在扫描…" : (summary == nil ? "开始扫描相册" : "重新扫描新增照片"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isScanning)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func startImport() {
        permissionDenied = false
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard status == .authorized || status == .limited else {
                permissionDenied = true
                return
            }
            isScanning = true
            let result = await PhotoFootprints.importLibrary(into: store) { current, total in
                Task { @MainActor in
                    scannedCount = current
                    totalCount = total
                }
            }
            summary = result
            isScanning = false
            tagger.enqueue()
        }
    }
}
