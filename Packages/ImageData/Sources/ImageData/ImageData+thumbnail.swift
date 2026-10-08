import Imagetool
import Phototool
import PhotosUI
import SwiftUI

private final class ThumbnailResult: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Image?
    func set(_ image: Image?) { lock.withLock { value = image } }
    func get() -> Image? { lock.withLock { value } }
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
        var image: Image?
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
                        result.set(decoded.map { Image(nsImage: $0) })
                    }
                    // Completion also runs for a cancelled, not-yet-started operation.
                    operation.completionBlock = { continuation.resume(returning: result.get()) }
                    Self.thumbnailQueue.addOperation(operation)
                }
            } onCancel: { operation.cancel() }
        case .photos(let pickerItem, _):
            if let thumbnail = await Phototool.image(from: pickerItem) {
                image = thumbnail
            }
        default:
            break
        }
        if Task.isCancelled { return Image(systemName: "photo.badge.exclamationmark") }
        if image == nil {
            // try to create an image of noImageView for proper
            // opacity
            await MainActor.run {
                let renderer = ImageRenderer(content: noImageView(maxDimension: maxDimension))
                renderer.scale = scale
                if let nsImage = renderer.nsImage {
                    image = Image(nsImage: nsImage)
                }
            }
        }
        if let image {
            return image
        }
        return Image(systemName: "photo.badge.exclamationmark")
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
