import SwiftUI
import UIKit
import CoreLocation

// MARK: - Fog of World (世界迷雾) Style 4-Bar GPS Signal Badge + Floating Popover

struct GPSSignalBadge: View {
    let location: CLLocation?
    var showAccuracyText: Bool = false

    @State private var showPopover = false

    private var accuracy: Double? {
        guard let acc = location?.horizontalAccuracy, acc > 0 else { return nil }
        return acc
    }

    private var level: Int {
        guard let acc = accuracy else { return 0 }
        if acc <= 15 { return 4 }
        if acc <= 35 { return 3 }
        if acc <= 80 { return 2 }
        return 1
    }

    private var barColor: Color {
        switch level {
        case 4: return Color(red: 0.30, green: 0.85, blue: 0.24) // 世界迷雾亮绿
        case 3: return Color(red: 0.56, green: 0.82, blue: 0.20)
        case 2: return .orange
        case 1: return .red
        default: return .secondary
        }
    }

    private var statusTitle: String {
        switch level {
        case 4: return "信号极佳"
        case 3: return "信号良好"
        case 2: return "信号一般"
        case 1: return "信号较弱"
        default: return "等待定位"
        }
    }

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            showPopover = true
        } label: {
            HStack(spacing: 5) {
                HStack(alignment: .bottom, spacing: 2.2) {
                    ForEach(1...4, id: \.self) { idx in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(idx <= level ? barColor : Color.secondary.opacity(0.22))
                            .frame(width: 3.4, height: CGFloat(4 + idx * 3))
                    }
                }
                if showAccuracyText {
                    if let acc = accuracy {
                        Text("\(statusTitle) · \(Int(acc.rounded())) 米")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    } else {
                        Text(statusTitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            AlwaysPopoverAnchor(isPresented: $showPopover) {
                GPSSignalPopoverContent(
                    location: location,
                    level: level,
                    barColor: barColor,
                    statusTitle: statusTitle
                )
            }
        )
        .accessibilityLabel("定位信号 \(statusTitle)")
    }
}

private struct GPSSignalPopoverContent: View {
    let location: CLLocation?
    let level: Int
    let barColor: Color
    let statusTitle: String

    @State private var showHelp = false
    @State private var copied = false

    private var accuracyMetersText: String {
        guard let acc = location?.horizontalAccuracy, acc > 0 else { return "--" }
        return "\(Int(acc.rounded()))"
    }

    private var coordText: String {
        guard let loc = location else { return "暂无坐标" }
        return String(format: "%.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude)
    }

    private var timeText: String {
        guard let ts = location?.timestamp else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: ts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                // Left column: 精度 / 大数字 / 米
                VStack(spacing: 3) {
                    Text("精度")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                    Text(accuracyMetersText)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("米")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 52)

                Divider()
                    .frame(height: 68)

                // Right column: 信号极佳标签 + ? + 坐标 + 时间
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(statusTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(barColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        Spacer(minLength: 8)
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showHelp.toggle()
                            }
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.title3)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Button {
                            guard location != nil else { return }
                            UIPasteboard.general.string = coordText
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation { copied = true }
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                await MainActor.run { withAnimation { copied = false } }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "location.north.fill")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                Text(copied ? "已复制坐标" : coordText)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(copied ? .green : .primary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill")
                                .font(.caption)
                                .foregroundColor(.primary)
                            Text(timeText)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            if showHelp {
                Text("精度表示 GPS 水平误差半径（米）。≤15 米为极佳，≤35 米为良好，≤80 米为一般；室内或省电模式下数值可能偏大。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 292)
    }
}

/// Presents a true floating popover bubble (with arrow) on iPhone on iOS 16+.
private struct AlwaysPopoverAnchor<PopoverContent: View>: UIViewRepresentable {
    @Binding var isPresented: Bool
    let content: () -> PopoverContent

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        if isPresented {
            if context.coordinator.presentedVC == nil {
                guard let presenter = uiView.nearestViewController else { return }
                let host = UIHostingController(rootView: content())
                host.modalPresentationStyle = .popover
                host.view.backgroundColor = .clear
                let targetSize = host.sizeThatFits(in: CGSize(width: 300, height: 220))
                host.preferredContentSize = targetSize

                if let pop = host.popoverPresentationController {
                    pop.sourceView = uiView
                    pop.sourceRect = uiView.bounds
                    pop.permittedArrowDirections = [.up, .down]
                    pop.delegate = context.coordinator
                }
                context.coordinator.presentedVC = host
                presenter.present(host, animated: true)
            } else if let host = context.coordinator.presentedVC {
                host.rootView = content()
                host.preferredContentSize = host.sizeThatFits(in: CGSize(width: 300, height: 220))
            }
        } else if let host = context.coordinator.presentedVC {
            context.coordinator.presentedVC = nil
            host.dismiss(animated: true)
        }
    }

    final class Coordinator: NSObject, UIPopoverPresentationControllerDelegate {
        var parent: AlwaysPopoverAnchor
        weak var presentedVC: UIHostingController<PopoverContent>?

        init(_ parent: AlwaysPopoverAnchor) {
            self.parent = parent
        }

        func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
            .none
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            presentedVC = nil
            parent.isPresented = false
        }
    }
}

private extension UIView {
    var nearestViewController: UIViewController? {
        var next: UIResponder? = self
        while let current = next {
            if let vc = current as? UIViewController { return vc }
            next = current.next
        }
        return nil
    }
}

// MARK: - On This Day Memory Card with Local Photo Thumbnail

struct OnThisDayMemoryCard: View {
    let memory: MemoriesEngine.OnThisDayMemory
    @State private var photoItem: PhotoPreviewItem?

    var body: some View {
        HStack(spacing: 11) {
            if let item = photoItem {
                Image(uiImage: item.thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onTapGesture {
                        PhotoLightboxPresenter.present(items: [item])
                    }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("\(memory.year) 年（\(memory.yearsAgo) 年前）")
                    .font(.caption2.bold())
                    .foregroundColor(.orange)
                Text(memory.stay.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let sub = memory.stay.subtitle {
                    Text(sub)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 170, maxWidth: 230, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task(id: memory.id) {
            photoItem = await StintPhotoFetcher.shared.dayPhotoItem(
                around: memory.stay.arrival,
                caption: "\(memory.year)年 · \(memory.stay.displayName)"
            )
        }
    }
}

// MARK: - MustSee Place Thumbnail (Strict Uniform Square + Custom Cover + Tap to Zoom)

struct MustSeePlaceThumbnail: View {
    let place: MustSeePlace
    let litDate: Date?
    @ObservedObject private var userStore = MustSeeUserStore.shared
    @State private var photoItem: PhotoPreviewItem?

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            Group {
                if let item = photoItem {
                    Image(uiImage: item.thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: side, height: side)
                        .clipped()
                        .onTapGesture {
                            PhotoLightboxPresenter.present(items: [item])
                        }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                litDate != nil
                                ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.78, blue: 0.35), .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                                : AnyShapeStyle(Color.secondary.opacity(0.12))
                            )
                        Image(systemName: place.kind.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(litDate != nil ? .white : .secondary)
                    }
                    .frame(width: side, height: side)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: "\(place.id)-\(litDate?.timeIntervalSince1970 ?? 0)-\(userStore.coverRevision)") {
            if let customImg = userStore.customCoverImage(for: place.id) {
                let caption = litDate.map { "\(place.name) · \(Formatters.dayTitle($0))" } ?? place.name
                photoItem = PhotoPreviewItem(id: "custom-cover-\(place.id)-\(userStore.coverRevision)", assetID: nil, thumbnail: customImg, caption: caption)
                return
            }
            guard let date = litDate else { photoItem = nil; return }
            photoItem = await StintPhotoFetcher.shared.dayPhotoItem(
                around: date,
                caption: "\(place.name) · \(Formatters.dayTitle(date))"
            )
        }
    }
}

// MARK: - Passport Recognized Data Editor Sheet (Border Crossings + Countries + Cities)

struct PassportDataEditorSheet: View {
    @EnvironmentObject private var store: DataStore
    @ObservedObject private var borderOverrides = BorderStampOverrideStore.shared
    @Environment(\.dismiss) private var dismiss

    enum Tab: Int, Hashable { case borders = 0, countries = 1, cities = 2 }

    @State private var tab: Tab = .borders
    @State private var searchText = ""
    @State private var borderStamps: [PassportStamp] = []
    @State private var countryGroups: [CountryGroup] = []
    @State private var cityGroups: [CityGroup] = []
    @State private var isLoading = true

    @State private var editingBorder: BorderStampRecord?
    @State private var showAddBorder = false
    @State private var renamingCity: CityGroup?
    @State private var newCityName = ""
    @State private var confirmDeleteTarget: DeleteTarget?

    struct CountryGroup: Identifiable, Sendable {
        let id: String // code
        let name: String
        let flag: String
        let stayCount: Int
        let stayIDs: Set<UUID>
    }

    struct CityGroup: Identifiable, Sendable {
        let id: String
        let city: String
        let countryCode: String?
        let stayCount: Int
        let stayIDs: Set<UUID>
    }

    struct DeleteTarget: Identifiable {
        let id = UUID()
        let title: String
        let stayIDs: Set<UUID>
    }

    private var filteredCities: [CityGroup] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return cityGroups }
        return cityGroups.filter { $0.city.localizedCaseInsensitiveContains(q) }
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("编辑类别", selection: $tab) {
                    Text("出入境 (\(borderStamps.count))").tag(Tab.borders)
                    Text("国家 (\(countryGroups.count))").tag(Tab.countries)
                    Text("城市 (\(cityGroups.count))").tag(Tab.cities)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .onChange(of: tab) { _ in
                    UISelectionFeedbackGenerator().selectionChanged()
                }

                if isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("正在读取识别数据…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if tab == .borders {
                            bordersSection
                        } else if tab == .countries {
                            countriesSection
                        } else {
                            citiesSection
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("编辑护照数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if tab == .borders {
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            showAddBorder = true
                        } label: {
                            Label("添加", systemImage: "plus")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        UISelectionFeedbackGenerator().selectionChanged()
                        dismiss()
                    }
                }
            }
            .task(id: "\(store.stays.count)-\(borderOverrides.revision)") {
                await reloadData()
            }
            .sheet(item: $editingBorder) { record in
                BorderStampEditForm(
                    initial: record,
                    isNew: false,
                    visitedCountryCodes: countryGroups.map(\.id)
                ) { saved in
                    borderOverrides.saveStamp(saved)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
            .sheet(isPresented: $showAddBorder) {
                let defaultCode = countryGroups.first(where: { $0.id != "CN" })?.id ?? "JP"
                BorderStampEditForm(
                    initial: BorderStampRecord(
                        id: "manual.\(UUID().uuidString)",
                        isEntry: true,
                        countryCode: defaultCode,
                        date: Date(),
                        port: "",
                        byAir: true,
                        days: 1
                    ),
                    isNew: true,
                    visitedCountryCodes: countryGroups.map(\.id)
                ) { saved in
                    borderOverrides.saveStamp(saved)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
            .alert("批量修改城市名称", isPresented: Binding(get: { renamingCity != nil }, set: { if !$0 { renamingCity = nil } })) {
                TextField("新的城市名", text: $newCityName)
                Button("取消", role: .cancel) { renamingCity = nil }
                Button("保存") {
                    if let target = renamingCity {
                        let cleaned = newCityName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty && cleaned != target.city {
                            let updated = store.stays.filter { target.stayIDs.contains($0.id) }.map { stay -> Stay in
                                var copy = stay
                                copy.city = cleaned
                                return copy
                            }
                            store.updateStaysBatch(updated)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    }
                    renamingCity = nil
                }
            } message: {
                Text("将「\(renamingCity?.city ?? "")」的 \(renamingCity?.stayCount ?? 0) 条记录统一修改为新名称（与已有城市同名则自动合并）。")
            }
            .alert(
                "确定删除吗？",
                isPresented: Binding(get: { confirmDeleteTarget != nil }, set: { if !$0 { confirmDeleteTarget = nil } }),
                presenting: confirmDeleteTarget
            ) { target in
                Button("确认删除", role: .destructive) {
                    store.deleteStays(ids: target.stayIDs)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    confirmDeleteTarget = nil
                }
                Button("取消", role: .cancel) {
                    confirmDeleteTarget = nil
                }
            } message: { target in
                Text("将删除\(target.title)，且照片记录不会再次自动导入。此操作不可撤销。")
            }
        }
    }

    // MARK: - Section 1: 出入境章编辑

    @ViewBuilder
    private var bordersSection: some View {
        Section {
            if borderStamps.isEmpty {
                VStack(spacing: 8) {
                    Text("暂无出入境章记录")
                        .font(.subheadline.weight(.semibold))
                    Text("点击左上角「+」可手动补录入境或出境章。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ForEach(borderStamps) { stamp in
                    let code = stamp.countryCode ?? ""
                    let isEntry = stamp.kind == .entry
                    let isManual = borderOverrides.isManual(id: stamp.id)
                    let isEdited = borderOverrides.isEditedAuto(id: stamp.id)

                    HStack(spacing: 12) {
                        Text(CountryText.flag(for: code))
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(CountryText.localizedName(code: code))
                                    .font(.body.weight(.semibold))
                                Text(isEntry ? "入境" : "出境")
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(isEntry ? Color.blue : Color.orange, in: Capsule())
                                if isManual {
                                    Text("手动")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                } else if isEdited {
                                    Text("已改")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            HStack(spacing: 6) {
                                Text(Self.dateFmt.string(from: stamp.date))
                                if let port = stamp.port, !port.isEmpty {
                                    Text("· \(port)")
                                }
                                Text(stamp.byAir ? "✈️" : "🚗")
                                if !isEntry && stamp.days > 0 {
                                    Text("· \(stamp.days)天")
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            editingBorder = BorderStampRecord.from(stamp)
                        } label: {
                            Image(systemName: "pencil")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.accentColor)
                                .padding(7)
                                .background(Color.accentColor.opacity(0.12), in: Circle())
                        }
                        .buttonStyle(.borderless)

                        Button(role: .destructive) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            borderOverrides.deleteStamp(id: stamp.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.red)
                                .padding(7)
                                .background(Color.red.opacity(0.12), in: Circle())
                        }
                        .buttonStyle(.borderless)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            borderOverrides.deleteStamp(id: stamp.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        } footer: {
            Text("点击铅笔可修改国家、出入境方向、日期、口岸与交通方式；点击垃圾桶或左滑可直接删除误识别的出入境章，护照本会实时更新。")
        }

        if borderOverrides.hasAnyOverrides {
            Section {
                Button("恢复所有被隐藏/修改的自动识别记录", role: .destructive) {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    borderOverrides.resetAutoOverrides()
                }
            }
        }
    }

    // MARK: - Section 2: 国家和地区

    @ViewBuilder
    private var countriesSection: some View {
        Section {
            ForEach(countryGroups) { group in
                HStack(spacing: 12) {
                    Text(group.flag).font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name).font(.body.weight(.semibold))
                        Text("\(group.stayCount) 条停留记录").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        confirmDeleteTarget = DeleteTarget(
                            title: "「\(group.name)」的全部 \(group.stayCount) 条记录",
                            stayIDs: group.stayIDs
                        )
                    } label: {
                        Text("删除")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.borderless)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        confirmDeleteTarget = DeleteTarget(
                            title: "「\(group.name)」的全部 \(group.stayCount) 条记录",
                            stayIDs: group.stayIDs
                        )
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        } footer: {
            Text("如果某个国家是国境线漂移或误识别产生的，可以直接在此删除该国家的全部停留记录。")
        }
    }

    // MARK: - Section 3: 城市

    @ViewBuilder
    private var citiesSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索城市名称…", text: $searchText)
                    .textInputAutocapitalization(.never)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }

        Section {
            ForEach(filteredCities) { group in
                HStack(spacing: 12) {
                    Text(group.countryCode.map { CountryText.flag(for: $0) } ?? "📍")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.city).font(.body.weight(.semibold))
                        Text("\(group.stayCount) 条停留记录").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        renamingCity = group
                        newCityName = group.city
                    } label: {
                        Text("改名")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.borderless)

                    Button(role: .destructive) {
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        confirmDeleteTarget = DeleteTarget(
                            title: "「\(group.city)」的全部 \(group.stayCount) 条记录",
                            stayIDs: group.stayIDs
                        )
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.red)
                            .padding(7)
                            .background(Color.red.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.borderless)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        confirmDeleteTarget = DeleteTarget(
                            title: "「\(group.city)」的全部 \(group.stayCount) 条记录",
                            stayIDs: group.stayIDs
                        )
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        } footer: {
            Text("改名可将一个城市的全部记录批量重命名或合并到另一个城市名下。")
        }
    }

    // MARK: - Async Data Loader (Zero Main-Thread Blocking on Open/Dismiss)

    private func reloadData() async {
        let staysSnap = store.stays
        let result = await Task.detached(priority: .userInitiated) { () -> ([PassportStamp], [CountryGroup], [CityGroup]) in
            let summary = PassportEngine.build(stays: staysSnap, chunks: [])
            let stamps = summary.passportStamps.reversed().map { $0 }

            let byCountry = Dictionary(grouping: staysSnap.filter { $0.countryCode != nil }) { $0.countryCode! }
            let countries = byCountry.map { code, list in
                CountryGroup(
                    id: code,
                    name: CountryText.localizedName(code: code),
                    flag: CountryText.flag(for: code),
                    stayCount: list.count,
                    stayIDs: Set(list.map(\.id))
                )
            }.sorted { $0.stayCount > $1.stayCount }

            let byCity = Dictionary(grouping: staysSnap.filter { ($0.city?.isEmpty == false) }) {
                "\($0.countryCode ?? "")|\($0.city!)"
            }
            let cities = byCity.map { key, items -> CityGroup in
                let first = items.first!
                return CityGroup(
                    id: key,
                    city: first.city!,
                    countryCode: first.countryCode,
                    stayCount: items.count,
                    stayIDs: Set(items.map(\.id))
                )
            }.sorted { $0.stayCount > $1.stayCount }

            return (stamps, countries, cities)
        }.value

        borderStamps = result.0
        countryGroups = result.1
        cityGroups = result.2
        isLoading = false
    }
}

// MARK: - Add / Edit Single Entry/Exit Border Stamp Form

private struct BorderStampEditForm: View {
    @Environment(\.dismiss) private var dismiss

    let isNew: Bool
    let visitedCountryCodes: [String]
    let onSave: (BorderStampRecord) -> Void

    @State private var id: String
    @State private var isEntry: Bool
    @State private var countryCode: String
    @State private var date: Date
    @State private var port: String
    @State private var byAir: Bool
    @State private var days: Int

    private static let commonCodes: [String] = [
        "CN", "HK", "MO", "TW",
        "JP", "KR", "SG", "TH", "MY", "VN", "ID", "PH", "KH",
        "CA", "US", "AU", "NZ",
        "GB", "FR", "DE", "IT", "ES", "CH", "NL", "AT", "CZ", "GR", "IS", "NO", "SE", "FI", "DK", "RU", "TR", "AE", "EG"
    ]

    private var pickerCodes: [String] {
        var list: [String] = []
        var seen = Set<String>()
        for c in ([countryCode] + visitedCountryCodes + Self.commonCodes) where !c.isEmpty {
            let up = c.uppercased()
            if seen.insert(up).inserted { list.append(up) }
        }
        return list
    }

    init(initial: BorderStampRecord, isNew: Bool, visitedCountryCodes: [String], onSave: @escaping (BorderStampRecord) -> Void) {
        self.isNew = isNew
        self.visitedCountryCodes = visitedCountryCodes
        self.onSave = onSave
        _id = State(initialValue: initial.id)
        _isEntry = State(initialValue: initial.isEntry)
        _countryCode = State(initialValue: initial.countryCode)
        _date = State(initialValue: initial.date)
        _port = State(initialValue: initial.port)
        _byAir = State(initialValue: initial.byAir)
        _days = State(initialValue: max(1, initial.days))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("出入境类型") {
                    Picker("类型", selection: $isEntry) {
                        Text("入境章 (ENTRY)").tag(true)
                        Text("出境章 (EXIT)").tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                Section("国家与口岸") {
                    Picker("国家 / 地区", selection: $countryCode) {
                        ForEach(pickerCodes, id: \.self) { code in
                            Text("\(CountryText.flag(for: code)) \(CountryText.localizedName(code: code)) (\(code))")
                                .tag(code)
                        }
                    }

                    DatePicker("日期", selection: $date, displayedComponents: .date)

                    TextField("口岸或城市（如：多伦多、羽田机场）", text: $port)

                    Toggle("航空出入境（显示飞机图标）", isOn: $byAir)

                    if !isEntry {
                        Stepper("本次停留天数：\(days) 天", value: $days, in: 1...3650)
                    }
                }
            }
            .navigationTitle(isNew ? "添加出入境记录" : "编辑出入境记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let record = BorderStampRecord(
                            id: id,
                            isEntry: isEntry,
                            countryCode: countryCode,
                            date: date,
                            port: port.trimmingCharacters(in: .whitespacesAndNewlines),
                            byAir: byAir,
                            days: isEntry ? 0 : days
                        )
                        onSave(record)
                        dismiss()
                    }
                }
            }
        }
    }
}
