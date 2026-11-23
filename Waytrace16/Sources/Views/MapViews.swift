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
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = true
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let signature = "\(chunks.map(\.id.uuidString).joined())|\(pendingPoints.count)|\(stays.map(\.id.uuidString).joined())"
        guard context.coordinator.lastSignature != signature else { return }
        context.coordinator.lastSignature = signature

        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })

        var rect = MKMapRect.null

        for chunk in chunks {
            let pts = chunk.points
            guard pts.count >= 2 else { continue }
            var coords = pts.map { $0.coordinate.onMap }
            let poly = StyledPolyline(coordinates: &coords, count: coords.count)
            poly.color = chunk.mode.uiColor
            poly.isDashed = (chunk.mode == .subway || chunk.mode == .flying)
            poly.lineWidth = chunk.mode == .flying ? 2.5 : 4.5
            map.addOverlay(poly)
            rect = rect.union(poly.boundingMapRect)
        }

        if pendingPoints.count >= 2 {
            var coords = pendingPoints.map { $0.coordinate.onMap }
            let poly = StyledPolyline(coordinates: &coords, count: coords.count)
            poly.color = .systemBlue
            poly.lineWidth = 4.5
            map.addOverlay(poly)
            rect = rect.union(poly.boundingMapRect)
        }

        for stay in stays {
            let ann = StayAnnotation(stay: stay)
            map.addAnnotation(ann)
            let pt = MKMapPoint(ann.coordinate)
            rect = rect.union(MKMapRect(x: pt.x - 1000, y: pt.y - 1000, width: 2000, height: 2000))
        }

        if !rect.isNull {
            let padded = map.mapRectThatFits(rect, edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40))
            map.setVisibleMapRect(padded, animated: false)
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
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let sig = "\(stays.count)|\(chunks.count)|\(showRoutes)"
        guard context.coordinator.lastSignature != sig else { return }
        context.coordinator.lastSignature = sig

        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)

        var rect = MKMapRect.null

        if showRoutes {
            for chunk in chunks {
                let pts = chunk.points.simplified(tolerance: 30)
                guard pts.count >= 2 else { continue }
                var coords = pts.map { $0.coordinate.onMap }
                let poly = StyledPolyline(coordinates: &coords, count: coords.count)
                poly.color = chunk.mode.uiColor.withAlphaComponent(0.75)
                poly.isDashed = (chunk.mode == .flying)
                poly.lineWidth = 2.5
                map.addOverlay(poly)
                rect = rect.union(poly.boundingMapRect)
            }
        } else {
            var buckets: [String: Stay] = [:]
            for stay in stays {
                let key = "\(Int((stay.latitude * 20).rounded()))_\(Int((stay.longitude * 20).rounded()))"
                if buckets[key] == nil { buckets[key] = stay }
            }
            for stay in buckets.values.prefix(500) {
                let ann = StayAnnotation(stay: stay)
                map.addAnnotation(ann)
                let pt = MKMapPoint(ann.coordinate)
                rect = rect.union(MKMapRect(x: pt.x - 10_000, y: pt.y - 10_000, width: 20_000, height: 20_000))
            }
        }

        if !rect.isNull {
            let padded = map.mapRectThatFits(rect, edgePadding: UIEdgeInsets(top: 36, left: 36, bottom: 36, right: 36))
            map.setVisibleMapRect(padded, animated: false)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var lastSignature = ""

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
            let size: CGFloat = 12
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            view.image = renderer.image { ctx in
                UIColor.systemOrange.withAlphaComponent(0.35).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
                UIColor.systemYellow.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 3, y: 3, width: size - 6, height: size - 6))
            }
            return view
        }
    }
}
