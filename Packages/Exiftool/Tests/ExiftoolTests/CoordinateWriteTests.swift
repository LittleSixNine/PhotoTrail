import Coords
import Foundation
import Metadata
import Testing
@testable import Exiftool

extension ExiftoolSerializedTests {
    @Test func dateOnlySavePreservesGPSAndExplicitLocationRoundTrips() async throws {
        let key = Exiftool.updateGPSTimestampsKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(false, forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        let fixture = try #require(Bundle.module.url(forResource: "IMG_5654", withExtension: "HEIC"))
        let folder = try makeTestFolder(andCopy: fixture)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent(fixture.lastPathComponent)
        // Seed an unknown datum and non-coordinate GPS fields, so preservation is observable.
        _ = try Exiftool.helper.run(["-overwrite_original", "-GPSMapDatum=", "-GPSProcessingMethod=CELLID",
                                    "-GPSStatus=V", "-GPSDOP=3.5", file.path])
        func gps() throws -> Data {
            try Exiftool.helper.run(["-j", "-n", "-EXIF:GPSAll", file.path])
        }
        let before = try gps()
        var dateEdit = Metadata(source: .image(file))
        dateEdit.dateTimeCreated = "2026:09:15 12:00:00"
        dateEdit.preserveGPSOnSave = true
        try await Exiftool.helper.update(image: file, from: dateEdit, timeZone: nil)
        #expect(try gps() == before)

        var locationEdit = dateEdit
        locationEdit.preserveGPSOnSave = false
        locationEdit.location = Coords(latitude: 31.23, longitude: 121.48)
        locationEdit.gpsMapDatum = "WGS-84"
        locationEdit.gpsProcessingMethod = "MANUAL"
        try await Exiftool.helper.update(image: file, from: locationEdit, timeZone: nil)
        let readback = Exiftool.helper.metadata(from: file, primaryURL: file)
        let location = try #require(readback.location)
        #expect(abs(location.latitude - 31.23) < 0.000001)
        #expect(abs(location.longitude - 121.48) < 0.000001)
        #expect(readback.gpsMapDatum == "WGS-84")
        #expect(readback.gpsProcessingMethod == "MANUAL")
    }
}
