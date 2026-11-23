import Foundation
import CryptoKit
import Observation
import os
import CapeKit

/// The cursor themes on pling.com, page by page, and their downloads. The app goes online
/// only here, when the gallery window is open; nothing runs in the background.
@MainActor @Observable
final class CursorGallery {
    /// All themes in the catalogue, or only those installed from here (to look for updates).
    enum Scope: Hashable {
        case all
        case installed
    }

    var search = ""
    var sort: PlingCatalog.Sort = .popular
    var scope: Scope = .all
    /// The themes installed from the gallery whose capes are still in the library (set by
    /// the app model, which knows the library).
    @ObservationIgnored var installedThemeIDs: () -> [Int] = { [] }
    private(set) var themes: [PlingTheme] = []
    private(set) var totalCount = 0
    private(set) var isLoading = false
    private(set) var reachedEnd = false
    var errorMessage: String?
    /// Themes being downloaded, by id.
    private(set) var downloading: Set<PlingTheme.ID> = []

    @ObservationIgnored private var nextPage = 0
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    /// Starts over with the current search and order.
    func reload() {
        loadTask?.cancel()
        themes = []
        totalCount = 0
        nextPage = 0
        reachedEnd = false
        errorMessage = nil
        loadMore()
    }

    /// The next page, unless one is loading or there are no more.
    func loadMore() {
        guard !isLoading, !reachedEnd else { return }
        isLoading = true
        if scope == .installed {
            loadInstalled()
            return
        }
        let url = PlingCatalog.listURL(search: search, sort: sort, page: nextPage)
        loadTask = Task {
            defer { isLoading = false }
            do {
                let page = try PlingCatalog.page(from: try await Downloader.data(from: url))
                guard !Task.isCancelled else { return }
                // A theme can move to another page between two requests; show it once.
                let known = Set(themes.map(\.id))
                themes += page.themes.filter { !known.contains($0.id) }
                totalCount = page.totalCount
                nextPage += 1
                reachedEnd = page.entryCount == 0 || nextPage * PlingCatalog.pageSize >= page.totalCount
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// The installed themes, one request each (there are only a few), in the chosen order;
    /// the search filters them by name.
    private func loadInstalled() {
        let ids = installedThemeIDs()
        let search = search.trimmingCharacters(in: .whitespaces)
        let sort = sort
        loadTask = Task {
            defer { isLoading = false }
            var found: [PlingTheme] = []
            for id in ids {
                guard !Task.isCancelled else { return }
                do {
                    found += try PlingCatalog.page(from: try await Downloader.data(from: PlingCatalog.themeURL(id: id))).themes
                } catch {
                    errorMessage = error.localizedDescription      // the others still show
                }
            }
            guard !Task.isCancelled else { return }
            if !search.isEmpty { found = found.filter { $0.name.localizedCaseInsensitiveContains(search) } }
            themes = found.sorted { first, second in
                switch sort {
                case .popular: first.downloads > second.downloads
                case .newest: (first.created ?? .distantPast) > (second.created ?? .distantPast)
                case .updated: (first.changed ?? .distantPast) > (second.changed ?? .distantPast)
                case .rating: first.score > second.score
                case .name: first.name.localizedStandardCompare(second.name) == .orderedAscending
                }
            }
            totalCount = themes.count
            reachedEnd = true
        }
    }

    /// The files of a theme Mousecape can import: archives of Windows or Linux themes,
    /// capes and MaCursor themes.
    static func installableFiles(of theme: PlingTheme) -> [PlingTheme.File] {
        theme.files.filter { isInstallable($0.name) }
    }

    static func isInstallable(_ fileName: String) -> Bool {
        let url = URL(fileURLWithPath: fileName)
        let ext = url.pathExtension.lowercased()
        return ThemeImport.isArchive(url) || ext == "cape" || ext == MaCursorTheme.fileExtension
    }

    /// Downloads `files` of a theme, each into a new temporary folder, and checks them; the
    /// caller imports them and removes the folders. The links in a list expire, so the theme
    /// is fetched again first for fresh ones. Returns each file on disk and the catalogue's
    /// entry for it.
    func download(_ files: [PlingTheme.File], of theme: PlingTheme) async throws -> [(file: URL, info: PlingTheme.File)] {
        downloading.insert(theme.id)
        defer { downloading.remove(theme.id) }
        let fresh = try PlingCatalog.page(from: try await Downloader.data(from: PlingCatalog.themeURL(id: theme.id)))
        let current = fresh.themes.first { $0.id == theme.id }?.files ?? []
        var downloads: [(file: URL, info: PlingTheme.File)] = []
        do {
            for file in files {
                guard let info = current.first(where: { $0.name == file.name }) ?? current.first(where: { $0.id == file.id }) else {
                    throw GalleryError.fileGone(file.name)
                }
                downloads.append((try await Downloader.file(info), info))
            }
        } catch {
            for download in downloads { try? FileManager.default.removeItem(at: download.file.deletingLastPathComponent()) }
            throw error
        }
        return downloads
    }

    func download(_ file: PlingTheme.File, of theme: PlingTheme) async throws -> (file: URL, info: PlingTheme.File) {
        try await download([file], of: theme)[0]
    }
}

enum GalleryError: LocalizedError {
    case fileGone(String)
    case tooLarge(String)
    case checksumMismatch(String)
    case httpStatus(Int)
    case versionGone(String)

    var errorDescription: String? {
        switch self {
        case .fileGone(let name): String(localized: "“\(name)” is no longer offered on pling.com.")
        case .tooLarge(let name): String(localized: "“\(name)” is larger than a cursor theme can be; it wasn't downloaded.")
        case .checksumMismatch(let name): String(localized: "“\(name)” arrived damaged (its checksum doesn't match); it wasn't imported.")
        case .httpStatus(let code): String(localized: "pling.com answered with error \(code).")
        case .versionGone(let name): String(localized: "The new file no longer has the version you installed (“\(name)”). Install the theme again to choose one.")
        }
    }
}

/// Requests to pling.com: HTTPS only, no cookies or cache kept, a size limit on every
/// download.
enum Downloader {
    /// No cursor theme comes near this; it keeps a wrong link from filling the disk.
    static let maximumFileSize: Int64 = 64 * 1024 * 1024
    static let maximumAnswerSize = 16 * 1024 * 1024

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: configuration)
    }()

    /// The app and its version, nothing about the user.
    static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return "Mousecape/\(version.split(separator: " ").first ?? "dev")"
    }

    static func data(from url: URL) async throws -> Data {
        guard url.scheme == "https" else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        try check(response)
        guard data.count <= maximumAnswerSize else { throw URLError(.dataLengthExceedsMaximum) }
        return data
    }

    /// Downloads into a new temporary folder under the file's (cleaned) name, so that the
    /// importer can tell the kind of archive by its extension.
    static func file(_ file: PlingTheme.File) async throws -> URL {
        if let size = file.size, size > maximumFileSize { throw GalleryError.tooLarge(file.name) }
        let limit = SizeLimit(maximum: maximumFileSize)
        let downloaded: URL
        let response: URLResponse
        do {
            (downloaded, response) = try await session.download(from: file.url, delegate: limit)
        } catch let error as URLError where error.code == .cancelled && limit.exceeded {
            throw GalleryError.tooLarge(file.name)
        }
        defer { try? FileManager.default.removeItem(at: downloaded) }
        try check(response)

        let folder = FileManager.default.temporaryDirectory.appending(path: "Mousecape-Download-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: file.name)
        do {
            try FileManager.default.moveItem(at: downloaded, to: destination)
            let size = (try destination.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            guard size <= maximumFileSize else { throw GalleryError.tooLarge(file.name) }
            if let expected = file.md5 {
                let digest = Insecure.MD5.hash(data: try Data(contentsOf: destination, options: .mappedIfSafe))
                let actual = digest.map { String(format: "%02x", $0) }.joined()
                guard actual == expected else { throw GalleryError.checksumMismatch(file.name) }
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return destination
    }

    private static func check(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GalleryError.httpStatus(http.statusCode)
        }
    }
}

/// Cancels a download as soon as it grows past the limit, rather than after it is complete.
private final class SizeLimit: NSObject, URLSessionDownloadDelegate, Sendable {
    let maximum: Int64
    private let state = OSAllocatedUnfairLock(initialState: false)

    init(maximum: Int64) { self.maximum = maximum }

    var exceeded: Bool { state.withLock { $0 } }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maximum || totalBytesExpectedToWrite > maximum {
            state.withLock { $0 = true }
            downloadTask.cancel()
        }
    }

    // Required by the protocol; the async download hands over the file itself.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
