import Foundation
import CoreLocation

enum GPXImporter {
    struct Summary: Equatable, Sendable {
        var addedChunks = 0
        var addedStays = 0
        var skippedDuplicates = 0
        var errorMessage: String?
    }

    struct ParsedFile: Sendable {
        var segments: [[TrackPoint]]
        var waypoints: [RawWaypoint]
        var errorMessage: String?
    }

    struct RawWaypoint: Sendable {
        var lat: Double
        var lon: Double
        var name: String?
        var time: Date
    }

    /// Reads and parses a GPX file off the main thread, using NSFileCoordinator so iCloud Drive files download reliably.
    nonisolated static func parseFile(at url: URL) -> ParsedFile {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        var fileData: Data?
        var coordError: NSError?
        var readError: Error?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordError) { safeURL in
            do {
                fileData = try Data(contentsOf: safeURL)
            } catch {
                readError = error
            }
        }

        guard let data = fileData else {
            let reason = readError?.localizedDescription ?? coordError?.localizedDescription ?? "无法读取文件内容"
            return ParsedFile(segments: [], waypoints: [], errorMessage: reason)
        }
        guard !data.isEmpty else {
            return ParsedFile(segments: [], waypoints: [], errorMessage: "文件为空")
        }

        let delegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        let ok = parser.parse()

        if !ok && delegate.trackSegments.isEmpty && delegate.waypoints.isEmpty {
            let err = parser.parserError?.localizedDescription ?? "GPX XML 格式解析失败"
            return ParsedFile(segments: [], waypoints: [], errorMessage: err)
        }

        return ParsedFile(segments: delegate.trackSegments, waypoints: delegate.waypoints, errorMessage: nil)
    }

    @MainActor
    static func importFiles(at urls: [URL], into store: DataStore) async -> Summary {
        let parsedList = await Task.detached(priority: .userInitiated) {
            urls.map { parseFile(at: $0) }
        }.value

        var summary = Summary()
        var firstError: String?

        for parsed in parsedList {
            if let err = parsed.errorMessage, firstError == nil {
                firstError = err
            }

            for segment in parsed.segments where segment.count >= 2 {
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
            for wpt in parsed.waypoints {
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
            if !newStays.isEmpty {
                store.insertStaysBatch(newStays)
            }
        }

        if summary.addedChunks == 0 && summary.addedStays == 0 && summary.skippedDuplicates == 0 {
            summary.errorMessage = firstError ?? "未在文件中找到有效的轨迹点（<trkpt>/<rtept>）或路点（<wpt>）。"
        }
        return summary
    }
}

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    var trackSegments: [[TrackPoint]] = []
    var waypoints: [GPXImporter.RawWaypoint] = []

    private var currentSegment: [TrackPoint] = []
    private var inPoint = false
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
    private let isoStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private let fallbackFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        textBuffer = ""
        let tag = elementName.lowercased()
        switch tag {
        case "trkseg", "rte":
            currentSegment = []
        case "trkpt", "rtept":
            inPoint = true
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
        let tag = elementName.lowercased()
        let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch tag {
        case "ele":
            if inPoint { currentEle = Double(trimmed) ?? 0 }
        case "time":
            currentTime = isoFractional.date(from: trimmed)
                ?? isoStandard.date(from: trimmed)
                ?? fallbackFormatter.date(from: trimmed)
        case "name":
            if inWpt { currentName = trimmed.nilIfEmpty }
        case "trkpt", "rtept":
            if inPoint {
                let ts = currentTime ?? currentSegment.last?.timestamp.addingTimeInterval(5) ?? Date()
                var speed = 0.0
                if let prev = currentSegment.last {
                    let dt = ts.timeIntervalSince(prev.timestamp)
                    if dt > 0 {
                        let dist = CLLocation(latitude: currentLat, longitude: currentLon).distance(from: prev.location)
                        speed = dist / dt
                    }
                }
                if abs(currentLat) <= 90, abs(currentLon) <= 180, (currentLat != 0 || currentLon != 0) {
                    currentSegment.append(TrackPoint(latitude: currentLat, longitude: currentLon, altitude: currentEle, speed: speed, accuracy: 10, timestamp: ts))
                }
                inPoint = false
            }
        case "trkseg", "rte":
            if currentSegment.count >= 2 { trackSegments.append(currentSegment) }
            currentSegment = []
        case "wpt":
            if inWpt {
                if abs(currentLat) <= 90, abs(currentLon) <= 180, (currentLat != 0 || currentLon != 0) {
                    waypoints.append(GPXImporter.RawWaypoint(lat: currentLat, lon: currentLon, name: currentName, time: currentTime ?? Date()))
                }
                inWpt = false
            }
        default:
            break
        }
    }
}
