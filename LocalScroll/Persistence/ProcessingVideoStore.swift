import Foundation

enum ProcessingVideoStore {
    private static let directoryName = "ProcessingVideos"

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

    static func store(videoURL: URL) throws -> String {
        let ext = videoURL.pathExtension.isEmpty ? "mov" : videoURL.pathExtension
        let fileName = UUID().uuidString + "." + ext
        let destination = try directory().appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: videoURL, to: destination)
        return fileName
    }

    static func url(for fileName: String) -> URL? {
        guard let dir = try? directory() else { return nil }
        let url = dir.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func delete(_ fileName: String) {
        guard let dir = try? directory() else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(fileName))
    }
}
