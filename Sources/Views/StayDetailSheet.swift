import SwiftUI
import MapKit
import CoreLocation
import UIKit

/// 1:1 Original PathTracker (漫迹) Timeline Stay Detail & In-Place Edit Sheet (iOS 16 compatible).
struct StayDetailSheet: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var tagger: PlaceTagger
    @Environment(\.dismiss) private var dismiss

    let stay: Stay
    var showsDayLink: Bool = false

    @State private var isEditing = false
    @State private var name = ""
    @State private var kind: PlaceKind = .none
    @State private var noteText = ""
    @State private var showNoteComposer = false
    @State private var isPrivateZone = false
    @State private var confirmingDelete = false
    @State private var photos: [PhotoPreviewItem] = []
    @State private var hasLoadedInitialFields = false

    enum PlaceKind: String, CaseIterable, Identifiable {
        case none, home, school, work, sight, mall, restaurant
        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: return "自动识别"
            case .sight: return "景点"
            case .home: return "家"
            case .school: return "学校"
            case .work: return "公司"
            case .mall: return "商场"
            case .restaurant: return "餐厅"
            }
        }

        var defaultName: String {
            switch self {
            case .home: return "家"
            case .school: return "学校"
            case .work: return "公司"
            default: return ""
            }
        }

        var symbol: String {
            switch self {
            case .none: return "sparkle.magnifyingglass"
            case .sight: return "binoculars.fill"
            case .home: return "house.fill"
            case .school: return "graduationcap.fill"
            case .work: return "briefcase.fill"
            case .mall: return "bag.fill"
            case .restaurant: return "fork.knife"
            }
        }
    }

    private var liveStay: Stay {
        store.stays.first(where: { $0.id == stay.id }) ?? stay
    }

    var body: some View {
        let current = liveStay
        NavigationStack {
            Group {
                if isEditing {
                    Form {
                        Section {
                            StayPinMKMapView(stay: current)
                                .frame(height: 200)
                                .listRowInsets(EdgeInsets())
                        }
                        editNameSection(current)
                        momentFormSection(current)
                        timeSection(current)
                        locationSection(current)
                        privacySection
                        Section {
                            Button(role: .destructive) {
                                confirmingDelete = true
                            } label: {
                                Label("删除这条记录", systemImage: "trash")
                            }
                        }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            StayPinMKMapView(stay: current)
                                .frame(height: 210)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                            overviewCard(current)

                            if !photos.isEmpty {
                                takenHereCard
                            }

                            momentCard(current)
                            timeCard(current)
                            skyCard(current)
                            locationCard(current)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 28)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle(current.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isEditing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            loadFields(from: current)
                            isEditing = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            saveChanges(for: current)
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.blue, in: Circle())
                        }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("编辑") {
                            Haptics.selection()
                            loadFields(from: current)
                            isEditing = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showNoteComposer) {
                StayNoteComposerSheet(
                    placeName: current.displayName,
                    initialNote: current.note ?? ""
                ) { savedNote in
                    var updated = current
                    updated.note = savedNote.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    store.upsertStay(updated)
                    noteText = updated.note ?? ""
                    Haptics.success()
                }
            }
            .confirmationDialog("删除这条停留记录？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    store.deleteStay(id: current.id)
                    Haptics.success()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("轨迹会保留，只删除这个地点的停留记录。")
            }
            .onAppear {
                if !hasLoadedInitialFields {
                    hasLoadedInitialFields = true
                    loadFields(from: current)
                }
            }
            .task(id: current.id) {
                photos = await StintPhotoFetcher.shared.stayPhotoItems(for: current)
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Unified 20pt Card Sections (Matching TodayView & MoveDetailSheet)

    private func cardHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.medium))
            .foregroundColor(.secondary)
            .padding(.leading, 12)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundColor(.primary)
            Spacer(minLength: 12)
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func overviewCard(_ current: Stay) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(current.displayName)
                    .font(.title3.bold())
                    .lineLimit(2)
                let regionLine = [current.city, current.country].compactMap { $0?.nilIfEmpty }.joined(separator: " · ")
                if !regionLine.isEmpty {
                    Text(regionLine)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else if let sub = current.subtitle {
                    Text(sub)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Text(timeSummaryLine(for: current))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            if showsDayLink {
                Divider().padding(.leading, 16)
                NavigationLink {
                    DayDetailPage(date: current.arrival)
                } label: {
                    HStack {
                        Label("查看这一天的轨迹", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.body.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var takenHereCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardHeader("在这里拍的照片 \(photos.count)")
            StayDetailPhotoStrip(photos: photos)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func momentCard(_ current: Stay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            cardHeader("动态")
            VStack(spacing: 0) {
                if let note = current.note, !note.isEmpty {
                    Text(note)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    Divider().padding(.leading, 16)
                    Button {
                        showNoteComposer = true
                    } label: {
                        Label("编辑", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                    }
                } else {
                    Button {
                        showNoteComposer = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "square.and.pencil")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 48, height: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.accentColor.gradient)
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text("记录心情")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("写下这一刻的心情或备注")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func timeCard(_ current: Stay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            cardHeader("时间")
            VStack(spacing: 0) {
                detailRow("到达", Self.fullDateTime(current.arrival))
                Divider().padding(.leading, 16)
                detailRow("离开", current.departure.map(Self.fullDateTime) ?? "仍在这里")
                Divider().padding(.leading, 16)
                detailRow("停留", Formatters.duration(current.duration))
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func skyCard(_ current: Stay) -> some View {
        let sun = SkyAstronomy.sunInfo(date: current.arrival, lat: current.latitude, lon: current.longitude)
        let moon = SkyAstronomy.moonPhase(for: current.arrival)
        let end = current.departure ?? current.arrival
        let caughtSunset: String? = {
            guard let sunsetDate = sun.sunsetDate else { return nil }
            if current.arrival <= sunsetDate && end >= sunsetDate {
                return "日落 \(sun.sunsetText) 时，你正在这里"
            }
            return nil
        }()

        return VStack(alignment: .leading, spacing: 8) {
            cardHeader("那天的天空")
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "sunrise.fill")
                        .foregroundColor(.orange)
                        .frame(width: 24, alignment: .center)
                    Text("日出 – 日落")
                        .foregroundColor(.primary)
                    Spacer()
                    Text(sun.rangeText)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                if let caughtSunset {
                    Divider().padding(.leading, 50)
                    HStack(spacing: 10) {
                        Image(systemName: "sunset.fill")
                            .foregroundColor(.orange)
                            .frame(width: 24, alignment: .center)
                        Text(caughtSunset)
                            .font(.subheadline)
                            .foregroundColor(.orange)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                Divider().padding(.leading, 50)
                HStack(spacing: 10) {
                    Image(systemName: moon.symbol)
                        .foregroundColor(.blue)
                        .frame(width: 24, alignment: .center)
                    Text("那晚的月亮")
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(moon.name) · \(moon.illuminationPercent)%")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func locationCard(_ current: Stay) -> some View {
        var rows: [(String, String)] = []
        if let placeName = current.placeName, !placeName.isEmpty { rows.append(("地点名称", placeName)) }
        if let street = current.street, !street.isEmpty { rows.append(("街道", street)) }
        if let city = current.city, !city.isEmpty { rows.append(("所在城市", city)) }
        if let country = current.country, !country.isEmpty {
            let flag = current.countryCode.map { CountryText.flag(for: $0) } ?? ""
            rows.append(("国家/地区", flag.isEmpty ? country : "\(flag) \(country)"))
        }

        return VStack(alignment: .leading, spacing: 8) {
            cardHeader("位置")
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    detailRow(row.0, row.1)
                    if idx < rows.count - 1 || current.tagState != .tagged {
                        Divider().padding(.leading, 16)
                    }
                }
                if current.tagState != .tagged {
                    Button {
                        var copy = current
                        copy.tagState = .pending
                        store.upsertStay(copy)
                        tagger.enqueue()
                    } label: {
                        Label("重新识别地点", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                    }
                }
                if !rows.isEmpty || current.tagState != .tagged {
                    Divider().padding(.leading, 16)
                }
                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: current.coordinate.onMap))
                    item.name = current.displayName
                    item.openInMaps()
                } label: {
                    Label("在“地图”中打开", systemImage: "map")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: - Edit Mode Form Sections

    private func editNameSection(_ current: Stay) -> some View {
        Section {
            TextField(current.placeName ?? current.street ?? "给这个地方起个名字", text: $name)
                .submitLabel(.done)
            Picker("类型", selection: $kind) {
                ForEach(PlaceKind.allCases) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("名称")
        } footer: {
            Text(kindFooter(for: current))
        }
    }

    private func kindFooter(for current: Stay) -> String {
        switch kind {
        case .none where current.isLandmark:
            return "已自动识别为景点。名称和类型会应用到附近 150 米内的所有到访记录。"
        case .none:
            return "漫迹会自动识别景点和店铺。没认出来的景点，可以在这里选“景点”。名称和类型会应用到附近 150 米内的所有到访记录。"
        case .sight:
            return "这里会算作景点，出现在旅程和年度足迹里。名称和类型会应用到附近 150 米内的所有到访记录。"
        default:
            return "名称和类型会应用到附近 150 米内的所有到访记录。"
        }
    }

    private func momentFormSection(_ current: Stay) -> some View {
        Section("动态") {
            if let note = current.note, !note.isEmpty {
                Text(note).font(.body)
                Button {
                    showNoteComposer = true
                } label: {
                    Label("编辑", systemImage: "square.and.pencil")
                }
            } else {
                Button {
                    showNoteComposer = true
                } label: {
                    Label("记录心情", systemImage: "square.and.pencil")
                }
            }
        }
    }

    private func timeSection(_ current: Stay) -> some View {
        Section("时间") {
            LabeledContent("到达", value: Self.fullDateTime(current.arrival))
            LabeledContent("离开", value: current.departure.map(Self.fullDateTime) ?? "仍在这里")
            LabeledContent("停留", value: Formatters.duration(current.duration))
        }
    }

    // MARK: - Location Section

    private func locationSection(_ current: Stay) -> some View {
        Section("位置") {
            if let placeName = current.placeName, !placeName.isEmpty {
                LabeledContent("地点名称", value: placeName)
            }
            if let street = current.street, !street.isEmpty {
                LabeledContent("街道", value: street)
            }
            if let city = current.city, !city.isEmpty {
                LabeledContent("所在城市", value: city)
            }
            if let country = current.country, !country.isEmpty {
                let flag = current.countryCode.map { CountryText.flag(for: $0) } ?? ""
                LabeledContent("国家/地区", value: flag.isEmpty ? country : "\(flag) \(country)")
            }
            if current.tagState != .tagged {
                Button {
                    var copy = current
                    copy.tagState = .pending
                    store.upsertStay(copy)
                    tagger.enqueue()
                } label: {
                    Label("重新识别地点", systemImage: "arrow.clockwise")
                }
            }
            Button {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: current.coordinate.onMap))
                item.name = current.displayName
                item.openInMaps()
            } label: {
                Label("在“地图”中打开", systemImage: "map")
            }
        }
    }

    // MARK: - Privacy Zone Toggle

    private var privacySection: some View {
        Section {
            Toggle(isOn: $isPrivateZone) {
                Label("分享和导出时隐藏这里", systemImage: "eye.slash")
            }
        } footer: {
            Text("周围 300 米内的轨迹和地点不会出现在分享图片和 GPX 文件里，你自己仍然能看到。适合家和其他私人地点。")
        }
    }

    // MARK: - Load & Save

    private static func resolveKind(of stay: Stay) -> PlaceKind {
        if let raw = stay.categoryRaw, let matched = PlaceKind(rawValue: raw) {
            return matched
        }
        return stay.isLandmark ? .sight : .none
    }

    private func loadFields(from current: Stay) {
        name = current.customName ?? ""
        kind = Self.resolveKind(of: current)
        noteText = current.note ?? ""
        isPrivateZone = store.isCoordinatePrivate(current.coordinate)
    }

    private func saveChanges(for current: Stay) {
        let prevKind = Self.resolveKind(of: current)
        var cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind != prevKind && !prevKind.defaultName.isEmpty && cleanedName == prevKind.defaultName {
            cleanedName = ""
        }
        let finalName = cleanedName.isEmpty ? (kind.defaultName.nilIfEmpty ?? nil) : cleanedName
        let catRaw: String? = kind == .none ? nil : kind.rawValue

        store.renameNearby(current, to: finalName, categoryRaw: catRaw, note: noteText)

        let existingZone = store.privacyZone(containing: current.coordinate)
        if isPrivateZone && existingZone == nil {
            let zoneName = finalName ?? current.displayName
            store.upsertPrivacyZone(PrivacyZone(name: zoneName, latitude: current.latitude, longitude: current.longitude, radius: 300))
        } else if !isPrivateZone, let zone = existingZone {
            store.deletePrivacyZone(id: zone.id)
        }

        Haptics.success()
        isEditing = false
    }

    private func timeSummaryLine(for current: Stay) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        let day = f.string(from: current.arrival)
        let start = Formatters.timeHM(current.arrival)
        let end = current.departure.map(Formatters.timeHM) ?? "现在"
        return "\(day) \(start) – \(end) · \(Formatters.duration(current.duration))"
    }

    private static func fullDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Single Stay Map Card with 1:1 Original Circular PlaceIcon Pin

private final class StayDetailPinAnnotation: NSObject, MKAnnotation {
    let stay: Stay
    let coordinate: CLLocationCoordinate2D
    var title: String? { stay.displayName }

    init(stay: Stay) {
        self.stay = stay
        self.coordinate = stay.coordinate.onMap
    }
}

private struct StayPinMKMapView: UIViewRepresentable {
    let stay: Stay

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        let config = MKStandardMapConfiguration(elevationStyle: .realistic)
        map.preferredConfiguration = config
        map.showsCompass = false
        map.showsScale = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.delegate = context.coordinator
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let sig = "\(stay.id.uuidString)|\(stay.displayName)|\(stay.categoryRaw ?? "")|\(stay.isLandmark)"
        guard context.coordinator.lastSig != sig else { return }
        context.coordinator.lastSig = sig
        map.removeAnnotations(map.annotations)
        let ann = StayDetailPinAnnotation(stay: stay)
        map.addAnnotation(ann)
        let region = MKCoordinateRegion(
            center: stay.coordinate.onMap,
            latitudinalMeters: 900,
            longitudinalMeters: 900
        )
        map.setRegion(region, animated: false)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var lastSig = ""

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let ann = annotation as? StayDetailPinAnnotation else { return nil }
            let id = "stayDetailPin"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: ann, reuseIdentifier: id)
            view.annotation = ann
            view.markerTintColor = UIColor(ann.stay.isLandmark ? .yellow : ann.stay.category.tint)
            view.glyphImage = UIImage(systemName: ann.stay.isLandmark ? "star.fill" : ann.stay.category.symbol)
            view.titleVisibility = .visible
            view.displayPriority = .required
            return view
        }
    }
}

// MARK: - Photos Grid Inside Detail Form (1:1 Original StayPhotoGrid)

private struct StayDetailPhotoStrip: View {
    let photos: [PhotoPreviewItem]
    @State private var expanded = false

    private static let cols = 4
    private static let collapsedLimit = 8

    private var shown: [PhotoPreviewItem] {
        expanded ? photos : Array(photos.prefix(Self.collapsedLimit))
    }

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 6) {
                ForEach(Array(stride(from: 0, to: shown.count, by: Self.cols)), id: \.self) { start in
                    HStack(spacing: 6) {
                        ForEach(start..<(start + Self.cols), id: \.self) { index in
                            if index < shown.count {
                                photoTile(shown[index], index: index)
                            } else {
                                Color.clear.aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
            }

            if photos.count > Self.collapsedLimit {
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        expanded.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(expanded ? "收起照片" : "展开全部 \(photos.count) 张")
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func photoTile(_ item: PhotoPreviewItem, index: Int) -> some View {
        Button {
            PhotoLightboxPresenter.present(items: photos, startIndex: index)
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(uiImage: item.thumbnail)
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Moment / Note Composer Sheet

private struct StayNoteComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let placeName: String
    let onSave: (String) -> Void
    @State private var text: String

    init(placeName: String, initialNote: String, onSave: @escaping (String) -> Void) {
        self.placeName = placeName
        self.onSave = onSave
        _text = State(initialValue: initialNote)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(placeName) {
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("写下这一刻的心情或备注…")
                                .font(.body)
                                .foregroundColor(Color(.placeholderText))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $text)
                            .font(.body)
                            .frame(minHeight: 150)
                            .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("记录心情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(text)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Offline Astronomical Sunrise / Sunset & Moon Phase Calculator

private enum SkyAstronomy {
    struct SunInfo {
        let rangeText: String
        let sunsetText: String
        let sunsetDate: Date?
    }

    struct MoonInfo {
        let name: String
        let symbol: String
        let illuminationPercent: Int
    }

    static func sunInfo(date: Date, lat: Double, lon: Double) -> SunInfo {
        let cal = Calendar(identifier: .gregorian)
        let dayOfYear = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let tzOffsetHours = Double(TimeZone.current.secondsFromGMT(for: date)) / 3600.0

        let gamma = 2.0 * .pi / 365.0 * (dayOfYear - 1.0)
        let eqTime = 229.18 * (
            0.000075
            + 0.001868 * cos(gamma)
            - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma)
            - 0.040849 * sin(2 * gamma)
        )
        let decl = 0.006918
            - 0.399912 * cos(gamma)
            + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma)
            + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma)
            + 0.00148 * sin(3 * gamma)

        let latRad = lat * .pi / 180.0
        let zenithRad = 90.833 * .pi / 180.0
        let cosHA = (cos(zenithRad) / (cos(latRad) * cos(decl))) - tan(latRad) * tan(decl)
        guard cosHA >= -1.0 && cosHA <= 1.0 else {
            let polar = cosHA < -1.0 ? "极昼" : "极夜"
            return SunInfo(rangeText: polar, sunsetText: "", sunsetDate: nil)
        }
        let haDeg = acos(cosHA) * 180.0 / .pi
        let sunriseMin = 720.0 - 4.0 * (lon + haDeg) - eqTime + tzOffsetHours * 60.0
        let sunsetMin = 720.0 - 4.0 * (lon - haDeg) - eqTime + tzOffsetHours * 60.0

        func fmt(_ totalMinutes: Double) -> String {
            let wrapped = (Int(totalMinutes.rounded()) % 1440 + 1440) % 1440
            return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
        }
        let sunsetStr = fmt(sunsetMin)
        let dayStart = Calendar.current.startOfDay(for: date)
        let wrappedSunset = (Int(sunsetMin.rounded()) % 1440 + 1440) % 1440
        let sunsetDate = dayStart.addingTimeInterval(Double(wrappedSunset) * 60.0)
        return SunInfo(rangeText: "\(fmt(sunriseMin)) – \(sunsetStr)", sunsetText: sunsetStr, sunsetDate: sunsetDate)
    }

    static func moonPhase(for date: Date) -> MoonInfo {
        let synodicMonth = 29.53058867
        let daysSinceRef = (date.timeIntervalSince1970 - 947_182_440.0) / 86_400.0
        var age = daysSinceRef.truncatingRemainder(dividingBy: synodicMonth)
        if age < 0 { age += synodicMonth }
        let phase = age / synodicMonth
        let illum = Int(((1.0 - cos(phase * 2.0 * .pi)) / 2.0 * 100.0).rounded())

        switch phase {
        case 0.0..<0.03, 0.97...1.0:
            return MoonInfo(name: "新月", symbol: "moonphase.new.moon", illuminationPercent: illum)
        case 0.03..<0.22:
            return MoonInfo(name: "蛾眉月", symbol: "moonphase.waxing.crescent", illuminationPercent: illum)
        case 0.22..<0.28:
            return MoonInfo(name: "上弦月", symbol: "moonphase.first.quarter", illuminationPercent: illum)
        case 0.28..<0.47:
            return MoonInfo(name: "盈凸月", symbol: "moonphase.waxing.gibbous", illuminationPercent: illum)
        case 0.47..<0.53:
            return MoonInfo(name: "满月", symbol: "moonphase.full.moon", illuminationPercent: illum)
        case 0.53..<0.72:
            return MoonInfo(name: "亏凸月", symbol: "moonphase.waning.gibbous", illuminationPercent: illum)
        case 0.72..<0.78:
            return MoonInfo(name: "下弦月", symbol: "moonphase.last.quarter", illuminationPercent: illum)
        default:
            return MoonInfo(name: "残月", symbol: "moonphase.waning.crescent", illuminationPercent: illum)
        }
    }
}
