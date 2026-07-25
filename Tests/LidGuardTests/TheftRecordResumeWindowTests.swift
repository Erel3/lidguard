import XCTest
@testable import LidGuard

/// Covers the resume window on a persisted theft record.
///
/// `startedAt` was written at activation and read by nothing, so a record had no
/// expiry: an incident resolved weeks earlier could still be resumed on a later
/// launch — siren, STOLEN overlay, "DEVICE POWERED BACK ON" alert and a tracking
/// loop for something already dealt with.
/// `@MainActor` because the window constants live on `TheftProtectionService`,
/// which is main-actor isolated.
@MainActor
final class TheftRecordResumeWindowTests: XCTestCase {
  private let maxAge = TheftProtectionService.theftRecordMaxAge
  private let skew = TheftProtectionService.theftRecordClockSkew
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func record(startedAt: Date) -> TheftStateRecord {
    TheftStateRecord(state: "theftMode", trigger: "lid_close", startedAt: startedAt)
  }

  private func isResumable(ageSeconds: TimeInterval) -> Bool {
    record(startedAt: now.addingTimeInterval(-ageSeconds))
      .isResumable(now: now, maxAge: maxAge, clockSkew: skew)
  }

  // MARK: - Inside the window

  func testJustActivatedIsResumable() {
    XCTAssertTrue(isResumable(ageSeconds: 0))
  }

  func testRecentRebootIsResumable() {
    // The case the feature exists for: powered off during theft, back on minutes later.
    XCTAssertTrue(isResumable(ageSeconds: 120))
  }

  func testExactlyAtMaxAgeIsResumable() {
    XCTAssertTrue(isResumable(ageSeconds: maxAge))
  }

  func testJustInsideMaxAgeIsResumable() {
    XCTAssertTrue(isResumable(ageSeconds: maxAge - 1))
  }

  // MARK: - Outside the window

  func testJustOverMaxAgeIsNotResumable() {
    XCTAssertFalse(isResumable(ageSeconds: maxAge + 1))
  }

  func testWeekOldRecordIsNotResumable() {
    XCTAssertFalse(isResumable(ageSeconds: 7 * 24 * 60 * 60))
  }

  func testMonthOldRecordIsNotResumable() {
    // The reported scenario: restore setting re-enabled long after the incident.
    XCTAssertFalse(isResumable(ageSeconds: 30 * 24 * 60 * 60))
  }

  // MARK: - Clock moved backwards

  func testSmallFutureSkewIsStillResumable() {
    // A record dated slightly ahead (clock adjusted on wake) is not the bug.
    XCTAssertTrue(isResumable(ageSeconds: -(skew / 2)))
  }

  func testLargeFutureTimestampIsNotResumable() {
    // A negative age would never exceed maxAge, so without the skew floor such a
    // record could never expire.
    XCTAssertFalse(isResumable(ageSeconds: -(skew + 1)))
  }

  func testFarFutureTimestampIsNotResumable() {
    XCTAssertFalse(isResumable(ageSeconds: -(365 * 24 * 60 * 60)))
  }

  // MARK: - Window configuration

  func testResumeWindowIsBounded() {
    XCTAssertGreaterThan(maxAge, 0, "An unbounded window is the defect this guards")
    XCTAssertGreaterThan(skew, 0, "Zero skew floor lets a future-dated record live forever")
  }

  func testRecordSurvivesEncodingWithItsTimestamp() {
    // isResumable is only meaningful if startedAt round-trips through the store.
    let original = record(startedAt: now.addingTimeInterval(-60))
    let store = TheftStateStore(directory: TestSupport.makeTempDir())
    store.save(original)
    let loaded = store.load()
    XCTAssertEqual(loaded, original)
    XCTAssertEqual(loaded?.isResumable(now: now, maxAge: maxAge, clockSkew: skew), true)
  }
}
