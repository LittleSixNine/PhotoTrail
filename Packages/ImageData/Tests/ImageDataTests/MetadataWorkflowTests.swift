import Exiftool
import Foundation
import Testing
@testable import ImageData

struct MetadataWorkflowTests {
    @Test func nativeListSourcesRoundTripCSVAndDoNotAcceptTextActions() throws {
        let url = URL(fileURLWithPath: "/authorized/a.jpg")
        let values: [MetadataTag: MetadataTagValue] = [.iptcByline: .list(["甲", "乙"]), .iptcKeywords: .list(["é", "e\u{301}"])]
        let record = try MetadataCSVRecord(url: url, relativePath: "a.jpg", values: values)
        let csv = try MetadataCSV.export([record], tags: [.iptcByline, .iptcKeywords])
        let imported = try MetadataCSV.load(csv, authorized: [record])
        #expect(imported.warnings.isEmpty)
        for operation in try #require(imported.operations[record.id]) {
            #expect(try operation.action.change(for: operation.tag, from: nil) == .set(values[operation.tag]!))
        }
        #expect(throws: MetadataFieldEditError.self) {
            try MetadataFieldEditAction.setText("wrong type").change(for: .iptcKeywords, from: nil)
        }
        #expect(try MetadataFieldEditAction.appendKeywords(["新增"]).change(for: .iptcKeywords, from: .list(["原有"]))
                == .set(.list(["原有", "新增"])))
    }

    @Test func datesKeepPrecisionOffsetsAndRejectInvalidComponents() throws {
        let original = try MetadataDate("2024:02:29 23:59:59.123456+08:00")
        #expect(original.text == "2024:02:29 23:59:59.123456+08:00")
        #expect(try original.shifting(seconds: 1).text == "2024:03:01 00:00:00.123456+08:00")
        #expect(throws: MetadataDateError.self) { try original.replacing(.year, with: 2023) }
        #expect(throws: MetadataDateError.self) { try MetadataDate("2024:02:30 00:00:00") }
        #expect(throws: MetadataDateError.self) { try MetadataDate("2024:01:01 00:00:00+15:00") }
        #expect(throws: MetadataDateError.self) {
            try MetadataDate("2024:03:09 02:30:00-05:00").addingCalendarDays(1, timeZoneID: "America/New_York")
        }
        let wall = try MetadataDate("2024:12:31 23:59:59")
        #expect(try wall.shifting(seconds: 1).text == "2025:01:01 00:00:00")
        let dst = try MetadataDate("2024:03:09 12:00:00-05:00")
        #expect(try dst.shifting(seconds: 86400).text == "2024:03:10 12:00:00-05:00")
        #expect(try dst.addingCalendarDays(1, timeZoneID: "America/New_York").text == "2024:03:10 12:00:00-04:00")
        #expect(try MetadataDate.sequence(start: wall.text, stepSeconds: 2, count: 3).last == "2025:01:01 00:00:03")
        #expect(try MetadataDate.distribute(start: "2024:01:01 00:00:00", end: "2024:01:01 00:00:05", count: 3)
                == ["2024:01:01 00:00:00", "2024:01:01 00:00:03", "2024:01:01 00:00:05"])
        #expect(try MetadataDate.distribute(start: wall.text, end: wall.text, count: 1) == [wall.text])
        #expect(throws: MetadataDateError.self) {
            try MetadataDate.distribute(start: "2024:01:02 00:00:00", end: "2024:01:01 00:00:00", count: 2)
        }
    }

    @Test func calendarOffsetsKeepEachDateAndRejectClamping() throws {
        let original = "2024:01:15 10:20:30.123456+08:00"
        let increase = MetadataFieldEditAction.offsetDate(years: 1, months: 1, days: 2,
                                                          hours: 3, minutes: 4, seconds: 5)
        let decrease = MetadataFieldEditAction.offsetDate(years: -1, months: -1, days: -2,
                                                          hours: -3, minutes: -4, seconds: -5)
        for tag in MetadataTag.allCases.filter(\.isDate) {
            #expect(try increase.change(for: tag, from: .text(original))
                    == .set(.text("2025:02:17 13:24:35.123456+08:00")))
            #expect(try decrease.change(for: tag, from: .text(original))
                    == .set(.text("2022:12:13 07:16:25.123456+08:00")))
            #expect(throws: MetadataDateError.self) { try increase.change(for: tag, from: nil) }
        }
        #expect(try MetadataDate("2024:12:31 23:59:59").offsetting(seconds: 1).text == "2025:01:01 00:00:00")
        #expect(try MetadataDate(original).offsetting().text == original)
        #expect(throws: MetadataDateError.self) { try MetadataDate("2024:02:29 12:00:00").offsetting(years: 1) }
        #expect(throws: MetadataDateError.self) { try MetadataDate("2024:01:31 12:00:00").offsetting(months: 1) }
        #expect(throws: MetadataDateError.self) { try MetadataDate("9999:12:31 23:59:59").offsetting(seconds: 1) }
        #expect(throws: MetadataDateError.self) { try MetadataDate(original).offsetting(years: Int.max) }
        #expect(throws: MetadataDateError.self) { try MetadataDate(original).offsetting(seconds: Int.min) }
        #expect(throws: MetadataFieldEditError.self) { try increase.change(for: .titleDefault, from: .text(original)) }
        let preset = try MetadataPreset(name: "offset", operations: [MetadataOperation(tag: .captureDate, action: increase)])
        #expect(try MetadataPreset.decode(preset.encode()) == preset)
    }

    @Test func presetVersionsAndCSVBoundaries() throws {
        let preset = try MetadataPreset(name: "署名", operations: [MetadataOperation(tag: .rightsDefault, action: .setText("© A")),
                                                               MetadataOperation(tag: .subject, action: .appendKeywords(["胶片"]))])
        #expect(try MetadataPreset.decode(preset.encode()) == preset)
        let wrong = String(decoding: try preset.encode(), as: UTF8.self).replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 2")
        #expect(throws: MetadataFieldEditError.self) { try MetadataPreset.decode(Data(wrong.utf8)) }
        let unknown = String(decoding: try preset.encode(), as: UTF8.self).replacingOccurrences(of: "setText", with: "script")
        #expect(throws: (any Error).self) { try MetadataPreset.decode(Data(unknown.utf8)) }
        let records = try ["a/same.jpg", "b/same.jpg"].map {
            try MetadataCSVRecord(url: URL(fileURLWithPath: "/authorized/\($0)"), relativePath: $0,
                                  values: [.descriptionDefault: .text("中文,\"引号\"\n第二行"), .subject: .list(["A,B", "二"]),
                                           .titleDefault: .text("=SUM(A1)")])
        }
        let tags: [MetadataTag] = [.titleDefault, .descriptionDefault, .subject]
        let text = try MetadataCSV.export(records, tags: tags)
        let imported = try MetadataCSV.load(text, authorized: records)
        #expect(imported.warnings.isEmpty && imported.operations.count == 2)
        #expect(imported.operations[records[0].id]?.contains(MetadataOperation(tag: .subject, action: .replaceKeywords(["A,B", "二"]))) == true)
        #expect(throws: MetadataCSVError.self) { try MetadataCSV.load(MetadataCSV.export(records + [records[0]], tags: tags), authorized: records) }
        let outside = text.replacingOccurrences(of: "a/same.jpg", with: "../same.jpg")
        #expect(try MetadataCSV.load(outside, authorized: records).warnings.count == 1)
        let display = try MetadataCSV.export(records, tags: tags, displayOnly: true)
        #expect(display.contains("'=SUM(A1)"))
        #expect(throws: MetadataCSVError.self) { try MetadataCSV.load(display, authorized: records) }
        #expect(throws: MetadataCSVError.self) { try MetadataCSV.parse("\"unterminated") }
        #expect(throws: MetadataCSVError.self) { try MetadataCSV.parse("\"x\"bad") }
        #expect(try MetadataCSV.parse("a,b\r\n\"a\r\nb\",\"x\"\"y\"\r\n") == [["a", "b"], ["a\r\nb", "x\"y"]])
    }

    @Test func numericFieldsValidateUnitsRangesAndEnums() throws {
        #expect(try MetadataTag.exposureTime.checkedText("1/125") == "0.008")
        #expect(try MetadataTag.iso.checkedText("100.0") == "100")
        for (tag, text) in [(MetadataTag.exposureTime, "1/0"), (.iso, "1.5"), (.fNumber, "0"),
                            (.whiteBalance, "2"), (.exposureProgram, "9"), (.focalLength, "nan")] {
            #expect(throws: Exiftool.ExiftoolError.self) { try tag.checkedText(text) }
        }
    }
}
