import Foundation
import CoreLocation

protocol DeviceInfoCollecting {
  func warmUp()
  func collect(completion: @escaping (DeviceInfo) -> Void)
}

final class DeviceInfoCollector: DeviceInfoCollecting {
  private let locationService: LocationProvider
  private let systemInfoService: SystemInfoProvider

  init(locationService: LocationProvider = LocationService(),
       systemInfoService: SystemInfoProvider = SystemInfoService()) {
    self.locationService = locationService
    self.systemInfoService = systemInfoService
  }

  func warmUp() {
    locationService.requestAuthorization()
  }

  func collect(completion: @escaping (DeviceInfo) -> Void) {
    locationService.requestLocation { [weak self] location in
      guard let self = self else { return }

      // Fetch public IP asynchronously
      self.systemInfoService.getPublicIP { publicIP in
        let info = DeviceInfo(
          timestamp: Date(),
          location: location,
          publicIP: publicIP,
          wifiName: self.systemInfoService.getWiFiName(),
          batteryLevel: self.systemInfoService.getBatteryLevel(),
          isCharging: self.systemInfoService.isCharging(),
          deviceName: self.systemInfoService.getDeviceName()
        )

        completion(info)
      }
    }
  }
}
