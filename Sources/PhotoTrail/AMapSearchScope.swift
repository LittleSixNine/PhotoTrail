import Foundation
import Coords

struct AMapSearchCity: Codable, Identifiable, Equatable, Sendable {
    let name: String
    let adcode: String
    let coordinate: MapCoordinate // GCJ-02, for map navigation only.
    var id: String { adcode }
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && adcode.utf8.count == 6 && adcode.utf8.allSatisfy({ (48...57).contains($0) })
            && adcode.hasSuffix("00") && adcode != "100000" && coordinate.isValid
    }
    static let recentKey = "PhotoTrailRecentSearchCities.v1"

    static func recent(from data: Data) -> [Self] {
        ((try? JSONDecoder().decode([Self].self, from: data)) ?? []).filter(\.isValid)
    }

    static func updated(_ city: Self, in cities: [Self]) -> [Self] {
        guard city.isValid else { return cities }
        return Array(([city] + cities.filter { $0.id != city.id && $0.isValid }).prefix(3))
    }
}

enum AMapSearchScope: Equatable {
    case nationwide
    case city(AMapSearchCity)
    case viewport

    var id: String {
        switch self {
        case .nationwide: "nationwide"
        case .city(let city): "city:" + city.adcode
        case .viewport: "viewport"
        }
    }

    var title: String {
        switch self {
        case .nationwide: L10n.text("全国")
        case .city(let city): city.name
        case .viewport: L10n.text("当前画面")
        }
    }

    var arguments: [String: Any] {
        if case .city(let city) = self {
            return ["mode": "city", "name": city.name, "adcode": city.adcode]
        }
        return ["mode": id]
    }
}
