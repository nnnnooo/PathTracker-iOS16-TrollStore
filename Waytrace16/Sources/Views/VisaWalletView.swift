import SwiftUI
import PhotosUI
import UIKit

/// Original PathTracker (漫迹) Visa Wallet UI ported 1:1 to iOS 16:
/// - Empty state with fanned sample cards + Scan / Photo / Manual buttons
/// - Wallet-style overlapping card stack; tap to lift card to top with circular countdown ring & bottom pile
/// - Full-featured Add/Edit sheet with live-updating VisaCard preview & Passport/Visa/eVisa segmented switcher
struct VisaWalletView: View {
    @EnvironmentObject private var store: DataStore
    @ObservedObject private var visaStore = VisaStore.shared

    @State private var editorRequest: VisaEditorRequest?
    @State private var showScanner = false
    @State private var pickingPhoto: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var isReadingPhoto = false
    @State private var selectedID: UUID?
    @Namespace private var cardNamespace

    private static let spring = Animation.spring(response: 0.55, dampingFraction: 0.82)
    private static let stripHeight: CGFloat = 38
    private static let pileStep: CGFloat = 9

    private var sortedDocs: [VisaRecord] { visaStore.sorted }
    private var chosen: VisaRecord? { selectedID.flatMap { id in visaStore.visas.first { $0.id == id } } }

    private var pileHeight: CGFloat {
        let count = min(5, max(visaStore.visas.count - 1, 0))
        return count == 0 ? 0 : 34 + CGFloat(count) * Self.pileStep
    }

    var body: some View {
        let cardWidth = max(280, UIScreen.main.bounds.width - 32)
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Color.clear.frame(height: 0).id("walletTop")

                    if visaStore.visas.isEmpty {
                        WalletEmptyState(
                            scan: { showScanner = true },
                            choosePhoto: { showPhotoPicker = true },
                            addByHand: { editorRequest = VisaEditorRequest(document: Self.blank(.visa)) }
                        )
                    } else if let chosen {
                        cardView(chosen, scrollProxy: scrollProxy)
                            .zIndex(10)

                        VisaDetailCardSection(
                            document: chosen,
                            stays: store.stays,
                            onEdit: { editorRequest = VisaEditorRequest(document: chosen) },
                            onDelete: {
                                withAnimation(Self.spring) { selectedID = nil }
                                visaStore.delete(id: chosen.id)
                            }
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))

                        Color.clear.frame(height: pileHeight)
                    } else {
                        WalletSummaryHeader(documents: sortedDocs)
                            .transition(.opacity)

                        cardStack(width: cardWidth, scrollProxy: scrollProxy)

                        if let schengen = sortedDocs.first(where: { $0.isSchengen && !$0.isExpired }) {
                            SchengenQuotaCard(visa: schengen, stays: store.stays)
                                .transition(.opacity)
                        }

                        Text("签证信息仅保存在本机。识别在手机上完成，画面和照片不会保存或上传。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .bottom) {
                if selectedID != nil {
                    bottomPile(width: cardWidth)
                }
            }
        }
        .navigationTitle(chosen.map { $0.kind == .passport ? "护照" : $0.countryName } ?? "签证夹")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let chosen {
                    Button("编辑") {
                        editorRequest = VisaEditorRequest(document: chosen)
                    }
                } else {
                    Menu {
                        Button { showScanner = true } label: {
                            Label("扫描签证", systemImage: "viewfinder")
                        }
                        Button { showPhotoPicker = true } label: {
                            Label("从照片中识别", systemImage: "photo.on.rectangle")
                        }
                        Divider()
                        Button { editorRequest = VisaEditorRequest(document: Self.blank(.visa)) } label: {
                            Label("手动添加签证", systemImage: "square.and.pencil")
                        }
                        Button { editorRequest = VisaEditorRequest(document: Self.blank(.eVisa)) } label: {
                            Label("手动添加电子签", systemImage: "qrcode")
                        }
                        Button {
                            editorRequest = VisaEditorRequest(document: visaStore.passport ?? Self.blank(.passport))
                        } label: {
                            Label(visaStore.passport == nil ? "添加护照" : "更新护照", systemImage: "person.text.rectangle")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                }
            }
        }
        .sheet(item: $editorRequest) { req in
            VisaEditorSheet(document: req.document, parsedNote: req.parsedNote)
        }
        .sheet(isPresented: $showScanner) {
            VisaScannerSheet { parsed in
                openEditor(from: parsed)
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickingPhoto, matching: .images)
        .onChange(of: pickingPhoto) { newItem in
            guard let newItem else { return }
            pickingPhoto = nil
            Task {
                isReadingPhoto = true
                defer { isReadingPhoto = false }
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let parsed = await MRZParser.recognize(image: image) {
                    await MainActor.run {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        openEditor(from: parsed)
                    }
                } else {
                    await MainActor.run {
                        let blank = Self.blank(.visa)
                        editorRequest = VisaEditorRequest(
                            document: blank,
                            parsedNote: VisaParsedNote(verified: false, hasExpiry: false)
                        )
                    }
                }
            }
        }
        .overlay {
            if isReadingPhoto {
                VStack(spacing: 14) {
                    ProgressView().scaleEffect(1.2)
                    Text("正在识别签证…").font(.subheadline.weight(.medium))
                }
                .padding(26)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    private func cardView(_ document: VisaRecord, scrollProxy: ScrollViewProxy) -> some View {
        let isSelected = selectedID == document.id
        return VisaCard(document: document, showSheen: isSelected)
            .matchedGeometryEffect(id: document.id, in: cardNamespace)
            .shadow(color: .black.opacity(0.08), radius: 1.5, y: -1)
            .shadow(color: .black.opacity(0.14), radius: 14, y: isSelected ? 10 : -2)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(Self.spring) {
                    selectedID = isSelected ? nil : document.id
                    scrollProxy.scrollTo("walletTop", anchor: .top)
                }
            }
    }

    private func cardStack(width: CGFloat, scrollProxy: ScrollViewProxy) -> some View {
        let overlap = max(0, width / VisaCard.aspect - Self.stripHeight)
        return VStack(spacing: -overlap) {
            ForEach(Array(sortedDocs.enumerated()), id: \.element.id) { index, document in
                cardView(document, scrollProxy: scrollProxy)
                    .zIndex(Double(index))
            }
        }
    }

    private func bottomPile(width: CGFloat) -> some View {
        let others = sortedDocs.filter { $0.id != selectedID }
        let shown = Array(others.prefix(5))
        return Group {
            if !shown.isEmpty {
                ZStack(alignment: .top) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, document in
                        VisaCard(document: document)
                            .frame(width: width, height: width / VisaCard.aspect)
                            .matchedGeometryEffect(id: document.id, in: cardNamespace)
                            .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
                            .scaleEffect(1 - CGFloat(shown.count - 1 - index) * 0.035, anchor: .top)
                            .offset(y: CGFloat(index) * Self.pileStep)
                            .zIndex(Double(index))
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: width, height: pileHeight, alignment: .top)
                .padding(.horizontal, 16)
                .background(alignment: .top) {
                    LinearGradient(colors: [.clear, Color(.systemGroupedBackground).opacity(0.92)], startPoint: .top, endPoint: .bottom)
                        .frame(height: pileHeight + 60)
                        .offset(y: -40)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(Self.spring) { selectedID = nil }
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    private func openEditor(from parsed: MRZParser.Parsed) {
        var doc = Self.blank(parsed.isPassport ? .passport : .visa)
        doc.countryCode = parsed.countryCode
        doc.countryName = parsed.countryName
        if !parsed.visaNumber.isEmpty { doc.visaNumber = parsed.visaNumber }
        if !parsed.holder.isEmpty { doc.holder = parsed.holder }
        if let exp = parsed.expiryDate { doc.expiryDate = exp }
        if doc.countryCode == "AU" || doc.countryCode == "NZ" { doc.kind = .eVisa }
        if parsed.isPassport, let existing = visaStore.passport { doc.id = existing.id }
        editorRequest = VisaEditorRequest(
            document: doc,
            parsedNote: VisaParsedNote(verified: parsed.verified, hasExpiry: parsed.expiryDate != nil)
        )
    }

    static func blank(_ kind: VisaDocumentKind) -> VisaRecord {
        let code = kind == .passport ? "CN" : "US"
        let years = kind == .passport ? 10 : 1
        return VisaRecord(
            kind: kind,
            countryCode: code,
            countryName: VisaCatalog.localizedName(for: code),
            visaType: "",
            entries: .multiple,
            stayDays: nil,
            issuedDate: nil,
            expiryDate: Calendar.current.date(byAdding: .year, value: years, to: Date()) ?? Date()
        )
    }
}

private struct VisaParsedNote {
    let verified: Bool
    let hasExpiry: Bool
}

private struct VisaEditorRequest: Identifiable {
    let id = UUID()
    var document: VisaRecord
    var parsedNote: VisaParsedNote? = nil
}

// MARK: - Summary Header

private struct WalletSummaryHeader: View {
    let documents: [VisaRecord]

    var body: some View {
        let validVisas = documents.filter { !$0.isExpired && $0.kind != .passport }
        let next = documents.filter { !$0.isExpired }.min { $0.expiryDate < $1.expiryDate }
        VStack(alignment: .leading, spacing: 4) {
            Text("\(validVisas.count) 张有效签证")
                .font(.title2.weight(.bold))
            if let next {
                HStack(spacing: 6) {
                    Circle()
                        .fill(next.isExpiringSoon ? Color.orange : Color.green)
                        .frame(width: 7, height: 7)
                    Text("\(next.kind == .passport ? "护照" : next.countryName) \(next.remainingDays) 天后到期")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
}

// MARK: - Empty State (1:1 Original Fanned 3 Cards + Scan / Photo / Manual)

private struct WalletEmptyState: View {
    let scan: () -> Void
    let choosePhoto: () -> Void
    let addByHand: () -> Void
    @State private var fanned = false

    private static let samples: [VisaRecord] = [
        VisaRecord(kind: .visa, countryCode: "JP", countryName: "日本", visaType: "短期滞在",
                   entries: .multiple, stayDays: 30, expiryDate: Date().addingTimeInterval(86_400 * 400)),
        VisaRecord(kind: .visa, countryCode: VisaCatalog.schengenCode, countryName: "申根区", visaType: "C",
                   entries: .multiple, stayDays: 90, expiryDate: Date().addingTimeInterval(86_400 * 700)),
        VisaRecord(kind: .visa, countryCode: "US", countryName: "美国", visaType: "B1/B2",
                   entries: .multiple, stayDays: nil, expiryDate: Date().addingTimeInterval(86_400 * 2_900))
    ]

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                ForEach(Array(Self.samples.enumerated()), id: \.offset) { index, sample in
                    VisaCard(document: sample)
                        .frame(width: 250)
                        .shadow(color: .black.opacity(0.14), radius: 12, y: 8)
                        .rotationEffect(.degrees(fanned ? Double(index - 1) * 7 : 0), anchor: .bottom)
                        .offset(x: fanned ? CGFloat(index - 1) * 26 : 0, y: fanned ? CGFloat(abs(index - 1)) * 10 : 0)
                }
            }
            .frame(height: 230)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.2)) {
                    fanned = true
                }
            }

            VStack(spacing: 8) {
                Text("把签证放进来")
                    .font(.title2.weight(.bold))
                Text("用相机对准护照上的签证页，就能自动读出国家、类型和有效期。哪张快到期、还能停留多久，一眼就知道，到期前也会提醒你。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)

            VStack(spacing: 12) {
                Button(action: scan) {
                    Label("扫描签证", systemImage: "viewfinder")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.blue, in: Capsule())
                        .shadow(color: Color.blue.opacity(0.26), radius: 8, y: 4)
                }
                .buttonStyle(PressableStyle())

                HStack(spacing: 10) {
                    Button(action: choosePhoto) {
                        Label("从照片识别", systemImage: "photo.on.rectangle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.8))
                    }
                    .buttonStyle(PressableStyle())

                    Button(action: addByHand) {
                        Label("手动填写", systemImage: "square.and.pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.8))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .padding(.top, 24)
    }
}

// MARK: - Schengen 90/180 Card

private struct SchengenQuotaCard: View {
    let visa: VisaRecord
    let stays: [Stay]
    var plain: Bool = false

    var body: some View {
        let used = VisaCatalog.schengenUsedDays(stays: stays)
        let limit = min(visa.stayDays ?? 90, 90)
        let remaining = max(0, limit - used)

        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: CGFloat(min(used, limit)) / CGFloat(max(limit, 1)))
                    .stroke(remaining < 15 ? Color.orange : Color.blue, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(remaining)").font(.title2.weight(.bold)).monospacedDigit()
                    Text("天可用").font(.caption2).foregroundColor(.secondary)
                }
            }
            .frame(width: 86, height: 86)

            VStack(alignment: .leading, spacing: 5) {
                Label("申根 90/180 天", systemImage: "eurosign.circle.fill")
                    .font(.headline)
                    .foregroundColor(.blue)
                Text("最近 180 天里，你在申根区待了 \(used) 天，还能再待 \(remaining) 天。")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(plain ? 0 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            plain ? Color.clear : Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }
}

// MARK: - Selected Card Detail Section (1:1 Original Back-of-Pass Sheet)

private struct VisaDetailCardSection: View {
    let document: VisaRecord
    let stays: [Stay]
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var confirmingDelete = false
    @State private var appeared = false

    private var tint: Color {
        document.isExpired ? .red : (document.isExpiringSoon ? .orange : .green)
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow.padding(18)

                if document.kind == .passport {
                    hairline
                    passportRuleRow.padding(18)
                }

                if document.isSchengen && !document.isExpired {
                    hairline
                    SchengenQuotaCard(visa: document, stays: stays, plain: true).padding(18)
                }

                if document.kind != .passport {
                    hairline
                    usageRow.padding(18)
                }

                hairline
                fieldsGrid.padding(18)
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            HStack(spacing: 12) {
                Button(action: onEdit) {
                    Label("编辑", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                }
                .buttonStyle(PressableStyle())

                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label("删除", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.85).delay(0.18)) {
                appeared = true
            }
        }
        .confirmationDialog(
            "删除这张\(document.kind == .passport ? "护照" : "签证")？",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive, action: onDelete)
            Button("取消", role: .cancel) {}
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: 0.5)
            .padding(.leading, 18)
    }

    private var headerRow: some View {
        let days = document.remainingDays
        let progress = document.validityProgress
        return HStack(spacing: 18) {
            ZStack {
                Circle().stroke(tint.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: appeared ? progress : 0)
                    .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: -2) {
                    Text("\(abs(days))")
                        .font(.system(size: abs(days) >= 1_000 ? 22 : 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(days >= 0 ? "天" : "天前")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 6) {
                Text(document.isExpired ? "已过期" : (document.isExpiringSoon ? "即将到期" : "有效"))
                    .font(.caption.weight(.bold))
                    .foregroundColor(tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.13), in: Capsule())

                Text("\(Self.zhLongDate(document.expiryDate)) 到期")
                    .font(.headline)

                if let issued = document.issuedDate {
                    Text("签发于 \(Self.zhLongDate(issued))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var passportRuleRow: some View {
        let short = document.remainingDays < 183
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: short ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundColor(short ? .orange : .blue)
                .font(.body)
                .padding(.top, 2)
            Text(short
                 ? "护照有效期已不足 6 个月。很多国家要求入境时护照还剩 6 个月以上，出发前记得先换发。"
                 : "很多国家要求入境时护照还剩 6 个月以上。到期前 6 个月，这里会提醒你。")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var usageRow: some View {
        let stats = VisaCatalog.usageStats(for: document, stays: stays)
        return HStack(spacing: 14) {
            Image(systemName: "airplane.arrival")
                .font(.body.weight(.semibold))
                .foregroundColor(.indigo)
                .frame(width: 38, height: 38)
                .background(Color.indigo.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("用这张签证去过").font(.caption).foregroundColor(.secondary)
                Text(stats.entries == 0 ? "还没有用过" : "\(stats.entries) 次入境 · 共 \(stats.days) 天")
                    .font(.headline)
                if document.entries != .multiple && stats.entries > 0 {
                    let allowed = document.entries == .single ? 1 : 2
                    Text(stats.entries >= allowed ? "入境次数已经用完" : "还能再入境 \(allowed - stats.entries) 次")
                        .font(.caption)
                        .foregroundColor(stats.entries >= allowed ? .orange : .secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var fieldsGrid: some View {
        var items: [(String, String)] = []
        if document.kind != .passport {
            items.append(("类型", document.visaType.isEmpty ? "—" : document.visaType))
            items.append(("入境次数", document.entries.rawValue))
            if let stay = document.stayDays {
                items.append(("每次停留", "\(stay) 天"))
            }
        }
        if !document.issuingPost.isEmpty { items.append(("签发地", document.issuingPost)) }
        if !document.holder.isEmpty { items.append(("持有人", document.holder)) }
        if let issued = document.issuedDate { items.append(("签发日期", Self.zhLongDate(issued))) }
        items.append(("到期日期", Self.zhLongDate(document.expiryDate)))

        return VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(
                columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.0).font(.caption).foregroundColor(.secondary)
                        Text(item.1).font(.body.weight(.medium)).lineLimit(2)
                    }
                }
            }

            if !document.visaNumber.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("号码").font(.caption).foregroundColor(.secondary)
                    Text(document.visaNumber)
                        .font(.body.weight(.medium).monospaced())
                        .textSelection(.enabled)
                }
            }

            if !document.notes.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("备注").font(.caption).foregroundColor(.secondary)
                    Text(document.notes).font(.body.weight(.medium))
                }
            }
        }
    }

    private static func zhLongDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: date)
    }
}

// MARK: - Add / Edit Sheet (1:1 Original Live-Preview Card + Segmented Kind + Clean Form)

private struct VisaEditorSheet: View {
    @ObservedObject private var visaStore = VisaStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var document: VisaRecord
    let parsedNote: VisaParsedNote?
    @State private var hasIssued: Bool
    @State private var hasStay: Bool

    init(document: VisaRecord, parsedNote: VisaParsedNote?) {
        _document = State(initialValue: document)
        self.parsedNote = parsedNote
        _hasIssued = State(initialValue: document.issuedDate != nil)
        _hasStay = State(initialValue: document.stayDays != nil)
    }

    private var preview: VisaRecord {
        var copy = document
        if !hasIssued { copy.issuedDate = nil }
        if !hasStay || copy.kind == .passport { copy.stayDays = nil }
        if copy.kind == .passport && copy.countryCode == VisaCatalog.schengenCode {
            copy.countryCode = "CN"
            copy.countryName = "中国"
        }
        return copy
    }

    private var isEditingExisting: Bool {
        visaStore.visas.contains { $0.id == document.id }
    }

    private var availableCountries: [(code: String, name: String)] {
        if document.kind == .passport {
            return VisaCatalog.presets.filter { $0.code != VisaCatalog.schengenCode }
        }
        return VisaCatalog.presets
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VisaCard(document: preview)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .animation(.easeInOut(duration: 0.25), value: preview)
                }

                if let note = parsedNote {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: note.verified ? "checkmark.seal.fill" : "text.viewfinder")
                                .foregroundColor(note.verified ? .green : .blue)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(note.hasExpiry ? "已从照片读出，请核对一遍。" : "没能读出到期日期，请手动填写。")
                                    .font(.subheadline.weight(.semibold))
                                Text(note.verified ? "到期日期来自底部机读码，已通过校验。" : "照片越清晰、越平整，识别越准。")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Picker("证件", selection: $document.kind) {
                        ForEach(VisaDocumentKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .onChange(of: document.kind) { newKind in
                        UISelectionFeedbackGenerator().selectionChanged()
                        if newKind == .passport && document.countryCode == VisaCatalog.schengenCode {
                            document.countryCode = "CN"
                            document.countryName = "中国"
                        }
                    }
                }

                Section {
                    Picker(document.kind == .passport ? "签发国" : "国家或地区", selection: $document.countryCode) {
                        ForEach(availableCountries, id: \.code) { item in
                            Text("\(item.code == VisaCatalog.schengenCode ? "🇪🇺" : CountryText.flag(for: item.code)) \(item.name)")
                                .tag(item.code)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .onChange(of: document.countryCode) { newCode in
                        document.countryName = VisaCatalog.localizedName(for: newCode)
                    }

                    if document.kind != .passport {
                        TextField("类型，比如 B1/B2、C、旅游", text: $document.visaType)

                        Picker("入境次数", selection: $document.entries) {
                            ForEach(VisaEntries.allCases) { e in
                                Text(e.rawValue).tag(e)
                            }
                        }

                        Toggle("限制每次停留天数", isOn: $hasStay.animation())
                        if hasStay {
                            Stepper(
                                value: Binding(
                                    get: { document.stayDays ?? 90 },
                                    set: { document.stayDays = $0 }
                                ),
                                in: 1...365
                            ) {
                                Text("每次停留 \(document.stayDays ?? 90) 天").monospacedDigit()
                            }
                        }
                    }
                }

                Section {
                    DatePicker("到期日期", selection: $document.expiryDate, displayedComponents: .date)
                    Toggle("填写签发日期", isOn: $hasIssued.animation())
                    if hasIssued {
                        DatePicker(
                            "签发日期",
                            selection: Binding(
                                get: { document.issuedDate ?? Date() },
                                set: { document.issuedDate = $0 }
                            ),
                            in: ...document.expiryDate,
                            displayedComponents: .date
                        )
                    }
                } footer: {
                    Text(document.kind == .passport
                         ? "到期前 6 个月、90 天、30 天和 7 天会各提醒你一次。"
                         : "到期前 90 天、30 天和 7 天会各提醒你一次。")
                }

                Section("可选") {
                    TextField(document.kind == .passport ? "护照号码" : "签证号码", text: $document.visaNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("持有人姓名", text: $document.holder)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    if document.kind != .passport {
                        TextField("签发地（如 SHANGHAI）", text: $document.issuingPost)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                    TextField("备注", text: $document.notes, axis: .vertical)
                }
            }
            .navigationTitle(isEditingExisting ? "编辑" : "添加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        var saved = preview
                        saved.visaType = saved.visaType.trimmingCharacters(in: .whitespacesAndNewlines)
                        saved.countryName = VisaCatalog.localizedName(for: saved.countryCode)
                        visaStore.upsert(saved)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
        }
    }
}

// MARK: - Passport Tab Shelf Card (1:1 Original Fanned Mini Visa Cards Entry)

struct VisaShelfCard: View {
    @ObservedObject private var visaStore = VisaStore.shared

    var body: some View {
        let sorted = visaStore.sorted
        NavigationLink {
            VisaWalletView()
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    if sorted.isEmpty {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                            .frame(width: 84, height: 54)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.title3.weight(.semibold))
                                    .foregroundColor(.secondary)
                            )
                    } else {
                        let previewDocs = Array(sorted.prefix(3))
                        ForEach(Array(previewDocs.enumerated().reversed()), id: \.element.id) { index, doc in
                            VisaCard(document: doc)
                                .frame(width: 76)
                                .shadow(color: .black.opacity(0.14), radius: 3, y: 2)
                                .rotationEffect(.degrees(Double(index) * -3.5), anchor: .bottomLeading)
                                .offset(x: CGFloat(index) * 3.0, y: CGFloat(index) * -2.2 + 4.0)
                        }
                    }
                }
                .frame(width: 94, height: 64)
                .clipped()

                VStack(alignment: .leading, spacing: 4) {
                    Text("签证夹")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(subtitle(sorted))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private func subtitle(_ sorted: [VisaRecord]) -> String {
        guard !sorted.isEmpty else { return "拍下护照上的签证，记住每张什么时候到期" }
        if let soon = sorted.first(where: \.isExpiringSoon) {
            return "\(soon.kind == .passport ? "护照" : soon.countryName) 还剩 \(soon.remainingDays) 天到期"
        }
        let valid = sorted.filter { !$0.isExpired && $0.kind != .passport }.count
        return "\(valid) 张有效签证"
    }
}
