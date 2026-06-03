import ActivityKit
import Foundation

struct ProcessingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var progress: Double
        var status: String
    }

    var videoName: String
}
