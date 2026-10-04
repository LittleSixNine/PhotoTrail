import Exiftool
import Foundation
import Testing
@testable import PhotoTrail

struct MetadataDeviceCatalogTests {
    @Test func bundledCatalogHasUniqueSourcedValues() throws {
        let catalog = MetadataDeviceCatalog.shared
        #expect(catalog.brands.count >= 100)
        #expect(catalog.brands.reduce(0) { $0 + $1.models.filter { !$0.isProductNameOnly }.count } >= 7000)
        #expect(Set(catalog.brands.map(\.id)).count == catalog.brands.count)
        for brand in catalog.brands {
            #expect(!brand.models.isEmpty)
            #expect(Set(brand.models.map(\.id)).count == brand.models.count)
            for device in brand.models {
                #expect(!device.name.isEmpty)
                if device.isProductNameOnly {
                    #expect(device.make.isEmpty && device.model.isEmpty)
                    #expect(device.value(for: .model) == nil && device.value(for: .make) == nil)
                    #expect(device.selectionValue(for: .model, productName: true) == device.name)
                } else { #expect(!device.make.isEmpty && !device.model.isEmpty) }
                #expect(URL(string: device.source)?.scheme == "https")
                #expect(device.make == device.make.trimmingCharacters(in: .whitespacesAndNewlines))
                #expect(device.model == device.model.trimmingCharacters(in: .whitespacesAndNewlines))
                #expect(device.value(for: .exifMake) == device.value(for: .make))
                #expect(device.value(for: .exifModel) == device.value(for: .model))
                #expect(device.value(for: .creator) == nil)
            }
        }
    }

    @Test func choicesUseMetadataValuesAndKeepCustomInputIndependent() throws {
        let catalog = MetadataDeviceCatalog.shared
        let sony = try #require(catalog.brands.first { $0.id == "sony" })
        let camera = try #require(sony.models.first { $0.name == "α7 IV" })
        #expect(camera.value(for: .exifModel) == "ILCE-7M4")
        #expect(camera.value(for: .make) == "SONY")
        #expect(camera.matches("ilce-7m4"))
        #expect(camera.matches("α7"))
        #expect(catalog.brand(matching: "My custom camera", tag: .model, make: nil, model: nil) == nil)
        #expect(!MetadataTag.creator.isDeviceIdentity)
        #expect(MetadataTag.exifModel.isDeviceIdentity)
    }

    @Test func brandHintDistinguishesDevicesSharingTheSameManufacturer() {
        let catalog = MetadataDeviceCatalog.shared
        let make = "RICOH IMAGING COMPANY, LTD."
        #expect(catalog.brand(matching: make, tag: .exifMake, make: make, model: "PENTAX K-1 Mark II") == "pentax")
        #expect(catalog.brand(matching: make, tag: .exifMake, make: make, model: "RICOH GR IV") == "ricoh")
        #expect(catalog.brand(matching: "", tag: .exifModel, make: make, model: "PENTAX K-1 Mark II") == "pentax")
        #expect(catalog.brand(matching: "ILCE-7M4", tag: .model, make: nil, model: nil) == "sony")
    }

    @Test func eitherNameCanBeChosenWithoutChangingMakerSemantics() {
        let camera = MetadataDeviceCatalog.Device(name: "α7 IV", make: "SONY", model: "ILCE-7M4", source: "https://exiftool.org/")
        #expect(camera.selectionValue(for: .exifModel, productName: true) == "α7 IV")
        #expect(camera.selectionValue(for: .model, productName: false) == "ILCE-7M4")
        #expect(camera.selectionValue(for: .exifMake, productName: true) == "SONY")
        #expect(camera.selectionValue(for: .creator, productName: true) == nil)
        let phone = MetadataDeviceCatalog.Device(name: "iPhone 16", make: "Apple", model: "iPhone 16", source: "https://exiftool.org/")
        #expect(phone.selectionValue(for: .model, productName: true) == phone.selectionValue(for: .model, productName: false))
        #expect(MetadataDeviceCatalog.shared.brand(matching: "α7 IV", tag: .model, make: nil, model: nil) == "sony")
    }


    @Test func retailOnlyChoicesNeverInventMetadataValues() {
        let device = MetadataDeviceCatalog.Device(name: "Example phone", make: "", model: "",
                                                  source: "https://storage.googleapis.com/play_public/supported_devices.html",
                                                  productNameOnly: true)
        #expect(device.selectionValue(for: .model, productName: true) == "Example phone")
        #expect(device.selectionValue(for: .model, productName: false) == nil)
        #expect(device.selectionValue(for: .make, productName: true) == nil)
        let catalog = MetadataDeviceCatalog(brands: [.init(id: "example", name: "Example", models: [device])])
        #expect(catalog.brand(matching: "", tag: .make, make: "", model: "") == nil)
        #expect(catalog.brand(matching: "Example phone", tag: .model, make: nil, model: nil) == "example")
    }

}
