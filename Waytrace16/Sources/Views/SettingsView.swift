import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var engine: LocationEngine
    @EnvironmentObject private var tagger: PlaceTagger

    @State private var showClearConfirm = false
    @State private var exportedURL: URL?

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

                Section("数据与导出") {
                    LabeledContent("已记录轨迹段", value: "\(store.chunks.count)")
                    LabeledContent("已记录停留点", value: "\(store.stays.count)")
                    LabeledContent("待识别地点", value: "\(tagger.pendingCount)")

                    Button("重新识别未命名地点") {
                        tagger.retryFailed()
                        tagger.enqueue()
                    }

                    if let url = exportedURL {
                        ShareLink(item: url) {
                            Label("分享已生成的 GPX 文件", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button("导出全部轨迹（GPX）") {
                            exportedURL = GPXExporter.export(chunks: store.chunks, stays: store.stays)
                        }
                    }
                }

                Section {
                    Button("清空全部本地数据", role: .destructive) {
                        showClearConfirm = true
                    }
                } footer: {
                    Text("Waytrace iOS 16 MVP · 适配 iOS 16.0+ / TrollStore，数据仅保存在本机 SQLite 数据库中。")
                }
            }
            .navigationTitle("设置")
            .confirmationDialog("确定清空所有轨迹和停留记录吗？此操作无法撤销。", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("全部清空", role: .destructive) {
                    store.deleteAllData()
                    engine.reloadAfterClear()
                    exportedURL = nil
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
