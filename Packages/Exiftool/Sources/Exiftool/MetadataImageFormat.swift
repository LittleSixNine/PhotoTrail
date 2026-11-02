import Foundation

/// Format support for controlled metadata fields, independent of preview decoding.
public enum MetadataImageFormat {
    private static let exifIPTCXMP: Set<String> = [
        "ai", "ait", "arq", "arw", "cr2", "cs1", "dng", "eps", "epsf", "erf", "fff", "gpr",
        "hdp", "iiq", "insp", "jng", "jp2", "jpe", "jpeg", "jpf", "jpg", "jpm", "jpx", "jxr",
        "mef", "mng", "mos", "mpo", "mrw", "nef", "nrw", "orf", "ori", "pef", "png", "ps",
        "psb", "psd", "psdt", "raf", "raw", "rw2", "rwl", "sr2", "srw", "thm", "tif", "tiff",
        "wdp", "x3f"
    ]
    private static let exifXMP: Set<String> = [
        "avif", "cr3", "flif", "heic", "heif", "hif", "jxl", "webp"
    ]
    private static let xmpOnly: Set<String> = ["ciff", "crw", "gif"]
    private static let readOnly: Set<String> = [
        "3fr", "bmp", "bpg", "btf", "czi", "dc3", "dcm", "dcr", "dib", "dic", "dicm", "dpx",
        "exr", "fits", "fpf", "fpx", "hdr", "j25", "j2c", "j2k", "jpc", "kdc", "lfp", "lfr",
        "lif", "mif", "miff", "mrc", "pbm", "pcd", "pct", "pcx", "pgf", "pgm", "pict", "pmp",
        "ppm", "psp", "pspimage", "qif", "qti", "qtif", "rwz", "seq", "srf", "svg", "xcf"
    ]

    public static let writableExtensions = exifIPTCXMP.union(exifXMP).union(xmpOnly)
    public static let readableExtensions = writableExtensions.union(readOnly)

    public static func supportsEditing(_ tag: MetadataTag, extension ext: String) -> Bool {
        let ext = ext.lowercased()
        guard writableExtensions.contains(ext) else { return false }
        if tag.isFileTime || tag.supportsSidecar { return true }
        if tag.rawValue.hasPrefix("IPTC:") { return exifIPTCXMP.contains(ext) }
        return exifIPTCXMP.contains(ext) || exifXMP.contains(ext)
    }

    public static func usesXMPGPS(extension ext: String) -> Bool {
        let ext = ext.lowercased()
        // Vector/PNG-derived containers may have XMP without a writable EXIF preview.
        return ext == "xmp" || xmpOnly.contains(ext) || ["ai", "ait", "eps", "epsf", "ps", "jng", "mng"].contains(ext)
    }
}
