import Testing
@testable import GeoTag

struct MapSearchHistoryTests {
    @Test func newestUniqueSearchesStayWithinThreeEntries() {
        let history = ["外滩", "静安寺", "人民广场"]
        #expect(SearchView.updatedRecentSearches(" 静安寺 ", in: history) == ["静安寺", "外滩", "人民广场"])
        #expect(SearchView.updatedRecentSearches("上海博物馆", in: history) == ["上海博物馆", "外滩", "静安寺"])
        #expect(SearchView.updatedRecentSearches("  ", in: history) == history)
    }
}
