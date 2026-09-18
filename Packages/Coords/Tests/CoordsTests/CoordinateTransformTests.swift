import Testing
@testable import Coords

struct CoordinateTransformTests {
    @Test func referenceFormula() throws {
        // Public example, cross-checked against the original JS implementation, not a survey fix.
        let beijing = MapCoordinate(latitude: 39.915, longitude: 116.404)
        let converted = try CoordinateTransform.wgs84ToGCJ02(beijing, region: .mainlandChina)
        let expected = MapCoordinate(latitude: 39.91640428150164, longitude: 116.41024449916938)
        #expect(converted.distance(to: expected) < 0.001)
    }

    @Test func roundTrips() throws {
        for point in [MapCoordinate(latitude: 31.2304, longitude: 121.4737),
                      MapCoordinate(latitude: 39.915, longitude: 116.404),
                      MapCoordinate(latitude: 30.5728, longitude: 104.0665),
                      MapCoordinate(latitude: 22.5431, longitude: 114.0579)] {
            let gcj = try CoordinateTransform.wgs84ToGCJ02(point, region: .mainlandChina)
            let restored = try CoordinateTransform.gcj02ToWGS84(gcj, region: .mainlandChina)
            #expect(point.distance(to: restored) < 0.1)
            #expect(point.distance(to: gcj) > 10)
        }
    }

    @Test func regionIsExplicit() throws {
        // Hanoi is inside the widely copied "China" rectangle. Do not shift it based on that bound.
        let hanoi = MapCoordinate(latitude: 21.0285, longitude: 105.8542)
        #expect(try CoordinateTransform.wgs84ToGCJ02(hanoi, region: .outsideMainlandChina) == hanoi)
        #expect(try CoordinateTransform.gcj02ToWGS84(hanoi, region: .outsideMainlandChina) == hanoi)
        for code in ["310101", "110101", "440304"] {
            #expect(CoordinateTransform.isMainlandAdministrativeCode(code))
        }
        for code in ["810001", "820001", "710000", "000000", "31", "３１０１０１", "31010x"] {
            #expect(!CoordinateTransform.isMainlandAdministrativeCode(code))
        }
    }

    @Test func invalidInputsFail() {
        for point in [MapCoordinate(latitude: .nan, longitude: 121),
                      MapCoordinate(latitude: 31, longitude: .infinity),
                      MapCoordinate(latitude: 91, longitude: 121),
                      MapCoordinate(latitude: 31, longitude: 181)] {
            #expect(throws: CoordinateTransformError.invalidCoordinate) {
                try CoordinateTransform.gcj02ToWGS84(point, region: .mainlandChina)
            }
        }
        #expect(throws: CoordinateTransformError.outsideFormulaDomain) {
            try CoordinateTransform.gcj02ToWGS84(MapCoordinate(latitude: 90, longitude: 0),
                                                region: .mainlandChina)
        }
    }
}
