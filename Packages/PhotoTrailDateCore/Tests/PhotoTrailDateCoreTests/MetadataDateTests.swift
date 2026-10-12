import Foundation
import Testing
import PhotoTrailDateCore

struct MetadataDateTests {
    private struct Vector: Decodable {
        let id: String
        let operation: String
        let input: String
        let parameters: [String: String]
        let expected: String?
        let observed: String?
    }

    @Test func existingCompatibilityVectors() throws {
        let url = try #require(Bundle.module.url(forResource: "date-core-v1", withExtension: "json",
                                                subdirectory: "Fixtures"))
        let vectors = try JSONDecoder().decode([Vector].self, from: Data(contentsOf: url))
        #expect(vectors.count == 35)
        #expect(vectors.filter { $0.expected != nil }.count == 19)
        #expect(Set(vectors.map(\.id)).count == vectors.count)
        for vector in vectors {
            let reference = try #require(vector.expected ?? vector.observed)
            #expect(try result(vector) == reference, "\(vector.id)")
        }
    }

    private func result(_ vector: Vector) throws -> String {
        func number(_ key: String) throws -> Int {
            let text = try #require(vector.parameters[key])
            return try #require(Int(text))
        }
        do {
            switch vector.operation {
            case "parse": return try MetadataDate(vector.input).text
            case "replace":
                let components: [String: Calendar.Component] = ["year": .year, "month": .month,
                    "day": .day, "hour": .hour, "minute": .minute, "second": .second]
                let componentName = try #require(vector.parameters["component"])
                let component = try #require(components[componentName])
                return try MetadataDate(vector.input).replacing(component, with: number("value")).text
            case "shift": return try MetadataDate(vector.input).shifting(seconds: number("seconds")).text
            case "calendarDays":
                return try MetadataDate(vector.input).addingCalendarDays(number("days"),
                                                                         timeZoneID: vector.parameters["zone"]).text
            case "sequence":
                return try MetadataDate.sequence(start: vector.input, stepSeconds: number("stepSeconds"),
                                                 count: number("count")).joined(separator: "|")
            default: throw MetadataDateError.invalidDate
            }
        } catch let error as MetadataDateError {
            switch error {
            case .invalidDate: return "error:invalidDate"
            case .missingDate: return "error:missingDate"
            case .invalidSequence: return "error:invalidSequence"
            }
        }
    }

    @Test func precisionAndWallClockRemainUnchanged() throws {
        for value in ["2024:01:15 10:20:30", "2024:01:15 10:20:30.123456789Z",
                      "2024:01:15 10:20:30.1-00:00", "2024:01:15 10:20:30+14:00"] {
            #expect(try MetadataDate(value).text == value)
        }
        #expect(try MetadataDate("2024:12:31 23:59:59").shifting(seconds: 1).text
                == "2025:01:01 00:00:00")
    }

    @Test func offsetsKeepOrderAndRejectClamping() throws {
        let date = try MetadataDate("2024:01:15 10:20:30.123456+08:00")
        #expect(try date.offsetting(years: 1, months: 1, days: 2, hours: 3, minutes: 4, seconds: 5).text
                == "2025:02:17 13:24:35.123456+08:00")
        #expect(try date.offsetting().text == date.text)
        #expect(throws: MetadataDateError.self) {
            try MetadataDate("2024:02:29 12:00:00").offsetting(years: 1)
        }
        #expect(throws: MetadataDateError.self) {
            try MetadataDate("2024:01:31 12:00:00").offsetting(months: 1)
        }
        #expect(throws: MetadataDateError.self) { try date.offsetting(years: Int.max) }
        #expect(throws: MetadataDateError.self) { try date.offsetting(seconds: Int.min) }
    }

    @Test func generationKeepsPrecisionEndpointsAndBounds() throws {
        let start = "2024:01:01 00:00:00.123456789+08:00"
        let end = "2024:01:01 00:00:05.123456789+08:00"
        #expect(try MetadataDate.distribute(start: start, end: end, count: 3)
                == [start, "2024:01:01 00:00:03.123456789+08:00", end])
        #expect(try MetadataDate.distribute(start: start, end: end, count: 1) == [start])
        #expect(try MetadataDate.sequence(start: start, stepSeconds: -1, count: 2).last
                == "2023:12:31 23:59:59.123456789+08:00")
        #expect(throws: MetadataDateError.self) {
            try MetadataDate.distribute(start: end, end: start, count: 3)
        }
        #expect(throws: MetadataDateError.self) {
            try MetadataDate.sequence(start: start, stepSeconds: 1, count: 0)
        }
    }
}
