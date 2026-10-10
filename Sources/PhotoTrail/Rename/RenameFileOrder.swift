import Foundation

struct RenameFileFilter: Equatable, Sendable {
    var query = ""
    var fileExtension = ""
    var folder = ""
    var camera = ""
    var dateFrom: Date?
    var dateTo: Date?
    var gps = 0
    var tag = ""
    var presence = 0

    var needsTags: Bool { !camera.isEmpty || dateFrom != nil || dateTo != nil || gps != 0 || !tag.isEmpty }

    func matches(_ input: RenameInput, settings: RenameSettings) -> Bool {
        func contains(_ text: String, _ search: String) -> Bool {
            search.isEmpty || text.localizedCaseInsensitiveContains(search)
        }
        guard contains(input.url.path, query),
              fileExtension.isEmpty || input.url.pathExtension.caseInsensitiveCompare(fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". "))) == .orderedSame,
              contains(input.directory.path, folder) else { return false }
        if needsTags && input.metadataFailure { return false }
        guard contains((RenameEngine.tag("CameraMake", input: input) ?? "") + " " + (RenameEngine.tag("CameraModel", input: input) ?? ""), camera) else { return false }
        if dateFrom != nil || dateTo != nil {
            guard let date = RenameEngine.shooting(input, settings: settings)?.date,
                  dateFrom.map({ date >= $0 }) ?? true, dateTo.map({ date <= $0 }) ?? true else { return false }
        }
        let located = RenameEngine.tag("GPSLatitude", input: input) != nil && RenameEngine.tag("GPSLongitude", input: input) != nil
        if gps != 0 && located != (gps == 1) { return false }
        if !tag.isEmpty && presence != 0 {
            let exists = !(RenameEngine.tag(tag, input: input) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if exists != (presence == 1) { return false }
        }
        return true
    }
}

enum RenameFileOrder {
    static func moving(_ moving: Set<String>, before target: String, visible: [String], full: [String]) -> [String] {
        guard !moving.isEmpty, !moving.contains(target), (target.isEmpty || visible.contains(target)), moving.isSubset(of: Set(visible)) else { return full }
        let block = visible.filter { moving.contains($0) }
        var reordered = visible.filter { !moving.contains($0) }
        guard let index = target.isEmpty ? reordered.count : reordered.firstIndex(of: target) else { return full }
        reordered.insert(contentsOf: block, at: index)
        let visibleSet = Set(visible)
        var next = reordered.makeIterator()
        return full.map { visibleSet.contains($0) ? next.next()! : $0 }
    }
}
