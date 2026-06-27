import XCTest
@testable import LidGuard

/// Tests `PhotoCadence.shouldCaptureOnUpdate(updateCount:everyN:)`.
/// Implemented rule: guard everyN > 0, updateCount > 1 else { return false }
///                   return (updateCount - 1) % everyN == 0
final class PhotoCadenceTests: XCTestCase {
  // MARK: - Guard clauses

  func testEveryNZeroAlwaysFalse() {
    XCTAssertFalse(PhotoCadence.shouldCaptureOnUpdate(updateCount: 3, everyN: 0))
    XCTAssertFalse(PhotoCadence.shouldCaptureOnUpdate(updateCount: 10, everyN: 0))
  }

  func testEveryNNegativeAlwaysFalse() {
    XCTAssertFalse(PhotoCadence.shouldCaptureOnUpdate(updateCount: 5, everyN: -1))
    XCTAssertFalse(PhotoCadence.shouldCaptureOnUpdate(updateCount: 5, everyN: -3))
  }

  func testUpdateCount1AlwaysFalse() {
    // updateCount == 1 is the initial activation message — cadence never fires here
    XCTAssertFalse(PhotoCadence.shouldCaptureOnUpdate(updateCount: 1, everyN: 1))
    XCTAssertFalse(PhotoCadence.shouldCaptureOnUpdate(updateCount: 1, everyN: 3))
  }

  func testUpdateCount0AlwaysFalse() {
    XCTAssertFalse(PhotoCadence.shouldCaptureOnUpdate(updateCount: 0, everyN: 3))
  }

  func testNegativeUpdateCountAlwaysFalse() {
    XCTAssertFalse(PhotoCadence.shouldCaptureOnUpdate(updateCount: -1, everyN: 3))
  }

  // MARK: - everyN = 3 (the default)

  func testEveryN3_updateCount2_false() {
    // (2-1) % 3 = 1 ≠ 0
    XCTAssertFalse(PhotoCadence.shouldCaptureOnUpdate(updateCount: 2, everyN: 3))
  }

  func testEveryN3_updateCount3_false() {
    // (3-1) % 3 = 2 ≠ 0
    XCTAssertFalse(PhotoCadence.shouldCaptureOnUpdate(updateCount: 3, everyN: 3))
  }

  func testEveryN3_updateCount4_true() {
    // (4-1) % 3 = 0
    XCTAssertTrue(PhotoCadence.shouldCaptureOnUpdate(updateCount: 4, everyN: 3))
  }

  func testEveryN3_updateCount5_false() {
    // (5-1) % 3 = 1 ≠ 0
    XCTAssertFalse(PhotoCadence.shouldCaptureOnUpdate(updateCount: 5, everyN: 3))
  }

  func testEveryN3_updateCount6_false() {
    // (6-1) % 3 = 2 ≠ 0
    XCTAssertFalse(PhotoCadence.shouldCaptureOnUpdate(updateCount: 6, everyN: 3))
  }

  func testEveryN3_updateCount7_true() {
    // (7-1) % 3 = 0
    XCTAssertTrue(PhotoCadence.shouldCaptureOnUpdate(updateCount: 7, everyN: 3))
  }

  // MARK: - everyN = 1 (capture every tracking update after first)

  func testEveryN1_updateCount2_true() {
    XCTAssertTrue(PhotoCadence.shouldCaptureOnUpdate(updateCount: 2, everyN: 1))
  }

  func testEveryN1_updateCount5_true() {
    XCTAssertTrue(PhotoCadence.shouldCaptureOnUpdate(updateCount: 5, everyN: 1))
  }

  // MARK: - everyN = 5

  func testEveryN5_updateCount6_true() {
    // (6-1) % 5 = 0
    XCTAssertTrue(PhotoCadence.shouldCaptureOnUpdate(updateCount: 6, everyN: 5))
  }

  func testEveryN5_updateCount4_false() {
    // (4-1) % 5 = 3 ≠ 0
    XCTAssertFalse(PhotoCadence.shouldCaptureOnUpdate(updateCount: 4, everyN: 5))
  }
}
