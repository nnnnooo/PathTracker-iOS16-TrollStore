import SwiftUI
import UIKit
import Photos
import CoreMotion
import UniformTypeIdentifiers

/// 1:1 Original PathTracker (漫迹) Settings Page adapted for iOS 16 & TrollStore.
struct SettingsView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var engine: LocationEngine
    @EnvironmentObject private var tagger: PlaceTagger
    @Environment(\.dismiss) private var dismiss

    @AppStorage("wt16.profile.name") private var profileName: String = "漫迹旅人"
    @AppStorage("wt16.profile.subtitle") private var profileSubtitle: String = "记录走过的每一步"
    @AppStorage("wt16.profile.nationality") private var nationalityCode: String = ""
    @AppStorage("wt16.passport.theme") private var passportThemeRaw: String = PassportTheme.obsidian.rawValue
    @AppStorage("wt16.settings.language") private var appLanguage: String = "system"
    @AppStorage("wt16.notify.arrivals") private var notifyArrivals: Bool = true
    @AppStorage("wt16.notify.milestones") private var notifyMilestones: Bool = true
    @AppStorage("wt16.notify.weekly") private var notifyWeekly: Bool = true
    @AppStorage(PhotoFootprints.autoImportEnabledKey) private var autoImportPhotos: Bool = false
    @AppStorage(StintPhotoFetcher.locatedOnlyKey) private var photosLocatedOnly: Bool = false

    private enum ImportKind: Identifiable {
        case gpx, backup
        var id: Int { self == .gpx ? 0 : 1 }
    }

    @State private var showProfileEdit = false
    @State private var showPhotoImport = false
    @State private var showClearConfirm = false
    @State private var retagged = false
    @State private var exportedGPXURL: URL?
    @State private var backupSQLiteURL: URL?
    @State private var activePicker: ImportKind?
    @State private var isImportingGPX = false
    @State private var importProgressText: String?
    @State private var alertMessage: String?
    @State private var motionAuthStatus: CMAuthorizationStatus = CMPedometer.authorizationStatus()

    private var passportTheme: PassportTheme {
        PassportTheme(rawValue: passportThemeRaw) ?? .obsidian
    }

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                languageSection
                passportStyleSection
                trackingSection
                notificationsSection
                permissionsSection
                photosSection
                privacyZonesSection
                dataSection
                aboutSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.blue, in: Circle())
                    }
                }
            }
            .sheet(isPresented: $showProfileEdit) {
                ProfileEditorSheet(name: $profileName, subtitle: $profileSubtitle, nationalityCode: $nationalityCode)
            }
            .sheet(isPresented: $showPhotoImport) {
                PhotoImportSheet()
            }
            .sheet(item: $activePicker) { kind in
                NativeDocumentPicker(allowMultiple: kind == .gpx) { urls in
                    guard !urls.isEmpty else { return }
                    Task { @MainActor in
                        if kind == .gpx {
                            isImportingGPX = true
                            importProgressText = "正在读取文件…"
                            let s = await GPXImporter.importFiles(at: urls, into: store) { status in
                                importProgressText = status
                            }
                            isImportingGPX = false
                            importProgressText = nil
                            tagger.enqueue()
                            if let err = s.errorMessage {
                                alertMessage = "GPX 导入未成功：\(err)"
                            } else {
                                alertMessage = "导入完成：共解析 \(s.totalPoints) 个点，新增 \(s.addedChunks) 段轨迹、\(s.addedStays) 个地点（跳过重复 \(s.skippedDuplicates) 项）。"
                            }
                        } else {
                            if let first = urls.first {
                                let res = store.restoreBackup(from: first)
                                if res.success {
                                    alertMessage = "数据库已恢复：共载入 \(store.chunks.count) 段轨迹、\(store.stays.count) 个地点、\(store.trips.count) 段旅程。"
                                } else {
                                    alertMessage = res.errorMessage ?? "恢复失败，请确认选择的是有效的 Waytrace16-Backup.sqlite 文件。"
                                }
                            } else {
                                alertMessage = "未选择任何备份文件。"
                            }
                        }
                    }
                }
            }
            .alert("提示", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .confirmationDialog("删除所有数据？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("删除所有数据", role: .destructive) {
                    store.deleteAllData()
                    engine.reloadAfterClear()
                    exportedGPXURL = nil
                    backupSQLiteURL = nil
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("所有轨迹、地点、旅程和隐私区域都会从这台设备永久删除，且无法恢复。")
            }
            .onAppear {
                motionAuthStatus = CMPedometer.authorizationStatus()
            }
        }
    }

    // MARK: - 1. Account Card

    private var accountSection: some View {
        Section {
            Button {
                showProfileEdit = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.14, green: 0.62, blue: 1.0), Color.blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text(String(profileName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased().nilIfEmpty ?? "F")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .frame(width: 58, height: 58)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(profileName.nilIfEmpty ?? "漫迹旅人")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.primary)
                        Text(profileSubtitle.nilIfEmpty ?? "设置头像、名字和个人信息")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                        Label("本地数据模式 · iOS 16", systemImage: "iphone")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 2. Language

    private var languageSection: some View {
        Section {
            Picker(selection: $appLanguage) {
                Text("跟随系统").tag("system")
                Text("简体中文").tag("zh-Hans")
                Text("English").tag("en")
            } label: {
                Label("语言", systemImage: "globe")
            }
        } footer: {
            Text("系统权限弹窗的语言会在下次打开 App 时更新。")
        }
    }

    // MARK: - 3. Passport Style (4 Miniature Covers)

    private var passportStyleSection: some View {
        Section {
            HStack(spacing: 14) {
                ForEach(PassportTheme.allCases) { item in
                    let isSelected = passportTheme == item
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            passportThemeRaw = item.rawValue
                        }
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
            .padding(.vertical, 8)
        } header: {
            Text("护照样式")
        } footer: {
            Text("封面和内页的纸张、底纹会一起换。")
        }
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

    // MARK: - 4. Tracking

    private var trackingSection: some View {
        Section {
            Picker(selection: $engine.isEnabled) {
                Text("全天自动").tag(true)
                Text("仅手动").tag(false)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    Text("记录方式")
                }
            }
            .onChange(of: engine.isEnabled) { _ in
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }

            LabeledContent {
                HStack(spacing: 8) {
                    if engine.isEnabled && engine.currentLocation != nil {
                        GPSSignalBadge(location: engine.currentLocation)
                    }
                    Text(statusText).foregroundColor(.secondary)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    Text("当前状态")
                }
            }

            if engine.isEnabled {
                Picker(selection: $engine.precision) {
                    ForEach(LocationEngine.Precision.allCases) { p in
                        Text(p.title).tag(p)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "scope")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        Text("记录精度")
                    }
                }
                .onChange(of: engine.precision) { _ in
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }

            if engine.isPaused {
                Button {
                    engine.resume()
                } label: {
                    Label(engine.isPausedIndefinitely ? "继续记录" : "恢复记录", systemImage: "play.circle")
                }
            }

            if engine.activeTrip != nil {
                Label("手动记录进行中，使用高精度定位", systemImage: "record.circle")
                    .foregroundColor(.orange)
            }
        } header: {
            Text("记录")
        } footer: {
            Text(precisionFooter)
        }
    }

    // MARK: - 5. Notifications

    private var notificationsSection: some View {
        Section {
            Toggle(isOn: $notifyArrivals) {
                Label("第一次到达新地方", systemImage: "mappin.and.ellipse")
            }
            Toggle(isOn: $notifyMilestones) {
                Label("达成里程碑", systemImage: "flag.checkered")
            }
            Toggle(isOn: $notifyWeekly) {
                Label("每周一回顾上周", systemImage: "calendar")
            }
        } header: {
            Text("通知")
        } footer: {
            Text("第一次到达新的国家、省份或城市，达成里程碑，以及每周一早上回顾上周。通知在手机上生成，不经过任何服务器。")
        }
    }

    // MARK: - 6. Permissions & Local Backup

    private var permissionsSection: some View {
        Section("权限与备份") {
            permissionRow(
                title: "位置",
                symbol: "location.circle.fill",
                tint: .blue,
                value: locationText,
                needsAction: !engine.hasAnyPermission || (engine.isEnabled && !engine.hasAlwaysPermission) || !engine.isPreciseLocation
            ) {
                switch engine.authorization {
                case .notDetermined: engine.requestWhenInUse()
                case .authorizedWhenInUse: engine.requestAlways()
                default: openSystemSettings()
                }
            }

            permissionRow(
                title: "运动与步数",
                symbol: "figure.walk.circle.fill",
                tint: .pink,
                value: motionAuthText,
                needsAction: motionAuthStatus != .authorized
            ) {
                requestOrOpenMotion()
            }

            permissionRow(
                title: "照片（时间线）",
                symbol: "photo.circle.fill",
                tint: .orange,
                value: photosAuthText,
                needsAction: PHPhotoLibrary.authorizationStatus(for: .readWrite) == .denied
            ) {
                if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
                    Task { _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
                } else {
                    openSystemSettings()
                }
            }

            if let url = backupSQLiteURL {
                ShareLink(item: url) {
                    Label("保存本地备份（.sqlite）", systemImage: "externaldrive.badge.checkmark")
                }
            } else {
                Button {
                    backupSQLiteURL = store.exportBackupFile()
                } label: {
                    HStack {
                        Label {
                            Text("本地数据库备份").foregroundColor(.primary)
                        } icon: {
                            Image(systemName: "icloud.fill").foregroundColor(.blue)
                        }
                        Spacer()
                        Text("导出 .sqlite")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                }
            }

            Button {
                activePicker = .backup
            } label: {
                Label("从备份文件恢复数据库", systemImage: "arrow.triangle.2.circlepath.icloud")
            }
        }
    }

    // MARK: - 6.5 Photos Filter

    private var photosSection: some View {
        Section {
            Toggle(isOn: $photosLocatedOnly) {
                Label("只显示带位置信息的照片", systemImage: "mappin.circle.fill")
            }
            .onChange(of: photosLocatedOnly) { _ in
                Task { await StintPhotoFetcher.shared.invalidateCaches() }
            }
        } footer: {
            Text("打开后，没有位置信息的图片（比如下载或保存的图片）不会出现在时间线、地点和旅程里。如果相机关闭了定位，拍的照片也没有位置，同样不会显示。")
        }
    }

    // MARK: - 7. Privacy Zones

    private var privacyZonesSection: some View {
        Section {
            if store.privacyZones.isEmpty {
                Text("还没有隐私区域")
                    .foregroundColor(.secondary)
            } else {
                ForEach(store.privacyZones) { zone in
                    Label(zone.name, systemImage: "eye.slash")
                }
                .onDelete { offsets in
                    let ids = offsets.compactMap { store.privacyZones.indices.contains($0) ? store.privacyZones[$0].id : nil }
                    for id in ids {
                        store.deletePrivacyZone(id: id)
                    }
                }
            }
        } header: {
            Text("隐私区域")
        } footer: {
            Text("在地点详情里打开“分享和导出时隐藏这里”即可添加，左滑可以删除。隐私区域内的轨迹不会出现在分享图片和 GPX 文件里。")
        }
    }

    // MARK: - 8. Data Management

    private var failedStaysCount: Int {
        store.stays.filter { Self.isUnresolvedStay($0) }.count
    }

    fileprivate static func isUnresolvedStay(_ stay: Stay) -> Bool {
        if stay.tagState == .failed { return true }
        if stay.customName == nil && (stay.countryCode == nil || (stay.city == nil && stay.placeName == nil)) {
            return true
        }
        return false
    }

    private var dataSection: some View {
        Section {
            LabeledContent {
                Text("\(store.chunks.count)").monospacedDigit().foregroundColor(.secondary)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "point.topleft.down.curvedto.point.filled.bottomright.up")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    Text("轨迹片段")
                }
            }

            LabeledContent {
                Text("\(store.stays.count)").monospacedDigit().foregroundColor(.secondary)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(.pink)
                        .frame(width: 24)
                    Text("到访记录")
                }
            }

            LabeledContent {
                Text("\(store.trips.count)").monospacedDigit().foregroundColor(.secondary)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "suitcase.rolling.fill")
                        .foregroundColor(.indigo)
                        .frame(width: 24)
                    Text("旅程与记录")
                }
            }

            if let url = exportedGPXURL {
                ShareLink(item: url) {
                    Label("分享已生成的 GPX 文件", systemImage: "square.and.arrow.up")
                }
            } else {
                Button {
                    exportedGPXURL = GPXExporter.export(
                        chunks: store.chunks,
                        stays: store.stays,
                        privacyZones: store.privacyZones
                    )
                } label: {
                    Label("导出全部轨迹（GPX）", systemImage: "square.and.arrow.up")
                }
                .disabled(store.chunks.isEmpty && store.stays.isEmpty)
            }

            Button {
                activePicker = .gpx
            } label: {
                HStack {
                    Label("导入 GPX 文件", systemImage: "square.and.arrow.down")
                    Spacer()
                    if isImportingGPX {
                        ProgressView()
                    } else if let status = importProgressText {
                        Text(status).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .disabled(isImportingGPX)

            Toggle(isOn: $autoImportPhotos) {
                Label("自动获取新增照片", systemImage: "photo.on.rectangle.angled")
            }
            .onChange(of: autoImportPhotos) { enabled in
                if enabled {
                    Task {
                        await PhotoFootprints.importNewPhotosIfEnabled(into: store, tagger: tagger, force: true)
                    }
                }
            }

            Button {
                showPhotoImport = true
            } label: {
                Label("重新从相册导入", systemImage: "photo.stack")
            }

            NavigationLink {
                FailedTaggedStaysView()
            } label: {
                HStack {
                    Label("识别失败 / 未命名地点", systemImage: "exclamationmark.triangle")
                    Spacer()
                    Text("\(failedStaysCount)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(failedStaysCount > 0 ? .orange : .secondary)
                }
            }

            Button {
                retagged = true
                tagger.retryFailed()
                tagger.enqueue()
            } label: {
                HStack(spacing: 8) {
                    Label {
                        if tagger.isTagging {
                            Text(tagger.progressText ?? "正在识别地点（剩余 \(tagger.pendingCount) 条）…")
                                .foregroundColor(.primary)
                        } else if retagged && tagger.pendingCount == 0 {
                            Text("地点识别已完成")
                                .foregroundColor(.green)
                        } else {
                            Text("重新识别未命名的地点")
                        }
                    } icon: {
                        if tagger.isTagging {
                            ProgressView()
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: (retagged && tagger.pendingCount == 0) ? "checkmark.circle.fill" : "arrow.clockwise")
                                .foregroundColor((retagged && tagger.pendingCount == 0) ? .green : .blue)
                        }
                    }
                    Spacer()
                    if tagger.isTagging && tagger.pendingCount > 0 {
                        Text("剩 \(tagger.pendingCount) 条")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            }
            .disabled(tagger.isTagging)

            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label("删除所有数据", systemImage: "trash")
            }
        } header: {
            Text("数据")
        } footer: {
            Text("开启“自动获取新增照片”后，每次打开或切回 App 时会自动增量导入（仅检查新照片元数据，冷却 5 分钟，几乎不耗电）。识别区域进度按 10km 网格合并计数。")
        }
    }

    // MARK: - 9. About

    private var aboutSection: some View {
        Section {
            NavigationLink {
                LocalPrivacyPolicyView()
            } label: {
                Label("隐私政策", systemImage: "hand.raised.fill")
            }

            LabeledContent("版本", value: appVersionText)
        } header: {
            Text("关于")
        } footer: {
            Text("漫迹 Waytrace · iOS 16 适配版")
                .font(.caption2)
                .foregroundColor(Color(.tertiaryLabel))
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
    }

    // MARK: - Helpers

    private func permissionRow(
        title: String,
        symbol: String,
        tint: Color,
        value: String,
        needsAction: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Label {
                    Text(title)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                } icon: {
                    Image(systemName: symbol).foregroundColor(tint)
                }
                Spacer(minLength: 8)
                Text(value)
                    .foregroundColor(needsAction ? .orange : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(.tertiaryLabel))
            }
        }
        .buttonStyle(.plain)
    }

    private var motionAuthText: String {
        guard CMPedometer.isStepCountingAvailable() else { return "此设备不支持" }
        switch motionAuthStatus {
        case .authorized: return "已允许"
        case .denied, .restricted: return "未允许"
        case .notDetermined: return "轻点授权"
        @unknown default: return "去设置"
        }
    }

    private func requestOrOpenMotion() {
        guard CMPedometer.isStepCountingAvailable() else {
            alertMessage = "当前设备不支持运动协处理器计步。"
            return
        }
        if motionAuthStatus == .notDetermined {
            let pedometer = CMPedometer()
            let now = Date()
            let start = Calendar.current.startOfDay(for: now)
            pedometer.queryPedometerData(from: start, to: now) { _, _ in
                Task { @MainActor in
                    self.motionAuthStatus = CMPedometer.authorizationStatus()
                }
            }
        } else {
            openSystemSettings()
        }
    }

    private var precisionFooter: String {
        guard engine.isEnabled else {
            return "仅手动：只在你从“今天”页开始记录时使用位置，结束后完全不定位。不需要“始终允许”位置权限。"
        }
        return engine.precision.subtitle + "也可以随时在“今天”页右上角手动记录一段。"
    }

    private var locationText: String {
        switch engine.authorization {
        case .authorizedAlways:
            return engine.isPreciseLocation ? "始终允许" : "精确位置已关闭"
        case .authorizedWhenInUse:
            return "使用期间"
        case .denied:
            return "已拒绝"
        case .restricted:
            return "受限制"
        default:
            return "未设置"
        }
    }

    private var statusText: String {
        if engine.isPaused && engine.activeTrip == nil { return "已暂停" }
        guard engine.isEnabled || engine.activeTrip != nil else { return "未在记录" }
        switch engine.activity {
        case .moving: return "移动中"
        case .stationary: return "静止"
        case .starting: return "启动中"
        case .unavailable: return "无法定位"
        case .off: return "等待权限"
        }
    }

    private var photosAuthText: String {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: return "全部照片"
        case .limited: return "部分照片"
        case .denied, .restricted: return "未允许"
        default: return "未开启"
        }
    }

    private var appVersionText: String {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.6"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "16"
        return "\(ver) (\(build))"
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Profile Editor Sheet

private struct ProfileEditorSheet: View {
    @Binding var name: String
    @Binding var subtitle: String
    @Binding var nationalityCode: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("个人资料") {
                    TextField("昵称（用于右上角头像首字）", text: $name)
                    TextField("个人简介 / 签名", text: $subtitle)
                }
                Section {
                    CountryPickerRow(
                        title: "国籍",
                        selection: $nationalityCode,
                        leading: [CountryChoice(code: "", flag: "", name: "自动（停留最久的国家）")]
                    )
                } footer: {
                    Text("用于护照页判断本国与出入境章。选择“自动”时按停留最久的国家计算。")
                }
            }
            .navigationTitle("编辑个人资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Built-in Privacy Policy View

private struct LocalPrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("你的足迹只属于你")
                    .font(.title3.bold())
                Text("漫迹16 所有轨迹、停留地点、旅程笔记、护照与签证信息均完全保存在你的设备本地数据库中，不会上传到任何第三方服务器。")
                Text("相册导入与签证识别均在手机本地完成，照片本身不会被上传或复制出系统相册。")
                Text("当你手动使用“导出 GPX”或“本地数据库备份”时，文件仅由你主动决定分享或保存位置。")
            }
            .font(.body)
            .foregroundColor(.primary.opacity(0.88))
            .padding(20)
        }
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Native UIDocumentPickerViewController with `asCopy: true`:
/// 100% reliable on iOS 16 inside sheets & TrollStore (no security-scope or iCloud permission failures).
// MARK: - Failed / Unresolved Photo & Location Stays Manager

private struct FailedTaggedStaysView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var tagger: PlaceTagger
    @State private var editingStay: Stay?

    private var failedStays: [Stay] {
        store.stays
            .filter { SettingsView.isUnresolvedStay($0) }
            .sorted { $0.arrival > $1.arrival }
    }

    var body: some View {
        Group {
            if failedStays.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.green)
                    Text("没有识别失败的地点")
                        .font(.headline)
                    Text("所有定位与相册足迹都已成功识别或手动命名。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            } else {
                List {
                    Section {
                        ForEach(failedStays) { stay in
                            Button {
                                editingStay = stay
                            } label: {
                                FailedStayRow(stay: stay)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.deleteStay(id: stay.id)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text("共 \(failedStays.count) 条 · 点击可手动命名或删除")
                    } footer: {
                        Text("多为海上、偏远无网络区域或海外坐标超出离线边界的照片，点击即可手动填写地点名称，或左滑删除。")
                    }
                }
            }
        }
        .navigationTitle("识别失败的地点")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !failedStays.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("重试识别") {
                        tagger.retryFailed()
                    }
                    .disabled(tagger.isTagging)
                }
            }
        }
        .sheet(item: $editingStay) { stay in
            StayDetailSheet(stay: stay)
        }
    }
}

private struct FailedStayRow: View {
    let stay: Stay
    @State private var thumb: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let thumb {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.tertiarySystemFill)
                    Image(systemName: stay.isFromPhotos ? "photo" : "mappin.slash")
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(stay.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(stay.isFromPhotos ? "相册" : "定位")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(stay.isFromPhotos ? .pink : .blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((stay.isFromPhotos ? Color.pink : Color.blue).opacity(0.12), in: Capsule())
                }
                Text("\(Formatters.dayTitle(stay.arrival)) \(Formatters.timeHM(stay.arrival))")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                Text(String(format: "%.4f, %.4f", stay.latitude, stay.longitude))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(Color(.tertiaryLabel))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(.vertical, 2)
        .task(id: stay.id) {
            let items = await StintPhotoFetcher.shared.stayPhotoItems(for: stay)
            thumb = items.first?.thumbnail
        }
    }
}

private struct NativeDocumentPicker: UIViewControllerRepresentable {
    let allowMultiple: Bool
    let onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = allowMultiple
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}
