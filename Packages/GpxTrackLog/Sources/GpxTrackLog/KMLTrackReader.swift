import Foundation

enum TrackReadError: Error {
    case unsupportedFormat, invalidKML, noPoints, invalidArchive, tooLarge
}

/// Reads local geometry only. Styles, links, overlays and embedded resources never execute or load.
final class KMLTrackReader: NSObject, XMLParserDelegate {
    private struct Geometry {
        let name: String
        let depth: Int
        var coordinates = [String]()
        var times = [String]()
        var altitudeMode = "clampToGround"
    }

    private let parser: XMLParser
    private var path = [String]()
    private var text = ""
    private var geometry: Geometry?
    private var segments = [GpxTrackLog.Segment]()
    private var failure: Error?
    private var pointCount = 0
    private let dateFormatter = ISO8601DateFormatter()
    private let fractionalFormatter = ISO8601DateFormatter()

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func parse() throws -> [GpxTrackLog.Track] {
        guard parser.parse(), failure == nil else { throw failure ?? TrackReadError.invalidKML }
        guard !segments.isEmpty else { throw TrackReadError.noPoints }
        return [.init(segments: segments)]
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let knownNamespace = ["", "http://www.opengis.net/kml/2.2", "http://www.opengis.net/kml/2.3",
                              "http://earth.google.com/kml/2.2", "http://earth.google.com/kml/2.1",
                              "http://www.google.com/kml/ext/2.2"].contains(namespaceURI ?? "")
        let name = knownNamespace ? elementName : ""
        path.append(name)
        text = ""
        if path.count == 1, name != "kml" { fail(TrackReadError.invalidKML); return }
        guard geometry == nil, ["LineString", "Track"].contains(name),
              let placemark = path.lastIndex(of: "Placemark"),
              path[..<placemark].allSatisfy({ ["kml", "Document", "Folder"].contains($0) }),
              path[(placemark + 1)..<(path.count - 1)].allSatisfy({ ["MultiGeometry", "MultiTrack"].contains($0) }) else {
            return
        }
        geometry = Geometry(name: name, depth: path.count)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        defer { path.removeLast(); text = "" }
        guard var current = geometry else { return }
        if path.count == current.depth + 1 {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch path.last {
            case "coordinates" where current.name == "LineString": current.coordinates.append(value)
            case "coord" where current.name == "Track": current.coordinates.append(value)
            case "when" where current.name == "Track": current.times.append(value)
            case "altitudeMode": current.altitudeMode = value
            default: break
            }
            geometry = current
        } else if path.count == current.depth {
            do { try append(current) } catch { fail(error) }
            geometry = nil
        }
    }

    private func append(_ geometry: Geometry) throws {
        let timed = !geometry.times.isEmpty
        let coordinates = geometry.name == "LineString"
            ? geometry.coordinates.joined(separator: " ").split(whereSeparator: \.isWhitespace).map(String.init)
            : geometry.coordinates
        guard !timed || geometry.times.count == coordinates.count else { throw TrackReadError.invalidKML }
        var points = [GpxTrackLog.Point]()
        for (index, coordinate) in coordinates.enumerated() {
            // Empty gx:coord represents a gap, not permission to bridge missing locations.
            if coordinate.isEmpty {
                if timed { _ = try timestamp(geometry.times[index]) }
                if !points.isEmpty { segments.append(.init(points: points)); points.removeAll(keepingCapacity: true) }
                continue
            }
            let parts = geometry.name == "LineString"
                ? coordinate.split(separator: ",", omittingEmptySubsequences: false)
                : coordinate.split(whereSeparator: \.isWhitespace)
            guard (2...3).contains(parts.count),
                  let lon = Double(parts[0]), let lat = Double(parts[1]),
                  lon.isFinite, lat.isFinite, abs(lon) <= 180, abs(lat) <= 90 else {
                throw TrackReadError.invalidKML
            }
            var elevation: Double?
            if parts.count == 3 {
                guard let value = Double(parts[2]), value.isFinite else { throw TrackReadError.invalidKML }
                // Relative-to-ground heights are not EXIF altitude above sea level.
                if geometry.altitudeMode == "absolute" { elevation = value }
            }
            var timestamp: TimeInterval = 0
            if timed {
                timestamp = try self.timestamp(geometry.times[index])
            }
            points.append(.init(hasRecordedTime: timed, lat: lat, lon: lon, ele: elevation, timeFromEpoch: timestamp))
            pointCount += 1
            guard pointCount <= 1_000_000 else { throw TrackReadError.tooLarge }
        }
        if !points.isEmpty { segments.append(.init(points: points)) }
    }

    private func timestamp(_ value: String) throws -> TimeInterval {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$"#,
                          options: .regularExpression) != nil,
              let date = fractionalFormatter.date(from: value) ?? dateFormatter.date(from: value) else {
            throw TrackReadError.invalidKML
        }
        return date.timeIntervalSince1970
    }

    private func fail(_ error: Error) { failure = error; parser.abortParsing() }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        fail(TrackReadError.invalidKML)
    }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String,
                publicID: String?, systemID: String?) { fail(TrackReadError.invalidKML) }
}
