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
    /// 屏幕视觉描边线宽（pt，随缩放自动收细，兼顾清晰度与零发热）
    static let litBorderScreenPoints: CGFloat = 0.90
    static let districtBorderScreenPoints: CGFloat = 0.65
    static let highlightBorderScreenPoints: CGFloat = 1.65
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
    @State private var hideChrome = false

    var body: some View {
        NavigationStack {
            ChinaLightUpSection(
                isFullScreen: $isFullScreen,
                hideChrome: $hideChrome
            )
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("省市县")
            .navigationBarTitleDisplayMode(.large)
            .toolbar(hideChrome ? .hidden : .automatic, for: .navigationBar)
            .toolbar(hideChrome ? .hidden : .automatic, for: .tabBar)
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
    @Binding var hideChrome: Bool

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

    init(isFullScreen: Binding<Bool> = .constant(false), hideChrome: Binding<Bool> = .constant(false)) {
        _isFullScreen = isFullScreen
        _hideChrome = hideChrome
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

    private func toggleFullScreen() {
        Haptics.selection()
        if !isFullScreen {
            // 进入全屏：先隐藏导航栏与底栏，再平滑展开地图
            hideChrome = true
            withAnimation(.easeInOut(duration: 0.25)) {
                isFullScreen = true
            }
        } else {
            // 退出全屏：先恢复底栏与导航栏占位（不带动画，避免地图穿到底部导航栏后面卡顿），再平滑收回卡片
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                hideChrome = false
            }
            withAnimation(.easeInOut(duration: 0.24)) {
                isFullScreen = false
            }
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
                .transition(.opacity)
            }

            // Single persistent MKMapView instance
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
                .ignoresSafeArea(edges: hideChrome ? .all : [])
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
            ChinaGitHubSyncSheet(initialLevel: level)
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
                // Top Control Row
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
                            Haptics.selection()
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
                            Haptics.selection()
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
                            toggleFullScreen()
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

                // Bottom Bar: 县 / 市 / 省 Switcher
                HStack(alignment: .bottom, spacing: 10) {
                    HStack(spacing: 8) {
                        ForEach(ChinaRegionLevel.allCases) { item in
                            Button {
                                guard level != item else { return }
                                Haptics.selection()
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
                Haptics.medium()
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
            Haptics.medium()
            showToast(nowLit ? "已点亮：\(tapped.name)" : "已取消：\(tapped.name)")
            updateSelectedInfo(for: tapped, isLit: nowLit)
        } else if selectedInfo?.feature.id == tapped.id {
            Haptics.selection()
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedInfo = nil
                renderRevision &+= 1
            }
        } else {
            Haptics.selection()
            let lit = chinaStore.isLit(tapped)
            updateSelectedInfo(for: tapped, isLit: lit)
        }
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

// MARK: - Fast Tile-Culled MKOverlayRenderer (Zero Heat, Thin Crisp Lines at Every Zoom, 60fps)

private final class ChinaRegionsCanvasOverlay: NSObject, MKOverlay {
    let coordinate = CLLocationCoordinate2D(latitude: 35.0, longitude: 105.0)
    let boundingMapRect: MKMapRect = {
        let nw = MKMapPoint(CLLocationCoordinate2D(latitude: 56.0, longitude: 70.0))
        let se = MKMapPoint(CLLocationCoordinate2D(latitude: 14.0, longitude: 138.0))
        return MKMapRect(x: min(nw.x, se.x), y: min(nw.y, se.y), width: abs(se.x - nw.x), height: abs(se.y - nw.y))
    }()
}

private struct ChinaRenderSnapshot {
    let features: [ChinaGeoFeature]
    let litKeys: Set<String>
    let highlightedID: String?
    let level: ChinaRegionLevel
    let isEditing: Bool
    let isDark: Bool
}

private final class ChinaRegionsCanvasRenderer: MKOverlayRenderer {
    private let lock = NSLock()
    private var snapshot = ChinaRenderSnapshot(features: [], litKeys: [], highlightedID: nil, level: .city, isEditing: false, isDark: false)

    private let lightLitFill = UIColor(red: 0.20, green: 0.54, blue: 0.96, alpha: 0.34).cgColor
    private let lightLitStroke = UIColor(red: 0.06, green: 0.28, blue: 0.72, alpha: 0.92).cgColor
    private let lightUnlitStroke = UIColor(red: 0.32, green: 0.38, blue: 0.46, alpha: 0.48).cgColor
    private let lightHlStroke = UIColor(red: 0.04, green: 0.22, blue: 0.68, alpha: 1.0).cgColor
    private let lightHlTint = UIColor(red: 0.12, green: 0.45, blue: 0.96, alpha: 0.15).cgColor

    private let darkLitFill = UIColor(red: 0.32, green: 0.76, blue: 1.0, alpha: 0.44).cgColor
    private let darkLitStroke = UIColor(red: 0.68, green: 0.92, blue: 1.0, alpha: 0.95).cgColor
    private let darkUnlitStroke = UIColor(white: 0.86, alpha: 0.42).cgColor
    private let darkHlStroke = UIColor.white.cgColor
    private let darkHlTint = UIColor(red: 0.50, green: 0.86, blue: 1.0, alpha: 0.18).cgColor

    func update(_ newSnapshot: ChinaRenderSnapshot) {
        lock.lock()
        snapshot = newSnapshot
        lock.unlock()
        setNeedsDisplay()
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        lock.lock()
        let snap = snapshot
        lock.unlock()

        guard !snap.features.isEmpty else { return }
        let safeZoom = max(zoomScale, 0.000001)
        let zoomFactor: CGFloat = zoomScale < 0.00005 ? 0.42 : (zoomScale < 0.00014 ? 0.62 : (zoomScale < 0.00035 ? 0.82 : 1.0))
        let baseLit = snap.level == .district ? ChinaMapLayoutConfig.districtBorderScreenPoints : ChinaMapLayoutConfig.litBorderScreenPoints
        let litLineWidth = (baseLit * zoomFactor) / safeZoom
        let unlitLineWidth = (0.50 * zoomFactor) / safeZoom
        let hlLineWidth = (ChinaMapLayoutConfig.highlightBorderScreenPoints * max(zoomFactor, 0.6)) / safeZoom

        let pad = 6.0 / safeZoom
        let queryRect = mapRect.insetBy(dx: -pad, dy: -pad)

        context.saveGState()
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.setMiterLimit(2.0)

        let useDetail = zoomScale >= 0.00025
        var highlightedFeature: ChinaGeoFeature?

        let litFill = snap.isDark ? darkLitFill : lightLitFill
        let litStroke = snap.isDark ? darkLitStroke : lightLitStroke
        let unlitStroke = snap.isDark ? darkUnlitStroke : lightUnlitStroke

        if snap.isEditing {
            let drawUnlitDistricts = snap.level != .district || zoomScale > 0.00055
            if drawUnlitDistricts {
                context.setStrokeColor(unlitStroke)
                context.setLineWidth(unlitLineWidth)
                for feat in snap.features where feat.mapRect.intersects(queryRect) {
                    let isLit = snap.litKeys.contains(feat.visitedKey) || snap.litKeys.contains(feat.name)
                    if isLit || feat.id == snap.highlightedID { continue }
                    addRings(useDetail ? feat.mapRings : feat.coarseMapRings, to: context)
                }
                context.strokePath()
            }
        }

        context.setFillColor(litFill)
        context.setStrokeColor(litStroke)
        context.setLineWidth(litLineWidth)
        for feat in snap.features where feat.mapRect.intersects(queryRect) {
            if feat.id == snap.highlightedID {
                highlightedFeature = feat
            }
            let isLit = snap.litKeys.contains(feat.visitedKey) || snap.litKeys.contains(feat.name)
            guard isLit else { continue }
            addRings(useDetail ? feat.mapRings : feat.coarseMapRings, to: context)
        }
        context.drawPath(using: .fillStroke)

        if let hl = highlightedFeature {
            let rings = useDetail ? hl.mapRings : hl.coarseMapRings
            context.setFillColor(snap.isDark ? darkHlTint : lightHlTint)
            addRings(rings, to: context)
            context.fillPath()

            context.setStrokeColor(snap.isDark ? darkHlStroke : lightHlStroke)
            context.setLineWidth(hlLineWidth)
            addRings(rings, to: context)
            context.strokePath()
        }

        context.restoreGState()
    }

    private func addRings(_ mapRings: [[MKMapPoint]], to context: CGContext) {
        for ring in mapRings where ring.count >= 3 {
            let first = point(for: ring[0])
            context.move(to: first)
            for i in 1..<ring.count {
                context.addLine(to: point(for: ring[i]))
            }
            context.closePath()
        }
    }
}

// MARK: - Layout-Aware MKMapView (Prevents Cold-Start Bottom Blank Strip)

private final class SafeChinaMapView: MKMapView {
    var pendingInitialRegion: MKCoordinateRegion?
    private var didApplyInitialLayoutRegion = false

    override func layoutSubviews() {
        super.layoutSubviews()
        if !didApplyInitialLayoutRegion, bounds.width > 10, bounds.height > 10, let reg = pendingInitialRegion {
            didApplyInitialLayoutRegion = true
            pendingInitialRegion = nil
            setRegion(reg, animated: false)
        }
    }
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

    func makeUIView(context: Context) -> SafeChinaMapView {
        let map = SafeChinaMapView()
        let config = MKStandardMapConfiguration(elevationStyle: .flat)
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

        map.addOverlay(context.coordinator.canvasOverlay, level: .aboveRoads)

        // 等第一次 layoutSubviews 获得真实非零尺寸后再设置 region，避免冷启动底部出现未渲染空白格
        if let initial = fitRegion {
            map.pendingInitialRegion = initial
            context.coordinator.hasFramedInitialRegion = true
        } else {
            map.pendingInitialRegion = MKCoordinateRegion(
                center: ChinaMapLayoutConfig.fallbackCenter,
                span: MKCoordinateSpan(
                    latitudeDelta: ChinaMapLayoutConfig.fallbackLatDelta,
                    longitudeDelta: ChinaMapLayoutConfig.fallbackLonDelta
                )
            )
        }
        return map
    }

    func updateUIView(_ map: SafeChinaMapView, context: Context) {
        context.coordinator.parent = self

        if !context.coordinator.hasFramedInitialRegion, let target = fitRegion {
            context.coordinator.hasFramedInitialRegion = true
            if map.bounds.width > 10 && map.bounds.height > 10 {
                map.setRegion(target, animated: false)
            } else {
                map.pendingInitialRegion = target
            }
        }

        let snap = ChinaRenderSnapshot(
            features: features,
            litKeys: litKeys,
            highlightedID: highlightedFeatureID,
            level: level,
            isEditing: isEditing,
            isDark: isDark
        )
        context.coordinator.latestSnapshot = snap
        if context.coordinator.lastRevision != renderRevision || context.coordinator.lastIsDark != isDark {
            context.coordinator.lastRevision = renderRevision
            context.coordinator.lastIsDark = isDark
            context.coordinator.canvasRenderer?.update(snap)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ChinaRegionsMKMapView
        let canvasOverlay = ChinaRegionsCanvasOverlay()
        weak var canvasRenderer: ChinaRegionsCanvasRenderer?
        var latestSnapshot = ChinaRenderSnapshot(features: [], litKeys: [], highlightedID: nil, level: .city, isEditing: false, isDark: false)
        var lastRevision = -1
        var lastIsDark = false
        var hasFramedInitialRegion = false

        init(_ parent: ChinaRegionsMKMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is ChinaRegionsCanvasOverlay {
                let r = ChinaRegionsCanvasRenderer(overlay: overlay)
                r.update(latestSnapshot)
                canvasRenderer = r
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
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

// MARK: - 地区管理与可折叠 GitHub 同步面板（复刻原版四标签管理界面）

struct ChinaGitHubSyncSheet: View {
    @EnvironmentObject private var chinaStore: ChinaRegionsStore
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: ChinaRegionsStore.ManageTab
    @State private var searchText = ""
    @State private var newItemText = ""
    @State private var showSyncConfig = false
    @State private var candidatePool: [ChinaGeoFeature] = []

    init(initialLevel: ChinaRegionLevel = .city) {
        switch initialLevel {
        case .district: _selectedTab = State(initialValue: .district)
        case .city: _selectedTab = State(initialValue: .city)
        case .province: _selectedTab = State(initialValue: .province)
        }
    }

    private var allItemsInTab: [String] {
        chinaStore.items(for: selectedTab)
    }

    private var filteredItems: [String] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return allItemsInTab }
        return allItemsInTab.filter { displayName(for: $0).localizedCaseInsensitiveContains(q) || $0.localizedCaseInsensitiveContains(q) }
    }

    private var addSuggestions: [ChinaGeoFeature] {
        let q = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return Array(candidatePool.filter { feat in
            let matchesName = feat.name.localizedCaseInsensitiveContains(q)
            if !matchesName { return false }
            if selectedTab == .municipality {
                return ChinaRegionsStore.municipalityNames.contains(feat.name)
            } else if selectedTab == .province || selectedTab == .city {
                return !ChinaRegionsStore.municipalityNames.contains(feat.name)
            }
            return true
        }.prefix(8))
    }

    private func displayName(for rawKey: String) -> String {
        if let bar = rawKey.firstIndex(of: "|") {
            return String(rawKey[..<bar])
        }
        return rawKey
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部标题栏：📍 地区管理 + ⚙️ 折叠同步配置 + × 关闭
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text("📍")
                        .font(.title3)
                    Text("地区管理")
                        .font(.title3.bold())
                }

                Spacer()

                Button {
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showSyncConfig.toggle()
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "gearshape.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(showSyncConfig ? .white : .primary)
                            .frame(width: 36, height: 36)
                            .background(
                                showSyncConfig ? Color.blue : Color(.tertiarySystemFill),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        if chinaStore.hasUnsyncedChanges && !showSyncConfig {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                                .offset(x: 2, y: -2)
                        }
                    }
                }
                .buttonStyle(.plain)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // 2. 可折叠的 GitHub 同步与足迹匹配配置（默认收起，避免误触拉取和推送）
            if showSyncConfig {
                collapsibleSyncPanel
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // 3. 四大下划线标签栏：区县 / 城市 / 省份 / 直辖市
            HStack(spacing: 0) {
                ForEach(ChinaRegionsStore.ManageTab.allCases) { tab in
                    let active = selectedTab == tab
                    Button {
                        guard selectedTab != tab else { return }
                        Haptics.selection()
                        selectedTab = tab
                        searchText = ""
                        newItemText = ""
                    } label: {
                        VStack(spacing: 8) {
                            Text(tab.title)
                                .font(.subheadline.weight(active ? .semibold : .regular))
                                .foregroundColor(active ? .primary : .secondary)
                            Rectangle()
                                .fill(active ? Color.blue : Color.clear)
                                .frame(height: 2.5)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay(alignment: .bottom) {
                Divider()
            }

            // 4. 搜索栏 + 当前数量角标
            HStack(spacing: 10) {
                TextField("搜索...", text: $searchText)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                    )

                Text("\(filteredItems.count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.blue.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // 5. 已点亮地区卡片列表（右侧红色 × 快速删除）
            ScrollView {
                LazyVStack(spacing: 8) {
                    if filteredItems.isEmpty {
                        Text(searchText.isEmpty ? "暂无已点亮的\(selectedTab.title)" : "没有找到匹配的\(selectedTab.title)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        ForEach(filteredItems, id: \.self) { rawKey in
                            HStack(spacing: 12) {
                                Text(displayName(for: rawKey))
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    Haptics.light()
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        chinaStore.removeItem(rawKey, from: selectedTab)
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(.red)
                                        .frame(width: 34, height: 30)
                                        .background(Color.red.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.leading, 16)
                            .padding(.trailing, 10)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            // 6. 底部添加栏（支持候选补全 + 手动添加）与同步状态条
            VStack(spacing: 10) {
                if !addSuggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(addSuggestions) { feat in
                                Button {
                                    addFeature(feat)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                            .font(.caption2.weight(.bold))
                                        Text(feat.name)
                                            .font(.caption.weight(.medium))
                                    }
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                HStack(spacing: 10) {
                    TextField(selectedTab.placeholder, text: $newItemText)
                        .font(.subheadline)
                        .submitLabel(.done)
                        .onSubmit { addManualInput() }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                        )

                    Button {
                        addManualInput()
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 42)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                }
                .padding(.horizontal, 16)

                // 底部状态按钮：只展开配置，防止误触直接推送
                Button {
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showSyncConfig = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: chinaStore.hasUnsyncedChanges ? "arrow.triangle.2.circlepath" : "checkmark")
                            .font(.subheadline.weight(.semibold))
                        Text(chinaStore.hasUnsyncedChanges ? "有本地改动 · 点此展开 GitHub 同步" : "已是最新")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(chinaStore.hasUnsyncedChanges ? .white : .white.opacity(0.95))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        chinaStore.hasUnsyncedChanges ? Color.blue : Color(.systemGray3),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .padding(.top, 8)
            .background(Color(.systemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .task(id: selectedTab) {
            let tab = selectedTab
            let loaded = await Task.detached(priority: .utility) { () -> [ChinaGeoFeature] in
                switch tab {
                case .district: return ChinaGeoLoader.loadDistricts()
                case .city: return ChinaGeoLoader.loadCities()
                case .province, .municipality: return ChinaGeoLoader.loadProvinces()
                }
            }.value
            candidatePool = loaded
        }
    }

    private var collapsibleSyncPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("GitHub 同步与足迹匹配", systemImage: "icloud.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("收起") {
                    withAnimation(.easeInOut(duration: 0.2)) { showSyncConfig = false }
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.blue)
            }

            Button {
                Task {
                    let added = await chinaStore.autoMatch(stays: store.stays, includeDistricts: true)
                    chinaStore.syncMessage = "从足迹新增：\(added.provinces) 省 · \(added.cities) 市 · \(added.districts) 区县"
                }
            } label: {
                HStack {
                    Label("从漫迹足迹自动匹配点亮", systemImage: "sparkles")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if chinaStore.isAutoMatching { ProgressView().scaleEffect(0.85) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(chinaStore.isAutoMatching)

            VStack(spacing: 8) {
                TextField("仓库（用户名/仓库名）", text: $chinaStore.ghRepo)
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                TextField("分支（默认 main）", text: $chinaStore.ghBranch)
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                SecureField("GitHub Personal Access Token", text: $chinaStore.ghToken)
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 10) {
                Button {
                    Task { await chinaStore.pullFromGitHub() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("从 GitHub 拉取")
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(chinaStore.isSyncing || !chinaStore.isGitHubConfigured)
                .opacity((chinaStore.isSyncing || !chinaStore.isGitHubConfigured) ? 0.45 : 1)

                Button {
                    Task { await chinaStore.pushToGitHub() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("推送到 GitHub")
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(chinaStore.isSyncing || !chinaStore.isGitHubConfigured)
                .opacity((chinaStore.isSyncing || !chinaStore.isGitHubConfigured) ? 0.45 : 1)
            }

            if chinaStore.isSyncing {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.8)
                    Text("正在与 GitHub 通信…").font(.caption).foregroundColor(.secondary)
                }
            }
            if let msg = chinaStore.syncMessage {
                Text(msg).font(.caption).foregroundColor(.green)
            }
            if let err = chinaStore.syncError {
                Text(err).font(.caption).foregroundColor(.red)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func addFeature(_ feat: ChinaGeoFeature) {
        Haptics.light()
        let key = selectedTab == .district ? feat.visitedKey : feat.name
        chinaStore.addItem(key, to: selectedTab)
        newItemText = ""
    }

    private func addManualInput() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Haptics.light()
        if selectedTab == .district,
           let matched = candidatePool.first(where: { $0.name == trimmed }) {
            chinaStore.addItem(matched.visitedKey, to: .district)
        } else {
            chinaStore.addItem(trimmed, to: selectedTab)
        }
        newItemText = ""
    }
}
