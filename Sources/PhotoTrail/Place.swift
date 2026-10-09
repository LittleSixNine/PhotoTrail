import MapKit
import SwiftUI

struct Place: Identifiable, Codable {
    var name: String
    var sublocation: String?
    var city: String?
    var state: String?
    var country: String?
    var countryCode: String?
    var coordinate: Coordinate
    var id = UUID()

    var regionName: String {
        var parts: [String] = []
        for value in [state, city, sublocation].compactMap({ $0 })
            where !value.isEmpty && !parts.contains(value) { parts.append(value) }
        return parts.joined(separator: " · ")
    }

    init(from item: MKMapItem) {
        let coordinate: CLLocationCoordinate2D
        if #available(macOS 26, *) {
            coordinate = item.location.coordinate
        } else {
            coordinate = item.placemark.coordinate
        }
        self.init(from: item.placemark, name: item.name, coordinate: Coordinate(coordinate))
    }

    init(from address: CLPlacemark, name: String?, coordinate: Coordinate) {
        self.name = name ?? "unknown"
        sublocation = address.subLocality
        if let city = address.locality {
            self.city = city
            if city != self.name {
                self.name += ", \(city)"
            }
        }
        if let state = address.administrativeArea {
            self.state = state
            if state != self.name {
                self.name += ", \(state)"
            }
        }
        if let country = address.country {
            self.country = country
            if country != "United States" {
                self.name += ", \(country)"
            }
        }
        self.countryCode = address.isoCountryCode
        self.coordinate = coordinate
    }

    init(name: String, city: String?, state: String?, country: String?,
         countryCode: String?, coordinate: Coordinate, sublocation: String? = nil) {
        self.name = name
        self.sublocation = sublocation
        self.city = city
        self.state = state
        self.country = country
        self.countryCode = countryCode
        self.coordinate = coordinate
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case city
        case sublocation
        case state
        case country
        case countryCode
        case coordinate
    }
}

// Equatable and Hashable conformance

extension Place: Equatable, Hashable {
    public static func == (lhs: Place, rhs: Place) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
    }
}

// a codable struct to hold the same data as a CLLocationCoordiante2D

struct Coordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var coord2D: CLLocationCoordinate2D {
        .init(self)
    }
}

// Coordinates are equitable
extension Coordinate: Equatable {
    static func == (lhs: Coordinate, rhs: Coordinate) -> Bool {
        return lhs.latitude == rhs.latitude &&
               lhs.longitude == rhs.longitude
    }
}

// conversions between Coordinate and CLLocationCoordinate2d

extension CLLocationCoordinate2D {
    init(_ coordinate: Coordinate) {
        self = .init(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude)
    }
}

extension Coordinate {
    init(_ coordinate: CLLocationCoordinate2D) {
        self = .init(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude)
    }
}
