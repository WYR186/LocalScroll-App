import Foundation
import Testing

struct Phase7PolishTests {
    @Test func privacyManifestDeclaresNoCollectionOrTracking() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let manifestURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("LocalScroll/PrivacyInfo.xcprivacy")

        let data = try Data(contentsOf: manifestURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]

        #expect(plist?["NSPrivacyTracking"] as? Bool == false)
        #expect((plist?["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true)
        #expect((plist?["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
    }
}
