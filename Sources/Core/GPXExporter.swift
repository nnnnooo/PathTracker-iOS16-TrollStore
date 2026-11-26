import Foundation

enum GPXExporter {
    static func export(
        chunks: [TrackChunk],
        stays: [Stay],
        privacyZones: [PrivacyZone] = [],
        filename: String = "Waytrace-Export.gpx"
    ) -> URL? {
        let iso = ISO8601DateFormatter()
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Waytrace16" xmlns="http://www.topografix.com/GPX/1/1">
        """

        for stay in stays {
            if privacyZones.contains(where: { $0.contains(stay.coordinate) }) { continue }
            let name = escape(stay.displayName)
            let time = iso.string(from: stay.arrival)
            xml += "\n  <wpt lat=\"\(stay.latitude)\" lon=\"\(stay.longitude)\"><time>\(time)</time><name>\(name)</name></wpt>"
        }

        for chunk in chunks {
            let segments = splitByPrivacy(points: chunk.points, privacyZones: privacyZones)
            for seg in segments where seg.count >= 2 {
                xml += "\n  <trk><name>\(escape(chunk.mode.title))</name><trkseg>"
                for p in seg {
                    xml += "\n    <trkpt lat=\"\(p.latitude)\" lon=\"\(p.longitude)\"><ele>\(p.altitude)</ele><time>\(iso.string(from: p.timestamp))</time></trkpt>"
                }
                xml += "\n  </trkseg></trk>"
            }
        }

        xml += "\n</gpx>\n"
        let safeName = filename.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
        do {
            try xml.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func splitByPrivacy(points: [TrackPoint], privacyZones: [PrivacyZone]) -> [[TrackPoint]] {
        guard !privacyZones.isEmpty else { return [points] }
        var segments: [[TrackPoint]] = []
        var current: [TrackPoint] = []
        for p in points {
            if privacyZones.contains(where: { $0.contains(p.coordinate) }) {
                if current.count >= 2 { segments.append(current) }
                current = []
            } else {
                current.append(p)
            }
        }
        if current.count >= 2 { segments.append(current) }
        return segments
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
