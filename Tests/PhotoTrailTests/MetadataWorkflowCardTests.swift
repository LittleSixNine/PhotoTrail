import Exiftool
import ImageData
import Testing
@testable import PhotoTrail

struct MetadataWorkflowCardTests {
    @Test func renamingPreservesOperationsAndRejectsNameConflicts() throws {
        let operation = MetadataOperation(tag: .captureDate, action: .shiftDate(seconds: 60))
        let presets = [try MetadataPreset(name: "图片", operations: [operation]),
                       try MetadataPreset(name: "图片 2", operations: [operation])]
        let renamed = try MetadataWorkflowCard.renamePreset("图片", to: "  统一时间  ", in: presets)
        #expect(renamed.map(\.name) == ["统一时间", "图片 2"])
        #expect(renamed[0].operations == presets[0].operations)
        #expect(try MetadataWorkflowCard.renamePreset("图片", to: "图片", in: presets) == presets)
        for invalid in ["图片 2", "  "] {
            #expect(throws: (any Error).self) {
                try MetadataWorkflowCard.renamePreset("图片", to: invalid, in: presets)
            }
        }
        #expect(throws: (any Error).self) {
            try MetadataWorkflowCard.renamePreset("不存在", to: "统一时间", in: presets)
        }
    }

    @Test func duplicatePresetNamesSkipExistingSuffixes() {
        #expect(MetadataWorkflowCard.uniquePresetName("图片", existing: ["图片", "图片 2"]) == "图片 3")
        #expect(MetadataWorkflowCard.uniquePresetName("图片", existing: ["图片", "图片 3"]) == "图片 2")
        #expect(MetadataWorkflowCard.uniquePresetName("图片 2", existing: ["图片 2"]) == "图片 2 2")
        #expect(MetadataWorkflowCard.uniquePresetName("图片", existing: [], allowOriginal: true) == "图片")
        #expect(MetadataWorkflowCard.uniquePresetName("图片", existing: ["图片", "图片 2"], allowOriginal: true) == "图片 3")
    }

    @Test func cardsPreserveOperationOrderAndLegacyPresetFormat() throws {
        let first = MetadataOperation(tag: .captureDate, action: .shiftDate(seconds: 60))
        let second = MetadataOperation(tag: .dateOriginal, action: .copy(.captureDate))
        let third = MetadataOperation(tag: .sidecarDate, action: .copy(.captureDate))
        var cards = MetadataWorkflowCard.cards(from: [first, second, third])
        #expect(cards.count == 2)
        #expect(cards.flatMap(\.operations) == [first, second, third])
        #expect(MetadataWorkflowCard.cards(from: [second, second]).count == 2)
        let selfCopy = MetadataOperation(tag: .captureDate, action: .copy(.captureDate))
        #expect(MetadataWorkflowCard.cards(from: [selfCopy, second]).count == 2)
        let id = cards[1].id
        cards.swapAt(0, 1)
        #expect(cards[0].id == id)
        let preset = try MetadataPreset(name: "日期", operations: cards.flatMap(\.operations))
        #expect(try MetadataPreset.decode(preset.encode()).operations == [second, third, first])
    }
}
