import SwiftUI

struct VisaWalletView: View {
    @EnvironmentObject private var store: DataStore
    @ObservedObject private var visaStore = VisaStore.shared

    @State private var selectedVisa: VisaRecord?
    @State private var showAddSheet = false
    @State private var editingVisa: VisaRecord?

    private var schengenUsed: Int { VisaCatalog.schengenUsedDays(stays: store.stays) }
    private var hasSchengenVisa: Bool { visaStore.visas.contains { $0.isSchengen && !$0.isExpired } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if hasSchengenVisa || schengenUsed > 0 {
                    schengenCard
                }

                if visaStore.visas.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: -24) {
                        ForEach(visaStore.visas) { visa in
                            visaCard(visa)
                                .onTapGesture {
                                    selectedVisa = visa
                                }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("签证夹")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            VisaEditorSheet(existing: nil)
        }
        .sheet(item: $selectedVisa) { visa in
            VisaDetailSheet(visa: visa)
        }
    }

    private var schengenCard: some View {
        let remaining = max(0, 90 - schengenUsed)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("申根区 90 / 180 天额度", systemImage: "eurosign.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.blue)
                Spacer()
                Text("还可停留 \(remaining) 天")
                    .font(.caption.bold())
                    .foregroundColor(remaining < 15 ? .red : .green)
            }
            ProgressView(value: min(1.0, Double(schengenUsed) / 90.0))
                .tint(remaining < 15 ? .red : .blue)
            Text("过去 180 天内你在申根国已停留 \(schengenUsed) 天（按足迹自动统计）。")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func visaCard(_ visa: VisaRecord) -> some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: visa.cardColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.22), radius: 8, y: 4)

            Text("WAYTRACE")
                .font(.system(size: 30, weight: .black))
                .foregroundColor(.white.opacity(0.06))
                .padding(16)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(visa.headerLabel)
                        .font(.caption2.monospaced().bold())
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text(visa.isExpired ? "已过期" : "剩 \(visa.remainingDays) 天")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(visa.isExpired ? Color.red : Color.white.opacity(0.22), in: Capsule())
                        .foregroundColor(.white)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(visa.countryName)
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    Text(visa.visaType)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                    Spacer()
                }

                HStack {
                    if !visa.visaNumber.isEmpty {
                        Text("NO. \(visa.visaNumber)")
                            .font(.caption.monospaced())
                            .foregroundColor(.white.opacity(0.9))
                    }
                    Spacer()
                    Text("有效期至 \(shortDate(visa.expiryDate))")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(18)
        }
        .frame(height: 156)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "creditcard.and.123")
                .font(.system(size: 46))
                .foregroundColor(.blue)
            Text("还没有添加签证")
                .font(.headline)
            Text("支持相机实时扫描签证页底部机读码（MRZ）自动填写，或手动录入；自动计算剩余天数、申根 90/180 天额度并在到期前 90/30/7 天提醒。")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Button {
                showAddSheet = true
            } label: {
                Label("添加第一张签证", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return f.string(from: date)
    }
}

private struct VisaDetailSheet: View {
    @EnvironmentObject private var store: DataStore
    @ObservedObject private var visaStore = VisaStore.shared
    @Environment(\.dismiss) private var dismiss

    let visa: VisaRecord
    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    var body: some View {
        let usage = VisaCatalog.usageStats(for: visa, stays: store.stays)
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .stroke(Color(.tertiarySystemFill), lineWidth: 8)
                            Circle()
                                .trim(from: 0, to: visa.validityProgress)
                                .stroke(visa.isExpired ? Color.red : Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 1) {
                                Text(visa.isExpired ? "过期" : "\(visa.remainingDays)")
                                    .font(.title3.bold())
                                if !visa.isExpired {
                                    Text("天").font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(width: 72, height: 72)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(visa.countryName) · \(visa.visaType)").font(.headline)
                            Text("入境次数：\(visa.entries.rawValue) · 单次最长 \(visa.maxStayDays) 天")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("已用记录：\(usage.entries) 次入境 · 累计 \(usage.days) 天")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("签证信息") {
                    if !visa.visaNumber.isEmpty { LabeledContent("签证号码", value: visa.visaNumber) }
                    if !visa.issuingPost.isEmpty { LabeledContent("签发地", value: visa.issuingPost) }
                    LabeledContent("签发日期", value: Formatters.dayTitle(visa.issueDate))
                    LabeledContent("到期日期", value: Formatters.dayTitle(visa.expiryDate))
                    if !visa.notes.isEmpty { LabeledContent("备注", value: visa.notes) }
                }

                Section {
                    Button("编辑签证信息") { showEdit = true }
                    Button("删除此签证", role: .destructive) { showDeleteConfirm = true }
                }
            }
            .navigationTitle("签证详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showEdit) {
                VisaEditorSheet(existing: visa)
            }
            .confirmationDialog("确定删除这张签证吗？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    visaStore.delete(id: visa.id)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
}

private struct VisaEditorSheet: View {
    @ObservedObject private var visaStore = VisaStore.shared
    @Environment(\.dismiss) private var dismiss

    let existing: VisaRecord?

    @State private var countryCode: String
    @State private var countryName: String
    @State private var visaType: String
    @State private var visaNumber: String
    @State private var issuingPost: String
    @State private var entries: VisaEntries
    @State private var maxStayDays: Int
    @State private var issueDate: Date
    @State private var expiryDate: Date
    @State private var notes: String
    @State private var showScanner = false

    init(existing: VisaRecord?) {
        self.existing = existing
        let v = existing ?? VisaRecord()
        _countryCode = State(initialValue: v.countryCode)
        _countryName = State(initialValue: v.countryName)
        _visaType = State(initialValue: v.visaType)
        _visaNumber = State(initialValue: v.visaNumber)
        _issuingPost = State(initialValue: v.issuingPost)
        _entries = State(initialValue: v.entries)
        _maxStayDays = State(initialValue: v.maxStayDays)
        _issueDate = State(initialValue: v.issueDate)
        _expiryDate = State(initialValue: v.expiryDate)
        _notes = State(initialValue: v.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                if existing == nil {
                    Section {
                        Button {
                            showScanner = true
                        } label: {
                            Label("相机实时扫描签证机读码（MRZ）", systemImage: "viewfinder")
                                .font(.subheadline.weight(.semibold))
                        }
                    } footer: {
                        Text("对准签证底部的两行机读码即可自动填充国家、签证号与到期日。")
                    }
                }

                Section("国家 / 地区") {
                    Picker("快捷选择", selection: $countryCode) {
                        ForEach(VisaCatalog.presets, id: \.code) { item in
                            Text("\(item.name) (\(item.code))").tag(item.code)
                        }
                    }
                    .onChange(of: countryCode) { newCode in
                        if let match = VisaCatalog.presets.first(where: { $0.code == newCode }) {
                            countryName = match.name
                        }
                    }
                    TextField("国家/地区名称", text: $countryName)
                }

                Section("签证详情") {
                    TextField("类型（如 B1/B2、申根 C 类、三年多次）", text: $visaType)
                    TextField("签证号码（可选）", text: $visaNumber)
                    TextField("签发地（可选，如 SHANGHAI）", text: $issuingPost)
                    Picker("入境次数", selection: $entries) {
                        ForEach(VisaEntries.allCases) { e in
                            Text(e.rawValue).tag(e)
                        }
                    }
                    Stepper("单次最长停留：\(maxStayDays) 天", value: $maxStayDays, in: 7...365, step: 15)
                    DatePicker("签发日期", selection: $issueDate, displayedComponents: .date)
                    DatePicker("到期日期", selection: $expiryDate, displayedComponents: .date)
                    TextField("备注（可选）", text: $notes)
                }
            }
            .navigationTitle(existing == nil ? "添加签证" : "编辑签证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let record = VisaRecord(
                            id: existing?.id ?? UUID(),
                            countryCode: countryCode,
                            countryName: countryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? countryCode,
                            visaType: visaType.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "旅游签",
                            visaNumber: visaNumber,
                            issuingPost: issuingPost,
                            entries: entries,
                            maxStayDays: maxStayDays,
                            issueDate: issueDate,
                            expiryDate: expiryDate,
                            notes: notes
                        )
                        visaStore.upsert(record)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                VisaScannerSheet { parsed in
                    countryCode = parsed.countryCode
                    countryName = parsed.countryName
                    if !parsed.visaNumber.isEmpty { visaNumber = parsed.visaNumber }
                    if let exp = parsed.expiryDate { expiryDate = exp }
                }
            }
        }
    }
}
