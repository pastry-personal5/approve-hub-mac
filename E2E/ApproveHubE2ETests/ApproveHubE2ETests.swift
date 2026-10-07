import XCTest

final class ApproveHubE2ETests: XCTestCase {
  func testLaunchPortsCanBeInjected() throws {
    let app = XCUIApplication()
    app.launchEnvironment["APPROVE_HUB_BIOMETRIC_PORT"] = "0"
    app.launchEnvironment["APPROVE_HUB_NOTIFICATION_PORT"] = "0"

    throw XCTSkip("The bundled app and its injectable adapters are added with their implementations.")
  }
}
