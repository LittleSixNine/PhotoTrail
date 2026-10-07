import GpxTrackLog
import ImageData
import OSLog
import SwiftUI
import UDF

enum OpenHelper {

    @MainActor @discardableResult
    static func importFiles(_ store: Store<PhotoTrailState, PhotoTrailEvent>, urls: [URL],
                            description: String, finished: (@MainActor () -> Void)? = nil) -> Task<Void, Never> {
        Task { @MainActor in
            guard !store.saveInProgress, !store.importProgress.isActive else { return }
            let progress = store.importProgress
            progress.begin(.scanning)
            defer { progress.finish(); finished?() }
            let result = await Task.detached(priority: .utility) { PhotoTrailReducer().scanFiles(urls) }.value
            store.send(.filesScanned(result.urls, ignored: result.ignored, scoped: result.scoped), undoable: false)
            let unique = store.uniqueURLs ?? []
            store.send(.clearUniqueURLs, undoable: false)
            guard !unique.isEmpty else { return }
            await open(store, urls: unique, description: description, spinnerEnabled: nil, ownsProgress: false).value
        }
    }

    // Start a mainactor task to process image and track files. The
    // task is returned so code tests can wait until the task is complete.

    @MainActor @discardableResult
    static func open(_ store: Store<PhotoTrailState, PhotoTrailEvent>, urls: [URL],
                     description: String,
                     spinnerEnabled: Binding<Bool>?, ownsProgress: Bool = true) -> Task<Void, Never> {
        let task = Task { @MainActor in
            guard !store.saveInProgress, !ownsProgress || !store.importProgress.isActive else { return }
            defer { if ownsProgress { store.importProgress.finish() } }
            if let spinnerEnabled {
                spinnerEnabled.wrappedValue = true
            }
            store.beginUndoGroup(description: description)
            await Self.images(for: urls, store: store)
            await Self.tracks(for: urls, store: store)
            store.endUndoGroup()
            if let spinnerEnabled {
                spinnerEnabled.wrappedValue = false
            }
        }
        return task
    }

    // Create ImageData entries for imported images and add them
    // to the table.

    @MainActor static private
    func images(for urls: [URL],
                store: Store<PhotoTrailState, PhotoTrailEvent>) async {
        let imageURLs = urls.filter(\.isSupportedPhotoImage)
        guard !imageURLs.isEmpty else { return }
        store.importProgress.begin(.images, total: imageURLs.count)
        var newImages: [ImageData] = []
        var lastProgress = ProcessInfo.processInfo.systemUptime

        let start = Date.now.timeIntervalSince1970

        await withTaskGroup { group in
            var limit = min(imageURLs.count, PhotoTrailApp.maxConcurrentImageLoads)
            for ix in 0..<limit {
                group.addTask {
                    let interval = Self.markStart(#function)
                    defer {
                        Self.markEnd(#function, interval: interval)
                    }
                    return ImageData(from: imageURLs[ix])
                }
            }
            for await imageData in group {
                newImages.append(imageData)
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastProgress >= 0.15 || newImages.count == imageURLs.count {
                    store.importProgress.update(completed: newImages.count)
                    lastProgress = now
                }
                if limit < imageURLs.count {
                    let url = imageURLs[limit]
                    limit += 1
                    group.addTask {
                        let interval = Self.markStart(#function)
                        defer {
                            Self.markEnd(#function, interval: interval)
                        }
                        return ImageData(from: url)
                    }
                }
            }
        }
        await MainActor.run {
            store.send(.addImages(newImages))
            if UserDefaults.standard.object(forKey: SettingsPreferences.pairJPGRAWKey) as? Bool != false {
                store.send(.linkPairedImages)
            }
            store.send(.sortUsingCurrentComparator)
        }
        let duration = Date.now.timeIntervalSince1970 - start
        Self.logger.info("""
            \(imageURLs.count, privacy: .public) items added in \
            \(duration, privacy: .public) seconds
            """)
    }

    @MainActor static private
    func tracks(for urls: [URL],
                store: Store<PhotoTrailState, PhotoTrailEvent>) async {
        let trackURLs = urls.filter(\.isTrackFile)
        guard !trackURLs.isEmpty else { return }
        await MainActor.run { store.send(.gpxLoadViewClosed, undoable: false) }
        store.importProgress.begin(.tracks, total: trackURLs.count)
        var tracklogs: [(String, GpxTrackLog?)] = []
        var lastProgress = ProcessInfo.processInfo.systemUptime

        let start = Date.now.timeIntervalSince1970

        await withTaskGroup(of: (String, GpxTrackLog?).self) { group in
            var limit = min(trackURLs.count, PhotoTrailApp.maxConcurrentTasks)
            for ix in 0..<limit {
                let url = trackURLs[ix]
                group.addTask {
                    do {
                        let trackLog = try GpxTrackLog(contentsOf: url)
                        return (url.path, trackLog)
                    } catch {
                        return (url.path, nil)
                    }
                }
            }
            for await (path, tracklog) in group {
                tracklogs.append((path, tracklog))
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastProgress >= 0.15 || tracklogs.count == trackURLs.count {
                    store.importProgress.update(completed: tracklogs.count)
                    lastProgress = now
                }
                if limit < trackURLs.count {
                    let url = trackURLs[limit]
                    group.addTask {
                        do {
                            let trackLog = try GpxTrackLog(contentsOf: url)
                            return (url.path, trackLog)
                        } catch {
                            return (url.path, nil)
                        }
                    }
                    limit += 1
                }
            }
        }
        await MainActor.run {
            for (path, tracklog) in tracklogs {
               store.send(.readTrackLog(path, tracklog))
            }
            store.send(.finishedAddingTracks)
        }
        let duration = Date.now.timeIntervalSince1970 - start
        Self.logger.info("""
            \(trackURLs.count, privacy: .public) tracks added in \
            \(duration, privacy: .public) seconds
            """)
    }
}

// logging and signposting support

extension OpenHelper {
    static let logger =
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "PhotoTrail",
               category: "OpenHelper")
    static let signposter = OSSignposter(logger: logger)

    static func markStart(_ desc: StaticString) -> OSSignpostIntervalState {
        let signpostID = Self.signposter.makeSignpostID()
        let interval = Self.signposter.beginInterval(desc, id: signpostID)
        return interval
    }

    static func markEnd(_ desc: StaticString, interval: OSSignpostIntervalState) {
        Self.signposter.endInterval(desc, interval)
    }
}
