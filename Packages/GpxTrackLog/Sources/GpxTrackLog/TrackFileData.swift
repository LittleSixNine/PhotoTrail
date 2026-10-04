import Foundation

enum TrackFileData {
    // Bounded input and expanded XML; KMZ resources never get extracted to disk.
    static let maximumBytes = 64 * 1_024 * 1_024

    static func read(_ url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw TrackReadError.tooLarge }
        return data
    }

    static func readKMZ(_ url: URL) throws -> Data {
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= maximumBytes else { throw TrackReadError.tooLarge }
        let listing = try unzip(["-Z1", url.path], maximum: 1_024 * 1_024)
        guard let names = String(data: listing, encoding: .utf8) else { throw TrackReadError.invalidArchive }
        let entries = names.split(separator: "\n").map(String.init).filter { $0.lowercased().hasSuffix(".kml") }
        // Standard KMZ has one main KML. Prefer root doc.kml; otherwise require one unambiguous document.
        let roots = entries.filter { $0.lowercased() == "doc.kml" }
        guard roots.count <= 1, let entry = roots.first ?? (entries.count == 1 ? entries.first : nil),
              !entry.hasPrefix("-") else {
            throw TrackReadError.invalidArchive
        }
        // unzip member arguments are patterns even without a shell. Quote their metacharacters.
        let literal = entry.reduce(into: "") { result, character in
            if "\\*?[]".contains(character) { result.append("\\") }
            result.append(character)
        }
        return try unzip(["-p", url.path, literal], maximum: maximumBytes)
    }

    private static func unzip(_ arguments: [String], maximum: Int) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/unzip")
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardOutput = output
        try process.run()
        defer {
            try? output.fileHandleForReading.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }
        var data = Data()
        while let chunk = try output.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
            guard data.count + chunk.count <= maximum else { throw TrackReadError.tooLarge }
            data.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw TrackReadError.invalidArchive }
        return data
    }
}
