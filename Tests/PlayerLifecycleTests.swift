import XCTest
@testable import AVS_iOS_App

final class PlayerLifecycleTests: XCTestCase {
    func testOnlyActualContainerExitIsMarkedForTeardown() {
        XCTAssertFalse(PlayerController.isExitTransition(
            movingFromParent: false,
            beingDismissed: false,
            navigationBeingDismissed: false
        ))
        XCTAssertTrue(PlayerController.isExitTransition(
            movingFromParent: true,
            beingDismissed: false,
            navigationBeingDismissed: false
        ))
        XCTAssertTrue(PlayerController.isExitTransition(
            movingFromParent: false,
            beingDismissed: true,
            navigationBeingDismissed: false
        ))
        XCTAssertTrue(PlayerController.isExitTransition(
            movingFromParent: false,
            beingDismissed: false,
            navigationBeingDismissed: true
        ))
    }
}
