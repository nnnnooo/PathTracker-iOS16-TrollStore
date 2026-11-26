import Foundation
import CoreLocation

enum GPXImporter {
    struct Summary: Equatable, Sendable {
        var addedChunks = 0
        var addedStays = 0
        var skippedDuplicates = 0
        var totalPoints = 0
        var errorMessage: String?
    }

    struct ParsedFile: Sendable {
        var segments: [[TrackPoint]]
        var waypoints: [RawWaypoint]
        var totalPoints: Int
        var errorMessage: String?
    }

    struct RawWaypoint: Sendable {
        var lat: Double
        var lon: Double
        var name: String?
        var time: Date
    }

    /// Streams and parses a GPX file (even 30MB+ multi-year backups) off the main thread.
    nonisolated static func parseFile(
        at url: URL,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) -> ParsedFile {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return ParsedFile(segments: [], waypoints: [], totalPoints: 0, errorMessage: "找不到所选文件")
        }

        // Stream directly from disk via XMLParser(contentsOf:) to avoid loading 33MB+ into RAM at once
        guard let parser = XMLParser(contentsOf: url) else {
            return ParsedFile(segments: [], waypoints: [], totalPoints: 0, errorMessage: "无法打开 GPX 文件流")
        }

        let delegate = GPXParserDelegate(onProgress: onProgress)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        let ok = parser.parse()
        delegate.flushTrailing()

        if !ok && delegate.trackSegments.isEmpty && delegate.waypoints.isEmpty {
            let err = parser.parserError?.localizedDescription ?? "GPX XML 格式解析失败"
            return ParsedFile(segments: [], waypoints: [], totalPoints: 0, errorMessage: err)
        }

        return ParsedFile(
            segments: delegate.trackSegments,
            waypoints: delegate.waypoints,
            totalPoints: delegate.totalPoints,
            errorMessage: nil
        )
    }

    @MainActor
    static func importFiles(
        at urls: [URL],
        into store: DataStore,
        onStatus: (@MainActor @Sendable (String) -> Void)? = nil
    ) async -> Summary {
        onStatus?("正在解析 GPX 文件…")

        let existingRanges: [(start: TimeInterval, end: TimeInterval)] = store.chunks.map {
            ($0.startDate.timeIntervalSince1970, $0.endDate.timeIntervalSince1970)
        }
        let existingStays: [(time: TimeInterval, lat: Double, lon: Double)] = store.stays.map {
            ($0.arrival.timeIntervalSince1970, $0.latitude, $0.longitude)
        }

        let work = await Task.detached(priority: .userInitiated) { () -> (chunks: [TrackChunk], stays: [Stay], summary: Summary) in
            var summary = Summary()
            var firstError: String?
            var newChunks: [TrackChunk] = []
            var newStays: [Stay] = []
            var knownRanges = existingRanges

            for url in urls {
                let parsed = parseFile(at: url) { count in
                    if let onStatus {
                        let text = count >= 10_000
                            ? String(format: "正在解析 GPX (已读 %.1f 万点)…", Double(count) / 10_000.0)
                            : "正在解析 GPX (已读 \(count) 点)…"
                        Task { @MainActor in onStatus(text) }
                    }
                }
                summary.totalPoints += parsed.totalPoints
                if let err = parsed.errorMessage, firstError == nil {
                    firstError = err
                }

                if let onStatus, !parsed.segments.isEmpty {
                    let segCount = parsed.segments.count
                    Task { @MainActor in onStatus("正在整理 \(segCount) 段轨迹…") }
                }

                for segment in parsed.segments where segment.count >= 2 {
                    let start = segment.first!.timestamp.timeIntervalSince1970
                    let end = segment.last!.timestamp.timeIntervalSince1970
                    let dur = max(1.0, end - start)

                    let isDuplicate = knownRanges.contains { existing in
                        let overlapStart = max(existing.start, start)
                        let overlapEnd = min(existing.end, end)
                        return (overlapEnd - overlapStart) / dur > 0.8
                    }
                    if isDuplicate {
                        summary.skippedDuplicates += 1
                        continue
                    }

                    let mode = MotionClassifier.mode(forSpeeds: segment.map(\.speed))
                    let chunk = TrackChunk(points: segment, mode: mode)
                    newChunks.append(chunk)
                    knownRanges.append((start, end))
                    summary.addedChunks += 1
                }

                for wpt in parsed.waypoints {
                    let ts = wpt.time.timeIntervalSince1970
                    let dup = existingStays.contains { existing in
                        abs(existing.time - ts) < 300
                            && fastDistanceMeters(lat1: existing.lat, lon1: existing.lon, lat2: wpt.lat, lon2: wpt.lon) < 100
                    }
                    if dup {
                        summary.skippedDuplicates += 1
                        continue
                    }
                    var stay = Stay(
                        arrival: wpt.time,
                        departure: wpt.time.addingTimeInterval(300),
                        coordinate: CLLocationCoordinate2D(latitude: wpt.lat, longitude: wpt.lon)
                    )
                    stay.customName = wpt.name
                    newStays.append(stay)
                    summary.addedStays += 1
                }
            }

            if summary.addedChunks == 0 && summary.addedStays == 0 && summary.skippedDuplicates == 0 {
                summary.errorMessage = firstError ?? "未在文件中找到有效的轨迹点（<trkpt>/<rtept>）或路点（<wpt>）。"
            }
            return (newChunks, newStays, summary)
        }.value

        if !work.chunks.isEmpty {
            onStatus?("正在写入 \(work.chunks.count) 段轨迹到数据库…")
            store.insertChunksBatch(work.chunks)
        }
        if !work.stays.isEmpty {
            store.insertStaysBatch(work.stays)
        }

        return work.summary
    }
}

// MARK: - Fast Math & Date Helpers (Zero ObjC / DateFormatter Overhead)

@inline(__always)
private func fastDistanceMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let rad = Double.pi / 180.0
    let dLat = (lat2 - lat1) * rad
    let dLon = (lon2 - lon1) * rad
    let a = sin(dLat * 0.5)
    let b = sin(dLon * 0.5)
    let h = a * a + cos(lat1 * rad) * cos(lat2 * rad) * b * b
    return 12_742_000.0 * asin(min(1.0, sqrt(h)))
}

/// Fast ASCII ISO-8601 parser: handles "2024-05-01T12:34:56Z", "2024-05-01T12:34:56.789Z",
/// "2024-05-01T12:34:56+08:00", and "2024-05-01 12:34:56" ~100x faster than ISO8601DateFormatter.
private func fastParseISO8601(_ s: String) -> Date? {
    let bytes = Array(s.utf8)
    guard bytes.count >= 19 else { return nil }
    func d(_ i: Int) -> Int? {
        let c = bytes[i]
        guard c >= 48 && c <= 57 else { return nil }
        return Int(c - 48)
    }
    guard let y1 = d(0), let y2 = d(1), let y3 = d(2), let y4 = d(3),
          let m1 = d(5), let m2 = d(6),
          let d1 = d(8), let d2 = d(9),
          let h1 = d(11), let h2 = d(12),
          let n1 = d(14), let n2 = d(15),
          let s1 = d(17), let s2 = d(18) else { return nil }

    let year = y1 * 1000 + y2 * 100 + y3 * 10 + y4
    let month = m1 * 10 + m2
    let day = d1 * 10 + d2
    let hour = h1 * 10 + h2
    let minute = n1 * 10 + n2
    let second = s1 * 10 + s2

    var tmVal = tm()
    tmVal.tm_year = Int32(year - 1900)
    tmVal.tm_mon = Int32(month - 1)
    tmVal.tm_mday = Int32(day)
    tmVal.tm_hour = Int32(hour)
    tmVal.tm_min = Int32(minute)
    tmVal.tm_sec = Int32(second)

    var epoch = Double(timegm(&tmVal))

    // Parse optional fractional seconds and timezone offset
    var idx = 19
    if idx < bytes.count && bytes[idx] == 46 { // '.'
        idx += 1
        var frac = 0.0
        var scale = 0.1
        while idx < bytes.count, let digit = d(idx) {
            frac += Double(digit) * scale
            scale *= 0.1
            idx += 1
        }
        epoch += frac
    }

    if idx < bytes.count {
        let tz = bytes[idx]
        if tz == 43 || tz == 45 { // '+' or '-'
            let sign: Double = (tz == 43) ? 1.0 : -1.0
            if idx + 2 < bytes.count, let tzh1 = d(idx + 1), let tzh2 = d(idx + 2) {
                var offset = Double((tzh1 * 10 + tzh2) * 3600)
                let minStart = (idx + 3 < bytes.count && bytes[idx + 3] == 58) ? idx + 4 : idx + 3
                if minStart + 1 < bytes.count, let tzm1 = d(minStart), let tzm2 = d(minStart + 1) {
                    offset += Double((tzm1 * 10 + tzm2) * 60)
                }
                epoch -= sign * offset
            }
        }
    }

    return Date(timeIntervalSince1970: epoch)
}

// MARK: - Streaming XML Parser Delegate

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    var trackSegments: [[TrackPoint]] = []
    var waypoints: [GPXImporter.RawWaypoint] = []
    var totalPoints = 0

    private let onProgress: (@Sendable (Int) -> Void)?
    private var currentSegment: [TrackPoint] = []
    private var inPoint = false
    private var inWpt = false
    private var currentLat: Double = 0
    private var currentLon: Double = 0
    private var currentEle: Double = 0
    private var currentTime: Date?
    private var currentName: String?
    private var textBuffer = ""

    private static let maxGapSeconds: TimeInterval = 20 * 60
    private static let maxPointsPerChunk = 600

    init(onProgress: (@Sendable (Int) -> Void)?) {
        self.onProgress = onProgress
    }

    func flushTrailing() {
        if currentSegment.count >= 2 {
            trackSegments.append(currentSegment)
        }
        currentSegment = []
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        textBuffer.removeAll(keepingCapacity: true)
        switch elementName {
        case "trkpt", "rtept", "TRKPT", "RTEPT":
            inPoint = true
            currentLat = Double(attributeDict["lat"] ?? "") ?? 0
            currentLon = Double(attributeDict["lon"] ?? "") ?? 0
            currentEle = 0
            currentTime = nil
        case "trkseg", "rte", "TRKSEG", "RTE":
            flushTrailing()
        case "wpt", "WPT":
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
        if inPoint || inWpt {
            textBuffer += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "ele", "ELE":
            if inPoint {
                currentEle = Double(textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            }
        case "time", "TIME":
            if inPoint || inWpt {
                let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                currentTime = fastParseISO8601(trimmed)
            }
        case "name", "NAME":
            if inWpt {
                currentName = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
        case "trkpt", "rtept", "TRKPT", "RTEPT":
            if inPoint {
                inPoint = false
                guard abs(currentLat) <= 90, abs(currentLon) <= 180, (currentLat != 0 || currentLon != 0) else { return }
                let ts = currentTime ?? currentSegment.last?.timestamp.addingTimeInterval(5) ?? Date()
                totalPoints += 1
                if totalPoints % 5000 == 0 {
                    onProgress?(totalPoints)
                }

                var speed = 0.0
                if let prev = currentSegment.last {
                    let dt = ts.timeIntervalSince(prev.timestamp)
                    let dist = fastDistanceMeters(lat1: prev.latitude, lon1: prev.longitude, lat2: currentLat, lon2: currentLon)

                    // Split into a new chunk on >20 min gap, >10 km jump, backwards time, or >=600 points
                    if dt < 0 || dt > Self.maxGapSeconds || dist > 10_000 || currentSegment.count >= Self.maxPointsPerChunk {
                        flushTrailing()
                    } else if dt < 2 && dist < 4 {
                        // Light deduplication for dense 1Hz GPS logs
                        return
                    } else if dt > 0 {
                        speed = dist / dt
                    }
                }

                currentSegment.append(
                    TrackPoint(
                        latitude: currentLat,
                        longitude: currentLon,
                        altitude: currentEle,
                        speed: speed,
                        accuracy: 10,
                        timestamp: ts
                    )
                )
            }
        case "trkseg", "rte", "TRKSEG", "RTE":
            flushTrailing()
        case "wpt", "WPT":
            if inWpt {
                inWpt = false
                if abs(currentLat) <= 90, abs(currentLon) <= 180, (currentLat != 0 || currentLon != 0) {
                    waypoints.append(
                        GPXImporter.RawWaypoint(
                            lat: currentLat,
                            lon: currentLon,
                            name: currentName,
                            time: currentTime ?? Date()
                        )
                    )
                }
            }
        default:
            break
        }
    }
}
