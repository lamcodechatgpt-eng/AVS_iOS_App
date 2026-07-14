import XCTest
@testable import AVS_iOS_App

final class AppLifecycleTests: XCTestCase {
    func testApplicationDeclaresWindowSceneConfiguration() throws {
        let manifest = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") as? [String: Any]
        )
        XCTAssertEqual(manifest["UIApplicationSupportsMultipleScenes"] as? Bool, false)

        let configurations = try XCTUnwrap(manifest["UISceneConfigurations"] as? [String: Any])
        let applicationRole = try XCTUnwrap(
            configurations["UIWindowSceneSessionRoleApplication"] as? [[String: Any]]
        )
        XCTAssertEqual(applicationRole.first?["UISceneConfigurationName"] as? String,
                       "Default Configuration")
        XCTAssertEqual(applicationRole.first?["UISceneDelegateClassName"] as? String,
                       NSStringFromClass(SceneDelegate.self))
    }
}
