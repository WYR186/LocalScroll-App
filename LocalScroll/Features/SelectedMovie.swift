import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct SelectedMovie: Transferable {
    let url: URL
    let originalFileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            try Self.importMovie(from: received.file)
        }
    }

    private static func importMovie(from source: URL) throws -> SelectedMovie {
        let originalName = SupportedVideoTypes.displayName(for: source)
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)

        if FileManager.default.fileExists(atPath: copy.path) {
            try FileManager.default.removeItem(at: copy)
        }
        try FileManager.default.copyItem(at: source, to: copy)
        return SelectedMovie(url: copy, originalFileName: originalName)
    }
}

enum SupportedVideoTypes {
    static let importableTypes: [UTType] = {
        let standardTypes: [UTType] = [
            .video,
            .movie,
            .mpeg4Movie,
            .quickTimeMovie,
        ]
        let extensionTypes = [
            "mov", "mp4", "m4v", "hevc",
            "avi", "mkv", "webm",
            "3gp", "3g2",
            "mpeg", "mpg",
            "ts", "mts", "m2ts",
        ].compactMap { UTType(filenameExtension: $0) }

        var seen = Set<String>()
        return (standardTypes + extensionTypes).filter { seen.insert($0.identifier).inserted }
    }()

    static func displayName(for url: URL, fallback: String = "Video") -> String {
        let candidate = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, candidate != "." else { return fallback }
        return candidate
    }
}
