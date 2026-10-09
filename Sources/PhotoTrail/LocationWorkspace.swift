import Coords
import Foundation
import MapKit
import Observation

struct SavedLocation: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var note: String
    let coordinate: MapCoordinate // Always WGS84; never infer this from an unlabelled photo.
}

struct AMapSearchResult: Identifiable {
    let id: String
    let name: String
    let address: String
    let coordinate: MapCoordinate // GCJ-02, only for AMap preview/validation.
}

struct AMapPhotoPosition: Identifiable, Equatable {
    let ids: [Int]
    let x: Double
    let y: Double
    var id: Int { ids[0] }
}

struct AMapPhotoEdgePosition: Identifiable, Equatable {
    let id: Int
    let x: Double
    let y: Double
    let angle: Double
}

@MainActor @Observable
final class LocationWorkspace {
    var listMatchResults: [LocationHelper.LocationById] = []
    var status = L10n.text("选择照片后，在地图上点选拍摄地点。")
    var query = ""
    var results: [AMapSearchResult] = []
    var searching = false
    var ready = false
    var session = UUID()
    var settingsPresented = false
    var credentials: AMapCredentials?
    var selectedResult: AMapSearchResult?
    var favoriteDraft: SavedLocation?
    var favorites: [SavedLocation] = []
    var favoriteError: String?
    var previewCoordinate: MapCoordinate?
    var previewName = L10n.text("地点预览")
    var previewID = UUID()
    var deviceCoordinate: MapCoordinate?
    var deviceFocusID = UUID()
    var appleHeading = 0.0
    var amapHeading = 0.0
    var amapPhotoPositions: [AMapPhotoPosition] = []
    var amapPhotoEdges: [AMapPhotoEdgePosition] = []
    let tracks: TrackLibrary
    @ObservationIgnored var appleNavigation: ((String) -> Void)?
    @ObservationIgnored var amapNavigation: ((String) -> Void)?
    @ObservationIgnored var lookupAMapRegion: ((MapCoordinate) async throws -> Place)?
    @ObservationIgnored var regionCache: [String: Place] = [:]

    @ObservationIgnored var setSatellite: ((Bool) -> Void)?
    @ObservationIgnored var invalidateSelection: (() -> Void)?
    @ObservationIgnored var search: ((String) -> Void)?
    @ObservationIgnored var previewSearch: ((AMapSearchResult) -> Void)?
    @ObservationIgnored var chooseSearch: ((AMapSearchResult, String) -> Void)?
    @ObservationIgnored var previewWGS84: ((MapCoordinate) -> Void)?
    @ObservationIgnored var moveAMapPhoto: ((Int, CGPoint) -> Void)?
    @ObservationIgnored var focusPhoto: ((Int) -> Void)?
    @ObservationIgnored var amapConnectionID: UUID?
    @ObservationIgnored var zoomAMap: ((Double, CGPoint) -> Void)?
    @ObservationIgnored private let favoritesURL: URL
    @ObservationIgnored private var didLoad = false

    init(favoritesURL: URL? = nil, tracks: TrackLibrary? = nil) {
        let current = favoritesURL ?? URL.applicationSupportDirectory
            .appendingPathComponent("PhotoTrail/Favorites.json")
        if favoritesURL == nil, ProcessInfo.processInfo.environment["PHOTOTRAIL_OFFLINE_TESTS"] != "1" {
            PhotoTrailMigration.file(at: current, legacyURL: URL.applicationSupportDirectory
                .appendingPathComponent("GeoTagCN/Favorites.json"))
        }
        self.favoritesURL = current
        self.tracks = tracks ?? TrackLibrary()
    }

    func address(at point: MapCoordinate, provider: String) async throws -> Place {
        let key = "\(L10n.language.rawValue):\(provider):\(point.latitude):\(point.longitude)"
        if let cached = regionCache[key] { return cached }
        guard ProcessInfo.processInfo.environment["PHOTOTRAIL_OFFLINE_TESTS"] != "1" else {
            throw URLError(.notConnectedToInternet)
        }
        let place: Place
        if provider == "amap", let lookupAMapRegion, ready {
            place = try await lookupAMapRegion(point)
        } else if #available(macOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location:
                CLLocation(latitude: point.latitude, longitude: point.longitude)) else {
                throw URLError(.badURL)
            }
            request.preferredLocale = L10n.locale
            guard let item = try await request.mapItems.first else { throw URLError(.badServerResponse) }
            var address = Place(from: item)
            address.coordinate = Coordinate(latitude: point.latitude, longitude: point.longitude)
            place = address
        } else {
            guard let address = try await ReverseLocationFinder.legacyPlace(
                at: CLLocation(latitude: point.latitude, longitude: point.longitude), locale: L10n.locale) else {
                throw URLError(.badServerResponse)
            }
            place = address
        }
        if regionCache.count >= 256 { regionCache.removeAll() }
        regionCache[key] = place
        return place
    }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        // Unit-test hosts must not load private favorites, credentials or live maps.
        guard ProcessInfo.processInfo.environment["PHOTOTRAIL_OFFLINE_TESTS"] != "1" else { return }
        loadFavorites()
        if UserDefaults.standard.string(forKey: "PhotoTrailMapProvider") ?? "amap" == "amap" {
            await loadCredentials()
        }
    }

    @ObservationIgnored private var loadingCredentials = false
    func loadCredentials() async {
        guard credentials == nil, !loadingCredentials,
              ProcessInfo.processInfo.environment["PHOTOTRAIL_OFFLINE_TESTS"] != "1" else { return }
        loadingCredentials = true
        defer { loadingCredentials = false }
        do { credentials = try await Task.detached { try AMapCredentials.load() }.value }
        catch { status = error.localizedDescription }
    }

    func loadFavorites() {
        guard FileManager.default.fileExists(atPath: favoritesURL.path) else { return }
        do {
            let saved = try JSONDecoder().decode([SavedLocation].self, from: Data(contentsOf: favoritesURL))
            guard saved.allSatisfy({ $0.coordinate.isValid }), Set(saved.map(\.id)).count == saved.count else {
                throw CocoaError(.fileReadCorruptFile)
            }
            favorites = saved
            favoriteError = nil
        } catch {
            favoriteError = L10n.text("收藏文件读取失败，原文件已保留。")
        }
    }

    func saveFavorite(_ value: SavedLocation) throws {
        guard value.coordinate.isValid, !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        var updated = favorites
        if let index = updated.firstIndex(where: { $0.id == value.id }) {
            updated[index] = value
        } else {
            updated.append(value)
        }
        try persist(updated)
    }

    func deleteFavorite(_ id: UUID) throws {
        try persist(favorites.filter { $0.id != id })
    }

    private func persist(_ updated: [SavedLocation]) throws {
        // Do not overwrite unreadable private data with an empty/new list.
        guard favoriteError == nil else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: favoritesURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(updated).write(to: favoritesURL, options: .atomic)
        favorites = updated
    }

    func reload() {
        ready = false
        searching = false
        results = []
        selectedResult = nil
        amapPhotoPositions = []
        amapPhotoEdges = []
        session = UUID()
    }

    func preview(_ coordinate: MapCoordinate, name: String = L10n.text("地点预览")) {
        previewCoordinate = coordinate
        previewName = name
        previewID = UUID()
        previewWGS84?(coordinate)
    }
}
