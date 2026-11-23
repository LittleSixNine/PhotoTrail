import AVFoundation
import Imagetool
import Phototool
import PhotosUI
import SwiftUI

public struct MeasuredThumbnail: Sendable {
    public let image: Image
    public let bytes: Int
    public init(image: Image, bytes: Int) { self.image = image; self.bytes = bytes }
    init(_ bitmap: CGImage) {
        image = Image(decorative: bitmap, scale: 1)
        bytes = bitmap.bytesPerRow * bitmap.height
    }
}

private final class ThumbnailResult: @unchecked Sendable {
    private let lock = NSLock()
    private var value: MeasuredThumbnail?
    func set(_ image: MeasuredThumbnail?) { lock.withLock { value = image } }
    func get() -> MeasuredThumbnail? { lock.withLock { value } }
}

extension ImageData {
    private static let thumbnailQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "PhotoTrail.thumbnails"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    public func makeThumbnail(scale: CGFloat, maxDimension: Double = 1024, prioritize: Bool = false) async -> Image {
        await measuredThumbnail(scale: scale, maxDimension: maxDimension, prioritize: prioritize).image
    }

    public func measuredThumbnail(scale: CGFloat, maxDimension: Double, prioritize: Bool = false) async -> MeasuredThumbnail {
        if videoInfo != nil, let url = metadataCreatorImageURL {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
            if let frame = try? await generator.image(at: .zero) { return MeasuredThumbnail(frame.image) }
            return MeasuredThumbnail(image: Image(systemName: "film"), bytes: 128)
        }
        var image: MeasuredThumbnail?
        switch metadata.source {
        case .image(let url), .xmp(let url):
            // ImageIO decoding must not occupy the UI executor. Bound RAW decoding as well.
            let operation = BlockOperation()
            operation.queuePriority = prioritize ? .veryHigh : .normal
            operation.qualityOfService = prioritize ? .userInitiated : .utility
            let result = ThumbnailResult()
            image = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    operation.addExecutionBlock {
                        let decoded = Imagetool.imageThumbnail(url: url, maxDimension: maxDimension)
                        result.set(decoded?.cgImage(forProposedRect: nil, context: nil, hints: nil).map(MeasuredThumbnail.init))
                    }
                    // Completion also runs for a cancelled, not-yet-started operation.
                    operation.completionBlock = { continuation.resume(returning: result.get()) }
                    Self.thumbnailQueue.addOperation(operation)
                }
            } onCancel: { operation.cancel() }
        case .photos(let pickerItem, let asset):
            if let thumbnail = await Phototool.thumbnail(from: pickerItem, asset: asset, maxDimension: Int(maxDimension)) {
                image = MeasuredThumbnail(thumbnail)
            }
        default:
            break
        }
        if Task.isCancelled { return MeasuredThumbnail(image: Image(systemName: "photo.badge.exclamationmark"), bytes: 128) }
        if image == nil {
            // try to create an image of noImageView for proper
            // opacity
            await MainActor.run {
                let renderer = ImageRenderer(content: noImageView(maxDimension: maxDimension))
                renderer.scale = scale
                if let bitmap = renderer.cgImage {
                    image = MeasuredThumbnail(bitmap)
                }
            }
        }
        if let image {
            return image
        }
        return MeasuredThumbnail(image: Image(systemName: "photo.badge.exclamationmark"), bytes: 128)
    }

    func noImageView(maxDimension: Double = 1024) -> some View {
        VStack {
            Image(systemName: "photo.badge.exclamationmark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .opacity(0.18)
        }
        .frame(width: max(32, maxDimension), height: max(32, maxDimension))
    }
}
