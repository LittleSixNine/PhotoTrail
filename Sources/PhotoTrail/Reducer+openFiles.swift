import Foundation
import ImageData
import SwiftUI
import UDF
import UniformTypeIdentifiers

// initiate processing of the given array of URLs. Get the full list
// of unique urls and save it for the next step.

extension PhotoTrailReducer {
    func openFiles(_ state: inout PhotoTrailState, urls: [URL]) {
        // Needed to access when using the fileImporter
        for url in urls {
            let startedAccess = url.startAccessingSecurityScopedResource()
            let importable = url.isSupportedPhotoImage || url.isGPXFile || isFolder(url)
            if startedAccess, importable {
                state.scopedURLs.append(url)
            } else if startedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Get all requested URLs
        var seenPaths = Set<String>()
        let requestedURLs = urls.flatMap { url in
            isFolder(url) ? urlsIn(folder: url) : [url]
        }.filter { seenPaths.insert($0.standardizedFileURL.path).inserted }
        state.ignoredFileCount = requestedURLs.filter { !$0.isSupportedPhotoImage && !$0.isGPXFile }.count
        let imageURLs = requestedURLs.filter { $0.isSupportedPhotoImage || $0.isGPXFile }

        // check for duplicates of URLs already known
        let processed = Set(state.imageData.map { $0.fullPath })
        let duplicates = imageURLs.filter { processed.contains($0.path) }
        if duplicates.isEmpty {
            state.uniqueURLs = imageURLs.uniqued()
        } else {
            state.addSheet(type: .duplicateImageSheet)
            let uniques = imageURLs.filter { !duplicates.contains($0) }.uniqued()
            if uniques.isEmpty {
                state.uniqueURLs = nil
            } else {
                state.uniqueURLs = uniques
            }
        }
    }

    // Check if a given file URL refers to a folder
    private func isFolder(_ url: URL) -> Bool {
        let resources = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return resources?.isDirectory ?? false
    }

    // Recursivly iterate over a folder looking for files.
    // Returns an array of contained urls
    private func urlsIn(folder url: URL) -> [URL] {
        var foundURLs = [URL]()
        let fileManager = FileManager.default
        guard let urlEnumerator =
            fileManager.enumerator(at: url,
                                   includingPropertiesForKeys: [.isDirectoryKey],
                                   options: UserDefaults.standard.object(forKey: SettingsPreferences.recursiveImportKey) as? Bool == false
                                       ? [.skipsHiddenFiles, .skipsSubdirectoryDescendants] : [.skipsHiddenFiles],
                                   errorHandler: nil) else {
                logger.error("\(#function, privacy: .public): No enumerator for \(url, privacy: .public)")
                return []
            }
        while let fileUrl = urlEnumerator.nextObject() as? URL {
            if !isFolder(fileUrl) {
                foundURLs.append(fileUrl)
            }
        }
        return foundURLs
    }
}

extension URL {
    var isGPXFile: Bool {
        pathExtension.lowercased() == "gpx"
    }

    var isSupportedPhotoImage: Bool {
        let ext = pathExtension.lowercased()
        guard !ext.isEmpty, !isGPXFile, !isVideoFile,
              let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .image)
    }

    var isVideoFile: Bool {
        let ext = pathExtension.lowercased()
        switch ext {
        case "3g2", "3gp", "avi", "braw", "crm", "flv", "m2ts", "m2v",
             "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "mts", "mxf",
             "ogv", "qt", "r3d", "ts", "vob", "webm", "wmv":
            return true
        default:
            return UTType(filenameExtension: ext)?.conforms(to: .movie) == true
        }
    }
}

// remove duplicates from a sequence while maintaining order

extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var set = Set<Element>()
        return filter { set.insert($0).inserted }
    }
}
