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

struct MetadataDateProjectionTests {
    private struct Fixture: Decodable {
        let version: Int
        let referenceSha256: String
        let entries: [Vector]
    }
    private struct Expected: Decodable {
        let kind: String
        let seconds: Int64
        let nanoseconds: Int32
        let offsetMinutes: Int?
    }
    private struct Vector: Decodable {
        let id: String
        let input: String
        let expected: Expected?
        let error: String?
    }
    @Test func baselineFoundationVectors() throws {
        let url = try #require(Bundle.module.url(forResource: "date-projection-v2", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        #expect(fixture.version == 2)
        #expect(fixture.referenceSha256 == "593fa443f634234b81308143d96b0e6bc0373782734d6ba85a69b90c4d153ccc")
        #expect(fixture.entries.count == 38)
        #expect(Set(fixture.entries.map(\.id)).count == fixture.entries.count)
        for vector in fixture.entries {
            if let expected = vector.expected {
                let date = try MetadataDate(vector.input)
                let result = try date.projection()
                #expect(result.kind.rawValue == expected.kind, "\(vector.id)")
                #expect(result.seconds == expected.seconds, "\(vector.id)")
                #expect(result.nanoseconds == expected.nanoseconds, "\(vector.id)")
                #expect(result.offsetMinutes == expected.offsetMinutes, "\(vector.id)")
                #expect(date.text == vector.input, "projection must not rewrite \(vector.id)")
            } else {
                #expect(vector.error == "invalidDate")
                #expect(throws: MetadataDateError.self) { try MetadataDate(vector.input).projection() }
            }
        }
    }
    @Test func epochNegativeSecondsAndDomains() throws {
        let epoch = try MetadataDate("1970:01:01 00:00:00Z").projection()
        #expect(epoch.seconds == 0 && epoch.nanoseconds == 0 && epoch.kind == .instant && epoch.offsetMinutes == 0)
        let before = try MetadataDate("1969:12:31 23:59:59.123456789Z").projection()
        #expect(before.seconds == -1 && before.nanoseconds == 123456789)
        let wall = try MetadataDate("1970:01:01 00:00:00.123456789").projection()
        #expect(wall.seconds == 0 && wall.nanoseconds == 123456789 && wall.kind == .wall && wall.offsetMinutes == nil)
        #expect(try MetadataDate("1970:01:01 00:00:00+14:00").projection().seconds == -50400)
        #expect(try MetadataDate("1970:01:01 00:00:00-14:00").projection().seconds == 50400)
    }
    @Test func fractionalPrecisionAndOffsetIdentity() throws {
        for digits in 1...9 {
            let fraction = String("123456789".prefix(digits))
            let result = try MetadataDate("1970:01:01 00:00:00." + fraction + "Z").projection()
            #expect(result.nanoseconds == Int32(fraction + String(repeating: "0", count: 9 - digits)))
        }
        #expect(try MetadataDate("1970:01:01 00:00:00.1Z").projection()
                == MetadataDate("1970:01:01 00:00:00.100000000Z").projection())
        let first = try MetadataDate("1970:01:01 00:00:00.123456788Z").projection()
        let second = try MetadataDate("1970:01:01 00:00:00.123456789Z").projection()
        #expect(first.seconds == second.seconds && second.nanoseconds - first.nanoseconds == 1)
        #expect(try MetadataDate("1970:01:01 08:00:00+08:00").projection().seconds == 0)
        let zero = try MetadataDate("1970:01:01 00:00:00.000000001-00:00")
        #expect(try zero.projection().nanoseconds == 1)
        #expect(try zero.projection().kind == .instant)
        #expect(zero.text == "1970:01:01 00:00:00.000000001-00:00")
    }
    @Test func historicalCutoverAndPlatformBounds() throws {
        let before = try MetadataDate("1582:10:04 00:00:00Z").projection()
        let after = try MetadataDate("1582:10:15 00:00:00Z").projection()
        #expect(after.seconds - before.seconds == 86400)
        #expect(try MetadataDate("1500:02:29 00:00:00Z").projection().kind == .instant)
        let lower = try MetadataDate("0001:01:01 00:00:00+14:00").projection()
        let upper = try MetadataDate("9999:12:31 23:59:59-14:00").projection()
        #expect(lower.seconds < -62135596800) // Platform DateTimeOffset minimum, not core validity.
        #expect(upper.seconds > 253402300799)
    }
}
