import Foundation
import GpxTrackLog
import ImageData
import SwiftUI
import UDF
import UniformTypeIdentifiers

// initiate processing of the given array of URLs. Get the full list
// of unique urls and save it for the next step.

extension PhotoTrailReducer {
    func openFiles(_ state: inout PhotoTrailState, urls: [URL]) {
        let result = scanFiles(urls)
        state.scopedURLs.append(contentsOf: result.scoped)
        state.ignoredFileCount = result.ignored
        selectUniqueFiles(&state, imageURLs: result.urls)
    }

    func selectUniqueFiles(_ state: inout PhotoTrailState, imageURLs: [URL]) {
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

    /// Filesystem work runs in a detached utility task at production import entry points.
    nonisolated func scanFiles(_ urls: [URL]) -> (urls: [URL], ignored: Int, scoped: [URL]) {
        var scoped: [URL] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            if access && (url.isSupportedPhotoImage || url.isTrackFile || isFolder(url)) { scoped.append(url) }
            else if access { url.stopAccessingSecurityScopedResource() }
        }
        var seen = Set<String>()
        let requested = urls.flatMap { isFolder($0) ? urlsIn(folder: $0) : [$0] }
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
        let accepted = requested.filter { $0.isSupportedPhotoImage || $0.isTrackFile }
        return (accepted, requested.count - accepted.count, scoped)
    }

    // Check if a given file URL refers to a folder
    nonisolated func isFolder(_ url: URL) -> Bool {
        let resources = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return resources?.isDirectory ?? false
    }

    // Recursivly iterate over a folder looking for files.
    // Returns an array of contained urls
    nonisolated func urlsIn(folder url: URL) -> [URL] {
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
    var isTrackFile: Bool {
        GpxTrackLog.supportedExtensions.contains(pathExtension.lowercased())
    }

    var isSupportedPhotoImage: Bool {
        let ext = pathExtension.lowercased()
        guard !ext.isEmpty, !isTrackFile, !isVideoFile,
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

extension UTType {
    static var photoTrailTracks: [UTType] {
        GpxTrackLog.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
    }
}
