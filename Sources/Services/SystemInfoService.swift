import Foundation
import CoreWLAN
import IOKit.ps
import os.log

protocol SystemInfoProvider {
  func getPublicIP(completion: @escaping (String?) -> Void)
  func getWiFiName() -> String?
  func getBatteryLevel() -> Int?
  func isCharging() -> Bool?
  func getDeviceName() -> String
}

final class SystemInfoService: SystemInfoProvider {
  private let session: URLSession
  private let ipServiceURL = "https://api.ipify.org"
  private let timeout: TimeInterval

  init(session: URLSession = .shared, timeout: TimeInterval = 3.0) {
    self.session = session
    self.timeout = timeout
  }

  func getPublicIP(completion: @escaping (String?) -> Void) {
    guard let url = URL(string: ipServiceURL) else {
      completion(nil)
      return
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = timeout

    session.dataTask(with: request) { data, _, error in
      if let error = error {
        Logger.system.error("Failed to get public IP: \(error.localizedDescription)")
        completion(nil)
        return
      }
      if let data = data, let ip = String(data: data, encoding: .utf8) {
        completion(ip.trimmingCharacters(in: .whitespacesAndNewlines))
      } else {
        completion(nil)
      }
    }.resume()
  }

  func getWiFiName() -> String? {
    CWWiFiClient.shared().interface()?.ssid()
  }

  func getBatteryLevel() -> Int? {
    getBatteryInfo()?.level
  }

  func isCharging() -> Bool? {
    getBatteryInfo()?.isCharging
  }

  func getDeviceName() -> String {
    Host.current().localizedName ?? "Unknown"
  }

  private func getBatteryInfo() -> (level: Int, isCharging: Bool)? {
    let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array

    for source in sources {
      guard let desc = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as? [String: Any],
            let capacity = desc[kIOPSCurrentCapacityKey] as? Int,
            let isCharging = desc[kIOPSIsChargingKey] as? Bool else { continue }
      return (capacity, isCharging)
    }
    return nil
  }
}
