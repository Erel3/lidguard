import XCTest
@testable import LidGuard

/// Tests the UserDefaults default values for the three theft-recovery settings.
/// Each test removes the relevant key before reading so we observe the compile-time default.
@MainActor
final class SettingsDefaultsTests: XCTestCase {
  private let restoreKey = "lidguard.restoreTheftModeEnabled"
  private let photoCaptureKey = "lidguard.photoCaptureEnabled"
  private let photoCaptureEveryNKey = "lidguard.photoCaptureEveryN"

  override func setUp() {
    super.setUp()
    let d = UserDefaults.standard
    d.removeObject(forKey: restoreKey)
    d.removeObject(forKey: photoCaptureKey)
    d.removeObject(forKey: photoCaptureEveryNKey)
  }

  override func tearDown() {
    // Clean up after ourselves so we don't pollute other tests.
    let d = UserDefaults.standard
    d.removeObject(forKey: restoreKey)
    d.removeObject(forKey: photoCaptureKey)
    d.removeObject(forKey: photoCaptureEveryNKey)
    super.tearDown()
  }

  func testRestoreTheftModeEnabledDefaultIsTrue() {
    XCTAssertTrue(SettingsService.shared.restoreTheftModeEnabled,
                  "restoreTheftModeEnabled should default to true")
  }

  func testPhotoCaptureEnabledDefaultIsFalse() {
    XCTAssertFalse(SettingsService.shared.photoCaptureEnabled,
                   "photoCaptureEnabled should default to false")
  }

  func testPhotoCaptureEveryNDefaultIsThree() {
    XCTAssertEqual(SettingsService.shared.photoCaptureEveryN, 3,
                   "photoCaptureEveryN should default to 3")
  }
}
