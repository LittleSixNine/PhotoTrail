import Foundation

/// Numeric coordinates at a map boundary; the caller must supply their reference frame.
public struct MapCoordinate: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    public func distance(to other: Self) -> Double {
        let radians = Double.pi / 180
        let deltaLat = (other.latitude - latitude) * radians
        let deltaLon = (other.longitude - longitude) * radians
        let value = pow(sin(deltaLat / 2), 2)
            + cos(latitude * radians) * cos(other.latitude * radians) * pow(sin(deltaLon / 2), 2)
        return 6_371_008.8 * 2 * asin(sqrt(min(1, max(0, value))))
    }
}

public enum CoordinateRegion: Sendable {
    case mainlandChina
    case outsideMainlandChina
}

public enum CoordinateTransformError: Error, Equatable {
    case invalidCoordinate
    case outsideFormulaDomain
    case didNotConverge
}

public enum CoordinateTransform {
    /// Region is supplied by the map service, never guessed from a country-sized rectangle.
    public static func isMainlandAdministrativeCode(_ code: String) -> Bool {
        let provinces: Set<String> = [
            "11", "12", "13", "14", "15", "21", "22", "23", "31", "32", "33", "34", "35", "36", "37",
            "41", "42", "43", "44", "45", "46", "50", "51", "52", "53", "54", "61", "62", "63", "64", "65"
        ]
        return code.utf8.count == 6 && code.utf8.allSatisfy { (48...57).contains($0) }
            && provinces.contains(String(code.prefix(2)))
    }

    public static func wgs84ToGCJ02(_ point: MapCoordinate,
                                    region: CoordinateRegion) throws -> MapCoordinate {
        guard point.isValid else { throw CoordinateTransformError.invalidCoordinate }
        if region == .outsideMainlandChina { return point }
        // This bound only rejects numerically inappropriate inputs. It does NOT establish a country.
        guard (0...56).contains(point.latitude), (70...140).contains(point.longitude) else {
            throw CoordinateTransformError.outsideFormulaDomain
        }
        return forward(point)
    }

    public static func gcj02ToWGS84(_ point: MapCoordinate,
                                    region: CoordinateRegion) throws -> MapCoordinate {
        _ = try wgs84ToGCJ02(point, region: region)
        if region == .outsideMainlandChina { return point }
        var candidate = point
        for _ in 0..<12 {
            let projected = forward(candidate)
            if projected.distance(to: point) < 0.001 { return candidate }
            candidate = MapCoordinate(latitude: candidate.latitude + point.latitude - projected.latitude,
                                      longitude: candidate.longitude + point.longitude - projected.longitude)
            guard candidate.isValid else { throw CoordinateTransformError.invalidCoordinate }
        }
        throw CoordinateTransformError.didNotConverge
    }

    // Forward formula adapted from wandergis/coordtransform (MIT), see THIRD_PARTY_NOTICES.md.
    // Inverse is iterative, not the reference implementation's one-step approximation.
    private static func forward(_ point: MapCoordinate) -> MapCoordinate {
        let axis = 6_378_245.0
        let eccentricity = 0.00669342162296594323
        let longitude = point.longitude - 105
        let latitude = point.latitude - 35
        var deltaLat = -100 + 2 * longitude + 3 * latitude + 0.2 * latitude * latitude
            + 0.1 * longitude * latitude + 0.2 * sqrt(abs(longitude))
        var deltaLon = 300 + longitude + 2 * latitude + 0.1 * longitude * longitude
            + 0.1 * longitude * latitude + 0.1 * sqrt(abs(longitude))
        let common = (20 * sin(6 * longitude * .pi) + 20 * sin(2 * longitude * .pi)) * 2 / 3
        deltaLat += common
        deltaLat += (20 * sin(latitude * .pi) + 40 * sin(latitude / 3 * .pi)) * 2 / 3
        deltaLat += (160 * sin(latitude / 12 * .pi) + 320 * sin(latitude * .pi / 30)) * 2 / 3
        deltaLon += common
        deltaLon += (20 * sin(longitude * .pi) + 40 * sin(longitude / 3 * .pi)) * 2 / 3
        deltaLon += (150 * sin(longitude / 12 * .pi) + 300 * sin(longitude / 30 * .pi)) * 2 / 3
        let radLat = point.latitude * .pi / 180
        let magic = 1 - eccentricity * pow(sin(radLat), 2)
        deltaLat = deltaLat * 180 / ((axis * (1 - eccentricity)) / (magic * sqrt(magic)) * .pi)
        deltaLon = deltaLon * 180 / (axis / sqrt(magic) * cos(radLat) * .pi)
        return MapCoordinate(latitude: point.latitude + deltaLat, longitude: point.longitude + deltaLon)
    }
}
