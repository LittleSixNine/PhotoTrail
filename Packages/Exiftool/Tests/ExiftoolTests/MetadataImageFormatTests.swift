import Testing
@testable import Exiftool

struct MetadataImageFormatTests {
    @Test func controlsNamespacesAndKeepsNonImagesOut() {
        #expect(MetadataImageFormat.readableExtensions.count == 108)
        #expect(MetadataImageFormat.writableExtensions.count == 61)
        for ext in ["PNG", "tiff", "psd", "jp2", "iiq", "x3f"] {
            #expect(MetadataImageFormat.supportsEditing(.exifArtist, extension: ext))
            #expect(MetadataImageFormat.supportsEditing(.iptcByline, extension: ext))
            #expect(MetadataImageFormat.supportsEditing(.creator, extension: ext))
        }
        for ext in ["hif", "avif", "jxl", "webp", "cr3"] {
            #expect(MetadataImageFormat.supportsEditing(.captureDate, extension: ext))
            #expect(MetadataImageFormat.supportsEditing(.creator, extension: ext))
            #expect(!MetadataImageFormat.supportsEditing(.iptcByline, extension: ext))
        }
        for ext in ["gif", "crw", "ciff"] {
            #expect(MetadataImageFormat.supportsEditing(.creator, extension: ext))
            #expect(!MetadataImageFormat.supportsEditing(.captureDate, extension: ext))
            #expect(!MetadataImageFormat.supportsEditing(.iptcByline, extension: ext))
        }
        for ext in ["3fr", "j2k", "dcm", "fits", "bmp", "exr", "qtif"] {
            #expect(MetadataImageFormat.readableExtensions.contains(ext))
            #expect(!MetadataImageFormat.supportsEditing(.creator, extension: ext))
        }
        for ext in ["pdf", "zip", "mov", "exe", "docx", ""] {
            #expect(!MetadataImageFormat.readableExtensions.contains(ext))
            #expect(!MetadataImageFormat.supportsEditing(.creator, extension: ext))
        }
    }
}
