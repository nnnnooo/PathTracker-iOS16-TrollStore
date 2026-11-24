import SwiftUI
import UIKit
import Photos
import HealthKit
import UniformTypeIdentifiers

/// 1:1 Original PathTracker (漫迹) Settings Page adapted for iOS 16 & TrollStore.
struct SettingsView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var engine: LocationEngine
    @EnvironmentObject private var tagger: PlaceTagger
    @Environment(\.dismiss) private var dismiss

    @AppStorage("wt16.profile.name") private var profileName: String = "漫迹旅人"
    @AppStorage("wt16.profile.subtitle") private var profileSubtitle: String = "记录走过的每一步"
    @AppStorage("wt16.passport.theme") private var passportThemeRaw: String = PassportTheme.obsidian.rawValue
    @AppStorage("wt16.settings.language") private var appLanguage: String = "system"
    @AppStorage("wt16.notify.arrivals") private var notifyArrivals: Bool = true
    @AppStorage("wt16.notify.milestones") private var notifyMilestones: Bool = true
    @AppStorage("wt16.notify.weekly") private var notifyWeekly: Bool = true

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
    @State private var healthNeedsRequest: Bool = true

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
                ProfileEditorSheet(name: $profileName, subtitle: $profileSubtitle)
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
                            if let first = urls.first, store.restoreBackup(from: first) {
                                alertMessage = "数据库已恢复：共载入 \(store.chunks.count) 段轨迹、\(store.stays.count) 个地点、\(store.trips.count) 段旅程。"
                            } else {
                                alertMessage = "恢复失败，请确认选择的是有效的 Waytrace16-Backup.sqlite 文件。"
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
            .task {
                await refreshHealthRequestStatus()
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
                Label("记录方式", systemImage: "location.fill")
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
                Label("当前状态", systemImage: "waveform.path.ecg")
            }

            if engine.isEnabled {
                Picker(selection: $engine.precision) {
                    ForEach(LocationEngine.Precision.allCases) { p in
                        Text(p.title).tag(p)
                    }
                } label: {
                    Label("记录精度", systemImage: "scope")
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
                title: "健康（步数）",
                symbol: "heart.circle.fill",
                tint: .pink,
                value: healthAuthText,
                needsAction: HKHealthStore.isHealthDataAvailable() && healthNeedsRequest
            ) {
                requestOrOpenHealth()
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
                    for idx in offsets {
                        store.deletePrivacyZone(id: store.privacyZones[idx].id)
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

    private var dataSection: some View {
        Section {
            LabeledContent("轨迹片段", value: "\(store.chunks.count)")
            LabeledContent("到访记录", value: "\(store.stays.count)")
            LabeledContent("旅程与记录", value: "\(store.trips.count)")

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

            Button {
                showPhotoImport = true
            } label: {
                Label("重新从相册导入", systemImage: "photo.stack")
            }

            Button {
                tagger.retryFailed()
                tagger.enqueue()
                withAnimation { retagged = true }
            } label: {
                Label(retagged ? "已开始重新识别" : "重新识别未命名的地点", systemImage: "arrow.clockwise")
            }
            .disabled(retagged)

            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label("删除所有数据", systemImage: "trash")
            }
        } header: {
            Text("数据")
        } footer: {
            Text("GPX 可以导入 AllTrails、Strava、Google Earth 等应用。TrollStore 环境下无法使用 iCloud 同步，建议定期导出 .sqlite 备份。")
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

    private var healthAuthText: String {
        guard HKHealthStore.isHealthDataAvailable() else { return "此设备不支持" }
        return healthNeedsRequest ? "轻点授权" : "在健康中管理"
    }

    private func refreshHealthRequestStatus() async {
        guard HKHealthStore.isHealthDataAvailable(),
              let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            healthNeedsRequest = false
            return
        }
        let healthStore = HKHealthStore()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: [stepType]) { status, _ in
                Task { @MainActor in
                    self.healthNeedsRequest = (status == .shouldRequest)
                    cont.resume()
                }
            }
        }
    }

    private func requestOrOpenHealth() {
        guard HKHealthStore.isHealthDataAvailable(),
              let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            alertMessage = "当前设备不支持 Apple 健康数据。"
            return
        }
        if !healthNeedsRequest {
            if let url = URL(string: "x-apple-health://") {
                UIApplication.shared.open(url)
            }
            return
        }
        let healthStore = HKHealthStore()
        healthStore.requestAuthorization(toShare: [], read: [stepType]) { _, error in
            Task { @MainActor in
                if let error {
                    alertMessage = "无法拉起系统健康授权（\(error.localizedDescription)），请前往“健康”App 中手动开启。"
                    if let url = URL(string: "x-apple-health://") {
                        UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    }
                } else {
                    await refreshHealthRequestStatus()
                }
            }
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("个人资料") {
                    TextField("昵称（用于右上角头像首字）", text: $name)
                    TextField("个人简介 / 签名", text: $subtitle)
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
        .presentationDetents([.medium])
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
