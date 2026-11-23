import Foundation
import CoreLocation

enum GPXImporter {
    struct Summary: Equatable {
        var addedChunks = 0
        var addedStays = 0
        var skippedDuplicates = 0
    }

    @MainActor
    static func importFile(at url: URL, into store: DataStore) -> Summary {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return Summary() }

        let delegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()

        var summary = Summary()

        for segment in delegate.trackSegments where segment.count >= 2 {
            let start = segment.first!.timestamp
            let end = segment.last!.timestamp
            let isDuplicate = store.chunks.contains { existing in
                let overlapStart = max(existing.startDate, start)
                let overlapEnd = min(existing.endDate, end)
                let overlap = overlapEnd.timeIntervalSince(overlapStart)
                let dur = max(1, end.timeIntervalSince(start))
                return overlap / dur > 0.8
            }
            if isDuplicate {
                summary.skippedDuplicates += 1
                continue
            }
            let mode = MotionClassifier.mode(forSpeeds: segment.map(\.speed))
            let chunk = TrackChunk(points: segment, mode: mode)
            store.insertChunk(chunk)
            summary.addedChunks += 1
        }

        var newStays: [Stay] = []
        for wpt in delegate.waypoints {
            let loc = CLLocation(latitude: wpt.lat, longitude: wpt.lon)
            let dup = store.stays.contains { existing in
                abs(existing.arrival.timeIntervalSince(wpt.time)) < 300 && existing.location.distance(from: loc) < 100
            }
            if dup {
                summary.skippedDuplicates += 1
                continue
            }
            var stay = Stay(arrival: wpt.time, departure: wpt.time.addingTimeInterval(300), coordinate: loc.coordinate)
            stay.customName = wpt.name
            newStays.append(stay)
            summary.addedStays += 1
        }
        store.insertStaysBatch(newStays)
        return summary
    }
}

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    struct RawWaypoint {
        var lat: Double
        var lon: Double
        var name: String?
        var time: Date
    }

    var trackSegments: [[TrackPoint]] = []
    var waypoints: [RawWaypoint] = []

    private var currentSegment: [TrackPoint] = []
    private var inTrkpt = false
    private var inWpt = false
    private var currentLat: Double = 0
    private var currentLon: Double = 0
    private var currentEle: Double = 0
    private var currentTime: Date?
    private var currentName: String?
    private var textBuffer = ""

    private let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoStandard = ISO8601DateFormatter()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        textBuffer = ""
        switch elementName {
        case "trkseg":
            currentSegment = []
        case "trkpt":
            inTrkpt = true
            currentLat = Double(attributeDict["lat"] ?? "") ?? 0
            currentLon = Double(attributeDict["lon"] ?? "") ?? 0
            currentEle = 0
            currentTime = nil
        case "wpt":
            inWpt = true
            currentLat = Double(attributeDict["lat"] ?? "") ?? 0
            currentLon = Double(attributeDict["lon"] ?? "") ?? 0
            currentTime = nil
            currentName = nil
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "ele":
            if inTrkpt { currentEle = Double(trimmed) ?? 0 }
        case "time":
            let d = isoFractional.date(from: trimmed) ?? isoStandard.date(from: trimmed)
            currentTime = d
        case "name":
            if inWpt { currentName = trimmed.nilIfEmpty }
        case "trkpt":
            if inTrkpt {
                let ts = currentTime ?? currentSegment.last?.timestamp.addingTimeInterval(5) ?? Date()
                var speed = 0.0
                if let prev = currentSegment.last {
                    let dt = ts.timeIntervalSince(prev.timestamp)
                    if dt > 0 {
                        let dist = CLLocation(latitude: currentLat, longitude: currentLon).distance(from: prev.location)
                        speed = dist / dt
                    }
                }
                currentSegment.append(TrackPoint(latitude: currentLat, longitude: currentLon, altitude: currentEle, speed: speed, accuracy: 10, timestamp: ts))
                inTrkpt = false
            }
        case "trkseg":
            if currentSegment.count >= 2 { trackSegments.append(currentSegment) }
            currentSegment = []
        case "wpt":
            if inWpt {
                waypoints.append(RawWaypoint(lat: currentLat, lon: currentLon, name: currentName, time: currentTime ?? Date()))
                inWpt = false
            }
        default:
            break
        }
    }
}
