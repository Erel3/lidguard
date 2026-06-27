import XCTest
@testable import LidGuard

final class CoalesceSummaryTests: XCTestCase {
  // MARK: - Helpers

  private func snap(
    timestamp: Date = Date(timeIntervalSince1970: 0),
    latitude: Double? = nil, longitude: Double? = nil, accuracy: Double? = nil,
    batteryLevel: Int? = nil, isCharging: Bool? = nil,
    publicIP: String? = nil, wifiName: String? = nil
  ) -> DeviceSnapshot {
    DeviceSnapshot(
      timestamp: timestamp,
      latitude: latitude, longitude: longitude, accuracy: accuracy,
      publicIP: publicIP, wifiName: wifiName,
      batteryLevel: batteryLevel, isCharging: isCharging,
      deviceName: "TestMac"
    )
  }

  // MARK: - Header / count noun

  func testEmptyArrayReturnsEmptyString() {
    XCTAssertEqual(CoalesceSummary.build(from: []), "")
  }

  func testHeaderContainsOFFLINE_SUMMARY() {
    let msg = CoalesceSummary.build(from: [snap()])
    XCTAssertTrue(msg.contains("OFFLINE SUMMARY"), "Missing OFFLINE SUMMARY header in: \(msg)")
  }

  func testSingleSnapshotUsesSingularNoun() {
    let msg = CoalesceSummary.build(from: [snap()])
    XCTAssertTrue(msg.contains("1 update"), "Expected '1 update' in: \(msg)")
    XCTAssertFalse(msg.contains("1 updates"))
  }

  func testMultipleSnapshotsUsePluralNoun() {
    let msg = CoalesceSummary.build(from: [snap(), snap()])
    XCTAssertTrue(msg.contains("2 updates"), "Expected '2 updates' in: \(msg)")
  }

  // MARK: - Location

  func testMapsLinkForLatestLocation() {
    let last = snap(latitude: 48.8566, longitude: 2.3522)
    let msg = CoalesceSummary.build(from: [snap(), last])
    XCTAssertTrue(msg.contains("https://maps.google.com/?q=48.8566,2.3522"),
                  "Missing Maps link in: \(msg)")
  }

  func testNoLocationShowsUnavailable() {
    let msg = CoalesceSummary.build(from: [snap()])
    XCTAssertTrue(msg.contains("unavailable"), "Expected 'unavailable' when no location")
  }

  func testAccuracyLineIncludedWhenPresent() {
    let s = snap(latitude: 1.0, longitude: 2.0, accuracy: 20)
    let msg = CoalesceSummary.build(from: [s])
    XCTAssertTrue(msg.contains("20m"), "Expected accuracy line in: \(msg)")
  }

  // MARK: - Battery

  func testBatteryStartToEndRange() {
    let s1 = snap(batteryLevel: 80, isCharging: false)
    let s2 = snap(batteryLevel: 60, isCharging: false)
    let msg = CoalesceSummary.build(from: [s1, s2])
    XCTAssertTrue(msg.contains("80% → 60%"), "Expected battery range in: \(msg)")
    XCTAssertTrue(msg.contains("discharging"))
  }

  func testBatteryShowsChargingStatus() {
    let s1 = snap(batteryLevel: 50, isCharging: true)
    let s2 = snap(batteryLevel: 55, isCharging: true)
    let msg = CoalesceSummary.build(from: [s1, s2])
    XCTAssertTrue(msg.contains("charging"))
  }

  // MARK: - IP changed marker

  func testIPChangedMarkerWhenDifferent() {
    let s1 = snap(publicIP: "1.2.3.4")
    let s2 = snap(publicIP: "5.6.7.8")
    let msg = CoalesceSummary.build(from: [s1, s2])
    XCTAssertTrue(msg.contains("5.6.7.8"), "Last IP should appear")
    XCTAssertTrue(msg.contains("(changed)"), "Expected (changed) for different IPs in: \(msg)")
  }

  func testIPNoChangedMarkerWhenSame() {
    let s1 = snap(publicIP: "1.2.3.4")
    let s2 = snap(publicIP: "1.2.3.4")
    let msg = CoalesceSummary.build(from: [s1, s2])
    XCTAssertFalse(msg.contains("(changed)"), "Should not show (changed) when IP is unchanged")
  }

  func testIPNoChangedMarkerWhenFirstNil() {
    // first has no IP → changed must not fire even if last has one
    let s1 = snap(publicIP: nil)
    let s2 = snap(publicIP: "9.9.9.9")
    let msg = CoalesceSummary.build(from: [s1, s2])
    XCTAssertFalse(msg.contains("(changed)"))
  }

  // MARK: - WiFi changed marker

  func testWiFiChangedMarkerWhenDifferent() {
    let s1 = snap(wifiName: "HomeNet")
    let s2 = snap(wifiName: "StarbucksWifi")
    let msg = CoalesceSummary.build(from: [s1, s2])
    XCTAssertTrue(msg.contains("StarbucksWifi"), "Last WiFi name should appear")
    XCTAssertTrue(msg.contains("(changed)"), "Expected (changed) for different WiFi in: \(msg)")
  }

  func testWiFiNoChangedMarkerWhenSame() {
    let s1 = snap(wifiName: "SameNet")
    let s2 = snap(wifiName: "SameNet")
    let msg = CoalesceSummary.build(from: [s1, s2])
    XCTAssertFalse(msg.contains("(changed)"))
  }
}
