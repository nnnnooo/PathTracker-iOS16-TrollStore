import SwiftUI
import MapKit

// MARK: - 省市县地图默认尺寸与样式配置

enum ChinaMapLayoutConfig {
    /// 自动聚焦全部点亮区域时的外扩留白比例（1.28 表示四周留约 14% 边距）
    static let fitPaddingMultiplier: Double = 1.28
    /// 无任何点亮区域时的兜底中心点与跨度
    static let fallbackCenter = CLLocationCoordinate2D(latitude: 35.0, longitude: 104.5)
    static let fallbackLatDelta: CLLocationDegrees = 34.0
    static let fallbackLonDelta: CLLocationDegrees = 48.0
    /// Metal 矢量描边线宽（pt，任意缩放级别均保持视网膜级锐利）
    static let litBorderLineWidth: CGFloat = 0.95
    static let districtBorderLineWidth: CGFloat = 0.65
    static let highlightBorderLineWidth: CGFloat = 1.75
}

// MARK: - Selected Region Visit Info

private struct SelectedChinaRegionInfo: Equatable {
    let feature: ChinaGeoFeature
    let isLit: Bool
    let firstVisit: Date?
    let lastVisit: Date?
    let visitDays: Int

    static func == (lhs: SelectedChinaRegionInfo, rhs: SelectedChinaRegionInfo) -> Bool {
        lhs.feature.id == rhs.feature.id && lhs.isLit == rhs.isLit && lhs.visitDays == rhs.visitDays
    }
}

// MARK: - Dedicated Bottom Tab for 省市县

struct ChinaLightUpTabView: View {
    @Binding var showingSettings: Bool
    @State private var isFullScreen = false

    var body: some View {
        NavigationStack {
            ChinaLightUpSection(isFullScreen: $isFullScreen)
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
                .navigationTitle("省市县")
                .navigationBarTitleDisplayMode(.large)
                .toolbar(isFullScreen ? .hidden : .visible, for: .navigationBar)
                .toolbar(isFullScreen ? .hidden : .visible, for: .tabBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ProfileToolbarButton(showingSettings: $showingSettings)
                    }
                }
        }
    }
}

// MARK: - China Administrative Region Light-Up Map Section

struct ChinaLightUpSection: View {
    @Binding var isFullScreen: Bool

    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var chinaStore: ChinaRegionsStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var level: ChinaRegionLevel = .city
    @State private var isEditing = false
    @State private var showSyncSheet = false
    @State private var features: [ChinaGeoFeature] = []
    @State private var fitRegion: MKCoordinateRegion?
    @State private var renderRevision: Int = 0
    @State private var isLoadingLevel = false
    @State private var toastText: String?
    @State private var selectedInfo: SelectedChinaRegionInfo?

    init(isFullScreen: Binding<Bool> = .constant(false)) {
        _isFullScreen = isFullScreen
    }

    private var litCountForCurrentLevel: Int {
        switch level {
        case .province: return chinaStore.litProvinceCount
        case .city: return chinaStore.litCityCount
        case .district: return chinaStore.litDistrictCount
        }
    }

    private var totalCountForCurrentLevel: Int {
        switch level {
        case .province: return 34
        case .city: return 337
        case .district: return 2847
        }
    }

    private var currentLitSet: Set<String> {
        switch level {
        case .district: return chinaStore.visitedDistricts
        case .city: return chinaStore.visitedCities.union(chinaStore.visitedMunicipalities)
        case .province: return chinaStore.visitedProvinces.union(chinaStore.visitedMunicipalities)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isFullScreen ? 0 : 12) {
            if !isFullScreen {
                // Summary Header
                HStack(alignment: .center, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(litCountForCurrentLevel)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.blue)
                        Text("/ \(totalCountForCurrentLevel)")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("已点亮\(level.fullTitle)")
                            .font(.subheadline.weight(.semibold))
                        Text("\(chinaStore.litProvinceCount) 省 · \(chinaStore.litCityCount) 市 · \(chinaStore.litDistrictCount) 区县")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Single persistent MKMapView instance: stays fixed in place while its frame expands smoothly to full screen
            mapContainer(interactive: true, fullScreen: isFullScreen)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: isFullScreen ? 0 : 28, style: .continuous))
                .overlay {
                    if !isFullScreen {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                }
                .padding(.horizontal, isFullScreen ? 0 : 16)
                .padding(.bottom, isFullScreen ? 0 : 16)
                .ignoresSafeArea(edges: isFullScreen ? .all : [])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: level) {
            await loadFeatures(for: level)
        }
        .onChange(of: currentLitSet) { _ in
            renderRevision &+= 1
        }
        .onChange(of: isEditing) { _ in
            renderRevision &+= 1
        }
        .onChange(of: colorScheme) { _ in
            renderRevision &+= 1
        }
        .sheet(isPresented: $showSyncSheet) {
            ChinaGitHubSyncSheet(level: level, features: features)
        }
    }

    @ViewBuilder
    private func mapContainer(interactive: Bool, fullScreen: Bool) -> some View {
        ZStack {
            ChinaRegionsMKMapView(
                features: features,
                litKeys: currentLitSet,
                highlightedFeatureID: selectedInfo?.feature.id,
                fitRegion: fitRegion,
                level: level,
                isEditing: isEditing,
                isDark: colorScheme == .dark,
                renderRevision: renderRevision,
                interactive: interactive
            ) { tapped in
                handleRegionTap(tapped)
            }

            if isLoadingLevel {
                ProgressView("加载\(level.fullTitle)…")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            VStack(spacing: 8) {
                // Top Control Row (full-screen shows stats at top-left matching embedded header)
                HStack(alignment: .center, spacing: 8) {
                    if fullScreen {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text("\(litCountForCurrentLevel)")
                                    .font(.system(.title3, design: .rounded).weight(.bold))
                                    .foregroundColor(.blue)
                                Text("/ \(totalCountForCurrentLevel) \(level.fullTitle)")
                                    .font(.caption2.weight(.medium))
                                    .foregroundColor(.secondary)
                            }
                            Text("\(chinaStore.litProvinceCount) 省 · \(chinaStore.litCityCount) 市 · \(chinaStore.litDistrictCount) 区县")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
                        .padding(.leading, 12)
                    } else if isEditing {
                        Label("点击区域点亮/取消", systemImage: "hand.tap.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.blue.opacity(0.92), in: Capsule())
                            .padding(.leading, 12)
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 8) {
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            isEditing.toggle()
                        } label: {
                            Image(systemName: isEditing ? "checkmark" : "pencil")
                                .font(.footnote.weight(.bold))
                                .foregroundColor(isEditing ? .white : .primary)
                                .frame(width: 36, height: 36)
                                .background(
                                    isEditing ? AnyShapeStyle(Color.blue) : AnyShapeStyle(.ultraThinMaterial),
                                    in: Circle()
                                )
                        }

                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            showSyncSheet = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.footnote.weight(.bold))
                                    .foregroundColor(.primary)
                                    .frame(width: 36, height: 36)
                                    .background(.ultraThinMaterial, in: Circle())
                                if chinaStore.hasUnsyncedChanges {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 9, height: 9)
                                        .offset(x: -1, y: 1)
                                }
                            }
                        }

                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
                                isFullScreen.toggle()
                            }
                        } label: {
                            Image(systemName: fullScreen ? "xmark" : "arrow.up.left.and.arrow.down.right")
                                .font(.footnote.weight(.bold))
                                .foregroundColor(.primary)
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    .padding(.trailing, 12)
                }
                .padding(.top, fullScreen ? 56 : 12)

                // Edit-mode hint in full-screen sits cleanly below top stats bar
                if fullScreen && isEditing {
                    Label("点击区域点亮/取消", systemImage: "hand.tap.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.92), in: Capsule())
                }

                if let toastText {
                    Text(toastText)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.76), in: Capsule())
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                Spacer()

                if let info = selectedInfo {
                    selectedRegionCard(info)
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Bottom Bar: 县 / 市 / 省 Switcher with comfortable spacing & touch targets
                HStack(alignment: .bottom, spacing: 10) {
                    HStack(spacing: 8) {
                        ForEach(ChinaRegionLevel.allCases) { item in
                            Button {
                                guard level != item else { return }
                                UISelectionFeedbackGenerator().selectionChanged()
                                selectedInfo = nil
                                level = item
                            } label: {
                                Text(item.shortTitle)
                                    .font(.subheadline.weight(level == item ? .bold : .semibold))
                                    .foregroundColor(level == item ? .white : .primary)
                                    .frame(width: 48, height: 38)
                                    .background(
                                        level == item ? Color.blue : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(5)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, fullScreen ? 32 : 12)
            }
        }
    }

    private func selectedRegionCard(_ info: SelectedChinaRegionInfo) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(info.feature.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(info.isLit ? "已点亮" : "未点亮")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(info.isLit ? .blue : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            (info.isLit ? Color.blue : Color.secondary).opacity(0.14),
                            in: Capsule()
                        )
                        .fixedSize()
                }

                if let first = info.firstVisit {
                    let dateDesc: String = {
                        if let last = info.lastVisit, !Calendar.current.isDate(first, inSameDayAs: last) {
                            return "去过 \(info.visitDays) 天 · \(Self.compactDateRange(first, last))"
                        }
                        return "到访于 \(Self.compactDate(first)) · \(info.visitDays) 天"
                    }()
                    Text(dateDesc)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else {
                    Text(info.isLit ? "来自历史标记 / 手动点亮" : "还没有足迹记录")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Button {
                let nowLit = chinaStore.toggle(info.feature)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                selectedInfo = SelectedChinaRegionInfo(
                    feature: info.feature,
                    isLit: nowLit,
                    firstVisit: info.firstVisit,
                    lastVisit: info.lastVisit,
                    visitDays: info.visitDays
                )
                renderRevision &+= 1
                showToast(nowLit ? "已点亮：\(info.feature.name)" : "已取消：\(info.feature.name)")
            } label: {
                Text(info.isLit ? "取消" : "点亮")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(info.isLit ? .primary : .white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        info.isLit ? Color(.tertiarySystemFill) : Color.blue,
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .layoutPriority(2)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedInfo = nil
                    renderRevision &+= 1
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private func handleRegionTap(_ tapped: ChinaGeoFeature) {
        if isEditing {
            let nowLit = chinaStore.toggle(tapped)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showToast(nowLit ? "已点亮：\(tapped.name)" : "已取消：\(tapped.name)")
            updateSelectedInfo(for: tapped, isLit: nowLit)
        } else if selectedInfo?.feature.id == tapped.id {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedInfo = nil
            }
        } else {
            UISelectionFeedbackGenerator().selectionChanged()
            let lit = chinaStore.isLit(tapped)
            updateSelectedInfo(for: tapped, isLit: lit)
        }
        renderRevision &+= 1
    }

    private func updateSelectedInfo(for feature: ChinaGeoFeature, isLit: Bool) {
        let staysSnap = store.stays
        Task.detached(priority: .userInitiated) {
            let cal = Calendar.current
            let matched = staysSnap.filter { stay in
                feature.contains(gcj02: stay.coordinate.onMap)
            }
            let first = matched.map(\.arrival).min()
            let last = matched.map { $0.departure ?? $0.arrival }.max()
            let days = Set(matched.map { cal.startOfDay(for: $0.arrival) }).count
            let info = SelectedChinaRegionInfo(
                feature: feature,
                isLit: isLit,
                firstVisit: first,
                lastVisit: last,
                visitDays: days
            )
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    selectedInfo = info
                    renderRevision &+= 1
                }
            }
        }
    }

    private func loadFeatures(for targetLevel: ChinaRegionLevel) async {
        isLoadingLevel = true
        let litSnapshot = currentLitSet
        let result = await Task.detached(priority: .userInitiated) { () -> ([ChinaGeoFeature], MKCoordinateRegion) in
            let loaded = ChinaGeoLoader.load(level: targetLevel)
            var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0
            var hasLit = false
            for feat in loaded {
                if litSnapshot.contains(feat.visitedKey) || litSnapshot.contains(feat.name) {
                    hasLit = true
                    if feat.minLat < minLat { minLat = feat.minLat }
                    if feat.maxLat > maxLat { maxLat = feat.maxLat }
                    if feat.minLon < minLon { minLon = feat.minLon }
                    if feat.maxLon > maxLon { maxLon = feat.maxLon }
                }
            }
            let region: MKCoordinateRegion
            if hasLit {
                let pad = ChinaMapLayoutConfig.fitPaddingMultiplier
                region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2.0, longitude: (minLon + maxLon) / 2.0),
                    span: MKCoordinateSpan(
                        latitudeDelta: min(56.0, max(5.0, (maxLat - minLat) * pad)),
                        longitudeDelta: min(72.0, max(6.0, (maxLon - minLon) * pad))
                    )
                )
            } else {
                region = MKCoordinateRegion(
                    center: ChinaMapLayoutConfig.fallbackCenter,
                    span: MKCoordinateSpan(
                        latitudeDelta: ChinaMapLayoutConfig.fallbackLatDelta,
                        longitudeDelta: ChinaMapLayoutConfig.fallbackLonDelta
                    )
                )
            }
            return (loaded, region)
        }.value

        guard !Task.isCancelled else { return }
        features = result.0
        if fitRegion == nil {
            fitRegion = result.1
        }
        renderRevision &+= 1
        isLoadingLevel = false
    }

    private func showToast(_ text: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            toastText = text
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                if toastText == text {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        toastText = nil
                    }
                }
            }
        }
    }

    private static func compactDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy.M.d"
        return f.string(from: date)
    }

    private static func compactDateRange(_ first: Date, _ last: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(first, equalTo: last, toGranularity: .year) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "M.d"
            return "\(compactDate(first))–\(f.string(from: last))"
        }
        return "\(compactDate(first))–\(compactDate(last))"
    }
}

// MARK: - Native GPU Vector MKMultiPolygon Overlays (Razor-Sharp at Every Zoom Level, Zero Tile Blur)

private final class ChinaMultiPolygonOverlay: MKMultiPolygon {
    enum Role { case unlit, lit, highlight }
    var role: Role = .lit
    var level: ChinaRegionLevel = .city
    var isDark: Bool = false
}

// MARK: - MapView Wrapper

private struct ChinaRegionsMKMapView: UIViewRepresentable {
    let features: [ChinaGeoFeature]
    let litKeys: Set<String>
    let highlightedFeatureID: String?
    let fitRegion: MKCoordinateRegion?
    let level: ChinaRegionLevel
    let isEditing: Bool
    let isDark: Bool
    let renderRevision: Int
    let interactive: Bool
    let onTapFeature: (ChinaGeoFeature) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        let config = MKStandardMapConfiguration(elevationStyle: .realistic)
        config.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = config
        map.showsCompass = false
        map.showsScale = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.isScrollEnabled = interactive
        map.isZoomEnabled = interactive
        map.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        map.addGestureRecognizer(tap)

        if let initial = fitRegion {
            map.setRegion(initial, animated: false)
            context.coordinator.hasFramedInitialRegion = true
        } else {
            let fallback = MKCoordinateRegion(
                center: ChinaMapLayoutConfig.fallbackCenter,
                span: MKCoordinateSpan(
                    latitudeDelta: ChinaMapLayoutConfig.fallbackLatDelta,
                    longitudeDelta: ChinaMapLayoutConfig.fallbackLonDelta
                )
            )
            map.setRegion(fallback, animated: false)
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self

        if !context.coordinator.hasFramedInitialRegion, let target = fitRegion {
            context.coordinator.hasFramedInitialRegion = true
            map.setRegion(target, animated: false)
        }

        let needsRebuild = context.coordinator.lastRevision != renderRevision
            || context.coordinator.lastIsDark != isDark
            || context.coordinator.lastLevel != level
            || context.coordinator.lastEditing != isEditing
            || context.coordinator.lastHighlightID != highlightedFeatureID
            || context.coordinator.lastFeatureCount != features.count

        guard needsRebuild else { return }
        context.coordinator.lastRevision = renderRevision
        context.coordinator.lastIsDark = isDark
        context.coordinator.lastLevel = level
        context.coordinator.lastEditing = isEditing
        context.coordinator.lastHighlightID = highlightedFeatureID
        context.coordinator.lastFeatureCount = features.count

        context.coordinator.rebuildOverlays(on: map, features: features, litKeys: litKeys, highlightedID: highlightedFeatureID, level: level, isEditing: isEditing, isDark: isDark)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ChinaRegionsMKMapView
        var lastRevision = -1
        var lastIsDark = false
        var lastLevel: ChinaRegionLevel?
        var lastEditing = false
        var lastHighlightID: String?
        var lastFeatureCount = -1
        var hasFramedInitialRegion = false

        // Light mode vector palette
        private let lightLitFill = UIColor(red: 0.20, green: 0.54, blue: 0.96, alpha: 0.34)
        private let lightLitStroke = UIColor(red: 0.06, green: 0.28, blue: 0.72, alpha: 0.92)
        private let lightUnlitStroke = UIColor(red: 0.32, green: 0.38, blue: 0.46, alpha: 0.48)
        private let lightHlStroke = UIColor(red: 0.04, green: 0.22, blue: 0.68, alpha: 1.0)
        private let lightHlTint = UIColor(red: 0.12, green: 0.45, blue: 0.96, alpha: 0.16)

        // Dark mode vector palette
        private let darkLitFill = UIColor(red: 0.32, green: 0.76, blue: 1.0, alpha: 0.44)
        private let darkLitStroke = UIColor(red: 0.68, green: 0.92, blue: 1.0, alpha: 0.95)
        private let darkUnlitStroke = UIColor(white: 0.86, alpha: 0.42)
        private let darkHlStroke = UIColor.white
        private let darkHlTint = UIColor(red: 0.50, green: 0.86, blue: 1.0, alpha: 0.18)

        private var activeOverlays: [MKOverlay] = []

        init(_ parent: ChinaRegionsMKMapView) {
            self.parent = parent
        }

        func rebuildOverlays(
            on map: MKMapView,
            features: [ChinaGeoFeature],
            litKeys: Set<String>,
            highlightedID: String?,
            level: ChinaRegionLevel,
            isEditing: Bool,
            isDark: Bool
        ) {
            if !activeOverlays.isEmpty {
                map.removeOverlays(activeOverlays)
                activeOverlays.removeAll()
            }
            guard !features.isEmpty else { return }

            var unlitPolys: [MKPolygon] = []
            var litPolys: [MKPolygon] = []
            var hlPolys: [MKPolygon] = []

            let includeUnlit = isEditing && level != .district

            for feat in features {
                let isLit = litKeys.contains(feat.visitedKey) || litKeys.contains(feat.name)
                let isHl = feat.id == highlightedID

                if isHl {
                    for ring in feat.rings where ring.count >= 3 {
                        var coords = ring
                        hlPolys.append(MKPolygon(coordinates: &coords, count: coords.count))
                    }
                }
                if isLit {
                    for ring in feat.rings where ring.count >= 3 {
                        var coords = ring
                        litPolys.append(MKPolygon(coordinates: &coords, count: coords.count))
                    }
                } else if includeUnlit && !isHl {
                    for ring in feat.rings where ring.count >= 3 {
                        var coords = ring
                        unlitPolys.append(MKPolygon(coordinates: &coords, count: coords.count))
                    }
                }
            }

            var toAdd: [MKOverlay] = []
            if !unlitPolys.isEmpty {
                let ov = ChinaMultiPolygonOverlay(unlitPolys)
                ov.role = .unlit
                ov.level = level
                ov.isDark = isDark
                toAdd.append(ov)
            }
            if !litPolys.isEmpty {
                let ov = ChinaMultiPolygonOverlay(litPolys)
                ov.role = .lit
                ov.level = level
                ov.isDark = isDark
                toAdd.append(ov)
            }
            if !hlPolys.isEmpty {
                let ov = ChinaMultiPolygonOverlay(hlPolys)
                ov.role = .highlight
                ov.level = level
                ov.isDark = isDark
                toAdd.append(ov)
            }

            activeOverlays = toAdd
            if !toAdd.isEmpty {
                map.addOverlays(toAdd, level: .aboveRoads)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let multi = overlay as? ChinaMultiPolygonOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let r = MKMultiPolygonRenderer(multiPolygon: multi)
            r.lineJoin = .round
            r.lineCap = .round
            switch multi.role {
            case .unlit:
                r.fillColor = .clear
                r.strokeColor = multi.isDark ? darkUnlitStroke : lightUnlitStroke
                r.lineWidth = 0.55
            case .lit:
                r.fillColor = multi.isDark ? darkLitFill : lightLitFill
                r.strokeColor = multi.isDark ? darkLitStroke : lightLitStroke
                r.lineWidth = multi.level == .district
                    ? ChinaMapLayoutConfig.districtBorderLineWidth
                    : ChinaMapLayoutConfig.litBorderLineWidth
            case .highlight:
                r.fillColor = multi.isDark ? darkHlTint : lightHlTint
                r.strokeColor = multi.isDark ? darkHlStroke : lightHlStroke
                r.lineWidth = ChinaMapLayoutConfig.highlightBorderLineWidth
            }
            return r
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let pt = gesture.location(in: map)
            let coord = map.convert(pt, toCoordinateFrom: map)
            if let hit = parent.features.first(where: { $0.contains(gcj02: coord) }) {
                parent.onTapFeature(hit)
            }
        }
    }
}

// MARK: - GitHub Sync & Searchable Region Editor Sheet

struct ChinaGitHubSyncSheet: View {
    @EnvironmentObject private var chinaStore: ChinaRegionsStore
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let level: ChinaRegionLevel
    let features: [ChinaGeoFeature]

    @State private var searchText = ""

    private var filteredFeatures: [ChinaGeoFeature] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Array(features.prefix(60)) }
        return Array(features.filter { $0.name.localizedCaseInsensitiveContains(q) }.prefix(80))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("已点亮统计")
                        Spacer()
                        Text("\(chinaStore.litProvinceCount) 省 · \(chinaStore.litCityCount) 市 · \(chinaStore.litDistrictCount) 区县")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.secondary)
                    }

                    Button {
                        Task {
                            let added = await chinaStore.autoMatch(stays: store.stays, includeDistricts: true)
                            chinaStore.syncMessage = "从当前足迹新增：\(added.provinces) 省 · \(added.cities) 市 · \(added.districts) 区县"
                        }
                    } label: {
                        HStack {
                            Label("从漫迹足迹自动匹配点亮", systemImage: "sparkles")
                            Spacer()
                            if chinaStore.isAutoMatching { ProgressView() }
                        }
                    }
                    .disabled(chinaStore.isAutoMatching)
                } header: {
                    Text("足迹同步")
                }

                Section {
                    TextField("仓库（格式：用户名/仓库名）", text: $chinaStore.ghRepo)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("分支（默认 main）", text: $chinaStore.ghBranch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("GitHub Personal Access Token", text: $chinaStore.ghToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack(spacing: 12) {
                        Button {
                            Task { await chinaStore.pullFromGitHub() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("从 GitHub 拉取")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(chinaStore.isSyncing || !chinaStore.isGitHubConfigured)
                        .opacity((chinaStore.isSyncing || !chinaStore.isGitHubConfigured) ? 0.45 : 1)

                        Button {
                            Task { await chinaStore.pushToGitHub() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.circle.fill")
                                Text("推送到 GitHub")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(chinaStore.isSyncing || !chinaStore.isGitHubConfigured)
                        .opacity((chinaStore.isSyncing || !chinaStore.isGitHubConfigured) ? 0.45 : 1)
                    }
                    .padding(.vertical, 4)

                    if chinaStore.isSyncing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在与 GitHub 通信…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    if let msg = chinaStore.syncMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    if let err = chinaStore.syncError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("GitHub 仓库双向同步（visited_areas.json）")
                } footer: {
                    Text("与原 MyTravelsChina 网页版使用完全一致的 visited_areas.json 格式，支持无缝拉取与回写。")
                }

                Section {
                    TextField("搜索\(level.fullTitle)名称以手动切换…", text: $searchText)
                    ForEach(filteredFeatures) { feat in
                        let lit = chinaStore.isLit(feat)
                        Button {
                            _ = chinaStore.toggle(feat)
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            HStack {
                                Text(feat.name)
                                    .foregroundColor(.primary)
                                if level == .district {
                                    Text("\(feat.adcode)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: lit ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(lit ? .blue : Color(.tertiaryLabel))
                            }
                        }
                    }
                } header: {
                    Text("快速检索并点亮（当前层级：\(level.fullTitle)）")
                }
            }
            .navigationTitle("省市县同步与管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
