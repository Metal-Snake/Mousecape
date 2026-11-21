import Foundation
import Testing
@testable import Mousecape

/// Which saved states a history limit drops, by number and by disk space.
struct HistoryLimitTests {
    /// Saved states of the given sizes in bytes, oldest first.
    func states(_ sizes: [Int64]) -> [(url: URL, size: Int64)] {
        sizes.enumerated().map { (URL(filePath: "/states/\($0.offset).cape"), $0.element) }
    }

    func names(_ urls: [URL]) -> [String] { urls.map(\.lastPathComponent) }

    @Test func dropsTheOldestBeyondTheNumber() {
        #expect(names(HistoryLimit.count(2).excess(of: states([1, 1, 1, 1]))) == ["0.cape", "1.cape"])
        #expect(HistoryLimit.count(5).excess(of: states([1, 1])).isEmpty)
    }

    @Test func dropsTheOldestUntilTheRestFit() {
        let megabyte: Int64 = 1_000_000
        // 30 MB in four states, 10 MB allowed: the newest two (4 + 6) fit.
        let saved = states([12, 8, 4, 6].map { $0 * megabyte })
        #expect(names(HistoryLimit.megabytes(10).excess(of: saved)) == ["0.cape", "1.cape"])
        #expect(HistoryLimit.megabytes(50).excess(of: saved).isEmpty)
    }

    @Test func keepsTheNewestEvenWhenItIsTooLarge() {
        let saved = states([5_000_000, 40_000_000])
        #expect(names(HistoryLimit.megabytes(10).excess(of: saved)) == ["0.cape"])
    }

    @Test func remembersBothKindsOfLimit() throws {
        let defaults = try #require(UserDefaults(suiteName: "HistoryLimitTests-\(UUID().uuidString)"))
        #expect(HistoryLimit.stored(in: defaults) == .standard)
        HistoryLimit.count(7).store(in: defaults)
        HistoryLimit.megabytes(250).store(in: defaults)
        #expect(HistoryLimit.stored(in: defaults) == .megabytes(250))
        #expect(HistoryLimit.storedCount(in: defaults) == .count(7))
        HistoryLimit.count(7).store(in: defaults)
        #expect(HistoryLimit.stored(in: defaults) == .count(7))
        #expect(HistoryLimit.storedSpace(in: defaults) == .megabytes(250))
    }
}
