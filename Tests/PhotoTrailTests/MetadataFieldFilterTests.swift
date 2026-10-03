import Testing
@testable import PhotoTrail

struct MetadataFieldFilterTests {
    @Test func lazyValuesPreserveSearchAndFilters() {
        var reads = 0
        var edits = 0
        func hasEdits() -> Bool { edits += 1; return false }
        func values() -> [String?] { reads += 1; return [nil, "Tokyo"] }
        func matches(_ query: String, present: Bool = false, edited: Bool = false) -> Bool {
            MetadataFieldFilter.matches(query: query, presentOnly: present, editedOnly: edited,
                                        names: ["XMP:City", "城市"], hasEdits: hasEdits(), values: values)
        }
        #expect(matches(""))
        #expect(matches("city"))
        #expect(matches("城市"))
        #expect(reads == 0 && edits == 0)
        #expect(!matches("", edited: true))
        #expect(reads == 0 && edits == 1)
        #expect(matches("", present: true))
        #expect(matches("TOKYO"))
        #expect(!matches("Kyoto"))
        #expect(reads == 3)
    }

    @Test func absentEmptyAndEditedValuesKeepTheirMeaning() {
        #expect(!MetadataFieldFilter.matches(query: "City", presentOnly: true, editedOnly: false,
                                              names: ["City"], hasEdits: false, values: { [nil, nil] }))
        #expect(MetadataFieldFilter.matches(query: "City", presentOnly: true, editedOnly: true,
                                             names: ["City"], hasEdits: true, values: { [nil, ""] }))
        #expect(MetadataFieldFilter.matches(query: "", presentOnly: false, editedOnly: true,
                                             names: ["City"], hasEdits: true, values: { [nil] }))
    }
}
