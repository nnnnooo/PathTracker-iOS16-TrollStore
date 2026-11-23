import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var engine: LocationEngine
    @EnvironmentObject private var tagger: PlaceTagger

    @State private var showClearConfirm = false
    @State private var exportedGPXURL: URL?
    @State private var backupSQLiteURL: URL?
    @State private var showGPXImporter = false
    @State private var showBackupRestorer = false
    @State private var alertMessage: String?

    private var gpxContentType: UTType {
        UTType(filenameExtension: "gpx") ?? .xml
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("全天自动记录足迹", isOn: $engine.isEnabled)
                } footer: {
                    Text("开启后 App 会在后台自动记录路线和停留地点；关闭后彻底释放定位，不消耗额外电量。")
                }

                Section("记录精度与省电") {
                    Picker("记录精度", selection: $engine.precision) {
                        ForEach(LocationEngine.Precision.allCases) { p in
                            Text(p.title).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(engine.precision.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("权限与状态") {
                    LabeledContent("定位权限", value: authText)
                    LabeledContent("精确位置", value: engine.isPreciseLocation ? "已开启" : "仅大致位置")
                    Button("打开系统定位设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                if !store.privacyZones.isEmpty {
                    Section("隐私区域（导出时隐藏 300m）") {
                        ForEach(store.privacyZones) { zone in
                            HStack {
                                Label(zone.name, systemImage: "eye.slash")
                                Spacer()
                                Button("移除", role: .destructive) {
                                    store.deletePrivacyZone(id: zone.id)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }

                Section("轨迹导入与导出") {
                    LabeledContent("轨迹段 / 停留 / 旅程", value: "\(store.chunks.count) / \(store.stays.count) / \(store.trips.count)")
                    LabeledContent("待识别地点", value: "\(tagger.pendingCount)")

                    Button("重新识别未命名地点") {
                        tagger.retryFailed()
                        tagger.enqueue()
                    }

                    Button("导入 GPX 轨迹文件") {
                        showGPXImporter = true
                    }

                    if let url = exportedGPXURL {
                        ShareLink(item: url) {
                            Label("分享已生成的 GPX 文件", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button("导出全部轨迹（GPX）") {
                            exportedGPXURL = GPXExporter.export(
                                chunks: store.chunks,
                                stays: store.stays,
                                privacyZones: store.privacyZones
                            )
                        }
                    }
                }

                Section {
                    if let url = backupSQLiteURL {
                        ShareLink(item: url) {
                            Label("保存数据库备份文件", systemImage: "externaldrive.badge.checkmark")
                        }
                    } else {
                        Button("导出本地数据库备份（.sqlite）") {
                            backupSQLiteURL = store.exportBackupFile()
                        }
                    }

                    Button("从备份文件恢复数据库") {
                        showBackupRestorer = true
                    }
                } header: {
                    Text("本地备份与恢复（替代 iCloud）")
                } footer: {
                    Text("TrollStore 环境下无法使用 iCloud 同步，建议定期导出 .sqlite 备份到「文件」或 iCloud 云盘。")
                }

                Section {
                    Button("清空全部本地数据", role: .destructive) {
                        showClearConfirm = true
                    }
                } footer: {
                    Text("Waytrace iOS 16 · 第 3 批增强版（此生必去 200 处 / 旅行盲盒 / 护照印章 / 分享卡片 / 旅程 / 统计图表 / 本地备份）。")
                }
            }
            .navigationTitle("设置")
            .fileImporter(isPresented: $showGPXImporter, allowedContentTypes: [gpxContentType, .xml], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    var chunksAdded = 0, staysAdded = 0, skipped = 0
                    for url in urls {
                        let s = GPXImporter.importFile(at: url, into: store)
                        chunksAdded += s.addedChunks
                        staysAdded += s.addedStays
                        skipped += s.skippedDuplicates
                    }
                    tagger.enqueue()
                    alertMessage = "导入完成：新增 \(chunksAdded) 段轨迹、\(staysAdded) 个地点（跳过重复 \(skipped) 项）。"
                case .failure(let err):
                    alertMessage = "导入失败：\(err.localizedDescription)"
                }
            }
            .fileImporter(isPresented: $showBackupRestorer, allowedContentTypes: [.data, .item], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let first = urls.first, store.restoreBackup(from: first) {
                        alertMessage = "数据库已恢复：共载入 \(store.chunks.count) 段轨迹、\(store.stays.count) 个地点、\(store.trips.count) 段旅程。"
                    } else {
                        alertMessage = "恢复失败，请确认选择的是有效的 Waytrace16-Backup.sqlite 文件。"
                    }
                case .failure(let err):
                    alertMessage = "恢复失败：\(err.localizedDescription)"
                }
            }
            .alert("提示", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .confirmationDialog("确定清空所有轨迹、停留和旅程记录吗？此操作无法撤销。", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("全部清空", role: .destructive) {
                    store.deleteAllData()
                    engine.reloadAfterClear()
                    exportedGPXURL = nil
                    backupSQLiteURL = nil
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private var authText: String {
        switch engine.authorization {
        case .authorizedAlways: return "始终允许"
        case .authorizedWhenInUse: return "仅使用期间（建议改为始终）"
        case .denied, .restricted: return "已拒绝"
        case .notDetermined: return "未授权"
        @unknown default: return "未知"
        }
    }
}
