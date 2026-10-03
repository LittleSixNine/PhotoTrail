import Foundation

enum MetadataFieldFilter {
    static func matches(query: String, presentOnly: Bool, editedOnly: Bool,
                        names: [String], hasEdits: @autoclosure () -> Bool,
                        values: () -> [String?]) -> Bool {
        if editedOnly && !hasEdits() { return false }
        let nameMatches = query.isEmpty || names.contains { $0.localizedCaseInsensitiveContains(query) }
        if !presentOnly && nameMatches { return true }
        let fieldValues = values()
        if presentOnly && !fieldValues.contains(where: { $0 != nil }) { return false }
        return nameMatches || fieldValues.contains { $0?.localizedCaseInsensitiveContains(query) == true }
    }
}
