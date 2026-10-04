import Exiftool
import Foundation

struct MetadataDeviceCatalog: Decodable, Sendable {
    struct Brand: Decodable, Identifiable, Sendable {
        let id: String
        let name: String
        let models: [Device]
    }

    struct Device: Decodable, Identifiable, Sendable {
        let name: String
        let make: String
        let model: String
        let source: String
        var productNameOnly: Bool? = nil

        var isProductNameOnly: Bool { productNameOnly == true }
        var id: String { isProductNameOnly ? "product:" + name : make + "\u{1f}" + model }

        func value(for tag: MetadataTag) -> String? {
            guard !isProductNameOnly else { return nil }
            return switch tag {
            case .make, .exifMake: make
            case .model, .exifModel: model
            default: nil
            }
        }

        func selectionValue(for tag: MetadataTag, productName: Bool) -> String? {
            if productName && [.model, .exifModel].contains(tag) { return name }
            return value(for: tag)
        }

        func matches(_ query: String) -> Bool {
            query.isEmpty || [name, make, model].contains { $0.localizedStandardContains(query) }
        }
    }

    let brands: [Brand]

    static let shared: Self = {
        guard let url = Bundle.main.url(forResource: "MetadataDevices", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self(brands: [])
        }
        return catalog
    }()

    func brand(matching value: String, tag: MetadataTag, make: String?, model: String?) -> String? {
        // Prefer the exact model and maker pair; model names can overlap across brands.
        let matches = brands.filter { brand in
            brand.models.contains { $0.value(for: tag) == value || $0.selectionValue(for: tag, productName: true) == value }
        }
        return matches.first(where: { brand in brand.models.contains { !$0.isProductNameOnly && $0.make == make && $0.model == model } })?.id
            ?? matches.first(where: { brand in brand.models.contains { !$0.isProductNameOnly && $0.make == make } })?.id
            ?? matches.first?.id
            ?? brands.first(where: { brand in brand.models.contains { !$0.isProductNameOnly && $0.make == make && $0.model == model } })?.id
            ?? brands.first(where: { brand in brand.models.contains { !$0.isProductNameOnly && $0.make == make } })?.id
    }
}

extension MetadataTag {
    var isDeviceIdentity: Bool {
        [.make, .model, .exifMake, .exifModel].contains(self)
    }
}
