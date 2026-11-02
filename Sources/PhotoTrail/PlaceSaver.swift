import Foundation

actor PlaceSaver {
    static let shared = PlaceSaver()
    private let url: URL
    private var unreadable = false

    init(url: URL = URL.applicationSupportDirectory.appendingPathComponent("Places")) { self.url = url }

    func read() throws -> [Place] {
        do {
            let places = try JSONDecoder().decode([Place].self, from: Data(contentsOf: url))
            unreadable = false
            return places
        } catch CocoaError.fileReadNoSuchFile { unreadable = false; return [] }
        catch { unreadable = true; throw error }
    }

    func write(places: [Place]) throws {
        // A failed read must not turn the next location selection into an overwrite of the old records.
        guard !unreadable else { throw CocoaError(.fileReadCorruptFile) }
        let encoded = try JSONEncoder().encode(places)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded.write(to: url, options: .atomic)
    }
}
