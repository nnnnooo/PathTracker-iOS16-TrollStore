import Foundation

enum GPXExporter {
    static func export(chunks: [TrackChunk], stays: [Stay]) -> URL? {
        let iso = ISO8601DateFormatter()
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Waytrace16" xmlns="http://www.topografix.com/GPX/1/1">
        """

        for stay in stays {
            let name = escape(stay.displayName)
            let time = iso.string(from: stay.arrival)
            xml += "\n  <wpt lat=\"\(stay.latitude)\" lon=\"\(stay.longitude)\"><time>\(time)</time><name>\(name)</name></wpt>"
        }

        for chunk in chunks {
            let pts = chunk.points
            guard !pts.isEmpty else { continue }
            xml += "\n  <trk><name>\(escape(chunk.mode.title))</name><trkseg>"
            for p in pts {
                xml += "\n    <trkpt lat=\"\(p.latitude)\" lon=\"\(p.longitude)\"><ele>\(p.altitude)</ele><time>\(iso.string(from: p.timestamp))</time></trkpt>"
            }
            xml += "\n  </trkseg></trk>"
        }

        xml += "\n</gpx>\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Waytrace-Export.gpx")
        do {
            try xml.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
