import XCTest
import CoreLocation
@testable import LidGuard

final class DeviceSnapshotTests: XCTestCase {
  // MARK: - Field mapping

  func testFieldsMappedFromDeviceInfo() {
    let coord = CLLocationCoordinate2D(latitude: 37.5, longitude: -122.3)
    let loc = CLLocation(coordinate: coord, altitude: 0,
                         horizontalAccuracy: 50.0, verticalAccuracy: 0,
                         timestamp: Date())
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let info = DeviceInfo(timestamp: now, location: loc,
                          publicIP: "1.2.3.4", wifiName: "TestNet",
                          batteryLevel: 80, isCharging: true, deviceName: "MyMac")
    let snap = DeviceSnapshot(info)
    XCTAssertEqual(snap.timestamp, now)
    XCTAssertEqual(snap.latitude, 37.5)
    XCTAssertEqual(snap.longitude, -122.3)
    XCTAssertEqual(snap.accuracy, 50.0)
    XCTAssertEqual(snap.publicIP, "1.2.3.4")
    XCTAssertEqual(snap.wifiName, "TestNet")
    XCTAssertEqual(snap.batteryLevel, 80)
    XCTAssertEqual(snap.isCharging, true)
    XCTAssertEqual(snap.deviceName, "MyMac")
  }

  func testAccuracyNilWhenZero() {
    let loc = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                         altitude: 0, horizontalAccuracy: 0, verticalAccuracy: 0,
                         timestamp: Date())
    let info = DeviceInfo(timestamp: Date(), location: loc, publicIP: nil,
                          wifiName: nil, batteryLevel: nil, isCharging: nil,
                          deviceName: "Mac")
    XCTAssertNil(DeviceSnapshot(info).accuracy)
  }

  func testAccuracyNilWhenNegative() {
    let loc = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                         altitude: 0, horizontalAccuracy: -1, verticalAccuracy: 0,
                         timestamp: Date())
    let info = DeviceInfo(timestamp: Date(), location: loc, publicIP: nil,
                          wifiName: nil, batteryLevel: nil, isCharging: nil,
                          deviceName: "Mac")
    XCTAssertNil(DeviceSnapshot(info).accuracy)
  }

  func testNilLocationYieldsNilLatLngAccuracy() {
    let info = DeviceInfo(timestamp: Date(), location: nil, publicIP: nil,
                          wifiName: nil, batteryLevel: nil, isCharging: nil,
                          deviceName: "Mac")
    let snap = DeviceSnapshot(info)
    XCTAssertNil(snap.latitude)
    XCTAssertNil(snap.longitude)
    XCTAssertNil(snap.accuracy)
  }

  // MARK: - Codable round-trip

  func testCodableRoundTrip() throws {
    let snap = DeviceSnapshot(
      timestamp: Date(timeIntervalSince1970: 1_700_000_000),
      latitude: 48.8566, longitude: 2.3522, accuracy: 10.5,
      publicIP: "8.8.8.8", wifiName: "Café", batteryLevel: 55,
      isCharging: false, deviceName: "MyMac"
    )
    let data = try JSONEncoder().encode(snap)
    let decoded = try JSONDecoder().decode(DeviceSnapshot.self, from: data)
    XCTAssertEqual(decoded, snap)
  }

  func testCodableRoundTripWithNilOptionals() throws {
    let snap = DeviceSnapshot(
      timestamp: Date(timeIntervalSince1970: 1_000_000),
      latitude: nil, longitude: nil, accuracy: nil,
      publicIP: nil, wifiName: nil, batteryLevel: nil,
      isCharging: nil, deviceName: "Mac"
    )
    let data = try JSONEncoder().encode(snap)
    let decoded = try JSONDecoder().decode(DeviceSnapshot.self, from: data)
    XCTAssertEqual(decoded, snap)
  }
}
