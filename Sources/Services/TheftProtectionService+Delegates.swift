import Foundation
import os.log

// MARK: - PowerMonitorDelegate
extension TheftProtectionService: PowerMonitorDelegate {
  func powerMonitorDidDetectDisconnect(_ monitor: PowerMonitorService) {
    guard state == .enabled || state == .enabledBluetooth else { return }
    guard SettingsService.shared.triggerPowerDisconnect else { return }
    ActivityLog.logAsync(.trigger, "Power disconnected detected")
    activateTheftMode(trigger: .powerDisconnected)
  }
}

// MARK: - GlobalShortcutDelegate
extension TheftProtectionService: GlobalShortcutDelegate {
  func globalShortcutTriggered() {
    delegate?.theftProtectionShortcutTriggered(self)
  }

  func bluetoothShortcutTriggered() {
    delegate?.theftProtectionBluetoothShortcutTriggered(self)
  }
}

// MARK: - BluetoothProximityDelegate
extension TheftProtectionService: BluetoothProximityDelegate {
  /// Returns whether protection was actually armed — the service re-offers while
  /// this is false, so declining here is not final.
  func bluetoothProximityAllDevicesLost(_ service: BluetoothProximityService) -> Bool {
    guard SettingsService.shared.bluetoothAutoArmEnabled else { return false }
    guard state == .disabled else { return false }

    if let lastDisarm = lastManualDisarmTime,
       Date().timeIntervalSince(lastDisarm) < 300 {
      Logger.bluetooth.info("Skipping auto-arm — manual disarm cooldown active")
      ActivityLog.logAsync(.bluetooth, "Auto-arm suppressed (manual disarm cooldown)")
      return false
    }

    enableProtectionBluetooth()
    return true
  }

  func bluetoothProximityDeviceReturned(_ service: BluetoothProximityService, device: TrustedBLEDevice) {
    guard SettingsService.shared.bluetoothAutoArmEnabled else { return }
    guard state == .enabledBluetooth else { return }
    guard bleAutoDisarmArmed else {
      Logger.bluetooth.info("Skipping auto-disarm — consent revoked by prior theft episode")
      return
    }

    Logger.bluetooth.info("Auto-disarming — device returned: \(device.name)")
    ActivityLog.logAsync(.bluetooth, "Auto-disarming — \(device.name) returned")
    disableProtection()
  }
}
