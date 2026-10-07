import Coords
import Metadata
import PhotosUI
import SwiftUI
import Testing
@testable import ImageData

@MainActor
@Suite("Image Data Thumbnail Tests")
struct ThumbnailTests {
    let badImage = Image(systemName: "photo.badge.exclamationmark")

    @Test func imageThumbnail() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "alldata",
                              withExtension: "jpg")
        )
        let imageData = ImageData(from: url)
        let image = await imageData.makeThumbnail(scale: 1.0)
        #expect(image != badImage)
    }

    @Test func cancelledQueuedThumbnailCompletesWithoutRenderingPlaceholder() async throws {
        let url = try #require(Bundle.module.url(forResource: "alldata", withExtension: "jpg"))
        let image = ImageData(metadata: Metadata(source: .image(url)), name: "cancelled.jpg")
        let task = Task { await image.makeThumbnail(scale: 2, maxDimension: 160) }
        task.cancel()
        #expect(await task.value == badImage)
    }

    @Test func imageWithXmpThumbnail() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "262M1559",
                              withExtension: "DNG")
        )
        let imageData = ImageData(from: url)
        let image = await imageData.makeThumbnail(scale: 1.0)
        #expect(image != badImage)
    }

    // Enabling this app will crash Xcode testing
    // NSPhotoLibraryUsageDescription isn't found in the test bundle?

    @Test(.disabled()) func photosThumbnail() async throws {
        let imageData = ImageData(from: PhotosPickerItem(itemIdentifier: "TestItem"),
                                  asset: nil)
        let image = await imageData.makeThumbnail(scale: 1.0)
        #expect(image != badImage)
    }

    @Test func noImage() async throws {
        let imageData = ImageData()
        let image = await imageData.makeThumbnail(scale: 1.0)
        #expect(image != badImage)
    }
}
