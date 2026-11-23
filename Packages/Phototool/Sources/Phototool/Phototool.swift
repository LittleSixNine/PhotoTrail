import Metadata
import OSLog
import Photos
import PhotosUI
import ImageIO
import UniformTypeIdentifiers
import SwiftUI

public struct Phototool {
    public static func metadata(from item: PhotosPickerItem, asset: PHAsset?) -> Metadata {
        var metadata = Metadata(source: .photos(item, asset))
        if let asset {
            metadata.dateTimeCreated = if let date = asset.creationDate {
                Metadata.timestamp(from: date)
            } else {
                nil
            }
            metadata.location = asset.location?.coordinate
            metadata.elevation = asset.location?.altitude
        }
        // no city/state/country in a PHAsset
        return metadata
    }

    private struct PickerFile: Transferable {
        let data: Data
        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(importedContentType: .image) { received in
                // Keep a mapping of the picker file after its temporary URL expires.
                try Self(data: Data(contentsOf: received.file, options: .alwaysMapped))
            }
            // Some picker providers vend only a data representation.
            DataRepresentation(importedContentType: .image) { Self(data: $0) }
        }
    }

    public static func image(from item: PhotosPickerItem) async -> Image? {
        await thumbnail(from: item, asset: nil, maxDimension: 1024).map { Image(decorative: $0, scale: 1) }
    }

    public static func thumbnail(from item: PhotosPickerItem, asset: PHAsset?, maxDimension: Int) async -> CGImage? {
        let size = max(1, min(4096, maxDimension))
        if let asset {
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            let stream = AsyncStream<CGImage?> { continuation in
                let request = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: size, height: size),
                    contentMode: .aspectFit, options: options) { image, info in
                    guard info?[PHImageResultIsDegradedKey] as? Bool != true else { return }
                    continuation.yield(image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
                    continuation.finish()
                }
                continuation.onTermination = { reason in
                    if case .cancelled = reason { PHImageManager.default().cancelImageRequest(request) }
                }
            }
            for await bitmap in stream {
                if let bitmap { return bitmap }
            }
        }
        guard !Task.isCancelled, let file = try? await item.loadTransferable(type: PickerFile.self) else { return nil }
        guard !Task.isCancelled else { return nil }
        return downsample(file.data, maxDimension: size)
    }

    static func downsample(_ data: Data, maxDimension size: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: size
              ] as CFDictionary) else { return nil }
        return cgImage
    }

    public static func assets(for id: String) async -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [id],
                                         options: nil)
        if let asset = result.firstObject {
            return asset
        }
        return nil
    }

    public static func name(from asset: PHAsset?) -> String {
        if let asset {
            let assetResources = PHAssetResource.assetResources(for: asset)
            return assetResources.first?.originalFilename ?? "unknown"
        }
        return "unknown"
    }

    public static func update(timestamp: Date? = nil,
                              location: CLLocation?,
                              for asset: PHAsset,
                              updateLocation: Bool = true) async -> Bool {
        let library = PHPhotoLibrary.shared()
        do {
            try await library.performChanges {
                let assetChangeReqeust = PHAssetChangeRequest(for: asset)
                // timestamps can only be changed, not deleted
                if let timestamp {
                    assetChangeReqeust.creationDate = timestamp
                }
                if updateLocation {
                    assetChangeReqeust.location = location
                }
            }
            return true
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "PhotoTool",
                   category: "Phototool")
                .error("update: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
