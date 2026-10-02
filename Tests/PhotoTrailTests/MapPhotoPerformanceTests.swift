import AppKit
import Coords
import ImageData
import MapKit
import Metadata
import Testing
import UDF
@testable import PhotoTrail

@MainActor struct MapPhotoPerformanceTests {
    @Test func inspectorCacheChecksBothSourcesScopesAndExplicitInvalidation() {
        let cache = MetadataInspectorReadCache(limit: 2)
        let image = URL(fileURLWithPath: "/tmp/cache-image.jpg")
        let sidecar = URL(fileURLWithPath: "/tmp/cache-image.xmp")
        let key = MetadataInspectorReadCache.Key(url: sidecar, imageURL: image, kind: .standard)
        let version = MetadataInspectionFileVersion.file(device: 1, inode: 2, size: 3,
            modifiedSeconds: 4, modifiedNanoseconds: 5, changedSeconds: 6, changedNanoseconds: 7)
        cache.insert(.display(["XMP-xmp:CreateDate": "value"]), for: key, versions: [version, version])
        if case .display(let values) = cache.value(for: key, versions: [version, version]) {
            #expect(values["XMP-xmp:CreateDate"] == "value")
        } else { Issue.record("Unchanged selection should reuse its read") }
        let full = MetadataInspectorReadCache.Key(url: sidecar, imageURL: image, kind: .additional)
        #expect(cache.value(for: full, versions: [version, version]) == nil)
        #expect(cache.value(for: key, versions: [version, .missing]) == nil)
        cache.insert(.display([:]), for: key, versions: [version, version])
        cache.invalidate(urls: [image])
        #expect(cache.value(for: key, versions: [version, version]) == nil)
        cache.insert(.display([:]), for: key, versions: [version, version])
        cache.insert(.display([:]), for: full, versions: [version, version])
        let third = MetadataInspectorReadCache.Key(url: image, imageURL: image, kind: .standard)
        cache.insert(.display([:]), for: third, versions: [version])
        #expect(cache.value(for: key, versions: [version, version]) == nil)
        #expect(cache.value(for: full, versions: [version, version]) != nil)
    }

    @Test func exposureDisplayUsesCameraFractionsAndMarksApproximation() {
        #expect(MetadataExposureDisplay.text("0.000633222438794438") == "≈ 1/1600 s")
        #expect(MetadataExposureDisplay.text("0.008") == "1/125 s")
        #expect(MetadataExposureDisplay.text("1/250") == "1/250 s")
        #expect(MetadataExposureDisplay.text("2") == "2 s")
        #expect(MetadataExposureDisplay.text("1.5") == "1.5 s")
        #expect(MetadataExposureDisplay.text("0.007") == "1/142.857 s")
        #expect(MetadataExposureDisplay.text("0") == nil)
        #expect(MetadataExposureDisplay.text("-1") == nil)
        #expect(MetadataExposureDisplay.text("nan") == nil)
        #expect(MetadataExposureDisplay.text("1/0") == nil)
    }

    @Test func metadataDateDisplayNormalizesInstantsWithoutInventingOffsets() {
        let zone = TimeZone(secondsFromGMT: 8 * 3600)!
        let local = MetadataInspectorDateDisplay.text("2024:02:29 12:34:56.123+08:00", timeZone: zone)
        #expect(local == "2024-02-29 12:34:56\nUTC+08:00 · " + L10n.text("亚秒 %1$@ 秒", "0.123"))
        #expect(MetadataInspectorDateDisplay.text("2024-02-29T04:34:56.123Z", timeZone: zone) == local)
        #expect(MetadataInspectorDateDisplay.text("2024:02:29 12:34:56", timeZone: zone)
                == "2024-02-29 12:34:56\n" + L10n.text("时区未记录"))
        #expect(MetadataInspectorDateDisplay.text("2024:02:29", timeZone: zone)
                == "2024-02-29\n" + L10n.text("仅日期"))
        #expect(MetadataInspectorDateDisplay.text("12:34:56+08:00", timeZone: zone)
                == "12:34:56\n" + L10n.text("仅时间") + " · UTC+08:00")
        #expect(MetadataInspectorDateDisplay.text("2024:02:30 12:34:56", timeZone: zone) == nil)
        #expect(MetadataInspectorDateDisplay.text("ExifIFD: 2024:02:29 12:34:56", timeZone: zone) == nil)
    }

    @Test func mapSidebarKeepsContentWidthAcrossOverflowBoundary() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 320))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 319))
        scroll.documentView = document
        SubtleScrollbars.Installer.configure(scroll, reservesVerticalScroller: true)
        scroll.tile()
        let width = scroll.contentView.bounds.width
        #expect(width < scroll.bounds.width)
        for height in [319.0, 320.0, 321.0, 320.0, 319.0] {
            document.setFrameSize(NSSize(width: width, height: height))
            scroll.tile()
            #expect(scroll.contentView.bounds.width == width)
            #expect(!scroll.autohidesScrollers)
        }
        let other = NSScrollView()
        other.autohidesScrollers = true
        SubtleScrollbars.Installer.configure(other)
        #expect(other.autohidesScrollers)
    }

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
