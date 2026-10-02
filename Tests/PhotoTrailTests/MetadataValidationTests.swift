import Testing
@testable import PhotoTrail

struct MetadataValidationTests {
    @Test func metadataValidationDoesNotQueryTheKeychain() throws {
        #expect(try AMapCredentials.load(bundleIdentifier: "local.PhotoTrail.MetadataReference20260930") == nil)
    }
}
