import Coords
import ImageData
import MapKit
import Metadata
import Testing
import UDF
@testable import PhotoTrail

@MainActor struct MapPhotoPerformanceTests {
    @Test func oneThousandPinsAreCappedBeforeRendering() {
        let pins = (0..<1_000).map { index in
            let latitude = 30.0 + Double(index / 40) * 0.01
            let longitude = 120.0 + Double(index % 40) * 0.01
            return MapView.PhotoPin(image: ImageData(metadata: Metadata(source: .copy),
                                                     name: "photo-\(index).jpg"),
                                    location: Coords(latitude: latitude, longitude: longitude),
                                    selected: false, editable: true)
        }

        let groups = MapView.groupedPhotoPins(pins, in: .world)

        #expect(groups.count <= 600)
        #expect(groups.flatMap(\.pins).count == pins.count)
    }

    @Test func duplicateCoordinatesCollapseWithoutDroppingPhotos() {
        let pins = (0..<1_000).map { index in
            MapView.PhotoPin(image: ImageData(metadata: Metadata(source: .copy),
                                              name: "photo-\(index).jpg"),
                             location: Coords(latitude: 31.23, longitude: 121.48),
                             selected: false, editable: true)
        }

        let groups = MapView.groupedPhotoPins(pins)

        #expect(groups.count == 1)
        #expect(groups[0].pins.count == pins.count)
    }

    @Test func scrollWheelZoomIsBoundedAndDirectionallyStable() {
        #expect(MapScrollWheelMonitor.steps(deltaY: 16, precise: true) == 2)
        #expect(MapScrollWheelMonitor.steps(deltaY: -12, precise: false) == -4)
        #expect(MapView.wheelZoomDistance(10_000, steps: 1) < 10_000)
        #expect(MapView.wheelZoomDistance(10_000, steps: -1) > 10_000)
        #expect(MapView.wheelZoomDistance(100, steps: 4) == 100)
        #expect(MapView.wheelZoomDistance(40_000_000, steps: -4) == 40_000_000)
        let center = MapView.wheelZoomCenter(MKMapPoint(x: 100, y: 100),
                                             anchor: MKMapPoint(x: 200, y: 300), ratio: 0.5)
        #expect(center.x == 150)
        #expect(center.y == 200)
    }

    @Test func sculptedPinAndEdgeMarkerEndInSharpTips() {
        let pin = PhotoThumbnailPinShape().path(in: CGRect(x: 0, y: 0, width: 48, height: 58))
        let edge = PhotoEdgePinShape().path(in: CGRect(x: 0, y: 0, width: 60, height: 60))

        #expect(pin.boundingRect.maxY == 57.5)
        #expect(abs(edge.boundingRect.maxX - 59) < 0.5)
        #expect(pin.contains(CGPoint(x: 24, y: 57)))
        #expect(edge.contains(CGPoint(x: 58.5, y: 30)))
    }

    @Test func importedLocationBadgeDisappearsWhenLocationIsCleared() {
        var embeddedMetadata = Metadata(source: .xmp(URL(fileURLWithPath: "/tmp/embedded.xmp")))
        embeddedMetadata.location = Coords(latitude: 31.23, longitude: 121.48)
        let embedded = ImageData(metadata: embeddedMetadata, name: "embedded.jpg")
        var state = PhotoTrailState()
        state.imageData = [embedded]
        state.selection = [embedded.id]
        let store = Store(initialState: state, reduce: PhotoTrailReducer(), undoEnabled: true)
        #expect(store[embedded.id].importedWithLocation)
        store.send(.deleteRequest)

        var added = ImageData(metadata: Metadata(source: .copy), name: "added.jpg")
        added.original = Metadata(copying: added.metadata)
        added.metadata.location = Coords(latitude: 31.23, longitude: 121.48)

        #expect(store[embedded.id].metadata.location == nil)
        #expect(!store[embedded.id].importedWithLocation)
        #expect(!added.importedWithLocation)
        store.undo()
        #expect(store[embedded.id].importedWithLocation)
    }
}
