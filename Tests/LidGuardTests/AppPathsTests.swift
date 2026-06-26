import XCTest
@testable import LidGuard

final class AppPathsTests: XCTestCase {
  func testSupportDirectoryEndsWithLidGuardAndExists() {
    let dir = AppPaths.supportDirectory
    XCTAssertEqual(dir.lastPathComponent, "LidGuard")
    XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
  }
}
