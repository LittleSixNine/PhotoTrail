import ImageData
import Metadata
import SwiftUI

/// View-local projections: selection and read-progress updates do not rebuild the photo list.
@MainActor final class PhotoListProjection {
    struct TableSnapshot {
        var images: [ImageData] = []
        var ids: Set<ImageData.ID> = []
        var counts: [PhotoListFilter: Int] = [:]
        var total = 0
    }

    private struct SearchKey: Equatable {
        let text: String
        let hideInvalid: Bool
    }
    private struct FilterKey: Equatable {
        let filter: PhotoListFilter
        let unmatchedIDs: Set<ImageData.ID>?
    }
    private struct SortKey: Equatable {
        let filter: PhotoListFilter
        let mode: PhotoStripSort
        let ascending: Bool
        let timeZone: TimeZone
    }
    private struct ParsedDate {
        let timestamp: String
        let timeZone: TimeZone
        let value: Date?
    }

    private var revision: UUID?
    private var visible: [ImageData] = []
    private var searchKey: SearchKey?
    private var filterKey: FilterKey?
    private var sortKey: SortKey?
    private var searchable: [ImageData] = []
    private var tableSnapshot = TableSnapshot()
    private var sorted: [ImageData] = []
    private var selectedIDs: Set<ImageData.ID>?
    private var selectionSort: [KeyPathComparator<ImageData>] = []
    private var selectedImages: [ImageData] = []
    private var dates: [ImageData.ID: ParsedDate] = [:]
    private let parseDate: (Metadata, TimeZone) -> Date?

    init(parseDate: @escaping (Metadata, TimeZone) -> Date? = { $0.parsedDate(timeZone: $1) }) {
        self.parseDate = parseDate
    }

    private func update(_ state: PhotoTrailState) {
        guard revision != state.imageRevision else { return }
        revision = state.imageRevision
        visible = state.visibleImages
        let ids = Set(visible.map(\.id))
        dates = dates.filter { ids.contains($0.key) }
        searchKey = nil
        filterKey = nil
        sortKey = nil
        selectedIDs = nil
    }

    func selected(_ state: PhotoTrailState) -> [ImageData] {
        update(state)
        if selectedIDs != state.selection || selectionSort != state.sortOrder {
            selectedIDs = state.selection
            selectionSort = state.sortOrder
            selectedImages = state.imageData.filter { state.selection.contains($0.id) }.sorted(using: state.sortOrder)
        }
        return selectedImages
    }

    func table(_ state: PhotoTrailState, search: String, hideInvalid: Bool,
               filter: PhotoListFilter, unmatchedIDs: Set<ImageData.ID>?) -> TableSnapshot {
        update(state)
        let searchKey = SearchKey(text: search, hideInvalid: hideInvalid)
        if self.searchKey != searchKey {
            self.searchKey = searchKey
            filterKey = nil
            searchable = visible.filter { (!hideInvalid || $0.updatable) && (search.isEmpty || $0.name.fuzzy(search)) }
            var counts: [PhotoListFilter: Int] = [:]
            for image in searchable {
                for option in PhotoListFilter.allCases where option.includes(image) { counts[option, default: 0] += 1 }
            }
            tableSnapshot.counts = counts
            tableSnapshot.total = visible.count
        }
        let filterKey = FilterKey(filter: filter, unmatchedIDs: unmatchedIDs)
        if self.filterKey != filterKey {
            self.filterKey = filterKey
            tableSnapshot.images = searchable.filter {
                filter.includes($0) && (unmatchedIDs?.contains($0.id) ?? true)
            }
            tableSnapshot.ids = Set(tableSnapshot.images.map(\.id))
        }
        return tableSnapshot
    }

    func filmstrip(_ state: PhotoTrailState, filter: PhotoListFilter,
                   mode: PhotoStripSort, ascending: Bool) -> [ImageData] {
        update(state)
        let key = SortKey(filter: filter, mode: mode, ascending: ascending, timeZone: state.timeZone)
        guard sortKey != key else { return sorted }
        sortKey = key
        let images = visible.filter { filter.includes($0) }
        if mode == .capturedAt {
            for image in images {
                if dates[image.id]?.timestamp != image.metadata.timestamp
                    || dates[image.id]?.timeZone != state.timeZone {
                    dates[image.id] = ParsedDate(timestamp: image.metadata.timestamp, timeZone: state.timeZone,
                                               value: parseDate(image.metadata, state.timeZone))
                }
            }
        }
        sorted = images.sorted { left, right in
            let ordered: Bool
            switch mode {
            case .importOrder: ordered = left.id < right.id
            case .filename:
                let comparison = left.name.localizedStandardCompare(right.name)
                ordered = comparison == .orderedSame ? left.id < right.id : comparison == .orderedAscending
            case .capturedAt:
                switch (dates[left.id]?.value, dates[right.id]?.value) {
                case let (lhs?, rhs?): ordered = lhs == rhs ? left.id < right.id : lhs < rhs
                case (_?, nil): ordered = true
                case (nil, _?): ordered = false
                case (nil, nil): ordered = left.id < right.id
                }
            }
            return ascending ? ordered : !ordered && left.id != right.id
        }
        return sorted
    }
}
