import Foundation

/// Codable, location-flattened mirror of `DeviceInfo` for on-disk queuing and
/// for building coalesced summaries. `CLLocation` is not Codable, so lat/lng/accuracy
/// are stored as plain Doubles.
struct DeviceSnapshot: Codable, Equatable, Sendable {
  var timestamp: Date
  var latitude: Double?
  var longitude: Double?
  var accuracy: Double?
  var publicIP: String?
  var wifiName: String?
  var batteryLevel: Int?
  var isCharging: Bool?
  var deviceName: String
}

extension DeviceSnapshot {
  init(_ info: DeviceInfo) {
    self.timestamp = info.timestamp
    self.latitude = info.location?.coordinate.latitude
    self.longitude = info.location?.coordinate.longitude
    if let acc = info.location?.horizontalAccuracy, acc > 0 { self.accuracy = acc } else { self.accuracy = nil }
    self.publicIP = info.publicIP
    self.wifiName = info.wifiName
    self.batteryLevel = info.batteryLevel
    self.isCharging = info.isCharging
    self.deviceName = info.deviceName
  }
}
