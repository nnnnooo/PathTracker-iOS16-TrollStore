import SwiftUI
import CoreLocation

/// Renders clean, shareable PNG summary cards using iOS 16's native ImageRenderer.
@MainActor
enum ShareCardGenerator {
    static func renderDayCard(
        title: String,
        subtitle: String,
        distance: Double,
        stayCount: Int,
        cities: [String],
        chunks: [TrackChunk],
        privacyZones: [PrivacyZone]
    ) -> URL? {
        let safePoints = chunks.flatMap(\.points).filter { pt in
            !privacyZones.contains { $0.contains(pt.coordinate) }
        }
        let view = ShareCardView(
            badge: "漫迹 · 今日足迹",
            title: title,
            subtitle: subtitle,
            distanceText: Formatters.distance(distance),
            secondaryLabel: "停留地点",
            secondaryValue: "\(stayCount) 处",
            cities: cities,
            points: safePoints
        )
        return renderToPNG(view: view, filename: "Waytrace-Day-Card.png")
    }

    static func renderTripCard(
        trip: Trip,
        distance: Double,
        stays: [Stay],
        chunks: [TrackChunk],
        privacyZones: [PrivacyZone]
    ) -> URL? {
        let safePoints = chunks.flatMap(\.points).filter { pt in
            !privacyZones.contains { $0.contains(pt.coordinate) }
        }
        let cities = stays.compactMap(\.city).removingDuplicates()
        let view = ShareCardView(
            badge: trip.isRecording ? "漫迹 · 运动记录" : "漫迹 · 旅程明信片",
            title: trip.title,
            subtitle: trip.dateRangeText,
            distanceText: Formatters.distance(distance),
            secondaryLabel: trip.isRecording ? "平均配速" : "经过地点",
            secondaryValue: trip.isRecording ? Formatters.pace(distance: distance, duration: trip.duration) : "\(stays.count) 处",
            cities: cities,
            points: safePoints
        )
        return renderToPNG(view: view, filename: "Waytrace-Trip-Card.png")
    }

    private static func renderToPNG<V: View>(view: V, filename: String) -> URL? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3.0
        guard let uiImage = renderer.uiImage, let data = uiImage.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

private struct ShareCardView: View {
    let badge: String
    let title: String
    let subtitle: String
    let distanceText: String
    let secondaryLabel: String
    let secondaryValue: String
    let cities: [String]
    let points: [TrackPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.orange)
                Spacer()
                Text("WAYTRACE 16")
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundColor(.white.opacity(0.45))
            }

            // Route Sketch Canvas
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                if points.count >= 2 {
                    RouteSketchCanvas(points: points)
                        .padding(20)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "map.fill")
                            .font(.largeTitle)
                            .foregroundColor(.white.opacity(0.3))
                        Text("足迹印记")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }
            .frame(height: 190)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
            }

            if !cities.isEmpty {
                Text(cities.prefix(5).joined(separator: " · "))
                    .font(.caption)
                    .foregroundColor(.orange.opacity(0.9))
            }

            Divider().background(Color.white.opacity(0.15))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(distanceText).font(.title3.bold()).foregroundColor(.white)
                    Text("移动里程").font(.caption2).foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(secondaryValue).font(.title3.bold()).foregroundColor(.white)
                    Text(secondaryLabel).font(.caption2).foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.10, blue: 0.16), Color(red: 0.14, green: 0.12, blue: 0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct RouteSketchCanvas: View {
    let points: [TrackPoint]

    var body: some View {
        Canvas { context, size in
            let simplified = points.simplified(tolerance: 25)
            guard simplified.count >= 2 else { return }
            let lats = simplified.map(\.latitude)
            let lons = simplified.map(\.longitude)
            guard let minLat = lats.min(), let maxLat = lats.max(),
                  let minLon = lons.min(), let maxLon = lons.max() else { return }
            let latSpan = max(0.0005, maxLat - minLat)
            let lonSpan = max(0.0005, maxLon - minLon)
            let scale = min(size.width / lonSpan, size.height / latSpan)
            let offsetX = (size.width - lonSpan * scale) / 2
            let offsetY = (size.height - latSpan * scale) / 2

            var path = Path()
            for (idx, pt) in simplified.enumerated() {
                let x = (pt.longitude - minLon) * scale + offsetX
                let y = size.height - ((pt.latitude - minLat) * scale + offsetY)
                if idx == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [.orange, .yellow, .pink]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)
                ),
                style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
            )
        }
    }
}
