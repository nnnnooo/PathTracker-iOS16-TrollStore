import SwiftUI
import MapKit

final class StyledPolyline: MKPolyline {
    var color: UIColor = .systemBlue
    var isDashed: Bool = false
    var lineWidth: CGFloat = 4
}

final class StayAnnotation: NSObject, MKAnnotation {
    let stay: Stay
    let coordinate: CLLocationCoordinate2D
    var title: String? { stay.displayName }
    var subtitle: String? { stay.subtitle }

    init(stay: Stay) {
        self.stay = stay
        self.coordinate = stay.coordinate.onMap
    }
}

struct DayRouteMapView: UIViewRepresentable {
    let chunks: [TrackChunk]
    let pendingPoints: [TrackPoint]
    let stays: [Stay]
    let currentLocation: CLLocation?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        let config = MKStandardMapConfiguration(elevationStyle: .realistic)
        config.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = config
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = true
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let locKey = currentLocation.map { String(format: "%.3f,%.3f", $0.coordinate.latitude, $0.coordinate.longitude) } ?? "none"
        let signature = "\(chunks.map(\.id.uuidString).joined())|\(pendingPoints.count)|\(stays.map(\.id.uuidString).joined())|\(locKey)"
        guard context.coordinator.lastSignature != signature else { return }
        context.coordinator.lastSignature = signature

        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })

        var allCoords: [CLLocationCoordinate2D] = []
        var lastTrackCoord: CLLocationCoordinate2D?

        for chunk in chunks {
            let pts = chunk.points
            guard pts.count >= 2 else { continue }
            var coords = pts.map { $0.coordinate.onMap }
            let poly = StyledPolyline(coordinates: &coords, count: coords.count)
            poly.color = chunk.mode.uiColor
            poly.isDashed = (chunk.mode == .subway || chunk.mode == .flying)
            poly.lineWidth = chunk.mode == .flying ? 2.5 : 4.5
            map.addOverlay(poly)
            allCoords.append(contentsOf: coords)
            lastTrackCoord = coords.last
        }

        if pendingPoints.count >= 2 {
            var coords = pendingPoints.map { $0.coordinate.onMap }
            let poly = StyledPolyline(coordinates: &coords, count: coords.count)
            poly.color = .systemBlue
            poly.lineWidth = 4.5
            map.addOverlay(poly)
            allCoords.append(contentsOf: coords)
            lastTrackCoord = coords.last
        } else if let pending = pendingPoints.last {
            let pt = pending.coordinate.onMap
            allCoords.append(pt)
            if let prev = lastTrackCoord {
                var bridge = [prev, pt]
                let poly = StyledPolyline(coordinates: &bridge, count: 2)
                poly.color = UIColor.systemBlue.withAlphaComponent(0.6)
                poly.isDashed = true
                poly.lineWidth = 3.0
                map.addOverlay(poly)
            }
            lastTrackCoord = pt
        }

        // Visually bridge small live GPS gap (<= 2.5 km) to user's current blue dot
        if let loc = currentLocation {
            let liveCoord = loc.coordinate.onMap
            allCoords.append(liveCoord)
            if let last = lastTrackCoord {
                let d = CLLocation(latitude: last.latitude, longitude: last.longitude)
                    .distance(from: CLLocation(latitude: liveCoord.latitude, longitude: liveCoord.longitude))
                if d > 30 && d < 2_500 {
                    var bridge = [last, liveCoord]
                    let poly = StyledPolyline(coordinates: &bridge, count: 2)
                    poly.color = UIColor.systemBlue.withAlphaComponent(0.55)
                    poly.isDashed = true
                    poly.lineWidth = 3.0
                    map.addOverlay(poly)
                }
            }
        }

        for stay in stays {
            let ann = StayAnnotation(stay: stay)
            map.addAnnotation(ann)
            allCoords.append(ann.coordinate)
        }

        // Explicit padded MKCoordinateRegion (avoids iOS 16 bounds==.zero edgePadding bug that clips top/bottom pins)
        if !allCoords.isEmpty {
            let lats = allCoords.map(\.latitude)
            let lons = allCoords.map(\.longitude)
            let minLat = lats.min()!, maxLat = lats.max()!
            let minLon = lons.min()!, maxLon = lons.max()!
            let latDelta = max(0.008, (maxLat - minLat) * 1.55)
            let lonDelta = max(0.008, (maxLon - minLon) * 1.55)
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2.0, longitude: (minLon + maxLon) / 2.0),
                span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
            )
            map.setRegion(region, animated: false)
        } else if let loc = currentLocation {
            let region = MKCoordinateRegion(center: loc.coordinate.onMap, latitudinalMeters: 2000, longitudinalMeters: 2000)
            map.setRegion(region, animated: false)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var lastSignature: String = ""

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let poly = overlay as? StyledPolyline {
                let renderer = MKPolylineRenderer(polyline: poly)
                renderer.strokeColor = poly.color
                renderer.lineWidth = poly.lineWidth
                renderer.lineCap = .round
                renderer.lineJoin = .round
                if poly.isDashed { renderer.lineDashPattern = [6, 6] }
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let stayAnn = annotation as? StayAnnotation else { return nil }
            let id = "stayPin"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: stayAnn, reuseIdentifier: id)
            view.annotation = stayAnn
            view.markerTintColor = UIColor(stayAnn.stay.category.tint)
            view.glyphImage = UIImage(systemName: stayAnn.stay.category.symbol)
            view.canShowCallout = true
            return view
        }
    }
}

struct WorldFootprintMapView: UIViewRepresentable {
    let stays: [Stay]
    let chunks: [TrackChunk]
    let showRoutes: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        map.mapType = .mutedStandard
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let sig = "\(stays.count)|\(chunks.count)|\(showRoutes)"
        guard context.coordinator.lastSignature != sig else { return }
        context.coordinator.lastSignature = sig

        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)

        var coords: [CLLocationCoordinate2D] = []

        if showRoutes {
            for chunk in chunks {
                let pts = chunk.points.simplified(tolerance: 30)
                guard pts.count >= 2 else { continue }
                var line = pts.map { $0.coordinate.onMap }
                let poly = StyledPolyline(coordinates: &line, count: line.count)
                poly.color = chunk.mode.uiColor.withAlphaComponent(0.75)
                poly.isDashed = (chunk.mode == .flying)
                poly.lineWidth = 2.5
                map.addOverlay(poly)
                if let first = line.first { coords.append(first) }
                if let last = line.last { coords.append(last) }
            }
        } else {
            var buckets: [String: Stay] = [:]
            for stay in stays {
                let key = "\(Int((stay.latitude * 12).rounded()))_\(Int((stay.longitude * 12).rounded()))"
                if buckets[key] == nil { buckets[key] = stay }
            }
            for stay in buckets.values.prefix(500) {
                let ann = StayAnnotation(stay: stay)
                map.addAnnotation(ann)
                coords.append(ann.coordinate)
            }
        }

        if !coords.isEmpty {
            let lats = coords.map(\.latitude).sorted()
            let lons = coords.map(\.longitude).sorted()
            let rawLonSpan = lons.last! - lons.first!
            if rawLonSpan > 150 {
                // Intercontinental footprints (e.g. China + Canada): center on the densest cluster (median) so highlights fill the card
                let medLat = lats[lats.count / 2]
                let medLon = lons[lons.count / 2]
                let localCoords = coords.filter { abs($0.longitude - medLon) < 60 }
                let localLats = localCoords.map(\.latitude)
                let localLons = localCoords.map(\.longitude)
                let minLat = localLats.min() ?? medLat - 15
                let maxLat = localLats.max() ?? medLat + 15
                let minLon = localLons.min() ?? medLon - 20
                let maxLon = localLons.max() ?? medLon + 20
                let region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                    span: MKCoordinateSpan(
                        latitudeDelta: min(75, max(24, (maxLat - minLat) * 1.45)),
                        longitudeDelta: min(95, max(30, (maxLon - minLon) * 1.45))
                    )
                )
                map.setRegion(region, animated: false)
            } else {
                let region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: (lats.first! + lats.last!) / 2, longitude: (lons.first! + lons.last!) / 2),
                    span: MKCoordinateSpan(
                        latitudeDelta: min(120, max(12, (lats.last! - lats.first!) * 1.45)),
                        longitudeDelta: min(180, max(16, rawLonSpan * 1.45))
                    )
                )
                map.setRegion(region, animated: false)
            }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var lastSignature = ""

        private lazy var glowDotImage: UIImage = {
            let size: CGFloat = 20
            return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
                let colors = [
                    UIColor.systemOrange.withAlphaComponent(0.70).cgColor,
                    UIColor.systemOrange.withAlphaComponent(0.0).cgColor
                ] as CFArray
                if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
                    ctx.cgContext.drawRadialGradient(
                        grad,
                        startCenter: CGPoint(x: 10, y: 10), startRadius: 1,
                        endCenter: CGPoint(x: 10, y: 10), endRadius: 10,
                        options: []
                    )
                }
                UIColor(red: 1.0, green: 0.94, blue: 0.68, alpha: 1.0).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 6.5, y: 6.5, width: 7, height: 7))
            }
        }()

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let poly = overlay as? StyledPolyline {
                let r = MKPolylineRenderer(polyline: poly)
                r.strokeColor = poly.color
                r.lineWidth = poly.lineWidth
                if poly.isDashed { r.lineDashPattern = [5, 5] }
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let stayAnn = annotation as? StayAnnotation else { return nil }
            let id = "worldDot"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: stayAnn, reuseIdentifier: id)
            view.annotation = stayAnn
            view.canShowCallout = true
            view.image = glowDotImage
            view.displayPriority = .required
            return view
        }
    }
}
