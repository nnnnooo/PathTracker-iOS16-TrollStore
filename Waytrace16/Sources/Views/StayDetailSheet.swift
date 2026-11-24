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
            Form {
                Section {
                    StayPinMKMapView(stay: current)
                        .frame(height: 200)
                        .listRowInsets(EdgeInsets())
                }

                if !isEditing {
                    overviewSection(current)
                }

                if isEditing {
                    editNameSection(current)
                }

                if !isEditing && !photos.isEmpty {
                    takenHereSection
                }

                momentSection(current)
                timeSection(current)

                if !isEditing {
                    skySection(current)
                }

                locationSection(current)

                if isEditing {
                    privacySection
                    Section {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Label("删除这条记录", systemImage: "trash")
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.22), value: isEditing)
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
                            UISelectionFeedbackGenerator().selectionChanged()
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
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
            .confirmationDialog("删除这条停留记录？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    store.deleteStay(id: current.id)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
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

    // MARK: - Overview Card

    private func overviewSection(_ current: Stay) -> some View {
        Section {
            HStack(spacing: 14) {
                if let first = photos.first {
                    Image(uiImage: first.thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                        .onTapGesture {
                            PhotoLightboxPresenter.present(items: photos, startIndex: 0)
                        }
                } else {
                    PlaceIcon(category: current.category, isLandmark: current.isLandmark, size: 52)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(current.displayName)
                        .font(.title3.bold())
                        .lineLimit(2)
                    if let sub = current.subtitle {
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
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Edit Name & Kind

    private func editNameSection(_ current: Stay) -> some View {
        Section {
            TextField(current.placeName ?? current.street ?? "给这个地方起个名字", text: $name)
                .submitLabel(.done)
            Picker("类型", selection: $kind) {
                ForEach(PlaceKind.allCases) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
            }
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

    // MARK: - Photos Taken Here

    private var takenHereSection: some View {
        Section {
            StayDetailPhotoStrip(photos: photos)
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        } header: {
            Text("在这里拍的照片 \(photos.count)")
        }
    }

    // MARK: - Moment / Note Section

    private func momentSection(_ current: Stay) -> some View {
        Section("动态") {
            if let note = current.note, !note.isEmpty {
                Text(note)
                    .font(.body)
                Button {
                    showNoteComposer = true
                } label: {
                    Label("编辑心情与备注", systemImage: "square.and.pencil")
                }
            } else {
                Button {
                    showNoteComposer = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.14, green: 0.62, blue: 1.0), Color.blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("发布照片和心情")
                                .font(.headline)
                                .foregroundColor(.blue)
                            Text(photos.isEmpty ? "留下这一刻" : "你在这里拍了 \(photos.count) 张照片")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Time Section

    private func timeSection(_ current: Stay) -> some View {
        Section("时间") {
            LabeledContent("到达", value: Self.fullDateTime(current.arrival))
            LabeledContent("离开", value: current.departure.map(Self.fullDateTime) ?? "仍在这里")
            LabeledContent("停留", value: Formatters.duration(current.duration))
        }
    }

    // MARK: - Sky Section (Astronomical Sunrise/Sunset & Moon Phase)

    private func skySection(_ current: Stay) -> some View {
        let sun = SkyAstronomy.sunTimes(date: current.arrival, lat: current.latitude, lon: current.longitude)
        let moon = SkyAstronomy.moonPhase(for: current.arrival)

        return Section("那天的天空") {
            HStack {
                Label {
                    Text("日出 – 日落")
                } icon: {
                    Image(systemName: "sunrise.fill")
                        .foregroundColor(.orange)
                }
                Spacer()
                Text(sun)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            HStack {
                Label {
                    Text("那晚的月亮")
                } icon: {
                    Image(systemName: moon.symbol)
                        .foregroundColor(.blue)
                }
                Spacer()
                Text("\(moon.name) · \(moon.illuminationPercent)%")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
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
        name = current.customName ?? current.placeName ?? ""
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

        UINotificationFeedbackGenerator().notificationOccurred(.success)
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

// MARK: - Single Stay Map Card with Styled Pin

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
            latitudinalMeters: 750,
            longitudinalMeters: 750
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

// MARK: - Photos Grid Inside Detail Form

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
            if photos.count <= 4 {
                HStack(spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { idx, item in
                        photoTile(item, index: idx)
                    }
                    if photos.count < 4 {
                        Spacer(minLength: 0)
                    }
                }
            } else {
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
            }

            if photos.count > Self.collapsedLimit {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
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
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func photoTile(_ item: PhotoPreviewItem, index: Int) -> some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            Image(uiImage: item.thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: photos.count <= 4 ? 82 : .infinity)
        .onTapGesture {
            PhotoLightboxPresenter.present(items: photos, startIndex: index)
        }
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
                    TextField("写下这一刻的心情或备注…", text: $text, axis: .vertical)
                        .lineLimit(4...10)
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
    struct MoonInfo {
        let name: String
        let symbol: String
        let illuminationPercent: Int
    }

    /// Computes approximate local sunrise & sunset times (HH:mm – HH:mm) using standard NOAA solar equations.
    static func sunTimes(date: Date, lat: Double, lon: Double) -> String {
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
            return cosHA < -1.0 ? "极昼" : "极夜"
        }
        let haDeg = acos(cosHA) * 180.0 / .pi
        let sunriseMin = 720.0 - 4.0 * (lon + haDeg) - eqTime + tzOffsetHours * 60.0
        let sunsetMin = 720.0 - 4.0 * (lon - haDeg) - eqTime + tzOffsetHours * 60.0

        func fmt(_ totalMinutes: Double) -> String {
            let wrapped = (Int(totalMinutes.rounded()) % 1440 + 1440) % 1440
            return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
        }
        return "\(fmt(sunriseMin)) – \(fmt(sunsetMin))"
    }

    /// Computes lunar phase name, SF Symbol, and illumination percentage using synodic month (29.53058867 days).
    static func moonPhase(for date: Date) -> MoonInfo {
        // Known New Moon reference: 2000-01-06 18:14 UTC (Unix timestamp 947182440)
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
