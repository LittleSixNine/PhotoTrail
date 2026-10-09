import MapKit
import Testing
@testable import PhotoTrail

struct PlaceTests {
    @Test func legacyAddressPreservesFieldsAndRequestedCoordinate() {
        let address = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 31.2, longitude: 121.5),
                                  addressDictionary: ["City": "上海市", "State": "上海市",
                                                      "SubLocality": "黄浦区", "Country": "中国",
                                                      "CountryCode": "CN"])
        let requested = Coordinate(latitude: 31.23, longitude: 121.48)
        let place = Place(from: address, name: "测试地点", coordinate: requested)
        #expect(place.city == "上海市")
        #expect(place.state == "上海市")
        #expect(place.sublocation == "黄浦区")
        #expect(place.country == "中国")
        #expect(place.countryCode == "CN")
        #expect(place.coordinate == requested)
        #expect(place.regionName == "上海市 · 黄浦区")
    }

    @Test func emptyAddressKeepsMissingFieldsEmpty() {
        let address = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0))
        let place = Place(from: address, name: nil, coordinate: Coordinate(latitude: 1, longitude: 2))
        #expect(place.name == "unknown")
        #expect(place.city == nil && place.state == nil && place.sublocation == nil)
        #expect(place.country == nil && place.countryCode == nil)
        #expect(place.regionName.isEmpty)
        #expect(place.coordinate == Coordinate(latitude: 1, longitude: 2))
    }

    @Test func mapSearchRetainsItemNameAndCoordinate() {
        let address = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37, longitude: -122),
                                  addressDictionary: ["City": "Example City", "State": "CA",
                                                      "Country": "United States", "CountryCode": "US"])
        let item = MKMapItem(placemark: address)
        item.name = "Example Place"
        let place = Place(from: item)
        #expect(place.name == "Example Place, Example City, CA")
        #expect(place.countryCode == "US")
        #expect(place.coordinate == Coordinate(address.coordinate))
    }
}
