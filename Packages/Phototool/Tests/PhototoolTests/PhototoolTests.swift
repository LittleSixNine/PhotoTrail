import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Phototool

struct PhototoolTests {
    @Test func pickerFileHonorsOrientationAndRequestedDimensions() throws {
        let context = try #require(CGContext(data: nil, width: 4000, height: 3000, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let input = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, input, [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        for size in [160, 1024] {
            let thumbnail = try #require(Phototool.downsample(data as Data, maxDimension: size))
            #expect(thumbnail.width == size * 3 / 4)
            #expect(thumbnail.height == size)
            print("4000x3000 rotated JPEG -> \(thumbnail.width)x\(thumbnail.height), bitmap bytes \(thumbnail.bytesPerRow * thumbnail.height)")
        }
    }
}
