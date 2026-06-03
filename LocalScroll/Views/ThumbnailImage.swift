import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Renders JPEG thumbnail `Data` as a SwiftUI `Image`, with a placeholder fallback.
struct ThumbnailImage: View {
    let data: Data

    var body: some View {
        if let image = Self.makeImage(data) {
            image
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "video")
                .imageScale(.large)
                .foregroundStyle(.secondary)
        }
    }

    static func makeImage(_ data: Data) -> Image? {
#if os(iOS)
        guard let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
#elseif os(macOS)
        guard let ns = NSImage(data: data) else { return nil }
        return Image(nsImage: ns)
#else
        return nil
#endif
    }
}
