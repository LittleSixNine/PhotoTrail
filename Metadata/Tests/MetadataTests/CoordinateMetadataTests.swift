import Coords
import Testing
@testable import Metadata

struct CoordinateMetadataTests {
    @Test func dateAndAddressEditsPreserveUnknownGPS() {
        var original = Metadata(source: .copy)
        original.location = Coords(latitude: 31.23, longitude: 121.48)
        original.gpsProcessingMethod = "CELLID"
        var edited = original
        edited.dateTimeCreated = "2026:09:15 12:00:00"
        edited.city = "Shanghai"
        let snapshot = edited.forSaving(comparedTo: original)
        #expect(snapshot.preserveGPSOnSave)
        #expect(snapshot.gpsMapDatum == nil)
        #expect(!Metadata(copying: snapshot).preserveGPSOnSave)
    }

    @Test func confirmedDatumAndLocationChangesRequireGPSWrite() {
        var original = Metadata(source: .copy)
        original.location = Coords(latitude: 31.23, longitude: 121.48)
        var edited = original
        edited.gpsMapDatum = "WGS-84"
        edited.gpsProcessingMethod = "MANUAL"
        #expect(!edited.forSaving(comparedTo: original).preserveGPSOnSave)
        edited.restore(from: original)
        #expect(edited.gpsMapDatum == nil)
        #expect(edited == original)
        edited.location = nil
        #expect(!edited.forSaving(comparedTo: original).preserveGPSOnSave)
    }

    @Test func unsupportedDatumIsNotSilentlyDisplayedAsWGS84() {
        var metadata = Metadata(source: .copy)
        #expect(metadata.canDisplayAsWGS84)
        metadata.gpsMapDatum = "WGS-84"
        #expect(metadata.canDisplayAsWGS84)
        metadata.gpsMapDatum = "GCJ-02"
        #expect(!metadata.canDisplayAsWGS84)
    }
}
