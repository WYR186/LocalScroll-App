import Foundation

/// Manages locally cached original videos under Application Support/`CachedVideos`.
///
/// Used only when the "Cache original videos" setting is enabled, so the user can
/// re-process the same video multiple times without re-importing it.
enum VideoCacheStore {
    /// A cached video entry surfaced in the management UI.
    struct CachedVideo: Identifiable, Hashable {
        let fileName: String
        let sizeBytes: Int64
        var id: String { fileName }
    }

    private static let directoryName = "CachedVideos"

    /// Directory holding cached videos, created on demand.
    static func directory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Copy a (temporary) video into the cache, returning the stored file name.
    static func store(tempURL: URL) throws -> String {
        let ext = tempURL.pathExtension.isEmpty ? "mov" : tempURL.pathExtension
        let fileName = UUID().uuidString + "." + ext
        let destination = try directory().appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: tempURL, to: destination)
        return fileName
    }

    /// Resolve a stored file name to its on-disk URL, if it still exists.
    static func url(for fileName: String) -> URL? {
        guard let dir = try? directory() else { return nil }
        let url = dir.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func delete(_ fileName: String) {
        guard let dir = try? directory() else { return }
        let url = dir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    /// All currently cached videos with their on-disk sizes.
    static func allCached() -> [CachedVideo] {
        guard let dir = try? directory(),
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return []
        }
        return names.map { name in
            let url = dir.appendingPathComponent(name)
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            return CachedVideo(fileName: name, sizeBytes: size)
        }
        .sorted { $0.fileName < $1.fileName }
    }

    static func totalSizeBytes() -> Int64 {
        allCached().reduce(0) { $0 + $1.sizeBytes }
    }

    static func deleteAll() {
        for video in allCached() {
            delete(video.fileName)
        }
    }
}
