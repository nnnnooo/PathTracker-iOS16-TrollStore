import SwiftUI
import MapKit

struct MustSeeView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var engine: LocationEngine
    @ObservedObject private var userStore = MustSeeUserStore.shared

    @State private var listType: MustSee.ListType = .china
    @State private var filter = 0 // 0=全部, 1=已点亮, 2=未点亮, 3=想去
    @State private var selectedPlace: MustSeePlace?
    @State private var visitedMap: [String: Date] = [:]
    @State private var isLoading = true

    private var places: [MustSeePlace] { listType.places }
    private var visitedCount: Int { visitedMap.count }

    private var filteredPlaces: [MustSeePlace] {
        switch filter {
        case 1: return places.filter { visitedMap[$0.id] != nil }
        case 2: return places.filter { visitedMap[$0.id] == nil }
        case 3: return places.filter { userStore.wishIDs.contains($0.id) }
        default: return places
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("清单", selection: $listType) {
                    ForEach(MustSee.ListType.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                MustSeeStarMap(places: places, visitedIDs: Set(visitedMap.keys))
                    .frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                progressGridCard

                Picker("筛选", selection: $filter) {
                    Text("全部").tag(0)
                    Text("已点亮 (\(visitedCount))").tag(1)
                    Text("未点亮").tag(2)
                    Text("想去").tag(3)
                }
                .pickerStyle(.segmented)

                if isLoading {
                    ProgressView("正在匹配足迹…")
                        .padding(.vertical, 24)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredPlaces) { place in
                            Button {
                                selectedPlace = place
                            } label: {
                                placeRow(place)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("此生必去")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(listType.rawValue)-\(store.stays.count)-\(userStore.manualVisits.count)") {
            let currentPlaces = listType.places
            let staysSnapshot = store.stays
            let manualSnapshot = userStore.manualVisits
            let computed = await Task.detached(priority: .userInitiated) {
                MustSee.visitedMap(places: currentPlaces, stays: staysSnapshot, manual: manualSnapshot)
            }.value
            visitedMap = computed
            isLoading = false
        }
        .sheet(item: $selectedPlace) { place in
            MustSeeDetailSheet(
                place: place,
                visitedDate: visitedMap[place.id],
                userLocation: engine.currentLocation
            )
        }
    }

    private var progressGridCard: some View {
        let tagline: String = {
            switch visitedCount {
            case 0: return "第一盏灯，等你去点亮"
            case 1..<10: return "旅途刚刚开始，前面还有大片风景"
            case 10..<30: return "已经走过不少名山大川与古城"
            case 30..<60: return "大半张地图都留下了你的脚印"
            case 60..<100: return "离集齐一百处越来越近了"
            default: return "一百处，你都去过了！"
            }
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("已点亮 \(visitedCount) / \(places.count)")
                    .font(.headline)
                Spacer()
                Text(tagline)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 20), spacing: 3) {
                ForEach(places) { place in
                    let lit = visitedMap[place.id] != nil
                    let wished = userStore.wishIDs.contains(place.id)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(lit ? Color.orange : (wished ? Color.pink.opacity(0.45) : Color(.tertiarySystemFill)))
                        .frame(height: 11)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func placeRow(_ place: MustSeePlace) -> some View {
        let litDate = visitedMap[place.id]
        let wished = userStore.wishIDs.contains(place.id)
        return HStack(spacing: 12) {
            Image(systemName: place.kind.symbol)
                .font(.subheadline)
                .foregroundColor(litDate != nil ? .white : .secondary)
                .frame(width: 34, height: 34)
                .background(litDate != nil ? Color.orange : Color(.tertiarySystemFill), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(place.name).font(.subheadline.weight(.semibold))
                    if wished {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundColor(.pink)
                    }
                }
                Text("\(place.region) · \(place.kind.title)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let date = litDate {
                Text(Formatters.dayTitle(date))
                    .font(.caption2)
                    .foregroundColor(.orange)
            } else if let loc = engine.currentLocation {
                let km = place.location.distance(from: loc) / 1000.0
                Text(km < 1000 ? "\(Int(km.rounded())) km" : String(format: "%.0f km", km))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MustSeeDetailSheet: View {
    @ObservedObject private var userStore = MustSeeUserStore.shared
    @Environment(\.dismiss) private var dismiss

    let place: MustSeePlace
    let visitedDate: Date?
    let userLocation: CLLocation?

    var body: some View {
        let isWished = userStore.wishIDs.contains(place.id)
        let isManuallyLit = userStore.manualVisits[place.id] != nil

        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: place.kind.symbol)
                    .font(.system(size: 44))
                    .foregroundColor(visitedDate != nil ? .orange : .secondary)
                    .frame(width: 84, height: 84)
                    .background((visitedDate != nil ? Color.orange.opacity(0.15) : Color(.tertiarySystemFill)), in: Circle())
                    .padding(.top, 16)

                VStack(spacing: 6) {
                    Text(place.name).font(.title2.bold())
                    Text("\(place.region) · \(place.nameEn)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 16) {
                    Label(place.kind.title, systemImage: place.kind.symbol)
                    if let loc = userLocation {
                        let km = place.location.distance(from: loc) / 1000.0
                        Label(String(format: "距你 %.0f km", km), systemImage: "location.fill")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)

                if let date = visitedDate {
                    Text("已于 \(Formatters.dayTitle(date)) 点亮")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                }

                Spacer()

                VStack(spacing: 10) {
                    Button {
                        userStore.toggleWish(place.id)
                    } label: {
                        Label(isWished ? "已加入想去清单" : "加入想去清单", systemImage: isWished ? "heart.fill" : "heart")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.pink)

                    Button {
                        userStore.toggleManualVisit(place.id)
                    } label: {
                        Label(isManuallyLit ? "取消手动点亮" : "我去过这里（手动点亮）", systemImage: isManuallyLit ? "checkmark.circle.fill" : "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Button {
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate.onMap))
                        item.name = place.name
                        item.openInMaps()
                    } label: {
                        Label("在 Apple 地图中打开", systemImage: "map")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private final class MustSeeAnnotation: NSObject, MKAnnotation {
    let place: MustSeePlace
    let lit: Bool
    let coordinate: CLLocationCoordinate2D
    var title: String? { place.name }
    var subtitle: String? { place.region }

    init(place: MustSeePlace, lit: Bool) {
        self.place = place
        self.lit = lit
        self.coordinate = place.coordinate.onMap
    }
}

private struct MustSeeStarMap: UIViewRepresentable {
    let places: [MustSeePlace]
    let visitedIDs: Set<String>

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let sig = "\(places.first?.id ?? "")|\(visitedIDs.count)"
        guard context.coordinator.lastSig != sig else { return }
        context.coordinator.lastSig = sig

        map.removeAnnotations(map.annotations)
        var rect = MKMapRect.null
        for place in places {
            let ann = MustSeeAnnotation(place: place, lit: visitedIDs.contains(place.id))
            map.addAnnotation(ann)
            let pt = MKMapPoint(ann.coordinate)
            rect = rect.union(MKMapRect(x: pt.x - 50_000, y: pt.y - 50_000, width: 100_000, height: 100_000))
        }
        if !rect.isNull {
            let padded = map.mapRectThatFits(rect, edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24))
            map.setVisibleMapRect(padded, animated: false)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var lastSig = ""

        private lazy var litImage: UIImage = {
            let size: CGFloat = 14
            return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
                UIColor.systemOrange.withAlphaComponent(0.35).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
                UIColor.systemYellow.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 3.5, y: 3.5, width: size - 7, height: size - 7))
            }
        }()

        private lazy var dimImage: UIImage = {
            let size: CGFloat = 7
            return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
                UIColor.white.withAlphaComponent(0.32).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
            }
        }()

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let ann = annotation as? MustSeeAnnotation else { return nil }
            let id = ann.lit ? "starLit" : "starDim"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: ann, reuseIdentifier: id)
            view.annotation = ann
            view.canShowCallout = true
            view.image = ann.lit ? litImage : dimImage
            return view
        }
    }
}
