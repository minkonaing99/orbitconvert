import XCTest
@testable import OrbitConvert

final class AppShellTests: XCTestCase {
    func testAppIdentityMatchesBundleConfiguration() {
        XCTAssertEqual(AppIdentity.name, Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.example.OrbitConvert")
    }
}
