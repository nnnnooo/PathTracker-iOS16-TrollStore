import SwiftUI
import Photos

struct WorldView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var tagger: PlaceTagger

    @State private var mapMode = 0
    @State private var showPhotoImport = false

    private struct RegionStat: Identifiable {
        let id: String
        let name: String
        let stayCount: Int
        let dayCount: Int
        let stays: [Stay]
    }

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    mapSection
                    statsGrid
                    passportBanner
                    mustSeeAndBlindBoxRow
                    photoImportBanner
                    if !countryStats.isEmpty {
                        regionSection(title: "去过的国家 / 地区", stats: countryStats)
                    }
                    if !cityStats.isEmpty {
                        regionSection(title: "去过的城市", stats: cityStats)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("足迹")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showPhotoImport = true
                    } label: {
                        Label("导入相册", systemImage: "photo.on.rectangle.angled")
                    }
                }
            }
            .sheet(isPresented: $showPhotoImport) {
                PhotoImportSheet()
            }
        }
    }

    private var mapSection: some View {
        VStack(spacing: 10) {
            Picker("地图显示", selection: $mapMode) {
                Text("足迹光点").tag(0)
                Text("全部路线").tag(1)
            }
            .pickerStyle(.segmented)

            WorldFootprintMapView(
                stays: store.stays,
                chunks: store.chunks,
                showRoutes: mapMode == 1
            )
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statBox(title: "国家 / 地区", value: "\(countryStats.count)", icon: "globe.asia.australia.fill", color: .blue)
            statBox(title: "去过的城市", value: "\(cityStats.count)", icon: "building.2.fill", color: .orange)
            statBox(title: "记录天数", value: "\(store.recordedDaysCount)", icon: "calendar", color: .green)
            statBox(title: "总里程", value: Formatters.distance(store.totalDistance), icon: "point.topleft.down.curvedto.point.bottomright.up", color: .purple)
        }
    }

    private func statBox(title: String, value: String, icon: String, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(value).font(.title3.bold())
                Text(title).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var passportBanner: some View {
        HStack(spacing: 10) {
            NavigationLink {
                PassportView()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "book.closed.fill")
                            .foregroundColor(Color(red: 0.87, green: 0.74, blue: 0.42))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text("护照与印章")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text("出入境 · 34省 · 套章")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            NavigationLink {
                VisaWalletView()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "creditcard.and.123")
                            .foregroundColor(.blue)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text("签证夹")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text("扫机读码 · 申根90/180")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var mustSeeAndBlindBoxRow: some View {
        HStack(spacing: 10) {
            NavigationLink {
                MustSeeView()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.orange)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text("此生必去")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text("中国 100 · 世界 100")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            NavigationLink {
                BlindBoxView()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "gift.fill")
                            .foregroundColor(.pink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text("旅行盲盒")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text("拆登机牌去未知之地")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var photoImportBanner: some View {
        Button {
            showPhotoImport = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "photo.stack.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("从相册找回历史足迹")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text("本地读取照片拍摄地点，点亮以前去过的城市与国家")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if tagger.isTagging {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func regionSection(title: String, stats: [RegionStat]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(stats.enumerated()), id: \.element.id) { index, item in
                    NavigationLink {
                        RegionStaysListView(title: item.name, stays: item.stays)
                    } label: {
                        HStack {
                            Text(item.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(item.dayCount) 天 · \(item.stayCount) 次")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    if index < stats.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

                Text("仅在本地读取照片和视频的拍摄时间与 GPS 坐标，自动聚合成停留记录并在后台识别城市与国家，照片本身不会上传。")
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
                        Text("城市与国家名称正在后台分批识别中。")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
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
